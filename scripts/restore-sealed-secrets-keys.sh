#!/bin/bash
#
# Restore Sealed Secrets Controller Keys from AWS Secrets Manager
# Restores encryption keys to prevent data loss after cluster recreation
#
# Usage: ./scripts/restore-sealed-secrets-keys.sh [environment] [region]
# Example: ./scripts/restore-sealed-secrets-keys.sh dev us-east-2
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. AWS CLI configured with appropriate credentials
# 3. Sealed Secrets keys previously backed up to AWS Secrets Manager
# 4. IAM permissions to read from AWS Secrets Manager
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
SECRET_PATH="/fineract/${ENV}/sealed-secrets/master-key"
TMP_DIR="/tmp/sealed-secrets-restore-$$"
KEYS_FILE="${TMP_DIR}/sealed-secrets-keys.yaml"

# Header
echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║       Sealed Secrets Key Restore from AWS Secrets Manager     ║${NC}"
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

# Check jq
if ! command -v jq &> /dev/null; then
    error_exit "jq not found. Install from: https://stedolan.github.io/jq/"
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
# Step 2: Check for Existing Keys in Kubernetes
# ============================================================================

log_info "Step 2: Checking for existing keys in Kubernetes..."
echo

EXISTING_KEYS=$(kubectl get secrets -n "$NAMESPACE" -l "sealedsecrets.bitnami.com/sealed-secrets-key" --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$EXISTING_KEYS" -gt 0 ]; then
    log_warn "Found $EXISTING_KEYS existing sealed secrets key(s) in the cluster"
    echo
    echo -e "${YELLOW}WARNING: Restoring keys will replace existing keys!${NC}"
    echo "This may cause issues if:"
    echo "  1. The cluster already has valid keys"
    echo "  2. There are sealed secrets encrypted with the current keys"
    echo
    echo -e "${YELLOW}Do you want to continue? (yes/no)${NC}"
    read -r CONFIRMATION

    if [ "$CONFIRMATION" != "yes" ]; then
        log "Restoration cancelled by user"
        exit 0
    fi

    log_info "Backing up existing keys before replacement..."
    BACKUP_FILE="${TMP_DIR}/existing-keys-backup.yaml"
    mkdir -p "$TMP_DIR"
    kubectl get secrets -n "$NAMESPACE" -l "sealedsecrets.bitnami.com/sealed-secrets-key" -o yaml > "$BACKUP_FILE"
    log "✓ Existing keys backed up to: $BACKUP_FILE"
    echo
else
    log "✓ No existing keys found (fresh installation)"
    echo
fi

# ============================================================================
# Step 3: Download Keys from AWS Secrets Manager
# ============================================================================

log_info "Step 3: Downloading keys from AWS Secrets Manager..."
echo

# Check if secret exists
if ! aws secretsmanager describe-secret --secret-id "$SECRET_PATH" --region "$AWS_REGION" &> /dev/null; then
    error_exit "Secret not found in AWS Secrets Manager: $SECRET_PATH"
fi

log "✓ Secret found in AWS Secrets Manager"

# Get secret metadata
SECRET_ARN=$(aws secretsmanager describe-secret \
    --secret-id "$SECRET_PATH" \
    --region "$AWS_REGION" \
    --query 'ARN' \
    --output text)

log_info "Secret ARN: $SECRET_ARN"
echo

# Download secret
log_info "Downloading secret..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_PATH" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text)

if [ -z "$SECRET_JSON" ]; then
    error_exit "Failed to download secret from AWS Secrets Manager"
fi

log "✓ Secret downloaded successfully"
echo

# ============================================================================
# Step 4: Parse and Validate Secret Content
# ============================================================================

log_info "Step 4: Parsing and validating secret content..."
echo

# Extract metadata
BACKUP_TIMESTAMP=$(echo "$SECRET_JSON" | jq -r '.timestamp')
BACKUP_ENV=$(echo "$SECRET_JSON" | jq -r '.environment')
BACKUP_CLUSTER=$(echo "$SECRET_JSON" | jq -r '.cluster_context')
KEY_COUNT=$(echo "$SECRET_JSON" | jq -r '.key_count')
BACKUP_VERSION=$(echo "$SECRET_JSON" | jq -r '.backup_version')

log_info "Backup Metadata:"
echo -e "  ${BLUE}Timestamp:${NC} $BACKUP_TIMESTAMP"
echo -e "  ${BLUE}Environment:${NC} $BACKUP_ENV"
echo -e "  ${BLUE}Cluster Context:${NC} $BACKUP_CLUSTER"
echo -e "  ${BLUE}Key Count:${NC} $KEY_COUNT"
echo -e "  ${BLUE}Backup Version:${NC} $BACKUP_VERSION"
echo

# Validate environment matches
if [ "$BACKUP_ENV" != "$ENV" ]; then
    log_warn "Environment mismatch: Backup is for '$BACKUP_ENV' but restoring to '$ENV'"
    echo -e "${YELLOW}Do you want to continue? (yes/no)${NC}"
    read -r ENV_CONFIRMATION

    if [ "$ENV_CONFIRMATION" != "yes" ]; then
        log "Restoration cancelled due to environment mismatch"
        exit 0
    fi
fi

# Extract and decode keys
log_info "Extracting encrypted keys..."
ENCODED_KEYS=$(echo "$SECRET_JSON" | jq -r '.keys')

if [ -z "$ENCODED_KEYS" ] || [ "$ENCODED_KEYS" = "null" ]; then
    error_exit "Failed to extract keys from secret"
