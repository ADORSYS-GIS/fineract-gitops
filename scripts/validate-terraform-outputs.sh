#!/bin/bash
# Validate Terraform Outputs
# Verifies all required Terraform outputs exist and are valid before deploying applications
#
# Usage: ./scripts/validate-terraform-outputs.sh [environment]
# Example: ./scripts/validate-terraform-outputs.sh dev
#
# Prerequisites:
# 1. Terraform state must exist (run terraform apply first)
# 2. AWS CLI configured
# 3. jq installed for JSON parsing
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment argument required${NC}"
    echo "Usage: $0 [dev|uat|production]"
    exit 1
fi

ENV=$1

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be dev, uat, or production${NC}"
    exit 1
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform/aws"
AWS_REGION="${AWS_REGION:-us-east-2}"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

error_exit() {
    log_error "$1"
    exit 1
}

# Header
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Terraform Outputs Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Terraform Dir: ${TERRAFORM_DIR}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    error_exit "Terraform not found. Install from: https://www.terraform.io/downloads"
fi

if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI not found. Install with: brew install awscli"
fi

if ! command -v jq &> /dev/null; then
    error_exit "jq not found. Install with: brew install jq"
fi

log "✓ All prerequisites met"
echo

# Change to Terraform directory
if [ ! -d "$TERRAFORM_DIR" ]; then
    error_exit "Terraform directory not found: $TERRAFORM_DIR"
fi

cd "$TERRAFORM_DIR"

# Verify Terraform state exists
log_info "Checking Terraform state..."
if ! terraform state list &> /dev/null; then
    error_exit "No Terraform state found. Run 'terraform apply' first."
fi

log "✓ Terraform state found"
echo

# Validation counters
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# Validate EKS Outputs
# ============================================================================

echo -e "${BLUE}→ Validating EKS outputs...${NC}"
echo

# EKS Cluster Name
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
if [ -n "$EKS_CLUSTER_NAME" ]; then
    echo -e "${GREEN}  ✓ eks_cluster_name: $EKS_CLUSTER_NAME${NC}"
    ((PASSED++))

    # Verify cluster exists in AWS
    log_info "  Verifying cluster exists in AWS..."
    if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        CLUSTER_STATUS=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.status' --output text)
        echo -e "${GREEN}  ✓ Cluster verified in AWS (Status: $CLUSTER_STATUS)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ Cluster not found in AWS${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}  ✗ eks_cluster_name: MISSING${NC}"
    ((FAILED++))
fi

# EKS Cluster Endpoint
EKS_ENDPOINT=$(terraform output -raw eks_cluster_endpoint 2>/dev/null || echo "")
if [ -n "$EKS_ENDPOINT" ]; then
    echo -e "${GREEN}  ✓ eks_cluster_endpoint: $EKS_ENDPOINT${NC}"
    ((PASSED++))
else
    echo -e "${RED}  ✗ eks_cluster_endpoint: MISSING${NC}"
    ((FAILED++))
fi

# OIDC Issuer URL
OIDC_ISSUER=$(terraform output -raw eks_cluster_oidc_issuer_url 2>/dev/null || echo "")
if [ -n "$OIDC_ISSUER" ]; then
    echo -e "${GREEN}  ✓ eks_cluster_oidc_issuer_url: $OIDC_ISSUER${NC}"
    ((PASSED++))
else
    echo -e "${RED}  ✗ eks_cluster_oidc_issuer_url: MISSING${NC}"
    ((FAILED++))
fi

echo

# ============================================================================
# Validate VPC Outputs
# ============================================================================

echo -e "${BLUE}→ Validating VPC outputs...${NC}"
echo

# VPC ID
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
if [ -n "$VPC_ID" ]; then
    echo -e "${GREEN}  ✓ vpc_id: $VPC_ID${NC}"
    ((PASSED++))

    # Verify VPC exists
    if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" &> /dev/null; then
        echo -e "${GREEN}  ✓ VPC verified in AWS${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ VPC not found in AWS${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}  ✗ vpc_id: MISSING${NC}"
    ((FAILED++))
fi

