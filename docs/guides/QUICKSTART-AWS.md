# Quick Start Guide: Deploy Fineract on AWS (End-to-End)

> Complete guide to deploy Apache Fineract with AWS managed services (RDS PostgreSQL, S3) and in-cluster Redis from scratch

**Time Required:** ~45-60 minutes
**Cost:** ~$140-150/month for development environment

## Overview

This guide will help you deploy:
- ✅ EKS Kubernetes cluster (if you don't have one)
- ✅ AWS managed infrastructure (RDS PostgreSQL, S3)
- ✅ In-cluster Redis (StatefulSet for caching)
- ✅ Fineract application with all components (OAuth2 Proxy + Keycloak)
- ✅ Monitoring and observability stack

---

## Part 1: Prerequisites & Setup (10 minutes)

### Step 1.1: Install Required Tools

**macOS:**
```bash
# Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install awscli terraform kubectl kustomize helm eksctl
```

**Linux:**
```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

### Step 1.2: Verify Tool Versions

```bash
aws --version          # Should be >= 2.0
terraform version      # Should be >= 1.5.0
kubectl version --client  # Should be >= 1.27
kustomize version      # Should be >= 5.0
eksctl version         # Should be >= 0.150
```

### Step 1.3: Configure AWS CLI

```bash
# Configure AWS credentials
aws configure

# Enter when prompted:
# AWS Access Key ID: [Your access key]
# AWS Secret Access Key: [Your secret key]
# Default region: us-east-2 (or your preferred region)
# Default output format: json

# Verify configuration
aws sts get-caller-identity
```

You should see your AWS account ID, user ARN, and user ID.

---

## Part 2: Create EKS Cluster (15-20 minutes)

### Step 2.1: Create EKS Cluster with eksctl

```bash
# Create cluster configuration file
cat > fineract-cluster.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: fineract-dev
  region: us-east-2
  version: "1.28"

# Use Graviton (ARM) instances for cost savings
iam:
  withOIDC: true  # Required for IRSA

managedNodeGroups:
  - name: fineract-nodes
    instanceType: t4g.medium  # 2 vCPU, 4GB RAM (~$24/month per node)
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 50
    privateNetworking: false  # Use public subnets for simplicity
    labels:
      role: fineract
    tags:
      Environment: development
      Project: fineract

# Enable common add-ons
addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy

# CloudWatch logging (optional)
cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator"]
EOF

# Create the cluster (takes 15-20 minutes)
eksctl create cluster -f fineract-cluster.yaml
```

**Note:** This will create:
- VPC with public and private subnets across 3 AZs
- EKS control plane
- 2 t4g.medium worker nodes
- IAM OIDC provider (for IRSA)
- Security groups

### Step 2.2: Verify Cluster Access

```bash
# Update kubeconfig
aws eks update-kubeconfig --name fineract-dev --region us-east-2

# Verify access
kubectl get nodes
kubectl get namespaces
```

You should see 2 nodes in "Ready" state.

### Step 2.3: Get Cluster Information (Save These!)

```bash
# Get VPC ID
export CLUSTER_NAME="fineract-dev"
export VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "VPC_ID: $VPC_ID"

# Get Subnet IDs
export SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds" --output text)
echo "SUBNET_IDS: $SUBNET_IDS"

# Get Cluster Security Group
export CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
echo "CLUSTER_SG: $CLUSTER_SG"

# Get OIDC Provider URL
export OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text)
echo "OIDC_PROVIDER: $OIDC_PROVIDER"

# Save to file for later use
cat > cluster-info.txt <<EOF
VPC_ID=$VPC_ID
SUBNET_IDS=$SUBNET_IDS
CLUSTER_SG=$CLUSTER_SG
OIDC_PROVIDER=$OIDC_PROVIDER
EOF

echo "Cluster information saved to cluster-info.txt"
```

---

## Part 3: Provision AWS Infrastructure with Terraform (10-15 minutes)

### Step 3.1: Navigate to Terraform Directory

```bash
cd terraform/aws
```

### Step 3.2: Create Environment Configuration

```bash
# Copy the dev template
cp environments/dev.tfvars my-dev.tfvars

