# EKS Deployment Guide

Complete guide for deploying Fineract on AWS EKS using GitOps and Infrastructure as Code.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Manual Deployment Steps](#manual-deployment-steps)
4. [Configuration Management](#configuration-management)
5. [Post-Deployment](#post-deployment)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

Install the following tools before starting:

```bash
# AWS CLI
brew install awscli

# Terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# kubectl
brew install kubectl

# Sealed Secrets CLI
brew install kubeseal

# ArgoCD CLI
brew install argocd

# jq (JSON processor)
brew install jq
```

### AWS Configuration

1. **AWS Credentials**: Configure AWS CLI with admin access
   ```bash
   aws configure
   # Enter your Access Key ID, Secret Access Key, Region (us-east-2)
   ```

2. **Verify Access**:
   ```bash
   aws sts get-caller-identity
   aws eks list-clusters --region us-east-2
   ```

### GitHub Access Token

For GitOps deployment, you need a GitHub Personal Access Token:

1. Create token at: https://github.com/settings/tokens
2. Scope required: `repo` (Full control of private repositories)
3. Store securely in macOS Keychain (see [GitHub Token Setup](GITHUB_TOKEN_SETUP.md))

## Quick Start

### Automated Deployment

For a complete automated deployment:

```bash
# Clone the repository
git clone https://github.com/ADORSYS-GIS/fineract-gitops.git
cd fineract-gitops

# Deploy dev environment with GitOps
./scripts/deploy-eks-environment.sh dev --gitops

# Or deploy directly (without ArgoCD Git sync)
./scripts/deploy-eks-environment.sh dev --direct
```

The script will:
1. Setup Terraform backend (S3 + DynamoDB)
2. Deploy AWS infrastructure (EKS, RDS, S3, VPC)
3. Configure kubectl
4. Install ArgoCD and Sealed Secrets
5. Create and apply sealed secrets
6. Deploy applications
7. Display endpoints

## Manual Deployment Steps

If you prefer step-by-step deployment or need to troubleshoot:

### Step 1: Setup Terraform Backend

```bash
cd terraform/aws

# Create S3 backend (idempotent)
../../scripts/setup-terraform-backend.sh
```

### Step 2: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file=environments/dev-eks.tfvars

# Apply infrastructure
terraform apply -var-file=environments/dev-eks.tfvars
```

**Resources Created**:
- EKS Cluster (Kubernetes 1.31)
- 2x t3.large worker nodes (auto-scaling 2-4)
- RDS PostgreSQL database
- S3 buckets (documents, backups)
- VPC with public/private subnets
- IRSA roles for pod-level AWS access
- EKS add-ons (VPC CNI, CoreDNS, EBS CSI, CloudWatch)

### Step 3: Validate Infrastructure

```bash
# Validate all Terraform outputs
../../scripts/validate-terraform-outputs.sh dev

# Check specific outputs
terraform output eks_cluster_name
terraform output rds_instance_endpoint
terraform output documents_bucket_name
```

### Step 4: Configure kubectl

```bash
# Get cluster name from Terraform
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)

# Update kubeconfig
aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-2

# Verify access
kubectl get nodes
kubectl cluster-info
```

### Step 5: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### Step 6: Install Sealed Secrets Controller

```bash
# Install controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/controller.yaml

# Wait for controller
kubectl wait --for=condition=available --timeout=120s deployment/sealed-secrets-controller -n kube-system

# Verify
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Step 7: Create Sealed Secrets

```bash
# Create all sealed secrets from Terraform outputs
../../scripts/seal-terraform-secrets-enhanced.sh dev

# Apply to cluster
kubectl apply -f ../../secrets/dev/namespace.yaml
kubectl apply -f ../../secrets/dev/ --recursive

# Verify secrets were decrypted
kubectl get secrets -n fineract-dev
```

### Step 8: Configure ArgoCD

```bash
# Apply project
kubectl apply -f ../../argocd/projects/project-dev.yaml

# Apply configuration
kubectl apply -f ../../argocd/config/argocd-cm.yaml
kubectl apply -f ../../argocd/config/argocd-rbac-cm.yaml

# Restart ArgoCD server
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd
```

### Step 9: Configure GitHub Credentials

```bash
# Create sealed secret for GitHub access
../../scripts/seal-argocd-github-credentials.sh

# Apply to cluster
kubectl apply -f ../../secrets/system/argocd-repo-credentials-sealed.yaml

# Verify
kubectl get secret repo-fineract-gitops -n argocd
```

### Step 10: Deploy Applications

**Option A: GitOps (Recommended)**

```bash
# Deploy app-of-apps
kubectl apply -f ../../argocd/bootstrap/dev/app-of-apps.yaml

# Monitor sync
kubectl get applications -n argocd -w

# Or use ArgoCD CLI
argocd app list
argocd app get fineract-dev-app-of-apps
argocd app sync fineract-dev-app-of-apps
```

**Option B: Direct Deployment**

```bash
# Deploy using kustomize
kubectl apply -k ../../environments/dev/

# Monitor pods
kubectl get pods -n fineract-dev -w
```

### Step 11: Wait for LoadBalancer

```bash
# Wait for AWS NLB provisioning (5-10 minutes)
../../scripts/wait-for-loadbalancer.sh dev

# Check services
kubectl get svc -n fineract-dev
```

### Step 12: Verify IRSA

```bash
# Verify IRSA credentials work
../../scripts/verify-irsa-credentials.sh dev
```

### Step 13: Get Endpoints

```bash
# Display all application endpoints
../../scripts/get-endpoints.sh dev
```

## Configuration Management

### Centralized Repository Configuration

All ArgoCD repository URLs and branch configurations are centralized in:
```
argocd/config/repository-config.yaml
```

#### Changing Branch Configuration

To deploy from a different branch (e.g., from `eks` to `develop`):

1. **Edit configuration**:
   ```bash
   vi argocd/config/repository-config.yaml
   ```

   Change:
   ```yaml
   TARGET_REVISION_DEV: "eks"
   ```

   To:
   ```yaml
   TARGET_REVISION_DEV: "develop"
   ```

2. **Apply changes**:
   ```bash
   ./scripts/update-argocd-config.sh

   # Review changes
   git diff argocd/

   # Commit
   git add argocd/
   git commit -m "chore: update dev environment to develop branch"
   git push
   ```

3. **Sync ArgoCD**:
   ```bash
   # ArgoCD will auto-sync if configured, or manually:
   argocd app sync fineract-dev-app-of-apps
   ```

### Environment-Specific Configuration

Each environment has its own configuration:

- **Dev**: `terraform/aws/environments/dev-eks.tfvars`
- **UAT**: `terraform/aws/environments/uat-eks.tfvars`
- **Production**: `terraform/aws/environments/production-eks.tfvars`

### Sealed Secrets Management

Sealed secrets are environment-specific and stored in:
```
secrets/dev/
secrets/uat/
secrets/production/
```

**Regenerating secrets** after Terraform changes:
```bash
./scripts/seal-terraform-secrets-enhanced.sh dev
kubectl apply -f secrets/dev/ --recursive
```

## Post-Deployment

### Access ArgoCD UI

```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
echo "Admin password: $ARGOCD_PASSWORD"

# Open browser
open https://localhost:8080
```

### Access Fineract API

```bash
# Get LoadBalancer DNS
FINERACT_URL=$(kubectl get svc -n fineract-dev -l app=fineract-write -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test API
curl https://$FINERACT_URL/fineract-provider/api/v1/self
```

### Monitor Pods

```bash
# Watch all pods
kubectl get pods -n fineract-dev -w

# Check specific deployment
kubectl get deployment fineract-write -n fineract-dev

# View logs
kubectl logs -n fineract-dev -l app=fineract-write --tail=100 -f
```

### CloudWatch Monitoring

See [CloudWatch Monitoring Guide](CLOUDWATCH_MONITORING.md) for:
- Container Insights setup
- Log queries
- Metrics and alarms
- Cost optimization

## Troubleshooting

### Common Issues

#### 1. ArgoCD Can't Sync - Authentication Error

**Error**: `authentication required: Repository not found`

**Solution**:
```bash
# Check if GitHub credentials exist
kubectl get secret repo-fineract-gitops -n argocd

# If missing, create them
./scripts/seal-argocd-github-credentials.sh
kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml

# Restart ArgoCD
kubectl rollout restart deployment/argocd-server -n argocd
```

#### 2. Sealed Secret Won't Decrypt

**Error**: Secret not appearing after applying SealedSecret

**Solution**:
```bash
# Check Sealed Secrets controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify certificate matches
kubeseal --fetch-cert > /tmp/current-cert.pem

# If certificate changed, regenerate secrets
./scripts/seal-terraform-secrets-enhanced.sh dev
kubectl apply -f secrets/dev/ --recursive
```

#### 3. Terraform State Locked

**Error**: `Error acquiring the state lock`

**Solution**:
```bash
# List locks
aws dynamodb scan --table-name fineract-gitops-terraform-lock

# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
```

#### 4. Pods Can't Access RDS

**Error**: Connection timeout to RDS

**Solution**:
```bash
# Check security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*fineract-dev*"

# Check RDS security group allows EKS nodes
# Verify IRSA credentials
./scripts/verify-irsa-credentials.sh dev

# Check pod can resolve DNS
kubectl run -it --rm debug --image=busybox --restart=Never -n fineract-dev -- nslookup <RDS_ENDPOINT>
```

#### 5. LoadBalancer Not Provisioning

**Error**: Service stuck in pending state

**Solution**:
```bash
# Check AWS Load Balancer Controller
kubectl get pods -n kube-system | grep aws-load-balancer

# Check service events
kubectl describe svc <SERVICE_NAME> -n fineract-dev

# Verify subnet tags
aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/role/elb,Values=1"
```

### Complete Troubleshooting Guide

For comprehensive troubleshooting, see:
- [EKS Troubleshooting Guide](TROUBLESHOOTING_EKS.md)
- [GitHub Token Setup](GITHUB_TOKEN_SETUP.md)

## Cleanup

### Destroy Environment

```bash
cd terraform/aws

# Destroy infrastructure
terraform destroy -var-file=environments/dev-eks.tfvars

# Remove kubectl config
kubectl config delete-context arn:aws:eks:us-east-2:<ACCOUNT_ID>:cluster/fineract-dev

# Clean up sealed secrets
kubectl delete namespace fineract-dev
```

### Preserve Data

Before destroying:

1. **Backup RDS**: Take final snapshot
   ```bash
   aws rds create-db-snapshot \
     --db-instance-identifier fineract-dev-dev-fineract \
     --db-snapshot-identifier fineract-dev-final-snapshot
   ```

2. **Backup S3**: Download critical data
   ```bash
   aws s3 sync s3://fineract-dev-dev-fineract-documents ./backups/documents/
   aws s3 sync s3://fineract-dev-dev-fineract-backups ./backups/backups/
   ```

## Additional Resources

- [EKS Implementation Status](EKS_IMPLEMENTATION_STATUS.md)
- [EKS Migration Plan](EKS_MIGRATION_PLAN.md)
- [AWS IAM Requirements](AWS_IAM_REQUIREMENTS.md)
- [CloudWatch Monitoring](CLOUDWATCH_MONITORING.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues or questions:
1. Check [Troubleshooting Guide](TROUBLESHOOTING_EKS.md)
2. Review ArgoCD application status: `kubectl get applications -n argocd`
3. Check pod logs: `kubectl logs -n fineract-dev <POD_NAME>`
4. Open an issue in the repository

## Change Log

- **2025-11-13**: Initial EKS deployment guide created
- Branch configuration centralized in `argocd/config/repository-config.yaml`
- Automated deployment via `deploy-eks-environment.sh`
- GitOps and direct deployment modes supported
