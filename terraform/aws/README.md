# Fineract AWS Infrastructure - Terraform

This Terraform configuration provisions AWS managed services for Apache Fineract, including RDS PostgreSQL, S3 storage, IAM roles with IRSA (IAM Roles for Service Accounts), and ElastiCache Redis. The ElastiCache Redis is provisioned by this module, not an in-cluster StatefulSet.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Account                          │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐                    │
│  │   EKS/K3s    │     │     RDS      │                    │
│  │   Cluster    │────▶│  PostgreSQL  │                    │
│  │              │     │  (Multi-AZ)  │                    │
│  │  ┌────────┐  │     └──────────────┘                    │
│  │  │ Redis  │  │                                          │
│  │  │(in-pod)│  │     ┌──────────────┐                    │
│  │  └────────┘  │     │      S3      │                    │
│  │              │────▶│   Buckets    │                    │
│  └──────────────┘     │ (Versioned)  │                    │
│                        └──────────────┘                    │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐                    │
│  │     IAM      │     │  Kubernetes  │                    │
│  │  IRSA Role   │────▶│   Secrets    │                    │
│  │              │     │              │                    │
│  └──────────────┘     └──────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

## What Gets Provisioned

### 1. RDS PostgreSQL
- **Purpose**: Primary database for Fineract
- **Features**:
  - Multi-AZ deployment (production)
  - Automated backups (7-30 days retention)
  - Performance Insights
  - Enhanced monitoring
  - Encryption at rest
  - Security group with EKS access only
  - Parameter group optimized for Fineract

### 2. S3 Buckets
- **Purpose**: Document storage and backups
- **Buckets Created**:
  - `{cluster}-{env}-fineract-documents`: Client documents
  - `{cluster}-{env}-fineract-backups`: Database backups
- **Features**:
  - Versioning enabled
  - Lifecycle policies (transition to Glacier, expiration)
  - Encryption at rest
  - Public access blocked
  - Optional Transfer Acceleration
  - Optional Intelligent Tiering

### 3. IAM IRSA Role
- **Purpose**: Secure access from Kubernetes pods to AWS services
- **Permissions**:
  - RDS: Describe instances, connect via IAM auth
  - S3: Read/write to documents and backups buckets
  - KMS: Encrypt/decrypt (if customer-managed keys used)

### 4. Kubernetes Resources
- **ServiceAccount**: `fineract-aws` with IRSA annotation
- **Secrets**: Connection details for RDS, Redis, S3
  - `aws-rds-credentials` - RDS endpoint
  - `fineract-db-credentials` - Database username/password
  - `fineract-redis-credentials` - Redis connection (in-cluster service)
  - `s3-connection` - S3 bucket configuration

**Note:** Redis runs in-cluster via StatefulSet (deployed via ArgoCD), not AWS ElastiCache

## Prerequisites

### 1. Required Tools

Install and verify these tools before proceeding:

| Tool | Minimum Version | Check Command | Installation |
|------|----------------|---------------|--------------|
| Terraform | >= 1.5.0 | `terraform version` | [terraform.io](https://terraform.io) or `brew install terraform` |
| AWS CLI | >= 2.0 | `aws --version` | [AWS CLI](https://aws.amazon.com/cli/) or `brew install awscli` |
| kubectl | >= 1.27 | `kubectl version --client` | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) or `brew install kubectl` |
| make | Any | `make --version` | Pre-installed on macOS/Linux |

**Quick Validation**: Run `make validate-terraform` from the repository root to check all prerequisites automatically.

### 2. AWS Account Setup
- AWS account with appropriate permissions (see [Required IAM Permissions](#required-iam-permissions))
- AWS CLI configured with credentials: `aws configure`
- AWS credentials must have permissions to create:
  - EKS clusters, VPCs, Security Groups
  - RDS instances
  - S3 buckets
  - IAM roles and policies
  - Route53 records (if using custom domain)
  - SES (if email enabled)
- Sufficient service quotas for:
  - RDS instances
  - S3 buckets
  - EKS clusters

**Verify AWS credentials**: The Makefile will automatically validate your AWS credentials are working:
```bash
make validate-terraform
```

### 3. Kubernetes Cluster
- EKS cluster (recommended) or K3s cluster must be running
- For EKS: OIDC provider must be configured for IRSA
- `kubectl` configured to access the cluster: `kubectl cluster-info`
- For K3s: Manual kubeconfig setup required

### 4. Network Infrastructure
- VPC with private subnets (for RDS)
- Cluster security group ID
- Subnet IDs for database tier

### 5. Terraform Backend (State Storage)
- S3 bucket for storing Terraform state
- DynamoDB table for state locking
- **Setup**: Run `make setup-terraform-backend` to create these automatically

## Quick Start with Make (Recommended)

The easiest way to work with Terraform is using the provided Makefile targets. This handles environment-specific configurations automatically.

### Step 1: Validate Prerequisites
```bash
# From repository root
make validate-terraform
```

This will check:
- ✅ Terraform version (>= 1.5.0)
- ✅ AWS CLI configuration
- ✅ AWS credentials validity
- ✅ kubectl installation
- ✅ Terraform backend accessibility

### Step 2: Setup Terraform Backend (First Time Only)
```bash
make setup-terraform-backend
```

This creates:
- S3 bucket for Terraform state storage
- DynamoDB table for state locking
- Proper IAM permissions

### Step 3: Initialize Terraform for Your Environment
```bash
# For development
make terraform-init-dev

# For UAT
make terraform-init-uat

# For production
make terraform-init-prod
```

### Step 4: Plan Infrastructure Changes
```bash
# Review what will be created
make terraform-plan-dev
```

This will:
- Load the correct environment variables from `environments/dev-eks.tfvars`
- Generate a plan showing all resources to be created
- Save the plan to `tfplan-dev` for review

### Step 5: Apply Infrastructure
```bash
# Apply the planned changes
make terraform-apply-dev
```

This will:
- Verify the plan file exists
- Apply infrastructure changes
- Create EKS cluster, RDS, S3, IAM resources
- Take 15-20 minutes for initial deployment

### Step 6: Generate Sealed Secrets
```bash
# After Terraform completes
make seal-terraform-secrets ENV=dev
```

### Step 7: View Terraform Outputs
```bash
# Check connection details
make terraform-output-dev
```

### Available Makefile Targets

| Target | Description |
|--------|-------------|
| `make validate-terraform` | Validate all prerequisites |
| `make setup-terraform-backend` | Create S3 backend and DynamoDB table |
| `make terraform-init-{env}` | Initialize Terraform for environment |
| `make terraform-plan-{env}` | Plan infrastructure changes |
| `make terraform-apply-{env}` | Apply infrastructure changes |
| `make terraform-destroy-{env}` | Destroy infrastructure |
| `make terraform-output-{env}` | Show Terraform outputs |

**Supported environments**: `dev`, `uat`, `prod`

---

## Manual Terraform Workflow (Alternative)

If you prefer to run Terraform commands directly instead of using Make:

### Step 1: Clone Repository
```bash
cd terraform/aws
```

### Step 2: Get Your EKS Cluster Information
```bash
# Get VPC ID
export CLUSTER_NAME="your-cluster-name"
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text

# Get Subnet IDs
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds" --output text

# Get Cluster Security Group
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text

# Get OIDC Provider URL
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text
```

### Step 3: Configure Environment Variables
Create a `terraform.tfvars` file or use an environment file:

```bash
cp environments/dev.tfvars terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
cluster_name = "your-cluster-name"
environment  = "dev"
vpc_id       = "${VPC_ID}"
database_subnet_ids = ["${SUBNET_ID_1}", "${SUBNET_ID_2}"]
cache_subnet_ids    = ["${SUBNET_ID_1}", "${SUBNET_ID_2}"]
eks_cluster_security_group_id = "${EKS_SECURITY_GROUP_ID}"
eks_oidc_provider_url = "${EKS_OIDC_PROVIDER_URL}"
```

### Step 4: Configure Terraform Remote State (Recommended)

For team collaboration and state locking, configure an S3 backend. Create or update `providers.tf` (or `main.tf`) with the following, replacing placeholders with your actual bucket and key:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket" # Replace with your S3 bucket name
    key            = "fineract/dev/terraform.tfstate" # Unique path for this environment's state
    region         = "us-east-2" # Your AWS region
    dynamodb_table = "terraform-state-lock" # DynamoDB table for state locking
    encrypt        = true
  }
}
```
Ensure the `terraform-state-lock` DynamoDB table exists as described in the [State Management](#state-management) section.

### Step 5: Initialize Terraform
```bash
terraform init
```

### Step 5: Plan Infrastructure
```bash
terraform plan -out=tfplan
```

Review the plan carefully. It will create:
- 1 RDS instance
- 1 ElastiCache replication group
- 2 S3 buckets
- 1 IAM role + 4 IAM policies
- 3 Kubernetes secrets
- 1 Kubernetes service account
- Various security groups, subnet groups, parameter groups

### Step 6: Apply Infrastructure
```bash
terraform apply tfplan
```

This will take **10-15 minutes** as RDS and ElastiCache provision.

### Step 7: Verify Deployment
```bash
# Check RDS
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw rds_instance_endpoint | cut -d: -f1)

