#!/bin/bash
# Setup Terraform Backend
# Creates S3 bucket and DynamoDB table for Terraform remote state storage
#
# Usage: ./scripts/setup-terraform-backend.sh
#
# Prerequisites:
# 1. AWS CLI configured with appropriate credentials
# 2. IAM permissions for S3 and DynamoDB operations
#
# This script is idempotent - safe to run multiple times
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-eu-central-1}"
S3_BUCKET="${S3_BUCKET:-fineract-gitops-terraform-state-2025}"
DYNAMODB_TABLE="${DYNAMODB_TABLE:-fineract-gitops-terraform-lock}"

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
echo -e "${BLUE}Terraform Backend Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AWS Region: ${AWS_REGION}${NC}"
echo -e "${BLUE}S3 Bucket: ${S3_BUCKET}${NC}"
echo -e "${BLUE}DynamoDB Table: ${DYNAMODB_TABLE}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI not found. Install with: brew install awscli"
fi

# Verify AWS credentials
if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    error_exit "AWS credentials not configured or invalid. Run: aws configure"
fi

log "✓ Prerequisites met"
echo

# Get AWS account info
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
AWS_USER=$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")

log_info "AWS Account ID: $AWS_ACCOUNT_ID"
log_info "AWS Identity: $AWS_USER"
echo

# ============================================================================
# S3 Bucket Creation
# ============================================================================

log_info "Checking S3 bucket: $S3_BUCKET"

if aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
    log_warn "S3 bucket already exists: $S3_BUCKET"
else
    log_info "Creating S3 bucket: $S3_BUCKET"

    # Create bucket
    if aws s3api create-bucket \
        --bucket "$S3_BUCKET" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>/dev/null; then
        log "✓ S3 bucket created: $S3_BUCKET"
    else
        error_exit "Failed to create S3 bucket: $S3_BUCKET"
    fi

    # Enable versioning
    log_info "Enabling versioning on S3 bucket..."
    if aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"; then
        log "✓ Versioning enabled"
    else
        log_warn "Failed to enable versioning (may not affect functionality)"
    fi

    # Enable encryption
    log_info "Enabling server-side encryption..."
    if aws s3api put-bucket-encryption \
        --bucket "$S3_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }' \
        --region "$AWS_REGION"; then
        log "✓ Encryption enabled"
    else
        log_warn "Failed to enable encryption (may not affect functionality)"
    fi

    # Block public access
    log_info "Blocking public access..."
    if aws s3api put-public-access-block \
        --bucket "$S3_BUCKET" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION"; then
        log "✓ Public access blocked"
    else
        log_warn "Failed to block public access (may not affect functionality)"
    fi

    # Add tags
    log_info "Adding tags..."
    if aws s3api put-bucket-tagging \
        --bucket "$S3_BUCKET" \
        --tagging 'TagSet=[
            {Key=Project,Value=fineract},
            {Key=ManagedBy,Value=terraform},
            {Key=Purpose,Value=terraform-state}
        ]' \
        --region "$AWS_REGION"; then
        log "✓ Tags added"
    else
        log_warn "Failed to add tags (may not affect functionality)"
    fi
fi

echo

# ============================================================================
# DynamoDB Table Creation
# ============================================================================

log_info "Checking DynamoDB table: $DYNAMODB_TABLE"

if aws dynamodb describe-table \
    --table-name "$DYNAMODB_TABLE" \
    --region "$AWS_REGION" &> /dev/null; then
    log_warn "DynamoDB table already exists: $DYNAMODB_TABLE"
else
    log_info "Creating DynamoDB table: $DYNAMODB_TABLE"

    if aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=fineract Key=ManagedBy,Value=terraform Key=Purpose,Value=terraform-lock \
        --region "$AWS_REGION" > /dev/null; then
        log "✓ DynamoDB table created: $DYNAMODB_TABLE"

        # Wait for table to be active
        log_info "Waiting for DynamoDB table to be active..."
        if aws dynamodb wait table-exists \
            --table-name "$DYNAMODB_TABLE" \
            --region "$AWS_REGION"; then
            log "✓ DynamoDB table is active"
        else
            log_warn "Table creation may still be in progress"
        fi
    else
        error_exit "Failed to create DynamoDB table: $DYNAMODB_TABLE"
    fi
fi

echo

# ============================================================================
# Verify Resources
# ============================================================================

log_info "Verifying backend resources..."

# Verify S3 bucket
if aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
    # Get bucket info
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$S3_BUCKET" --region "$AWS_REGION" --query Status --output text 2>/dev/null || echo "Disabled")
    ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null && echo "Enabled" || echo "Disabled")

    log "✓ S3 bucket verified: $S3_BUCKET"
    log_info "  Versioning: $VERSIONING"
    log_info "  Encryption: $ENCRYPTION"
else
    error_exit "S3 bucket verification failed"
fi

echo

# Verify DynamoDB table
if aws dynamodb describe-table \
    --table-name "$DYNAMODB_TABLE" \
    --region "$AWS_REGION" &> /dev/null; then

    TABLE_STATUS=$(aws dynamodb describe-table \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION" \
        --query 'Table.TableStatus' \
        --output text)

    log "✓ DynamoDB table verified: $DYNAMODB_TABLE"
    log_info "  Status: $TABLE_STATUS"
else
    error_exit "DynamoDB table verification failed"
fi

echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Terraform Backend Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Backend configuration:"
echo "  S3 Bucket: $S3_BUCKET"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo "  AWS Region: $AWS_REGION"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Initialize Terraform with the backend:"
echo "   cd terraform/aws"
echo "   terraform init"
echo
echo "2. Verify backend configuration in terraform/aws/main.tf:"
echo "   terraform {"
echo "     backend \"s3\" {"
echo "       bucket         = \"$S3_BUCKET\""
echo "       key            = \"fineract/terraform.tfstate\""
echo "       region         = \"$AWS_REGION\""
echo "       dynamodb_table = \"$DYNAMODB_TABLE\""
echo "       encrypt        = true"
echo "     }"
echo "   }"
echo
echo -e "${GREEN}Done!${NC}"
