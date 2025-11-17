# Troubleshooting Guide for EKS Deployment

**Last Updated**: 2025-11-13
**Target Audience**: DevOps Engineers, SREs, Developers

This guide provides solutions to common issues encountered when deploying and operating Fineract on Amazon EKS.

---

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Cluster Issues](#cluster-issues)
- [Node Issues](#node-issues)
- [Pod Issues](#pod-issues)
- [IRSA (IAM Roles for Service Accounts)](#irsa-iam-roles-for-service-accounts)
- [Storage Issues (EBS CSI)](#storage-issues-ebs-csi)
- [Networking Issues](#networking-issues)
- [LoadBalancer Issues](#loadbalancer-issues)
- [Ingress Issues](#ingress-issues)
- [Application Issues](#application-issues)
- [ArgoCD Issues](#argocd-issues)
- [Database Connection Issues](#database-connection-issues)
- [Performance Issues](#performance-issues)

---

## Quick Diagnostics

### Essential Commands

```bash
# Check cluster connectivity
kubectl cluster-info

# Get all resources in namespace
kubectl get all -n fineract-dev

# Check pod status
kubectl get pods -n fineract-dev

# View pod logs
kubectl logs <pod-name> -n fineract-dev

# Describe pod (shows events)
kubectl describe pod <pod-name> -n fineract-dev

# Check node status
kubectl get nodes

# Check recent events
kubectl get events -n fineract-dev --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -n fineract-dev
```

### Verification Scripts

```bash
# Validate Terraform outputs
./scripts/validate-terraform-outputs.sh dev

# Verify IRSA configuration
./scripts/verify-irsa-credentials.sh dev

# Get application endpoints
./scripts/get-endpoints.sh dev

# Wait for LoadBalancer
./scripts/wait-for-loadbalancer.sh dev
```

---

## Cluster Issues

### Issue: Cannot Connect to Cluster

**Symptoms**:
- `kubectl cluster-info` fails
- `Unable to connect to the server: dial tcp: lookup`
- `error: You must be logged in to the server (Unauthorized)`

**Causes**:
1. Kubeconfig not configured
2. AWS credentials expired/invalid
3. EKS cluster not created or still creating
4. Wrong AWS region

**Solutions**:

```bash
# 1. Update kubeconfig
aws eks update-kubeconfig \
  --name fineract-dev \
  --region us-east-2

# 2. Verify AWS credentials
aws sts get-caller-identity

# 3. Check cluster status
aws eks describe-cluster \
  --name fineract-dev \
  --region us-east-2 \
  --query 'cluster.status'

# Expected: "ACTIVE"

# 4. Verify cluster exists
aws eks list-clusters --region us-east-2
```

### Issue: Cluster Creation Failed

**Symptoms**:
- Terraform apply fails with EKS errors
- Cluster stuck in "CREATING" state

**Common Errors**:

#### Error: "Cluster security group does not exist"

```bash
# Solution: Verify VPC and security groups
aws ec2 describe-security-groups --region us-east-2

# Recreate with Terraform
terraform destroy -target=module.eks
terraform apply
```

#### Error: "Insufficient permissions"

See `docs/AWS_IAM_REQUIREMENTS.md` for required IAM policies.

#### Error: "Subnet requirements not met"

**Cause**: EKS requires at least 2 subnets in different AZs

```bash
# Check subnets
terraform output private_subnet_ids
terraform output public_subnet_ids

# Should have 2+ subnets each
```

---

## Node Issues

### Issue: Nodes Not Joining Cluster

**Symptoms**:
- `kubectl get nodes` shows 0 nodes
- Node status: "NotReady"

**Solutions**:

```bash
# 1. Check node group status
aws eks describe-nodegroup \
  --cluster-name fineract-dev \
  --nodegroup-name fineract-dev-nodes \
  --region us-east-2

# 2. Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?Tags[?Key==`eks:cluster-name` && Value==`fineract-dev`]]' \
  --region us-east-2

# 3. Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=fineract-dev" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress]' \
  --output table \
  --region us-east-2

# 4. Check instance user data logs (SSH to node)
ssh ec2-user@<node-ip>
sudo journalctl -u kubelet
```

**Common Causes**:
- IAM role missing permissions
- Security group blocking communication
- Subnet routing issues
- AMI compatibility issues

### Issue: Node Pressure Conditions

**Symptoms**:
- Nodes show "DiskPressure", "MemoryPressure", or "PIDPressure"
- Pods evicted

**Solutions**:

```bash
# Check node conditions
kubectl describe node <node-name> | grep -A 5 Conditions

# DiskPressure
# - Increase EBS volume size in Terraform
# - Clean up unused images: kubectl debug node/<node-name> -- sh -c "crictl rmi --prune"

# MemoryPressure
# - Scale up to larger instance types (t3.large → t3.xlarge)
# - Reduce pod resource requests

# PIDPressure
# - Reduce number of pods per node
# - Increase pid limit in kubelet config
```

---

## Pod Issues

### Issue: Pods Stuck in Pending

**Symptoms**:
- `kubectl get pods` shows "Pending" status

**Diagnose**:

```bash
kubectl describe pod <pod-name> -n fineract-dev
# Look at "Events" section
```

**Common Causes & Solutions**:

#### 1. Insufficient CPU/Memory

**Event**: `0/2 nodes are available: 2 Insufficient cpu/memory`

```bash
# Solution 1: Scale up nodes
kubectl scale deployment <deployment> --replicas=1

# Solution 2: Reduce resource requests
kubectl edit deployment <deployment>
# Reduce: resources.requests.cpu/memory

# Solution 3: Add more nodes (increase node group size)
```

#### 2. PersistentVolumeClaim Not Bound

**Event**: `pod has unbound immediate PersistentVolumeClaims`

```bash
# Check PVC status
kubectl get pvc -n fineract-dev

# Check storage class
kubectl get storageclass

# Verify EBS CSI driver is running
kubectl get pods -n kube-system -l app=ebs-csi-controller

# Check EBS CSI driver logs
kubectl logs -n kube-system -l app=ebs-csi-controller -c ebs-plugin
```

See [Storage Issues](#storage-issues-ebs-csi) section.

#### 3. Image Pull Errors

**Event**: `Failed to pull image: rpc error: code = Unknown desc = Error response from daemon: pull access denied`

```bash
# For ECR images
# 1. Verify ECR permissions
aws ecr get-login-password --region us-east-2

# 2. Create image pull secret (if needed)
kubectl create secret docker-registry ecr-secret \
  --docker-server=<account-id>.dkr.ecr.us-east-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-2) \
  -n fineract-dev

# For public images
# Check image name is correct
docker pull <image-name>
```

### Issue: Pods CrashLoopBackOff

**Symptoms**:
- Pod status: "CrashLoopBackOff"
- High restart count

**Diagnose**:

```bash
# Check logs
kubectl logs <pod-name> -n fineract-dev --previous

# Check events
kubectl describe pod <pod-name> -n fineract-dev
```

**Common Causes**:

#### 1. Application Error

```bash
# View last 100 lines of logs
kubectl logs <pod-name> -n fineract-dev --tail=100

# Look for:
# - Exception stack traces
# - "Error:" messages
# - Configuration errors
```

#### 2. Missing Configuration/Secrets

```bash
# Verify secrets exist
kubectl get secrets -n fineract-dev

# Check secret is mounted
kubectl describe pod <pod-name> -n fineract-dev | grep -A 5 Mounts
```

#### 3. Liveness/Readiness Probe Failures

```bash
# Check probe configuration
kubectl get pod <pod-name> -n fineract-dev -o yaml | grep -A 10 livenessProbe

# Test probe endpoint manually
kubectl exec <pod-name> -n fineract-dev -- curl http://localhost:8080/actuator/health
```

**Solution**: Adjust probe `initialDelaySeconds`, `timeoutSeconds`, or `failureThreshold`

### Issue: Pods OOMKilled (Out of Memory)

**Symptoms**:
- Pod status: "OOMKilled"
- Container exit code: 137

**Diagnose**:

```bash
# Check memory limits
kubectl get pod <pod-name> -n fineract-dev -o yaml | grep -A 5 resources

# Check actual memory usage
kubectl top pod <pod-name> -n fineract-dev
```

**Solutions**:

```bash
# Increase memory limit
kubectl edit deployment <deployment-name> -n fineract-dev

# Change:
resources:
  limits:
    memory: "2Gi"  # Increase from 1Gi
  requests:
    memory: "1.5Gi"
```

---

## IRSA (IAM Roles for Service Accounts)

### Issue: Pods Cannot Access S3/AWS Services

**Symptoms**:
- Application logs: "Access Denied" when accessing S3
- `aws s3 ls` fails in pod

**Diagnose**:

```bash
# Run verification script
./scripts/verify-irsa-credentials.sh dev

# Manual checks
kubectl get sa fineract-aws -n fineract-dev -o yaml

# Check for annotation:
# eks.amazonaws.com/role-arn: arn:aws:iam::...
```

**Common Causes & Solutions**:

#### 1. Service Account Missing IRSA Annotation

```bash
# Check service account
kubectl describe sa fineract-aws -n fineract-dev

# If annotation missing, apply it
kubectl apply -f secrets/dev/service-account.yaml
```

#### 2. Pod Not Using Correct Service Account

```bash
# Check pod's service account
kubectl get pod <pod-name> -n fineract-dev -o yaml | grep serviceAccountName

# Fix: Edit deployment to use correct SA
kubectl edit deployment <deployment-name>

# Add under spec.template.spec:
serviceAccountName: fineract-aws
```

#### 3. IAM Role Trust Policy Issues

```bash
# Get OIDC provider
aws eks describe-cluster --name fineract-dev --region us-east-2 \
  --query 'cluster.identity.oidc.issuer' --output text

# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check role trust policy
aws iam get-role --role-name <role-name> \
  --query 'Role.AssumeRolePolicyDocument'

# Should include:
# - Correct OIDC provider ARN
# - Correct namespace:serviceaccount condition
```

**Fix**: Recreate IRSA role with Terraform:

```bash
cd terraform/aws
terraform destroy -target=module.eks.aws_iam_role.app_service_account
terraform apply
```

#### 4. IAM Role Missing Permissions

```bash
# Check attached policies
aws iam list-attached-role-policies --role-name <role-name>

# Check inline policies
aws iam list-role-policies --role-name <role-name>

# Get policy document
aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>

# Verify S3 permissions exist:
# - s3:GetObject
# - s3:PutObject
# - s3:DeleteObject
# - s3:ListBucket
```

**Fix**: Update IAM policy in `terraform/aws/modules/eks/irsa.tf` and reapply.

---

## Storage Issues (EBS CSI)

### Issue: PVC Stuck in Pending

**Symptoms**:
- `kubectl get pvc` shows "Pending" status
- Pods waiting for volume

**Diagnose**:

```bash
# Check PVC
kubectl describe pvc <pvc-name> -n fineract-dev

# Check storage class
kubectl get storageclass

# Check EBS CSI driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

**Common Causes**:

#### 1. EBS CSI Driver Not Running

```bash
# Check CSI driver pods
kubectl get pods -n kube-system -l app=ebs-csi-controller

# If missing, check add-on
aws eks describe-addon \
  --cluster-name fineract-dev \
  --addon-name aws-ebs-csi-driver \
  --region us-east-2

# If add-on missing, check Terraform module
```

#### 2. Storage Class Not Found

```bash
# Check storage class
kubectl get storageclass gp3

# If missing, create it
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

#### 3. IRSA Permissions Missing

```bash
# Verify EBS CSI driver role
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml

# Check for annotation
# eks.amazonaws.com/role-arn: arn:aws:iam::...

# Verify IAM role has permissions
aws iam list-attached-role-policies --role-name <ebs-csi-role>
```

### Issue: Volume Mount Failed

**Symptoms**:
- Pod events: "Unable to attach or mount volumes"
- "Multi-Attach error for volume"

**Solutions**:

```bash
# Check volume attachment
aws ec2 describe-volumes --region us-east-2 \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=<pvc-name>"

# If volume stuck attached to wrong node
# Force detach (use with caution!)
aws ec2 detach-volume --volume-id <vol-id>

# Delete and recreate pod
kubectl delete pod <pod-name> -n fineract-dev
```

---

## Networking Issues

### Issue: Pods Cannot Communicate

**Symptoms**:
- Service unreachable from other pods
- `curl: (7) Failed to connect`

**Diagnose**:

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- sh
nslookup fineract-write-service.fineract-dev.svc.cluster.local

# Test service connectivity
curl http://fineract-write-service.fineract-dev:8080/actuator/health

# Check service endpoints
kubectl get endpoints <service-name> -n fineract-dev

# Should show pod IPs
```

**Common Causes**:

#### 1. Service Selector Mismatch

```bash
# Check service selector
kubectl get service <service-name> -n fineract-dev -o yaml | grep -A 5 selector

# Check pod labels
kubectl get pod <pod-name> -n fineract-dev --show-labels

# Labels must match!
```

#### 2. Network Policies Blocking Traffic

```bash
# Check network policies
kubectl get networkpolicies -n fineract-dev

# Describe policy
kubectl describe networkpolicy <policy-name> -n fineract-dev

# Temporarily delete policy to test
kubectl delete networkpolicy <policy-name> -n fineract-dev
```

#### 3. VPC CNI Issues

```bash
# Check VPC CNI pods
kubectl get pods -n kube-system -l k8s-app=aws-node

# Check logs
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
```

---

## LoadBalancer Issues

### Issue: LoadBalancer Not Provisioning

**Symptoms**:
- `kubectl get svc` shows LoadBalancer with `<pending>` EXTERNAL-IP
- Ingress-nginx service not getting external endpoint

**Diagnose**:

```bash
# Check service
kubectl describe service ingress-nginx-controller -n ingress-nginx

# Look for events like:
# - "Creating load balancer"
# - "Ensured load balancer"
# - Error messages

# Check AWS ELB
aws elbv2 describe-load-balancers --region us-east-2

# Use wait script
./scripts/wait-for-loadbalancer.sh dev
```

**Common Causes**:

#### 1. IAM Permissions Missing

Node IAM role needs:
- `elasticloadbalancing:*`
- `ec2:DescribeSubnets`
- `ec2:DescribeSecurityGroups`

#### 2. Subnet Tags Missing

**Cause**: EKS Load Balancer Controller requires specific subnet tags

```bash
# Check subnet tags
aws ec2 describe-subnets --region us-east-2 \
  --filters "Name=vpc-id,Values=<vpc-id>"

# Required tags:
# kubernetes.io/cluster/<cluster-name> = shared
# kubernetes.io/role/elb = 1 (for public subnets)
# kubernetes.io/role/internal-elb = 1 (for private subnets)
```

**Fix**: Add tags via Terraform in `terraform/aws/modules/eks/main.tf`

#### 3. Service Annotation Issues

```bash
# Check service annotations
kubectl get service ingress-nginx-controller -n ingress-nginx -o yaml

# For NLB, should have:
# service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

---

## Ingress Issues

### Issue: Ingress Not Routing Traffic

**Symptoms**:
- `curl https://<domain>` returns 404 or connection refused
- Ingress exists but traffic not reaching pods

**Diagnose**:

```bash
# Check ingress
kubectl get ingress -n fineract-dev
kubectl describe ingress <ingress-name> -n fineract-dev

# Check ingress-nginx pods
kubectl get pods -n ingress-nginx

# Check ingress-nginx logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100
```

**Common Issues**:

#### 1. Ingress Class Not Set

```bash
# Check ingress class
kubectl get ingressclass

# Ingress should reference it:
kubectl get ingress <ingress-name> -n fineract-dev -o yaml | grep ingressClassName

# Should be: ingressClassName: nginx
```

#### 2. Host/Path Mismatch

```bash
# Test with IP directly
curl -H "Host: example.com" http://<LoadBalancer-IP>

# If works: DNS issue
# If fails: ingress config issue
```

#### 3. Backend Service Not Ready

```bash
# Check service has endpoints
kubectl get endpoints <service-name> -n fineract-dev

# If empty, pods are not ready
kubectl get pods -n fineract-dev -l app=<app-name>
```

---

## Application Issues

### Issue: Fineract API Returning Errors

#### Error: "Database connection failed"

**Diagnose**:

```bash
# Check database secret
kubectl get secret fineract-db-credentials -n fineract-dev -o yaml

# Decode values
kubectl get secret fineract-db-credentials -n fineract-dev \
  -o jsonpath='{.data.host}' | base64 -d

# Test database connectivity from pod
kubectl exec <fineract-pod> -n fineract-dev -- \
  nc -zv <rds-host> 5432
```

**Solutions**:

1. Verify RDS instance is running:
   ```bash
   aws rds describe-db-instances --region us-east-2
   ```

2. Check security group allows traffic from EKS nodes:
   ```bash
   aws ec2 describe-security-groups --region us-east-2
   # Verify ingress rule: port 5432 from node security group
   ```

3. Recreate database secret:
   ```bash
   ./scripts/seal-terraform-secrets-enhanced.sh dev
   kubectl delete secret fineract-db-credentials -n fineract-dev
   kubectl apply -f secrets/dev/fineract-db-credentials-sealed.yaml
   kubectl rollout restart deployment/fineract-write -n fineract-dev
   ```

#### Error: "S3 Access Denied"

**Diagnose**: See [IRSA Issues](#irsa-iam-roles-for-service-accounts) section

**Quick Fix**:

```bash
# Verify IRSA
./scripts/verify-irsa-credentials.sh dev

# Check S3 bucket permissions
aws s3 ls s3://<bucket-name>

# Test from pod (if AWS CLI available)
kubectl exec <pod-name> -n fineract-dev -- \
  aws s3 ls s3://<bucket-name>
```

---

## ArgoCD Issues

### Issue: ArgoCD Applications OutOfSync

**Symptoms**:
- ArgoCD shows "OutOfSync" status
- Changes not deploying automatically

**Solutions**:

```bash
# Manual sync
argocd app sync <app-name>

# Or via kubectl
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Check sync status
argocd app get <app-name>
```

### Issue: ArgoCD Cannot Access Git Repository

**Symptoms**:
- "connection timed out" errors
- "authentication failed"

**Solutions**:

```bash
# Check ArgoCD repo credentials
argocd repo list

# Update credentials
argocd repo add https://github.com/org/repo \
  --username <username> \
  --password <token>

# For SSH
argocd repo add git@github.com:org/repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

---

## Database Connection Issues

### Issue: Too Many Database Connections

**Symptoms**:
- Application logs: "FATAL: sorry, too many clients already"
- RDS metrics show connection limit reached

**Solutions**:

1. **Increase RDS max_connections**:
   ```bash
   # Check current value
   aws rds describe-db-instances \
     --db-instance-identifier fineract-dev-db \
     --query 'DBInstances[0].MaximumConnections'

   # Increase by modifying parameter group
   ```

2. **Reduce application connection pool size**:
   ```yaml
   # In application configuration
   spring.datasource.hikari.maximum-pool-size: 10  # Reduce from 20
   ```

3. **Scale application pods** (if too many replicas):
   ```bash
   kubectl scale deployment fineract-write --replicas=2 -n fineract-dev
   ```

---

## Performance Issues

### Issue: High CPU Usage

**Diagnose**:

```bash
# Check pod CPU
kubectl top pods -n fineract-dev

# Check node CPU
kubectl top nodes

# Check CloudWatch metrics
# See docs/CLOUDWATCH_MONITORING.md
```

**Solutions**:

1. **Scale horizontally** (more pods):
   ```bash
   kubectl scale deployment fineract-write --replicas=3 -n fineract-dev
   ```

2. **Scale vertically** (larger nodes):
   Update Terraform `node_instance_types = ["t3.xlarge"]`

3. **Enable Cluster Autoscaler**:
   ```bash
   ./scripts/install-cluster-autoscaler.sh dev
   ```

### Issue: High Memory Usage

**Diagnose**:

```bash
# Check memory
kubectl top pods -n fineract-dev --sort-by=memory
kubectl top nodes

# Check for memory leaks in logs
kubectl logs <pod-name> -n fineract-dev | grep -i "OutOfMemoryError"
```

**Solutions**:

1. Increase pod memory limits
2. Investigate memory leaks (heap dumps)
3. Scale to larger instance types

---

## Additional Resources

- [EKS Troubleshooting Official Docs](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Kubernetes Debugging Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [CloudWatch Monitoring Guide](docs/CLOUDWATCH_MONITORING.md)
- [AWS IAM Requirements](docs/AWS_IAM_REQUIREMENTS.md)

---

## Getting Help

If you're still stuck after trying these solutions:

1. Check CloudWatch logs for detailed error messages
2. Run all diagnostic scripts in `scripts/` directory
3. Collect diagnostics:
   ```bash
   kubectl describe pod <pod-name> -n fineract-dev > pod-describe.txt
   kubectl logs <pod-name> -n fineract-dev > pod-logs.txt
   kubectl get events -n fineract-dev --sort-by='.lastTimestamp' > events.txt
   ```
4. Contact the DevOps team with diagnostic files

---

**Remember**: Most issues can be diagnosed by checking pod events (`kubectl describe pod`) and logs (`kubectl logs`). Start there!