# Check ElastiCache
aws elasticache describe-replication-groups --replication-group-id $(terraform output -raw elasticache_replication_group_id)

# Check S3 buckets
aws s3 ls | grep fineract

# Check Kubernetes secrets
kubectl get secrets -n fineract-dev
kubectl get serviceaccount fineract-aws -n fineract-dev
```

### Step 8: Deploy Fineract
```bash
# Navigate to environments
cd ../../environments

# Deploy with AWS provider
kubectl apply -k dev-aws
```

## Cost Estimates

### Development Environment
Using `environments/dev.tfvars` configuration:

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| RDS | db.t4g.micro, 20GB | ~$12 |
| ElastiCache | cache.t4g.micro x1 | ~$11 |
| S3 | ~100GB documents | ~$3 |
| Data Transfer | Moderate | ~$3 |
| Backups | 20GB | ~$1 |
| **Total** | | **~$30/month** |

### Production Environment
Using `environments/production.tfvars` configuration:

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| RDS | db.r6g.large Multi-AZ, 100GB | ~$380 |
| ElastiCache | cache.r6g.large x3 | ~$240 |
| S3 | ~500GB documents | ~$15 |
| Data Transfer | High | ~$30 |
| Backups | 100GB | ~$10 |
| **Total** | | **~$675/month** |

**Cost Optimization Tips:**
- Use Reserved Instances for 30-40% discount (1-year commitment)
- Use Graviton (ARM) instances for 20% savings
- Enable S3 Intelligent Tiering
- Review and adjust instance sizes based on actual usage

## Module Structure

```
terraform/aws/
├── main.tf                     # Root module composition
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── providers.tf                # Provider configuration
├── README.md                   # This file
│
├── environments/               # Environment-specific configurations
│   ├── dev.tfvars             # Development settings
│   └── production.tfvars       # Production settings
│
└── modules/                    # Reusable modules
    ├── rds/                    # RDS PostgreSQL module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── elasticache/            # ElastiCache Redis module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── s3/                     # S3 buckets module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── iam/                    # IAM IRSA module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── kubernetes-secret/      # Kubernetes secrets module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Configuration Options

### Environment Selection

**Development** (cost-optimized):
```bash
terraform apply -var-file=environments/dev.tfvars
```

**Production** (HA-optimized):
```bash
terraform apply -var-file=environments/production.tfvars
```

### Custom Configuration

Override specific variables:
```bash
terraform apply \
  -var="rds_instance_class=db.t4g.medium" \
  -var="redis_num_cache_clusters=2"
```

### High Availability

Enable Multi-AZ for production:
```hcl
rds_multi_az = true
redis_num_cache_clusters = 3  # Primary + 2 replicas
```

### Security Enhancements

Enable encryption in transit for Redis:
```hcl
redis_encryption_in_transit = true
redis_auth_token_enabled    = true
```

Use customer-managed KMS keys:
```hcl
kms_key_id = "${KMS_KEY_ARN}"
```

## Outputs

After `terraform apply`, retrieve outputs:

```bash
# Connection endpoints
terraform output rds_instance_endpoint
terraform output elasticache_primary_endpoint

# Bucket names
terraform output documents_bucket_name
terraform output backups_bucket_name

# IAM role for IRSA
terraform output irsa_role_arn

# All connection details
terraform output connection_details
```

## Maintenance

### Backup and Restore

**RDS Backups:**
```bash
# List automated backups
aws rds describe-db-snapshots \
  --db-instance-identifier $(terraform output -raw rds_instance_endpoint | cut -d: -f1)

# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier fineract-dev-fineract \
  --db-snapshot-identifier fineract-dev-manual-$(date +%Y%m%d)
```

**S3 Backups:**
```bash
# Sync backups bucket locally
aws s3 sync s3://$(terraform output -raw backups_bucket_name) ./local-backups/
```

### Monitoring

**RDS Performance Insights:**
```bash
# Open in AWS Console
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_endpoint | cut -d: -f1) \
  --query "DBInstances[0].PerformanceInsightsEnabled"
```

**ElastiCache Metrics:**
```bash
# Get CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name CPUUtilization \
  --dimensions Name=CacheClusterId,Value=fineract-dev-fineract-001 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Scaling

**Vertical Scaling (instance size):**
```hcl
# Update terraform.tfvars
rds_instance_class = "db.r6g.xlarge"  # Upgrade
redis_node_type    = "cache.r6g.xlarge"