# Edit with your cluster information
# Replace the placeholders with actual values from cluster-info.txt
cat > my-dev.tfvars <<EOF
# Basic Configuration
cluster_name = "fineract-dev"
environment  = "dev"
aws_region   = "us-east-2"

# Network Configuration - REPLACE WITH YOUR VALUES
vpc_id               = "$VPC_ID"
database_subnet_ids  = [$(echo $SUBNET_IDS | tr '\t' ',' | sed 's/\([^,]*\)/"\1"/g')]
cache_subnet_ids     = [$(echo $SUBNET_IDS | tr '\t' ',' | sed 's/\([^,]*\)/"\1"/g')]

# EKS Configuration - REPLACE WITH YOUR VALUES
eks_cluster_security_group_id = "$CLUSTER_SG"
eks_oidc_provider_url         = "$OIDC_PROVIDER"

# Kubernetes
kubernetes_namespace = "fineract-dev"

# RDS Configuration - Cost Optimized for Dev
rds_postgres_version  = "15.14"  # Latest stable (see docs/VERSION_MATRIX.md)
rds_instance_class    = "db.t4g.micro"
rds_allocated_storage = 20
rds_max_allocated_storage = 50
rds_storage_type      = "gp3"

rds_database_name  = "fineract"
rds_master_username = "fineract"
rds_max_connections = "100"

rds_multi_az                = false
rds_backup_retention_period = 3
rds_performance_insights_enabled = true
rds_monitoring_interval          = 60
rds_deletion_protection = false

# Redis - Using in-cluster StatefulSet (no ElastiCache needed)
# This saves ~$11/month in managed service costs
# For production, consider using ElastiCache for high availability

# S3 Configuration
s3_enable_versioning            = true
s3_documents_lifecycle_enabled  = true
s3_backups_expiration_days      = 90
s3_enable_transfer_acceleration = false
s3_enable_intelligent_tiering   = false

# Tags
tags = {
  CostCenter  = "engineering"
  Team        = "platform"
  Purpose     = "development"
  AutoShutdown = "enabled"
}
EOF
```

### Step 3.3: Initialize Terraform

```bash
terraform init
```

You should see "Terraform has been successfully initialized!"

### Step 3.4: Plan Infrastructure

```bash
terraform plan -var-file=my-dev.tfvars -out=tfplan
```

Review the plan. It will create approximately:
- 1 RDS PostgreSQL instance (db.t4g.micro)
- 2 S3 buckets (documents, backups)
- 1 IAM role + policies (for IRSA)
- 2 Kubernetes secrets (rds-connection, s3-connection)
- 1 Kubernetes ServiceAccount (with IRSA annotation)
- Security groups, subnet groups, parameter groups

### Step 3.5: Apply Infrastructure

```bash
terraform apply tfplan
```

This takes **10-15 minutes** as RDS provisions.

Go grab a coffee! ☕

### Step 3.6: Save Terraform Outputs

```bash
# View all outputs
terraform output

# Save important outputs
terraform output -json > terraform-outputs.json

# View connection details
terraform output connection_details
```

---

## Part 4: Deploy Fineract Application (5 minutes)

### Step 4.1: Navigate to Repository Root

```bash
cd ../..  # Back to repository root
```

### Step 4.2: Verify Kubernetes Secrets Created by Terraform

```bash
kubectl get secrets -n fineract-dev
kubectl get serviceaccount fineract-aws -n fineract-dev
```

You should see:
- `rds-connection` secret
- `s3-connection` secret
- `fineract-aws` service account with IRSA annotation

### Step 4.3: Build and Review Configuration

```bash
# Build the dev-aws environment
kubectl kustomize environments/dev-aws > preview.yaml

# Review what will be deployed (optional)
less preview.yaml
```

### Step 4.4: Deploy Fineract

```bash
# Deploy everything
kubectl apply -k environments/dev-aws