# Public Subnets
PUBLIC_SUBNETS=$(terraform output -json public_subnet_ids 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
if [ -n "$PUBLIC_SUBNETS" ]; then
    SUBNET_COUNT=$(echo "$PUBLIC_SUBNETS" | wc -l | tr -d ' ')
    echo -e "${GREEN}  ✓ public_subnet_ids: $SUBNET_COUNT subnets${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}  ⚠ public_subnet_ids: MISSING (may be optional)${NC}"
    ((WARNINGS++))
fi

# Private Subnets
PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
if [ -n "$PRIVATE_SUBNETS" ]; then
    SUBNET_COUNT=$(echo "$PRIVATE_SUBNETS" | wc -l | tr -d ' ')
    echo -e "${GREEN}  ✓ private_subnet_ids: $SUBNET_COUNT subnets${NC}"
    ((PASSED++))
else
    echo -e "${RED}  ✗ private_subnet_ids: MISSING${NC}"
    ((FAILED++))
fi

echo

# ============================================================================
# Validate IRSA Outputs
# ============================================================================

echo -e "${BLUE}→ Validating IRSA outputs...${NC}"
echo

# EBS CSI Driver Role
EBS_CSI_ROLE=$(terraform output -raw ebs_csi_driver_role_arn 2>/dev/null || echo "")
if [ -n "$EBS_CSI_ROLE" ]; then
    echo -e "${GREEN}  ✓ ebs_csi_driver_role_arn: $EBS_CSI_ROLE${NC}"
    ((PASSED++))

    # Verify IAM role exists
    ROLE_NAME=$(echo "$EBS_CSI_ROLE" | awk -F'/' '{print $NF}')
    if aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" &> /dev/null; then
        echo -e "${GREEN}  ✓ IAM role verified: $ROLE_NAME${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ IAM role not found: $ROLE_NAME${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}  ✗ ebs_csi_driver_role_arn: MISSING${NC}"
    ((FAILED++))
fi

# Cluster Autoscaler Role
AUTOSCALER_ROLE=$(terraform output -raw cluster_autoscaler_role_arn 2>/dev/null || echo "")
if [ -n "$AUTOSCALER_ROLE" ]; then
    echo -e "${GREEN}  ✓ cluster_autoscaler_role_arn: $AUTOSCALER_ROLE${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}  ⚠ cluster_autoscaler_role_arn: MISSING (needed for auto-scaling)${NC}"
    ((WARNINGS++))
fi

# App Service Account Role
APP_ROLE=$(terraform output -raw app_service_account_role_arn 2>/dev/null || echo "")
if [ -n "$APP_ROLE" ]; then
    echo -e "${GREEN}  ✓ app_service_account_role_arn: $APP_ROLE${NC}"
    ((PASSED++))

    # Verify IAM role exists
    ROLE_NAME=$(echo "$APP_ROLE" | awk -F'/' '{print $NF}')
    if aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" &> /dev/null; then
        echo -e "${GREEN}  ✓ IAM role verified: $ROLE_NAME${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ IAM role not found: $ROLE_NAME${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}  ✗ app_service_account_role_arn: MISSING${NC}"
    ((FAILED++))
fi

echo

# ============================================================================
# Validate RDS Outputs
# ============================================================================

echo -e "${BLUE}→ Validating RDS outputs...${NC}"
echo

# RDS Endpoint
RDS_ENDPOINT=$(terraform output -raw rds_instance_endpoint 2>/dev/null || echo "")
if [ -n "$RDS_ENDPOINT" ]; then
    echo -e "${GREEN}  ✓ rds_instance_endpoint: $RDS_ENDPOINT${NC}"
    ((PASSED++))

    # Extract hostname and verify RDS instance
    RDS_HOST=$(echo "$RDS_ENDPOINT" | cut -d: -f1)
    RDS_INSTANCE=$(echo "$RDS_HOST" | cut -d. -f1)

    if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE" --region "$AWS_REGION" &> /dev/null; then
        RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE" --region "$AWS_REGION" --query 'DBInstances[0].DBInstanceStatus' --output text)
        echo -e "${GREEN}  ✓ RDS instance verified (Status: $RDS_STATUS)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ RDS instance not found: $RDS_INSTANCE${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}  ✗ rds_instance_endpoint: MISSING${NC}"
    ((FAILED++))
fi

# RDS Database Name
DB_NAME=$(terraform output -raw rds_database_name 2>/dev/null || echo "")
if [ -n "$DB_NAME" ]; then
    echo -e "${GREEN}  ✓ rds_database_name: $DB_NAME${NC}"
    ((PASSED++))
else
    echo -e "${RED}  ✗ rds_database_name: MISSING${NC}"
    ((FAILED++))
fi

# RDS Username
DB_USERNAME=$(terraform output -raw rds_master_username 2>/dev/null || echo "")
if [ -n "$DB_USERNAME" ]; then
    echo -e "${GREEN}  ✓ rds_master_username: $DB_USERNAME${NC}"
    ((PASSED++))
else
    echo -e "${RED}  ✗ rds_master_username: MISSING${NC}"
    ((FAILED++))
fi

echo

# ============================================================================
# Validate S3 Outputs
# ============================================================================

echo -e "${BLUE}→ Validating S3 outputs...${NC}"
echo

# S3 Documents Bucket
DOCS_BUCKET=$(terraform output -raw documents_bucket_name 2>/dev/null || echo "")
if [ -n "$DOCS_BUCKET" ]; then
    echo -e "${GREEN}  ✓ documents_bucket_name: $DOCS_BUCKET${NC}"
    ((PASSED++))

    # Verify bucket exists
    if aws s3api head-bucket --bucket "$DOCS_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Documents bucket verified${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ Documents bucket not found${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}  ✗ documents_bucket_name: MISSING${NC}"
    ((FAILED++))
fi

# S3 Backups Bucket
BACKUPS_BUCKET=$(terraform output -raw backups_bucket_name 2>/dev/null || echo "")
if [ -n "$BACKUPS_BUCKET" ]; then
    echo -e "${GREEN}  ✓ backups_bucket_name: $BACKUPS_BUCKET${NC}"
    ((PASSED++))

    # Verify bucket exists
    if aws s3api head-bucket --bucket "$BACKUPS_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Backups bucket verified${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ Backups bucket not found${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}  ⚠ backups_bucket_name: MISSING (may be optional)${NC}"
    ((WARNINGS++))
fi

echo

# ============================================================================
# Validate Route53 Outputs (Optional)
# ============================================================================

echo -e "${BLUE}→ Validating Route53 outputs (optional)...${NC}"
echo

ROUTE53_ZONE=$(terraform output -raw route53_zone_id 2>/dev/null || echo "")
if [ -n "$ROUTE53_ZONE" ]; then
    echo -e "${GREEN}  ✓ route53_zone_id: $ROUTE53_ZONE${NC}"
    ((PASSED++))

    # Get nameservers
    NAMESERVERS=$(terraform output -json route53_name_servers 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    if [ -n "$NAMESERVERS" ]; then
        echo -e "${GREEN}  ✓ route53_name_servers:${NC}"
        echo "$NAMESERVERS" | while read -r ns; do
            echo -e "${GREEN}    - $ns${NC}"
        done
        ((PASSED++))
    fi
else
    echo -e "${YELLOW}  ⚠ route53_zone_id: Not configured (using LoadBalancer DNS)${NC}"
    ((WARNINGS++))
fi

echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${GREEN}  Passed: $PASSED${NC}"
echo -e "${RED}  Failed: $FAILED${NC}"
echo -e "${YELLOW}  Warnings: $WARNINGS${NC}"
echo

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All validations passed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Create sealed secrets:"
    echo "   ./scripts/seal-terraform-secrets-enhanced.sh $ENV"
    echo
    echo "2. Deploy applications with ArgoCD:"
    echo "   kubectl apply -k argocd/applications/$ENV/"
    echo
    echo -e "${GREEN}Ready to deploy!${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Validation failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo
    echo -e "${YELLOW}Action Required:${NC}"
    echo "Fix the failed validations above before deploying applications."
    echo
    echo "Common fixes:"
    echo "1. If resources are missing, run: terraform apply"
    echo "2. If AWS resources not found, check AWS region: $AWS_REGION"
    echo "3. If IRSA roles missing, ensure EKS module is properly configured"
    echo
    exit 1
fi
