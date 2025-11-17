# Terraform Destroy Guide - Complete AWS Resource Cleanup

**⚠️ WARNING: This will DELETE ALL AWS resources and is IRREVERSIBLE!**

This guide helps you safely destroy all Terraform-managed AWS infrastructure.

---

## What Will Be Deleted?

### AWS Resources Created by Terraform

**Database & Storage:**
- ✅ RDS PostgreSQL instance (Fineract + Keycloak databases)
- ✅ RDS subnet group
- ✅ RDS security group
- ✅ RDS parameter group
- ✅ RDS monitoring IAM role
- ✅ S3 buckets (documents, backups, artifacts)
- ✅ S3 bucket policies

**Networking:**
- ✅ VPC (if created by Terraform)
- ✅ Public subnets (2 availability zones)
- ✅ Private subnets (2 availability zones)
- ✅ Internet Gateway
- ✅ NAT Gateway
- ✅ Elastic IP for NAT Gateway
- ✅ Route tables
- ✅ VPC Flow Logs
- ✅ CloudWatch Log Group for VPC Flow Logs

**Security & Access:**
- ✅ IAM roles (Fineract service role, RDS monitoring)
- ✅ IAM policies (RDS, S3, KMS, SES access)
- ✅ IAM role policy attachments
- ✅ Security groups

**Secrets Management:**
- ✅ AWS Secrets Manager secrets (5 secrets):
  - `fineract-dev-fineract-dev-db-credentials`
  - `fineract-dev-fineract-dev-keycloak-db-credentials`
  - `fineract-dev-fineract-dev-keycloak-admin-credentials`
  - `fineract-dev-fineract-dev-oauth2-proxy-secrets`
  - `fineract-dev-fineract-dev-s3-connection`

**Email (if enabled):**
- ✅ SES email identities
- ✅ SES domain identity
- ✅ SES DKIM records
- ✅ SES configuration set
- ✅ SES IAM user for SMTP
- ✅ SES IAM access keys

**Note:** EKS cluster (if you created one) is NOT managed by this Terraform and won't be deleted.

---

## Cost Impact

**Before Destroying - Understand Your Costs:**

| Resource | Monthly Cost (Approx) | Total for Dev Env |
|----------|----------------------|-------------------|
| RDS PostgreSQL (db.t3.medium) | ~$60-80 | Included |
| S3 Storage (100GB) | ~$2-3 | Included |
| NAT Gateway | ~$32 | Included |
| Elastic IP (NAT) | ~$3.60 | Included |
| VPC Flow Logs | ~$5 | Included |
| AWS Secrets Manager (5 secrets) | ~$2 | Included |
| Data Transfer | ~$5-10 | Variable |
| **Total** | **~$110-140/month** | **Savings after destroy** |

**After Destroying:**
- 💰 Save ~$110-140/month
- ✅ No ongoing charges
- ⚠️ Lose all data in RDS and S3

---

## Pre-Destruction Checklist

### Step 1: Backup Critical Data

**⚠️ CRITICAL: Backup before destroying!**

```bash
# 1. Backup RDS databases
cd terraform/aws
RDS_ENDPOINT=$(terraform output -raw rds_instance_endpoint | cut -d: -f1)
RDS_PASSWORD=$(terraform output -raw rds_master_password)

# Backup Fineract database
pg_dump -h $RDS_ENDPOINT -U fineract -d fineract -f fineract-backup-$(date +%Y%m%d).sql

# Backup Keycloak database
pg_dump -h $RDS_ENDPOINT -U keycloak -d keycloak -f keycloak-backup-$(date +%Y%m%d).sql

# 2. Backup S3 data
aws s3 sync s3://$(terraform output -raw documents_bucket_name) ./s3-backup-documents/
aws s3 sync s3://$(terraform output -raw backups_bucket_name) ./s3-backup-backups/

# 3. Backup Terraform state
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# 4. Export AWS Secrets Manager secrets (for reference)
aws secretsmanager get-secret-value \
  --secret-id fineract-dev-fineract-dev-db-credentials \
  --query SecretString --output text > secrets-backup-$(date +%Y%m%d).json
```