# Watch the deployment
watch kubectl get pods -n fineract-dev
```

**Expected Resources:**
- Namespaces: fineract-dev, backup, observability
- Deployments: fineract-read, fineract-write, fineract-batch, oauth2-proxy, keycloak
- StatefulSets: redis (in-cluster caching), postgresql (scaled to 0 in AWS mode)
- Services, ConfigMaps, Secrets

### Step 4.5: Wait for Pods to be Ready

```bash
# Check pod status (may take 3-5 minutes)
kubectl get pods -n fineract-dev -w

# Check if all pods are running
kubectl get pods -n fineract-dev | grep -v Running
```

All pods should show "Running" status and "1/1" ready.

---

## Part 5: Initialize Fineract Database (5 minutes)

### Step 5.1: Check Fineract Logs

```bash
# Check fineract-write pod logs
kubectl logs -n fineract-dev -l app=fineract,component=write --tail=50
```

Look for:
- ✅ "HikariPool-1 - Start completed" (database connected)
- ✅ "Tomcat started on port" (application started)

### Step 5.2: Run Database Initialization (First Time Only)

Fineract will auto-initialize the database on first startup. Verify:

```bash
# Port-forward to fineract-write
kubectl port-forward -n fineract-dev svc/fineract-write 8443:8443 &

# Wait 30 seconds for port-forward to be ready
sleep 30

# Test health endpoint
curl -k https://localhost:8443/fineract-provider/actuator/health

# You should see: {"status":"UP"}
```


---

## Part 6: Access Fineract (5 minutes)

### Step 6.1: Expose Fineract Service

**Option A: Port-Forward (Quick Testing)**

```bash
# Forward fineract-write service
kubectl port-forward -n fineract-dev svc/fineract-write 8443:8443

# In another terminal, test API
curl -k -u mifos:password https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default"
```

**Option B: LoadBalancer (Public Access)**

```bash
# Patch oauth2-proxy service to LoadBalancer
kubectl patch svc oauth2-proxy -n fineract-dev -p '{"spec":{"type":"LoadBalancer"}}'

# Wait for external IP (takes 2-3 minutes)
kubectl get svc oauth2-proxy -n fineract-dev -w

