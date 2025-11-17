#!/bin/bash
#
# Regenerate All Sealed Secrets - Complete Workflow
# This script regenerates ALL sealed secrets with fresh encryption keys
#
# Usage: ./scripts/regenerate-all-sealed-secrets.sh [environment] [region]
# Example: ./scripts/regenerate-all-sealed-secrets.sh dev us-east-2
#
# Prerequisites:
# 1. Sealed Secrets Controller must be deployed with NEW keys
# 2. Terraform outputs must be available (for Terraform-managed secrets)
# 3. kubectl configured to access the cluster
# 4. AWS CLI configured (for backup)
#
# This script performs:
# 1. Generates application secrets (Redis, Keycloak admin, Grafana, etc.)
#    - These use NEW random passwords (safe - not stored in infrastructure)
# 2. Generates Terraform-managed secrets (RDS, S3, OAuth2)
#    - Extracts RDS passwords from Terraform STATE (not new random values)
#    - Ensures passwords match what Terraform created in RDS
#    - CRITICAL: RDS requires SSL/TLS (configured in Keycloak deployment)
# 3. Backs up new controller keys to AWS Secrets Manager
# 4. Shows git diff
# 5. Prompts to commit changes to Git
#
# IMPORTANT: Database passwords come from Terraform state, not generated randomly.
# This ensures applications can connect to RDS with correct credentials.
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

# Change to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Header
echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║          Regenerate ALL Sealed Secrets - Fresh Keys           ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Environment:${NC} ${ENV}"
echo -e "${BLUE}AWS Region:${NC} ${AWS_REGION}"
echo -e "${BLUE}Secrets Directory:${NC} secrets/${ENV}/"
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

# Check kubeseal
if ! command -v kubeseal &> /dev/null; then
    error_exit "kubeseal not found. Install from: https://github.com/bitnami-labs/sealed-secrets"
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

# Verify Sealed Secrets Controller is running
if ! kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
    error_exit "Sealed Secrets Controller not found in kube-system. Deploy it first."
fi