### Step 2: Verify What Will Be Destroyed

```bash
cd terraform/aws

# See destruction plan (doesn't actually destroy anything)
terraform plan -destroy -var-file=environments/dev.tfvars

# Count resources to be destroyed
terraform plan -destroy -var-file=environments/dev.tfvars | grep "Plan:"
# Should show something like: "Plan: 0 to add, 0 to change, 45 to destroy."
```

### Step 3: Check for Dependencies

```bash
# Check if any Kubernetes resources are still using AWS resources
kubectl get pods -n fineract-dev
kubectl get pvc -n fineract-dev

# If pods are running, they may be accessing RDS/S3
# Recommended: Delete Kubernetes resources first
kubectl delete namespace fineract-dev
```

---

## Destruction Methods

### Method 1: Safe Incremental Destruction (Recommended)

Destroy resources in reverse dependency order:

```bash
cd terraform/aws

# 1. Delete application-level resources first
terraform destroy \
  -target=aws_secretsmanager_secret_version.fineract_db \
  -target=aws_secretsmanager_secret_version.keycloak_db \
  -target=aws_secretsmanager_secret_version.keycloak_admin \
  -target=aws_secretsmanager_secret_version.oauth2_proxy \
  -target=aws_secretsmanager_secret_version.s3_connection \
  -var-file=environments/dev.tfvars

# 2. Delete Secrets Manager secrets
terraform destroy \
  -target=aws_secretsmanager_secret.fineract_db \
  -target=aws_secretsmanager_secret.keycloak_db \
  -target=aws_secretsmanager_secret.keycloak_admin \
  -target=aws_secretsmanager_secret.oauth2_proxy \
  -target=aws_secretsmanager_secret.s3_connection \
  -var-file=environments/dev.tfvars

# 3. Delete S3 buckets (WARNING: Must be empty first!)
# Empty S3 buckets first
aws s3 rm s3://$(terraform output -raw documents_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw backups_bucket_name) --recursive

terraform destroy \
  -target=module.s3 \
  -var-file=environments/dev.tfvars

# 4. Delete RDS instance
terraform destroy \
  -target=module.rds \
  -var-file=environments/dev.tfvars

# 5. Delete remaining resources
terraform destroy -var-file=environments/dev.tfvars
```

### Method 2: Complete Destruction (Fast but Risky)

**⚠️ WARNING: This destroys everything at once! No going back!**

```bash
cd terraform/aws

# Empty S3 buckets first (Terraform can't delete non-empty buckets)
DOCS_BUCKET=$(terraform output -raw documents_bucket_name 2>/dev/null)
BACKUPS_BUCKET=$(terraform output -raw backups_bucket_name 2>/dev/null)

if [ -n "$DOCS_BUCKET" ]; then
  echo "Emptying documents bucket..."
  aws s3 rm s3://$DOCS_BUCKET --recursive
fi

if [ -n "$BACKUPS_BUCKET" ]; then
  echo "Emptying backups bucket..."
  aws s3 rm s3://$BACKUPS_BUCKET --recursive
fi

# Destroy all resources
terraform destroy -var-file=environments/dev.tfvars

# Type 'yes' when prompted
```

---

## Automated Destroy Script

**Location:** `terraform/aws/scripts/destroy-all.sh`

```bash
#!/bin/bash
# Use the automated script (safer)
./scripts/destroy-all.sh dev

# Script will:
# 1. Show what will be destroyed
# 2. Ask for confirmation
# 3. Backup critical data
# 4. Empty S3 buckets
# 5. Destroy all resources
# 6. Verify destruction
```

---

## Troubleshooting Destruction Issues

### Issue 1: S3 Bucket Not Empty

**Error:**
```
Error: deleting S3 Bucket (fineract-dev-documents-xxxx): BucketNotEmpty
```

