# Quick Start: Deploy Fineract on AWS with K3s (Cost-Optimized)

> Deploy Apache Fineract with K3s + AWS managed services in **8-10 minutes** for **~$40-50/month** (70% cheaper than EKS!)

## Overview

This guide deploys:
- ✅ **K3s cluster** on EC2 (2 nodes, ARM Graviton)
- ✅ **AWS managed services** (RDS PostgreSQL, S3)
- ✅ **In-cluster Redis** (StatefulSet for caching)
- ✅ **Complete Fineract stack** (write, read, batch, OAuth2 Proxy, web apps)
- ✅ **Cost-optimized** (~$40-50/month for dev)

**Total Time:** 8-10 minutes (vs 20-25 minutes for EKS)
**Total Cost:** ~$40-50/month (vs ~$150-160/month for EKS)

---

## Prerequisites

### 1. Tools Installed ✅

You should have already installed:
- ✅ AWS CLI
- ✅ Terraform
- ✅ kubectl
- ✅ kustomize (built into kubectl)

### 2. AWS Credentials

Configure AWS:
```bash
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: us-east-2
# - Output format: json

# Verify
aws sts get-caller-identity
```

---

## Deployment Steps

### Step 1: Navigate to Terraform Directory (10 seconds)

```bash
cd terraform/aws
```

### Step 2: Initialize Terraform (30 seconds)

```bash
terraform init
```

You should see: `Terraform has been successfully initialized!`

### Step 3: Plan Infrastructure (1 minute)

```bash
terraform plan -var-file=environments/dev-k3s.tfvars -out=tfplan
```

**What will be created:**
- 1 VPC with public/private subnets across 2 AZs
- 2 K3s nodes (1 server, 1 agent) - t4g.small instances
- 1 RDS PostgreSQL database (db.t4g.micro)
- 2 S3 buckets (documents, backups)
- IAM roles with IRSA for S3 access
- Security groups, Kubernetes secrets

**Review the plan** - it should create ~50-60 resources.

### Step 4: Deploy Infrastructure (8-10 minutes)

```bash
terraform apply tfplan
```

This will:
1. Create VPC and networking (2-3 min)
2. Launch K3s EC2 instances (1-2 min)
3. Install K3s automatically (2-3 min)
4. Create RDS and S3 in parallel (5-8 min)
5. Configure Kubernetes secrets and IRSA