# Get the external URL
export FINERACT_URL=$(kubectl get svc oauth2-proxy -n fineract-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Fineract URL: https://$FINERACT_URL"

# Test API (via OAuth2 Proxy)
curl -k -u mifos:password https://$FINERACT_URL/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default"
```

**Option C: Ingress with Domain (Production)**

See `docs/INGRESS-SETUP.md` for configuring:
- AWS ALB Ingress Controller
- Route53 DNS
- ACM certificates
- Custom domain

### Step 6.2: Default Credentials

**Fineract API:**
- Username: `mifos`
- Password: `password`
- Tenant ID: `default`

**⚠️ IMPORTANT:** Change these credentials before production use!

---

## Part 7: Deploy Frontend Applications (Optional, 5 minutes)

### Step 7.1: Build and Deploy Web Apps

```bash
# From repository root
cd environments/dev-aws

# Verify web apps are included
grep -A5 "web-apps" kustomization.yaml

# Web apps are already deployed with main deployment
kubectl get pods -n fineract-dev | grep web-app
```

### Step 7.2: Access Web Interface

```bash
# Port-forward web-app service
kubectl port-forward -n fineract-dev svc/fineract-web-app 8080:80

# Open in browser
open http://localhost:8080
```

**Login with:**
- Username: `mifos`
- Password: `password`

---

## Part 8: Verification & Testing (5 minutes)

### Step 8.1: Health Checks

```bash
# Check all services are healthy
kubectl get pods -n fineract-dev
kubectl get pods -n backup
kubectl get pods -n observability

# Check fineract health
kubectl exec -n fineract-dev deploy/fineract-write -- curl -s http://localhost:8080/fineract-provider/actuator/health
```

### Step 8.2: Database Connectivity

```bash
# Test RDS connection
kubectl exec -n fineract-dev deploy/fineract-write -- env | grep HIKARI

# Check connection pool
kubectl logs -n fineract-dev deploy/fineract-write | grep -i "hikari"
```

### Step 8.3: Redis Connectivity

```bash
# Check in-cluster Redis StatefulSet
kubectl get statefulset redis -n fineract-dev
kubectl get pods -n fineract-dev -l app=redis

# Test Redis connection from Fineract pod
kubectl exec -n fineract-dev deploy/fineract-write -- curl -s http://localhost:8080/fineract-provider/actuator/metrics/cache.size
```

### Step 8.4: S3 Connectivity (via IRSA)

```bash
# Verify S3 bucket access
aws s3 ls | grep fineract

# Test from pod (should work via IRSA - no credentials needed)
kubectl exec -n fineract-dev deploy/fineract-write -it -- \
  aws s3 ls s3://$(cd terraform/aws && terraform output -raw documents_bucket_name)/

# Verify IRSA role annotation
kubectl get sa fineract-aws -n fineract-dev -o yaml | grep eks.amazonaws.com/role-arn
```

### Step 8.5: Run Smoke Tests

```bash
# Test API endpoints
export FINERACT_URL="https://localhost:8443"
export FINERACT_TENANT="default"

# Get offices
curl -k -u mifos:password $FINERACT_URL/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: $FINERACT_TENANT"

# Get users
curl -k -u mifos:password $FINERACT_URL/fineract-provider/api/v1/users \
  -H "Fineract-Platform-TenantId: $FINERACT_TENANT"

# Get clients
curl -k -u mifos:password $FINERACT_URL/fineract-provider/api/v1/clients \
  -H "Fineract-Platform-TenantId: $FINERACT_TENANT"
```

---

## Part 9: Monitoring & Observability (Optional)

### Step 9.1: Deploy Prometheus & Grafana

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace

# Wait for pods to be ready
kubectl get pods -n observability -w
```

### Step 9.2: Access Grafana

```bash
# Get Grafana password
kubectl get secret -n observability monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# Port-forward Grafana
kubectl port-forward -n observability svc/monitoring-grafana 3000:80

# Open browser
open http://localhost:3000
# Username: admin
# Password: [from above command]
```

### Step 9.3: Import Fineract Dashboard

1. In Grafana, go to Dashboards → Import
2. Upload dashboard JSON from `operations/monitoring/dashboards/fineract-overview.json`
3. Select Prometheus datasource
4. Click Import

---

## Part 10: Cost Management

### Daily Costs (Development Environment)

```bash
# View AWS costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE

# Estimated monthly costs:
# - EKS Control Plane: $72/month ($0.10/hour)
# - EC2 (2x t4g.medium): ~$48/month
# - RDS (db.t4g.micro): ~$12/month
# - In-cluster Redis: $0/month (no managed service cost)
# - S3: ~$3-5/month
# - Data Transfer: ~$3-5/month
# TOTAL: ~$140-150/month (saving ~$11/month with in-cluster Redis)
```

### Cost Optimization Tips

**For Testing/Development:**
```bash
# Stop EKS nodes after hours (scale to 0)
eksctl scale nodegroup --cluster=fineract-dev --name=fineract-nodes --nodes=0

# Stop RDS
aws rds stop-db-instance --db-instance-identifier fineract-dev-fineract

# Resume when needed
eksctl scale nodegroup --cluster=fineract-dev --name=fineract-nodes --nodes=2
aws rds start-db-instance --db-instance-identifier fineract-dev-fineract
```

**Savings:**
- Stop nights/weekends: Save ~50% (~$70/month)
- Use Spot instances for EKS nodes: Save ~70% on compute
- Use Reserved Instances: Save 30-40% (1-year commitment)
- Using in-cluster Redis instead of ElastiCache: Save ~$11/month

---

## Troubleshooting

### Issue: Pods Stuck in Pending

```bash
# Check pod events
kubectl describe pod -n fineract-dev <pod-name>

# Common causes:
# - Insufficient node capacity → scale nodes
# - PVC not bound → check storage class
```

### Issue: Fineract Can't Connect to RDS

```bash
# Verify security group allows EKS cluster
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Check RDS endpoint
kubectl get secret rds-connection -n fineract-dev -o yaml

# Check pod can resolve RDS endpoint
kubectl exec -n fineract-dev deploy/fineract-write -- nslookup <rds-endpoint>

# Check RDS connection from pod
kubectl logs -n fineract-dev deploy/fineract-write | grep -i hikari
```

### Issue: IRSA Not Working

```bash
# Verify service account annotation
kubectl get sa fineract-aws -n fineract-dev -o yaml | grep eks.amazonaws.com/role-arn

# Verify pod is using service account
kubectl get pod -n fineract-dev <pod-name> -o yaml | grep serviceAccountName

# Check OIDC provider exists
aws iam list-open-id-connect-providers
```

### Issue: High Costs

```bash
# Check EC2 instance utilization
kubectl top nodes

# Check RDS utilization
aws rds describe-db-instances --db-instance-identifier fineract-dev-fineract \
  --query 'DBInstances[0].DBInstanceStatus'

# Consider downsizing if utilization < 50%
# Note: Already using in-cluster Redis to save ~$11/month vs ElastiCache
```

---

## Cleanup (When Done Testing)

### Step 1: Delete Kubernetes Resources

```bash
kubectl delete -k environments/dev-aws
```

### Step 2: Destroy Terraform Infrastructure

```bash
cd terraform/aws

# Empty S3 buckets first
aws s3 rm s3://$(terraform output -raw documents_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw backups_bucket_name) --recursive

# Destroy infrastructure
terraform destroy -var-file=my-dev.tfvars
```

### Step 3: Delete EKS Cluster

```bash
eksctl delete cluster --name fineract-dev --region us-east-2
```

**Total cleanup time:** ~15-20 minutes

---

## Next Steps

### Production Deployment

1. **Read production guides:**
   - `terraform/aws/README.md` - Production Terraform configuration
   - `docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md` - Multi-cloud provider support
   - `docs/AWS_COST_ANALYSIS.md` - Cost optimization
   - `docs/SECRETS_MANAGEMENT.md` - Security best practices

2. **Use production tfvars:**
   ```bash
   terraform apply -var-file=environments/production.tfvars
   ```

3. **Deploy to production environment:**
   ```bash
   kubectl apply -k environments/production-aws
   ```

4. **Set up monitoring:**
   - CloudWatch dashboards
   - PagerDuty/Opsgenie alerts
   - Log aggregation (ELK/Loki)

5. **Set up backups:**
   - RDS automated snapshots (enabled by default)
   - Velero for Kubernetes resources
   - S3 cross-region replication

### Multi-Cloud Deployment

To deploy on Azure or GCP instead:

```bash
# Azure
kubectl apply -k environments/dev-azure

# GCP
kubectl apply -k environments/dev-gcp
```

See `docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md` for details on multi-cloud deployment.

---

## Support

- **Documentation:** See `/docs` directory
- **Issues:** GitHub issues
- **Fineract Docs:** https://fineract.apache.org
- **AWS Support:** https://aws.amazon.com/support/

---

## Summary

You now have a fully functional Fineract deployment on AWS with:

✅ EKS Kubernetes cluster
✅ RDS PostgreSQL 15.x database
✅ In-cluster Redis StatefulSet for caching
✅ S3 document storage with IRSA
✅ OAuth2 Proxy + Keycloak for authentication
✅ Fineract application (read, write, batch)
✅ Web applications (optional)
✅ Monitoring stack (optional)
✅ Secure IRSA authentication (no static credentials)
✅ Cost-optimized configuration (~$140-150/month)

**Total Time:** 45-60 minutes
**Next:** Start building your fintech application! 🚀