**Solution:**
```bash
# Empty the bucket
aws s3 rm s3://fineract-dev-documents-xxxx --recursive

# Retry destroy
terraform destroy -var-file=environments/dev.tfvars
```

### Issue 2: RDS Instance Has Deletion Protection

**Error:**
```
Error: Cannot delete DB instance with DeletionProtection enabled
```

**Solution:**
```bash
# Disable deletion protection
aws rds modify-db-instance \
  --db-instance-identifier fineract-dev \
  --no-deletion-protection

# Wait for modification to complete (2-3 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier fineract-dev

# Retry destroy
terraform destroy -var-file=environments/dev.tfvars
```

### Issue 3: Secrets Manager Secret Marked for Deletion

**Error:**
```
Error: secret is already scheduled for deletion
```

**Solution:**
```bash
# Force immediate deletion (bypasses 30-day recovery window)
aws secretsmanager delete-secret \
  --secret-id fineract-dev-fineract-dev-db-credentials \
  --force-delete-without-recovery

# Retry destroy
terraform destroy -var-file=environments/dev.tfvars
```

### Issue 4: Dependency Violations

**Error:**
```
Error: DependencyViolation: resource has a dependent object
```

**Solution:**
```bash
# Use targeted destroy to remove dependencies first
terraform destroy -target=module.rds -var-file=environments/dev.tfvars
terraform destroy -target=module.vpc -var-file=environments/dev.tfvars
terraform destroy -var-file=environments/dev.tfvars
```

### Issue 5: NAT Gateway Still In Use

**Error:**
```
Error: timeout while waiting for NAT Gateway to become available
```

**Solution:**
```bash
# Manually delete NAT Gateway
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=fineract-dev-nat" \
  --query "NatGateways[0].NatGatewayId" --output text

aws ec2 delete-nat-gateway --nat-gateway-id nat-xxxxxxxxx

# Wait for deletion (5-10 minutes)
sleep 600

# Retry destroy
terraform destroy -var-file=environments/dev.tfvars
```

---

## Post-Destruction Verification

### Step 1: Verify All Resources Deleted

```bash
cd terraform/aws

# Terraform state should be empty
terraform show

# Check AWS Console or CLI
aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier=='fineract-dev']"
# Should return empty array: []

aws s3 ls | grep fineract-dev
# Should return nothing

aws secretsmanager list-secrets | grep fineract-dev
# Should return nothing (or marked for deletion)

aws ec2 describe-vpcs --filters "Name=tag:Name,Values=fineract-dev-vpc"
# Should return empty (if VPC was created by Terraform)
```

### Step 2: Check for Orphaned Resources

Sometimes resources aren't managed by Terraform but were created alongside:

```bash
# Check for orphaned security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=fineract" \
  --query "SecurityGroups[].GroupId"

# Check for orphaned EIPs
aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=fineract" \
  --query "Addresses[].AllocationId"

# Check for orphaned CloudWatch Log Groups
aws logs describe-log-groups \
  --log-group-name-prefix /aws/fineract

# Manually delete if found
```

### Step 3: Verify Cost Savings

```bash
# Check AWS Cost Explorer
# It may take 24-48 hours for costs to reflect the deletion

# Or use AWS CLI
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

---

## Cleanup Terraform State

After successful destruction:

```bash
cd terraform/aws

# Remove Terraform state files (if you're done with this environment)
rm -f terraform.tfstate
rm -f terraform.tfstate.backup
rm -rf .terraform/

# Or keep them for historical reference
mkdir -p ../destroyed-states/
mv terraform.tfstate ../destroyed-states/dev-tfstate-$(date +%Y%m%d).json
```

---

## Recreating Resources Later

If you need to recreate resources:

```bash
cd terraform/aws

# 1. Reinitialize Terraform
terraform init

# 2. Apply with your environment file
terraform apply -var-file=environments/dev.tfvars