**Go grab a coffee!** ☕ This takes about **8-10 minutes** (much faster than EKS's 20-25 minutes).

### Step 5: Get Cluster Access (30 seconds)

```bash
# Save kubeconfig
terraform output -raw kubeconfig > ~/.kube/config-fineract-dev

# Use this kubeconfig
export KUBECONFIG=~/.kube/config-fineract-dev

# Verify cluster access
kubectl get nodes
```

**Expected output:**
```
NAME                 STATUS   ROLES                  AGE   VERSION
fineract-dev-server-1   Ready    control-plane,master   3m    v1.28.5+k3s1
fineract-dev-agent-1    Ready    <none>                 2m    v1.28.5+k3s1
```

### Step 6: Verify AWS Services (1 minute)

```bash
# Check Kubernetes secrets created by Terraform
kubectl get secrets -n fineract-dev
# You should see: rds-connection, s3-connection

# Check IRSA service account
kubectl get serviceaccount fineract-aws -n fineract-dev -o yaml

# Get connection details
terraform output connection_details
```

### Step 7: Deploy Fineract (2 minutes)

```bash
# Navigate back to repository root
cd ../..

# Deploy Fineract application
kubectl apply -k environments/dev-aws

# Watch pods start up
kubectl get pods -n fineract-dev -w
```

Wait for all pods to show `Running` status (takes 2-3 minutes).

### Step 8: Access Fineract (1 minute)

**Port-forward to access locally:**
```bash
# Forward Fineract API
kubectl port-forward -n fineract-dev svc/fineract-write 8443:8443 &

# Test API
curl -k -u mifos:password https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default"
```

**Or expose via LoadBalancer:**
```bash
# Create LoadBalancer
kubectl patch svc oauth2-proxy -n fineract-dev \
  -p '{"spec":{"type":"LoadBalancer"}}'

# Wait for external IP (takes 2-3 minutes)
kubectl get svc oauth2-proxy -n fineract-dev -w

# Get URL
export FINERACT_URL=$(kubectl get svc oauth2-proxy -n fineract-dev \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Fineract URL: https://$FINERACT_URL"
```

**Default credentials:**
- Username: `mifos`
- Password: `password`
- Tenant: `default`

---

## Cost Breakdown

### Monthly Costs (Development)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| **K3s Instances** | 2x t4g.small (ARM) | **$12** |
| **RDS** | db.t4g.micro, 20GB | **$12** |
| **In-cluster Redis** | StatefulSet (no cost) | **$0** |
| **NAT Gateway** | Single NAT | **$32** |
| **S3** | ~100GB | **$3-5** |
| **EBS Volumes** | 60GB total | **$3-5** |
| **Data Transfer** | Moderate | **$2-3** |
| **TOTAL** | | **~$40-50** |

### Comparison: K3s vs EKS

| Item | K3s (This Guide) | EKS Alternative | Savings |
|------|-----------------|-----------------|---------|
| Control Plane | **$0** | $72/month | **-100%** |
| Compute | **$12** (t4g.small) | $48 (t4g.medium) | **-75%** |
| RDS | $12 | $12 | 0% |
| Redis | **$0** (in-cluster) | $11 (ElastiCache) | **-100%** |
| Networking | $32 | $32 | 0% |
| **Total** | **~$40-50** | ~$150-160 | **-70%** |

**Annual Savings:** ~$1,320/year! 💰

---

## Cost Optimization Tips

### 1. Auto-Shutdown (Save ~50%)

Stop instances during off-hours:

```bash
# Get instance IDs
terraform output k3s_server_public_ips

# Stop K3s instances (evenings/weekends)
aws ec2 stop-instances --instance-ids i-xxxxx i-yyyyy

# Stop RDS
aws rds stop-db-instance --db-instance-identifier fineract-dev-fineract

# Start again when needed
aws ec2 start-instances --instance-ids i-xxxxx i-yyyyy
aws rds start-db-instance --db-instance-identifier fineract-dev-fineract
```

**Running 8hrs/day instead of 24hrs/day:** ~$20-25/month (50% savings!)

### 2. Remove NAT Gateway (Save $32/month)

If your RDS doesn't need internet access:

```hcl
# In dev-k3s.tfvars
enable_nat_gateway = false  # Saves $32/month
```

**New total:** ~$15-20/month (but RDS won't get updates automatically)

### 3. Use Reserved Instances (Save 30-40%)

For stable workloads, commit to 1 year:
- RDS Reserved: $8/month (instead of $12)

**Total with RIs:** ~$35-45/month

---

## Verify Everything Works

### Health Checks

```bash
# All pods running
kubectl get pods -A

# Fineract health
kubectl exec -n fineract-dev deploy/fineract-write -- \
  curl -s http://localhost:8080/fineract-provider/actuator/health
# Should return: {"status":"UP"}

# RDS connection
kubectl logs -n fineract-dev deploy/fineract-write | grep -i "hikari"
# Should see: "HikariPool-1 - Start completed"

# Redis connection (in-cluster StatefulSet)
kubectl exec -n fineract-dev deploy/fineract-write -- \
  curl -s http://localhost:8080/fineract-provider/actuator/metrics/cache.size

# S3 access (via IRSA)
kubectl exec -n fineract-dev deploy/fineract-write -- \
  aws s3 ls
# Should list S3 buckets
```

### Test API Endpoints

```bash
export FINERACT_URL="https://localhost:8443"
export TENANT="default"

# List offices
curl -k -u mifos:password $FINERACT_URL/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: $TENANT"

# List users
curl -k -u mifos:password $FINERACT_URL/fineract-provider/api/v1/users \
  -H "Fineract-Platform-TenantId: $TENANT"

# Get system info
curl -k -u mifos:password $FINERACT_URL/fineract-provider/api/v1/runreports/FullRunReport \
  -H "Fineract-Platform-TenantId: $TENANT"
```

---

## Troubleshooting

### Issue: K3s nodes not ready

```bash
# Check K3s server logs
terraform output k3s_ssh_command
# Use the SSH command, then:
sudo journalctl -u k3s -f
```

### Issue: Pods can't connect to RDS

```bash
# Verify security group allows K3s nodes
aws ec2 describe-security-groups \
  --group-ids $(terraform output rds_security_group_id)

# Test RDS connectivity from pod
kubectl exec -n fineract-dev deploy/fineract-write -- \
  nc -zv $(terraform output rds_instance_endpoint | cut -d: -f1) 5432
```

### Issue: Terraform apply fails

```bash
# Check if AWS quotas are exceeded
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A  # Running On-Demand instances

# Or destroy and retry
terraform destroy -var-file=environments/dev-k3s.tfvars
terraform apply -var-file=environments/dev-k3s.tfvars
```

---

## Cleanup

### Destroy Everything

```bash
cd terraform/aws

# Empty S3 buckets first
aws s3 rm s3://$(terraform output -raw documents_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw backups_bucket_name) --recursive

# Destroy infrastructure
terraform destroy -var-file=environments/dev-k3s.tfvars
```

**Time:** ~5-8 minutes
**Result:** All resources deleted, no recurring costs

---

## Next Steps

### Production Deployment

For production, consider:
1. **Use EKS** instead of K3s for enterprise support
2. **Enable Multi-AZ** for RDS
3. **Use managed Redis** (ElastiCache) for production workloads
4. **Add monitoring** (Prometheus, Grafana, CloudWatch)
5. **Set up backups** (Velero, RDS snapshots)
6. **Configure ingress** (AWS ALB, TLS certificates with OAuth2 Proxy)

See `environments/production-eks.tfvars` for production configuration.

### Add Monitoring

```bash
# Install Prometheus + Grafana
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace observability --create-namespace

# Access Grafana
kubectl port-forward -n observability svc/monitoring-grafana 3000:80
open http://localhost:3000
```

### Load Initial Data

```bash
cd operations/fineract-data/scripts
python3 main.py --environment dev-aws
```

---

## Summary

You now have:

✅ **K3s cluster** - 2 nodes, production-grade Kubernetes
✅ **RDS PostgreSQL** - Managed database with backups
✅ **In-cluster Redis** - StatefulSet caching layer
✅ **S3 storage** - Document and backup storage with IRSA
✅ **Fineract running** - Full stack deployed with OAuth2 Proxy
✅ **Cost-optimized** - ~$40-50/month (70% cheaper than EKS!)

**Deployment Time:** 8-10 minutes
**Cost:** ~$40-50/month
**Savings vs EKS:** ~$110/month (70%)

🎉 **Your Fineract platform is ready!** Start building your fintech application!

---

## Support

- **K3s Issues:** https://docs.k3s.io
- **Terraform Issues:** Check module READMEs in `terraform/aws/modules/`
- **Fineract Issues:** https://fineract.apache.org
- **Cost Optimization:** See `terraform/aws/environments/dev-k3s.tfvars` comments

For EKS deployment instead, use `environments/production-eks.tfvars`.