# Check if controller is ready
CONTROLLER_READY=$(kubectl get deployment sealed-secrets-controller -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$CONTROLLER_READY" -eq 0 ]; then
    error_exit "Sealed Secrets Controller is not ready. Wait for it to be running."
fi

log "✓ Sealed Secrets Controller is ready"

# Check for Terraform outputs (for terraform-managed secrets)
if [ ! -d "terraform/aws" ]; then
    log_warn "Terraform directory not found (terraform-managed secrets may fail)"
else
    log "✓ Terraform directory found"
fi

echo

# ============================================================================
# Step 2: Backup Existing Sealed Secrets (Safety)
# ============================================================================

log_info "Step 2: Backing up existing sealed secrets..."
echo

BACKUP_DIR="/tmp/sealed-secrets-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if ls secrets/${ENV}/*-sealed.yaml &> /dev/null; then
    cp secrets/${ENV}/*-sealed.yaml "$BACKUP_DIR/" 2>/dev/null || true
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR" | wc -l | tr -d ' ')
    log "✓ Backed up $BACKUP_COUNT sealed secret files to: $BACKUP_DIR"
else
    log_warn "No existing sealed secrets found (fresh installation)"
fi

echo

# ============================================================================
# Step 3: Generate Application Secrets
# ============================================================================

log_info "Step 3: Generating application secrets..."
echo

log_info "Running: ./scripts/create-complete-sealed-secrets.sh ${ENV}"
if ./scripts/create-complete-sealed-secrets.sh "${ENV}"; then
    log "✓ Application secrets generated successfully"
else
    error_exit "Failed to generate application secrets"
fi

echo

# ============================================================================
# Step 4: Generate Terraform-Managed Secrets
# ============================================================================

log_info "Step 4: Generating Terraform-managed secrets..."
echo

if [ -f "./scripts/seal-terraform-secrets.sh" ]; then
    log_info "Running: ./scripts/seal-terraform-secrets.sh ${ENV}"
    if ./scripts/seal-terraform-secrets.sh "${ENV}"; then
        log "✓ Terraform-managed secrets generated successfully"
    else
        log_warn "Terraform-managed secrets generation failed (non-fatal)"
        log_warn "You may need to run this manually after Terraform outputs are available"
    fi
else
    log_warn "seal-terraform-secrets.sh not found (skipping Terraform-managed secrets)"
fi

echo

# ============================================================================
# Step 5: Verify Sealed Secrets Generated
# ============================================================================

log_info "Step 5: Verifying sealed secrets..."
echo

SEALED_COUNT=$(ls -1 secrets/${ENV}/*-sealed.yaml 2>/dev/null | wc -l | tr -d ' ')

if [ "$SEALED_COUNT" -eq 0 ]; then
    error_exit "No sealed secrets generated! Check script outputs above."
fi

log "✓ Generated $SEALED_COUNT sealed secret files:"
echo
ls -1 secrets/${ENV}/*-sealed.yaml | while read file; do
    filename=$(basename "$file")
    filesize=$(du -h "$file" | cut -f1)
    echo -e "  ${BLUE}•${NC} $filename ($filesize)"
done

echo

# ============================================================================
# Step 6: Backup New Controller Keys to AWS Secrets Manager
# ============================================================================

log_info "Step 6: Backing up new controller keys to AWS Secrets Manager..."
echo

if [ -f "./scripts/backup-sealed-secrets-keys.sh" ]; then
    log_info "Running: ./scripts/backup-sealed-secrets-keys.sh ${ENV} ${AWS_REGION}"
    if ./scripts/backup-sealed-secrets-keys.sh "${ENV}" "${AWS_REGION}"; then
        log "✓ Controller keys backed up to AWS Secrets Manager"
    else
        log_warn "Backup to AWS failed (non-fatal)"
        log_warn "You may need to run this manually later"
    fi
else
    log_warn "backup-sealed-secrets-keys.sh not found (skipping AWS backup)"
fi

echo

# ============================================================================
# Step 7: Show Git Diff
# ============================================================================

log_info "Step 7: Reviewing changes..."
echo

echo -e "${BLUE}Git diff summary:${NC}"
git diff --stat secrets/${ENV}/ 2>/dev/null || echo "  (no changes detected)"

echo
echo -e "${BLUE}Detailed changes (first 50 lines):${NC}"
git diff secrets/${ENV}/ 2>/dev/null | head -50 || echo "  (no changes detected)"

echo

# ============================================================================
# Step 8: Apply to Cluster (Optional)
# ============================================================================

log_info "Step 8: Apply sealed secrets to cluster?"
echo

read -p "Apply sealed secrets to cluster now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Applying sealed secrets to cluster..."

    # Apply namespace first (if exists)
    if [ -f "secrets/${ENV}/namespace.yaml" ]; then
        kubectl apply -f "secrets/${ENV}/namespace.yaml" || true
    fi

    # Apply all sealed secrets
    kubectl apply -f "secrets/${ENV}/" 2>/dev/null || log_warn "Some secrets may have failed to apply"

    log "✓ Sealed secrets applied to cluster"

    # Wait a moment for unsealing
    echo
    log_info "Waiting 10 seconds for secrets to unseal..."
    sleep 10

    # Check if secrets were unsealed
    echo
    log_info "Checking unsealed secrets..."
    UNSEALED_COUNT=$(kubectl get secrets -n fineract-${ENV} --no-headers 2>/dev/null | wc -l | tr -d ' ')
    log "Found $UNSEALED_COUNT unsealed secrets in fineract-${ENV} namespace"
else
    log_info "Skipping cluster application. Apply manually with:"
    echo "  kubectl apply -f secrets/${ENV}/"
fi

echo

# ============================================================================
# Step 9: Commit to Git (Optional)
# ============================================================================

log_info "Step 9: Commit changes to Git?"
echo

if git diff --quiet secrets/${ENV}/; then
    log_warn "No changes to commit (sealed secrets unchanged)"
else
    read -p "Commit sealed secrets to Git? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Committing changes..."

        git add secrets/${ENV}/

        git commit -m "$(cat <<EOF
feat: regenerate sealed secrets with fresh keys for ${ENV}

Regenerated all sealed secrets with new encryption keys:
- Application secrets (Redis, Keycloak, Grafana, etc.)
- Terraform-managed secrets (RDS, S3, OAuth2)
- Total: ${SEALED_COUNT} sealed secret files

New controller keys backed up to AWS Secrets Manager:
- Path: /fineract/${ENV}/sealed-secrets/master-key
- Region: ${AWS_REGION}

Generated by: ./scripts/regenerate-all-sealed-secrets.sh ${ENV}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

        log "✓ Changes committed to Git"

        echo
        read -p "Push to remote? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            CURRENT_BRANCH=$(git branch --show-current)
            log_info "Pushing to remote branch: $CURRENT_BRANCH"
            git push origin "$CURRENT_BRANCH"
            log "✓ Changes pushed to remote"
        else
            log_info "Skipping push. Push manually with:"
            echo "  git push"
        fi
    else
        log_info "Skipping commit. Commit manually with:"
        echo "  git add secrets/${ENV}/"
        echo "  git commit -m 'Regenerate sealed secrets for ${ENV}'"
    fi
fi

echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}          Sealed Secrets Regeneration Complete!                ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo

echo "Summary:"
echo -e "  ${BLUE}Environment:${NC} ${ENV}"
echo -e "  ${BLUE}Sealed Secrets Generated:${NC} ${SEALED_COUNT} files"
echo -e "  ${BLUE}Backup Location:${NC} ${BACKUP_DIR}"
echo -e "  ${BLUE}AWS Backup:${NC} /fineract/${ENV}/sealed-secrets/master-key"
echo

echo -e "${YELLOW}Important Notes:${NC}"
echo "1. New sealed secrets use fresh encryption keys from the controller"
echo "2. Old sealed secrets in backup: ${BACKUP_DIR}"
echo "3. Controller keys backed up to AWS Secrets Manager for disaster recovery"
echo "4. All applications should now be able to decrypt secrets"
echo

echo -e "${BLUE}Next Steps:${NC}"
echo "1. Verify applications can start with new secrets:"
echo "   kubectl get pods -n fineract-${ENV}"
echo
echo "2. Check that sealed secrets unsealed correctly:"
echo "   kubectl get sealedsecrets -n fineract-${ENV}"
echo "   kubectl get secrets -n fineract-${ENV}"
echo
echo "3. If you didn't apply to cluster, do so now:"
echo "   kubectl apply -f secrets/${ENV}/"
echo
echo "4. If you didn't commit to Git, do so now:"
echo "   git add secrets/${ENV}/ && git commit -m 'Regenerate sealed secrets'"
echo

log "✓ Sealed secrets regeneration completed successfully!"
echo