# Apply changes
terraform apply
```

**Horizontal Scaling (read replicas):**
```hcl
# Add more Redis replicas
redis_num_cache_clusters = 5  # 1 primary + 4 replicas
```

### Security Updates

**Update PostgreSQL version:**
```hcl
rds_postgres_version = "15.14"  # Latest stable version (see docs/VERSION_MATRIX.md)
```

**Update Redis version:**
```hcl
redis_version = "7.1"
```

Apply with care during maintenance windows.

## Troubleshooting

### Issue: Prerequisite Validation Fails

Run `make validate-terraform` to diagnose common issues:

**Error:** `✗ Terraform version X.Y.Z is below required 1.5.0`

**Solution:**
```bash
# Upgrade Terraform
brew upgrade terraform
# Or download from https://terraform.io
```

**Error:** `✗ AWS credentials invalid or not configured`

**Solution:**
```bash
# Configure AWS CLI
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"

# Verify credentials work
aws sts get-caller-identity
```

**Error:** `⚠ AWS region not configured`

**Solution:**
```bash
aws configure set region us-east-1
```

**Error:** `⚠ Terraform backend bucket not accessible`

**Solution:**
```bash
# Create backend infrastructure
make setup-terraform-backend

# Or verify bucket exists
aws s3 ls s3://your-terraform-state-bucket
```

### Issue: Terraform Init Fails

**Error:** "Failed to download provider"

**Solution:**
```bash
terraform init -upgrade
```

### Issue: RDS Connection Timeout

**Error:** Fineract pods can't connect to RDS

**Check:**
1. Security group allows EKS cluster SG:
   ```bash
   aws ec2 describe-security-groups \
     --group-ids $(terraform output -raw rds_security_group_id)
   ```

2. RDS is in correct subnets:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier fineract-dev-fineract \
     --query "DBInstances[0].DBSubnetGroup.Subnets[*].SubnetIdentifier"
   ```

3. Kubernetes secret exists:
   ```bash
   kubectl get secret rds-connection -n fineract-dev -o yaml
   ```

### Issue: IRSA Not Working

**Error:** "An error occurred (AccessDenied) when calling..."

**Check:**
1. Service account has annotation:
   ```bash
   kubectl get sa fineract-aws -n fineract-dev -o yaml
   ```

2. Pod is using the service account:
   ```bash
   kubectl get pod <pod-name> -n fineract-dev -o yaml | grep serviceAccountName
   ```

3. IAM role trust policy is correct:
   ```bash
   aws iam get-role --role-name $(terraform output -raw irsa_role_name)
   ```

### Issue: S3 Access Denied

**Check IAM policy:**
```bash
aws iam list-attached-role-policies --role-name $(terraform output -raw irsa_role_name)
```

**Test S3 access from pod:**
```bash
kubectl run -it --rm aws-cli --image=amazon/aws-cli --serviceaccount=fineract-aws -n fineract-dev -- \
  s3 ls s3://$(terraform output -raw documents_bucket_name)/
```

## Cleanup

### Destroy Infrastructure

```bash
# Review what will be deleted
terraform plan -destroy

# Destroy everything
terraform destroy

# Or use specific var file
terraform destroy -var-file=environments/dev.tfvars
```

**Warning:** This will:
- Delete RDS instance (final snapshot will be created unless skip_final_snapshot=true)
- Delete ElastiCache cluster (final snapshot will be created)
- Delete S3 buckets (will fail if buckets contain objects)

### Delete S3 Buckets with Contents

```bash
# Empty buckets first
aws s3 rm s3://$(terraform output -raw documents_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw backups_bucket_name) --recursive

# Then destroy
terraform destroy
```

## State Management

### Remote State (Recommended for Teams)

Configure S3 backend in `providers.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "fineract/dev/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

### State Locking

Create DynamoDB table:
```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

## Best Practices

1. **Always use `-var-file` for environment-specific configurations**
2. **Enable deletion protection in production** (`rds_deletion_protection=true`)
3. **Use Multi-AZ for production workloads**
4. **Enable encryption at rest and in transit**
5. **Use customer-managed KMS keys for compliance**
6. **Configure backup retention appropriately** (30 days for production)
7. **Tag all resources consistently** (use `tags` variable)
8. **Use Remote State with locking for team collaboration**
9. **Review costs regularly** with AWS Cost Explorer
10. **Test disaster recovery procedures** periodically

## Support

- **Terraform Issues**: Check [Terraform AWS Provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- **AWS Issues**: Contact AWS Support or check AWS documentation
- **Fineract Issues**: See main repository README

## License

Apache License 2.0 - See main repository for details.