fi

# Create temporary directory
mkdir -p "$TMP_DIR"
trap "rm -rf $TMP_DIR" EXIT

# Decode keys
log_info "Decoding keys..."
echo "$ENCODED_KEYS" | base64 -d > "$KEYS_FILE"

if [ ! -s "$KEYS_FILE" ]; then
    error_exit "Failed to decode keys from base64"
fi

FILE_SIZE=$(du -h "$KEYS_FILE" | cut -f1)
log "✓ Keys decoded successfully ($FILE_SIZE)"
echo

# Validate YAML structure
log_info "Validating YAML structure..."
if ! kubectl apply --dry-run=client -f "$KEYS_FILE" &> /dev/null; then
    error_exit "Invalid YAML structure in decoded keys"
fi

log "✓ YAML structure is valid"
echo

# ============================================================================
# Step 5: Delete Existing Keys (if any)
# ============================================================================

if [ "$EXISTING_KEYS" -gt 0 ]; then
    log_info "Step 5: Deleting existing keys..."
    echo

    kubectl delete secrets -n "$NAMESPACE" -l "sealedsecrets.bitnami.com/sealed-secrets-key" 2>/dev/null || true

    # Wait for deletion to complete
    log_info "Waiting for deletion to complete..."
    sleep 5

    log "✓ Existing keys deleted"
    echo
else
    log_info "Step 5: No existing keys to delete (skipped)"
    echo
fi

# ============================================================================
# Step 6: Apply Keys to Kubernetes
# ============================================================================

log_info "Step 6: Applying keys to Kubernetes..."
echo

# Apply the keys
if ! kubectl apply -f "$KEYS_FILE"; then
    error_exit "Failed to apply keys to Kubernetes"
fi

log "✓ Keys applied successfully"
echo

# Wait for keys to be ready
log_info "Waiting for keys to be ready..."
sleep 5

# ============================================================================
# Step 7: Verify Restoration
# ============================================================================

log_info "Step 7: Verifying restoration..."
echo

# Check key count
RESTORED_KEYS=$(kubectl get secrets -n "$NAMESPACE" -l "sealedsecrets.bitnami.com/sealed-secrets-key" --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$RESTORED_KEYS" -ne "$KEY_COUNT" ]; then
    error_exit "Key count mismatch! Expected: $KEY_COUNT, Restored: $RESTORED_KEYS"
fi

log "✓ Key count verified: $RESTORED_KEYS keys restored"
echo

# Display restored keys
log_info "Restored Keys:"
kubectl get secrets -n "$NAMESPACE" -l "sealedsecrets.bitnami.com/sealed-secrets-key" | grep -v "^NAME" | while read -r line; do
    SECRET_NAME=$(echo "$line" | awk '{print $1}')
    AGE=$(echo "$line" | awk '{print $3}')
    echo -e "  ${BLUE}•${NC} $SECRET_NAME (age: $AGE)"
done
echo

# ============================================================================
# Step 8: Restart Sealed Secrets Controller (Optional)
# ============================================================================

log_info "Step 8: Checking for Sealed Secrets controller..."
echo

CONTROLLER_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "app.kubernetes.io/name=sealed-secrets" --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$CONTROLLER_DEPLOYMENT" ]; then
    log_info "Found controller: $CONTROLLER_DEPLOYMENT"
    echo -e "${BLUE}Restart controller to pick up new keys? (yes/no)${NC}"
    read -r RESTART_CONFIRMATION

    if [ "$RESTART_CONFIRMATION" = "yes" ]; then
        log_info "Restarting controller..."
        kubectl rollout restart deployment "$CONTROLLER_DEPLOYMENT" -n "$NAMESPACE"

        log_info "Waiting for controller to be ready..."
        kubectl rollout status deployment "$CONTROLLER_DEPLOYMENT" -n "$NAMESPACE" --timeout=120s

        log "✓ Controller restarted successfully"
    else
        log_info "Skipping controller restart (keys will be picked up on next restart)"
    fi
else
    log_warn "Sealed Secrets controller not found (may not be deployed yet)"
fi

echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    Restoration Complete!                      ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo

echo "Summary:"
echo -e "  ${BLUE}Environment:${NC} $ENV"
echo -e "  ${BLUE}Keys Restored:${NC} $RESTORED_KEYS"
echo -e "  ${BLUE}Backup Timestamp:${NC} $BACKUP_TIMESTAMP"
echo -e "  ${BLUE}Source Cluster:${NC} $BACKUP_CLUSTER"
echo -e "  ${BLUE}Target Cluster:${NC} $CURRENT_CONTEXT"
echo

echo -e "${YELLOW}Important Notes:${NC}"
echo "1. Keys have been restored from backup dated: $BACKUP_TIMESTAMP"
echo "2. All sealed secrets encrypted with these keys should now decrypt"
echo "3. Sealed secrets encrypted with OTHER keys will NOT decrypt"
echo "4. Controller will use these keys for decryption automatically"
echo

echo -e "${BLUE}Next Steps:${NC}"
echo "1. Verify sealed secrets can be decrypted:"
echo "   kubectl get sealedsecrets -A"
echo "2. Test application connectivity to ensure secrets are working"
echo "3. If controller was not restarted, restart it manually:"
echo "   kubectl rollout restart deployment sealed-secrets-controller -n kube-system"
echo

log "✓ Sealed Secrets keys restored successfully from AWS Secrets Manager"
echo
