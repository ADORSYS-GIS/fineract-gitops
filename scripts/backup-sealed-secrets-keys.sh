#!/bin/bash
#
# Backup Sealed Secrets Controller Keys to AWS Secrets Manager
# Prevents catastrophic data loss if cluster is destroyed
#
# Usage: ./scripts/backup-sealed-secrets-keys.sh [environment] [region]
# Example: ./scripts/backup-sealed-secrets-keys.sh dev us-east-2
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. AWS CLI configured with appropriate credentials
# 3. Sealed Secrets controller deployed in kube-system namespace
# 4. IAM permissions to write to AWS Secrets Manager
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Parse arguments
ENV="${1:-dev}"
AWS_REGION="${2:-us-east-2}"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    error_exit "Invalid environment. Must be dev, uat, or production"
fi

# Configuration
NAMESPACE="kube-system"
SECRET_LABEL="sealedsecrets.bitnami.com/sealed-secrets-key"
SECRET_PATH="/fineract/${ENV}/sealed-secrets/master-key"
TMP_DIR="/tmp/sealed-secrets-backup-$$"
BACKUP_FILE="${TMP_DIR}/sealed-secrets-keys.yaml"

# Header
echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║        Sealed Secrets Key Backup to AWS Secrets Manager       ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Environment:${NC} ${ENV}"
echo -e "${BLUE}AWS Region:${NC} ${AWS_REGION}"
echo -e "${BLUE}Secret Path:${NC} ${SECRET_PATH}"
echo -e "${BLUE}Namespace:${NC} ${NAMESPACE}"
echo
echo "═══════════════════════════════════════════════════════════════"
echo

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================

log_info "Step 1: Checking prerequisites..."
echo

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    error_exit "kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/"
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error_exit "aws CLI not found. Install from: https://aws.amazon.com/cli/"
fi

# Verify cluster access
if ! kubectl cluster-info &> /dev/null; then
    error_exit "Cannot access Kubernetes cluster. Configure kubectl first."
fi

CURRENT_CONTEXT=$(kubectl config current-context)
log "✓ Connected to cluster: $CURRENT_CONTEXT"

# Verify AWS credentials
if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    error_exit "Cannot access AWS. Configure AWS CLI credentials."
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text)
log "✓ AWS Account: $AWS_ACCOUNT"
echo

# ============================================================================
# Step 2: Extract Keys from Kubernetes
# ============================================================================

log_info "Step 2: Extracting Sealed Secrets keys from Kubernetes..."
echo

# Create temporary directory
mkdir -p "$TMP_DIR"
trap "rm -rf $TMP_DIR" EXIT

# Get sealed secrets keys
log_info "Looking for secrets with label: $SECRET_LABEL"
echo