# 3. Regenerate sealed secrets
cd ../..
./scripts/seal-terraform-secrets.sh dev
./scripts/create-complete-sealed-secrets.sh dev

# 4. Redeploy Kubernetes resources
kubectl apply -k environments/dev/
```

---

## Alternative: Pause Instead of Destroy

If you want to save money but keep your data:

### Pause RDS (Save ~$60-80/month)

```bash
# Stop RDS instance (can be stopped for up to 7 days)
aws rds stop-db-instance --db-instance-identifier fineract-dev

# RDS will automatically restart after 7 days
# To stop again, create a Lambda function or CloudWatch Event
```

### Use S3 Intelligent-Tiering (Save ~$1-2/month)

```bash
# Enable Intelligent-Tiering on S3 buckets
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket $(terraform output -raw documents_bucket_name) \
  --id EntireS3Bucket \
  --intelligent-tiering-configuration file://s3-tiering-config.json
```

### Delete NAT Gateway (Save ~$32/month)

```bash
# Manually delete NAT Gateway (can recreate later)
aws ec2 delete-nat-gateway --nat-gateway-id nat-xxxxxxxxx

# Keep VPC, subnets, etc.
# Pods won't have internet access but will still work for internal communication
```

---

## Emergency Rollback

If you accidentally started destroying and want to stop:

```bash
# Press Ctrl+C immediately
# Terraform will stop gracefully

# Check what was destroyed
terraform show

# Reapply to recreate destroyed resources
terraform apply -var-file=environments/dev.tfvars

# Note: Data in destroyed resources (RDS, S3) is LOST
# Restore from backups if available
```

---

## Security Cleanup

After destroying infrastructure:

### Revoke IAM Access

```bash
# If you created IAM users for access
aws iam delete-access-key --access-key-id AKIA... --user-name dev-fineract

aws iam delete-user --user-name dev-fineract
```

### Delete SSH Keys

```bash
# If you created EC2 key pairs
aws ec2 delete-key-pair --key-name fineract-dev-key
```

### Remove kubectl Context

```bash
# Remove EKS cluster context (if cluster was deleted separately)
kubectl config delete-context arn:aws:eks:us-east-2:xxxx:cluster/fineract-dev
kubectl config delete-cluster arn:aws:eks:us-east-2:xxxx:cluster/fineract-dev
```

---

## Summary Checklist

**Before Destroying:**
- [ ] Backup RDS databases (pg_dump)
- [ ] Backup S3 data (aws s3 sync)
- [ ] Backup Terraform state
- [ ] Export AWS Secrets Manager secrets
- [ ] Verify destruction plan (terraform plan -destroy)
- [ ] Delete Kubernetes resources first
- [ ] Understand cost implications (~$110-140/month savings)

**During Destruction:**
- [ ] Empty S3 buckets first
- [ ] Disable RDS deletion protection (if enabled)
- [ ] Use incremental destruction (recommended) or complete destruction
- [ ] Monitor for errors
- [ ] Take notes of any manual cleanup needed

**After Destruction:**
- [ ] Verify all resources deleted (terraform show)
- [ ] Check for orphaned resources
- [ ] Delete Terraform state (or archive)
- [ ] Verify cost savings in 24-48 hours
- [ ] Update documentation

---

## Support

**If you encounter issues:**
1. Check troubleshooting section above
2. Review Terraform destroy logs
3. Manually delete stuck resources via AWS Console
4. Contact AWS Support for persistent issues

**Cost Savings:**
- After successful destruction: ~$110-140/month savings
- Total saved over 1 year: ~$1,320-1,680

---

**⚠️ FINAL WARNING**

Destroying Terraform resources is **PERMANENT** and **IRREVERSIBLE**. All data in RDS and S3 will be lost. Make sure you have backups before proceeding!

---

**Ready to Destroy?**

```bash
cd terraform/aws
terraform destroy -var-file=environments/dev.tfvars
```

Type `yes` when prompted, and Terraform will delete all resources.

Good luck! 🚀