# Check if any keys exist
KEY_COUNT=$(kubectl get secrets -n "$NAMESPACE" -l "$SECRET_LABEL" --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$KEY_COUNT" -eq 0 ]; then
    error_exit "No sealed secrets keys found in namespace $NAMESPACE. Is the controller deployed?"
fi

log "✓ Found $KEY_COUNT sealed secrets key(s)"
echo

# Extract all keys to YAML file
log_info "Extracting keys to temporary file..."
kubectl get secrets -n "$NAMESPACE" -l "$SECRET_LABEL" -o yaml > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
    error_exit "Failed to extract keys to YAML file"
fi

FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "✓ Keys extracted to: $BACKUP_FILE ($FILE_SIZE)"
echo

# Display key information
log_info "Key Details:"
kubectl get secrets -n "$NAMESPACE" -l "$SECRET_LABEL" | grep -v "^NAME" | while read -r line; do
    SECRET_NAME=$(echo "$line" | awk '{print $1}')
    AGE=$(echo "$line" | awk '{print $3}')
    echo -e "  ${BLUE}•${NC} $SECRET_NAME (age: $AGE)"
done
echo

# ============================================================================
# Step 3: Check if Secret Already Exists in AWS Secrets Manager
# ============================================================================

log_info "Step 3: Checking if secret already exists in AWS Secrets Manager..."
echo

SECRET_EXISTS=false
if aws secretsmanager describe-secret --secret-id "$SECRET_PATH" --region "$AWS_REGION" &> /dev/null; then
    SECRET_EXISTS=true
    log_warn "Secret already exists in AWS Secrets Manager"

    # Get current version count
    VERSION_COUNT=$(aws secretsmanager list-secret-version-ids \
        --secret-id "$SECRET_PATH" \
        --region "$AWS_REGION" \
        --query 'length(Versions)' \
        --output text)

    log_info "Current version count: $VERSION_COUNT"
    echo
else
    log "✓ Secret does not exist yet (will be created)"
    echo
fi

# ============================================================================
# Step 4: Upload to AWS Secrets Manager
# ============================================================================

log_info "Step 4: Uploading keys to AWS Secrets Manager..."
echo

# Base64 encode the YAML file to preserve formatting
ENCODED_KEYS=$(cat "$BACKUP_FILE" | base64)

if [ -z "$ENCODED_KEYS" ]; then
    error_exit "Failed to encode keys"
fi

# Create JSON payload
cat > "${TMP_DIR}/secret-payload.json" <<EOF
{
  "keys": "${ENCODED_KEYS}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "${ENV}",
  "cluster_context": "${CURRENT_CONTEXT}",
  "key_count": ${KEY_COUNT},
  "backup_version": "1.0"
}
EOF

# Upload to AWS Secrets Manager
if [ "$SECRET_EXISTS" = true ]; then
    log_info "Updating existing secret..."

    aws secretsmanager put-secret-value \
        --secret-id "$SECRET_PATH" \
        --secret-string file://"${TMP_DIR}/secret-payload.json" \
        --region "$AWS_REGION" \
        > /dev/null

    log "✓ Secret updated successfully"
else
    log_info "Creating new secret..."

    aws secretsmanager create-secret \
        --name "$SECRET_PATH" \
        --description "Sealed Secrets controller encryption keys for ${ENV} environment" \
        --secret-string file://"${TMP_DIR}/secret-payload.json" \
        --region "$AWS_REGION" \
        --tags Key=Environment,Value="$ENV" \
               Key=ManagedBy,Value="sealed-secrets-backup-script" \
               Key=Purpose,Value="disaster-recovery" \
        > /dev/null

    log "✓ Secret created successfully"
fi

echo

# ============================================================================
# Step 5: Verify Backup
# ============================================================================

log_info "Step 5: Verifying backup..."
echo

# Retrieve the secret to verify
RETRIEVED_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_PATH" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text)

if [ -z "$RETRIEVED_SECRET" ]; then
    error_exit "Failed to retrieve secret from AWS Secrets Manager"
fi

# Verify key count matches
STORED_KEY_COUNT=$(echo "$RETRIEVED_SECRET" | jq -r '.key_count')
if [ "$STORED_KEY_COUNT" != "$KEY_COUNT" ]; then
    error_exit "Key count mismatch! Expected: $KEY_COUNT, Stored: $STORED_KEY_COUNT"
fi

log "✓ Backup verified successfully"

# Display backup metadata
TIMESTAMP=$(echo "$RETRIEVED_SECRET" | jq -r '.timestamp')
BACKUP_VERSION=$(echo "$RETRIEVED_SECRET" | jq -r '.backup_version')

echo
log_info "Backup Metadata:"
echo -e "  ${BLUE}Timestamp:${NC} $TIMESTAMP"
echo -e "  ${BLUE}Keys Backed Up:${NC} $STORED_KEY_COUNT"
echo -e "  ${BLUE}Backup Version:${NC} $BACKUP_VERSION"
echo -e "  ${BLUE}Secret ARN:${NC}"

aws secretsmanager describe-secret \
    --secret-id "$SECRET_PATH" \
    --region "$AWS_REGION" \
    --query 'ARN' \
    --output text | sed 's/^/    /'

echo

# ============================================================================
# Step 6: Set Retention Policy
# ============================================================================

log_info "Step 6: Configuring retention policy..."
echo

# Note: AWS Secrets Manager doesn't support automatic version deletion
# Versions are kept indefinitely unless manually deleted
# This is actually beneficial for disaster recovery

log_info "AWS Secrets Manager will retain all versions indefinitely"
log_info "To clean up old versions manually, use:"
echo "  aws secretsmanager list-secret-version-ids --secret-id $SECRET_PATH --region $AWS_REGION"
echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    Backup Complete!                           ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo

echo "Summary:"
echo -e "  ${BLUE}Environment:${NC} $ENV"
echo -e "  ${BLUE}Keys Backed Up:${NC} $KEY_COUNT"
echo -e "  ${BLUE}Secret Path:${NC} $SECRET_PATH"
echo -e "  ${BLUE}AWS Region:${NC} $AWS_REGION"
echo -e "  ${BLUE}Backup Time:${NC} $TIMESTAMP"
echo

echo -e "${YELLOW}Important Notes:${NC}"
echo "1. Keys are encrypted at rest by AWS Secrets Manager"
echo "2. All versions are retained indefinitely for disaster recovery"
echo "3. Access is controlled by IAM policies and CloudTrail logs all access"
echo "4. In case of disaster, use: ./scripts/restore-sealed-secrets-keys.sh $ENV"
echo

echo -e "${BLUE}Next Steps:${NC}"
echo "1. Test restoration in a test environment"
echo "2. Verify all sealed secrets can still be decrypted"
echo "3. Document backup schedule and retention policy"
echo

log "✓ Sealed Secrets keys backed up successfully to AWS Secrets Manager"
echo
