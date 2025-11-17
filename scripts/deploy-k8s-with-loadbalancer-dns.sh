#!/bin/bash
#
# Kubernetes Deployment Script - LoadBalancer DNS Mode (Phase 2 only)
# Deploy Kubernetes resources with LoadBalancer DNS after infrastructure is ready
#
# Usage: ./scripts/deploy-k8s-with-loadbalancer-dns.sh [environment]
# Example: ./scripts/deploy-k8s-with-loadbalancer-dns.sh dev
#
# Prerequisites:
# 1. Infrastructure must be deployed (make deploy-infrastructure-dev)
# 2. Kubeconfig must be configured
# 3. GITHUB_TOKEN must be set
#
# This script performs:
# 1. Deploys GitOps tools (ArgoCD, Sealed Secrets, ingress-nginx, cert-manager)
# 2. Waits for LoadBalancer DNS to be provisioned
# 2.5. Handles sealed secrets strategy (restore old keys OR regenerate fresh)
# 3. Automatically updates all configurations with actual LoadBalancer DNS
# 4. Commits configuration changes to Git
# 5. Deploys applications (Fineract, Keycloak, OAuth2-Proxy)
# 6. Waits for applications to be ready
#
# IMPORTANT NOTES:
# - RDS PostgreSQL requires SSL/TLS connections (configured in Keycloak deployment)
# - Database passwords MUST come from Terraform state (via seal-terraform-secrets.sh)
# - Regenerating sealed secrets creates NEW passwords that won't match RDS
# - Use option 2 in sealed secrets strategy to properly extract Terraform passwords
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

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment argument required${NC}"
    echo "Usage: $0 [dev|uat|production]"
    exit 1
fi

ENV=$1

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    error_exit "Invalid environment. Must be dev, uat, or production"
fi

# Change to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Verify we're in the correct directory
if [ ! -f "Makefile" ]; then
    error_exit "Not in repository root. Expected to find Makefile."
fi

# ============================================================================
# Pre-Flight Checks
# ============================================================================

preflight_check() {
    local errors=0

    log_info "Running pre-flight checks..."
    echo

    # Check 1: KUBECONFIG
    if [ -z "$KUBECONFIG" ]; then
        log_error "KUBECONFIG environment variable not set"
        echo "  Fix: export KUBECONFIG=~/.kube/config-fineract-$ENV"
        ((errors++))
    else
        log "✓ KUBECONFIG is set: $KUBECONFIG"
    fi

    # Check 2: Kubernetes cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "  Fix: Ensure infrastructure is deployed and kubeconfig is configured"
        echo "       Run: ./scripts/setup-eks-kubeconfig.sh $ENV"
        ((errors++))
    else
        CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
        log "✓ Connected to cluster: $CLUSTER_NAME"
    fi

    # Check 3: GITHUB_TOKEN
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "GITHUB_TOKEN environment variable not set"
        echo "  Fix: export GITHUB_TOKEN='your_token'"
        ((errors++))
    else
        log "✓ GITHUB_TOKEN is set"
    fi

    # Check 4: Terraform outputs (needed for sealed secrets)
    if [ ! -d "terraform/aws" ]; then
        log_warn "Terraform directory not found"
        echo "  This may cause sealed secrets generation to fail"
        ((errors++))
    else
        # Check if terraform state exists
        if [ -f "terraform/aws/terraform.tfstate" ] || [ -d "terraform/aws/.terraform" ]; then
            log "✓ Terraform state found"

            # Try to verify terraform outputs are available
            if cd terraform/aws && terraform output &> /dev/null; then
                OUTPUT_COUNT=$(terraform output -json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
                if [ "$OUTPUT_COUNT" -gt 0 ]; then
                    log "✓ Terraform outputs available ($OUTPUT_COUNT outputs)"
                else
                    log_warn "Terraform outputs appear empty"
                    echo "  Run: cd terraform/aws && terraform apply"
                fi
                cd "$REPO_ROOT"
            else
                log_warn "Cannot read Terraform outputs"
                echo "  Run: cd terraform/aws && terraform init && terraform apply"
                cd "$REPO_ROOT"
            fi
        else
            log_error "Terraform not initialized or no state file"
            echo "  Fix: cd terraform/aws && terraform init && terraform apply"
            ((errors++))
        fi
    fi

    # Check 5: AWS CLI and credentials
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI not found (optional for backups)"
    else
        if aws sts get-caller-identity &> /dev/null; then
            AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
            log "✓ AWS CLI authenticated (Account: $AWS_ACCOUNT)"
        else
            log_warn "AWS CLI not authenticated (optional for backups)"
        fi
    fi

    echo

    if [ $errors -gt 0 ]; then
        log_error "Pre-flight checks failed with $errors error(s)"
        echo
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Deployment cancelled due to pre-flight check failures"
        fi
        log_warn "Continuing despite errors..."
    else
        log "✓ All pre-flight checks passed"
    fi

    echo
}

# Run pre-flight checks
preflight_check

# Verify prerequisites (kept for backwards compatibility)
if [ -z "$KUBECONFIG" ]; then
    error_exit "KUBECONFIG environment variable not set. Run: export KUBECONFIG=~/.kube/config-fineract-$ENV"
fi

if ! kubectl cluster-info &> /dev/null; then
    error_exit "Cannot connect to Kubernetes cluster. Ensure infrastructure is deployed and kubeconfig is configured."
fi

if [ -z "$GITHUB_TOKEN" ]; then
    error_exit "GITHUB_TOKEN environment variable not set. Run: export GITHUB_TOKEN='your_token'"
fi

echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║     Fineract GitOps - Kubernetes Deployment (Phase 2)         ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║     Mode: LoadBalancer DNS (No Custom DNS)                    ║${NC}"
echo -e "${BLUE}║     Environment: ${ENV}                                        ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# ============================================================================
# PHASE 1: Deploy GitOps Tools
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 1: Deploy GitOps Tools (ArgoCD, Sealed Secrets)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-2"
if ! make deploy-step-2; then
    error_exit "GitOps deployment failed (deploy-step-2)"
fi

log "✓ GitOps tools deployed successfully"
echo

# ============================================================================
# PHASE 1.5: Backup Sealed Secrets Keys
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 1.5: Backup Sealed Secrets Controller Keys${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Backing up Sealed Secrets controller keys to AWS Secrets Manager..."
log_info "This ensures disaster recovery if cluster is destroyed"
echo

# Determine AWS region from Terraform variables
AWS_REGION=$(grep -oP 'aws_region\s*=\s*"\K[^"]+' terraform/aws/environments/${ENV}-eks.tfvars || echo "us-east-2")

if ! ./scripts/backup-sealed-secrets-keys.sh "${ENV}" "${AWS_REGION}"; then
    log_warn "Sealed Secrets key backup failed (non-fatal)"
    log_warn "You can backup manually later: ./scripts/backup-sealed-secrets-keys.sh ${ENV}"
    echo
else
    log "✓ Sealed Secrets keys backed up successfully"
    echo
fi

# ============================================================================
# PHASE 2: Wait for LoadBalancer DNS
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 2: Wait for LoadBalancer DNS Provisioning${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Waiting for ingress-nginx LoadBalancer to be provisioned..."
echo

# Wait for LoadBalancer and retrieve DNS
LB_DNS=""
MAX_WAIT=600  # 10 minutes
ELAPSED=0
CHECK_INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    LB_DNS=$(kubectl get service -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [ -n "$LB_DNS" ]; then
        echo
        log "✓ LoadBalancer DNS provisioned: $LB_DNS"
        break
    fi

    # Progress indicator
    REMAINING=$((MAX_WAIT - ELAPSED))
    printf "\r${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} Waiting for LoadBalancer... (${ELAPSED}s elapsed, ${REMAINING}s remaining)"

    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo
echo

# Check if we timed out
if [ -z "$LB_DNS" ]; then
    error_exit "Timed out waiting for LoadBalancer DNS after ${MAX_WAIT}s"
fi

# ============================================================================
# PHASE 2.5: Sealed Secrets Strategy - Restore or Regenerate
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 2.5: Sealed Secrets Strategy${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Choosing sealed secrets approach..."
echo

# Check if sealed secrets already exist
SEALED_SECRETS_EXIST=false
if ls "$REPO_ROOT/secrets/${ENV}/"*-sealed.yaml &> /dev/null 2>&1; then
    SEALED_SECRETS_EXIST=true
    SEALED_COUNT=$(ls -1 "$REPO_ROOT/secrets/${ENV}/"*-sealed.yaml 2>/dev/null | wc -l | tr -d ' ')
    log "Found $SEALED_COUNT existing sealed secret files in secrets/${ENV}/"
fi

# Check if backup exists in AWS Secrets Manager
BACKUP_EXISTS=false
if aws secretsmanager describe-secret --secret-id "/fineract/${ENV}/sealed-secrets/master-key" --region "$AWS_REGION" &> /dev/null; then
    BACKUP_EXISTS=true
    BACKUP_DATE=$(aws secretsmanager get-secret-value \
        --secret-id "/fineract/${ENV}/sealed-secrets/master-key" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null | jq -r '.timestamp' 2>/dev/null || echo "unknown")
    log "Found controller key backup in AWS Secrets Manager (dated: $BACKUP_DATE)"
fi

echo
echo -e "${YELLOW}Choose sealed secrets approach:${NC}"
echo
echo "  ${BLUE}1)${NC} Restore old keys from AWS Secrets Manager backup"
if [ "$BACKUP_EXISTS" = true ]; then
    echo "     - Uses existing encrypted sealed secrets (no regeneration needed)"
    echo "     - Backup date: $BACKUP_DATE"
    echo "     - ${GREEN}Faster deployment${NC}"
else
    echo "     - ${RED}Not available (no backup found in AWS)${NC}"
fi
echo
echo "  ${BLUE}2)${NC} Regenerate all sealed secrets with fresh keys ${YELLOW}(RECOMMENDED for fresh deployment)${NC}"
echo "     - Generates new encryption keys (better security)"
echo "     - Creates fresh sealed secrets from Terraform outputs"
echo "     - ${GREEN}REQUIRED if this is your first deployment${NC}"
echo "     - ${GREEN}REQUIRED if Terraform was re-run and RDS passwords changed${NC}"
echo "     - Commits changes to Git"
echo
echo "  ${BLUE}3)${NC} Skip - Use existing sealed secrets as-is"
echo "     - Assumes sealed secrets and controller keys already match"
echo "     - ${YELLOW}Only works if sealed secrets were previously generated${NC}"
echo "     - ${RED}Will fail if this is a fresh deployment${NC}"
echo

# Get user choice
VALID_CHOICE=false
while [ "$VALID_CHOICE" = false ]; do
    read -p "Enter choice [1-3]: " CHOICE
    case $CHOICE in
        1)
            if [ "$BACKUP_EXISTS" = false ]; then
                log_error "Cannot restore: No backup found in AWS Secrets Manager"
                echo "Please choose option 2 or 3"
            else
                VALID_CHOICE=true
            fi
            ;;
        2|3)
            VALID_CHOICE=true
            ;;
        *)
            log_error "Invalid choice. Enter 1, 2, or 3"
            ;;
    esac
done

echo

case $CHOICE in
    1)
        # Restore old keys from AWS Secrets Manager
        log_info "Restoring sealed secrets controller keys from AWS Secrets Manager..."
        echo

        if "$REPO_ROOT/scripts/restore-sealed-secrets-keys.sh" "$ENV" "$AWS_REGION"; then
            log "✓ Controller keys restored from backup"
            echo
            log_info "Existing sealed secrets will work with restored keys"
        else
            error_exit "Failed to restore controller keys from AWS Secrets Manager"
        fi
        ;;

    2)
        # Regenerate all sealed secrets with new keys
        log_info "Regenerating all sealed secrets with fresh encryption keys..."
        echo

        log_warn "This will:"
        echo "  1. Generate new application secrets (Redis, Keycloak admin, etc.)"
        echo "  2. Extract and seal Terraform secrets from state (RDS passwords, S3, OAuth2)"
        echo "     ${BLUE}→ RDS passwords come from Terraform state (NOT new random values)${NC}"
        echo "     ${BLUE}→ Ensures passwords match what Terraform created in RDS${NC}"
        echo "  3. Backup new controller keys to AWS"
        echo "  4. Show git diff for review"
        echo

        read -p "Continue with regeneration? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warn "Regeneration cancelled. Existing sealed secrets will be used."
        else
            if "$REPO_ROOT/scripts/regenerate-all-sealed-secrets.sh" "$ENV" "$AWS_REGION"; then
                log "✓ Sealed secrets regenerated successfully"
            else
                log_warn "Sealed secrets regeneration had issues (check output above)"
                log_warn "Continuing with deployment..."
            fi
        fi
        ;;

    3)
        # Skip - use existing sealed secrets
        log_info "Skipping sealed secrets regeneration"
        log_warn "Using existing sealed secrets as-is"
        log_warn "If controller keys don't match, secrets won't decrypt!"
        echo

        # Validate that critical sealed secrets exist
        REQUIRED_SECRETS=(
            "fineract-db-credentials-sealed.yaml"
            "keycloak-db-credentials-sealed.yaml"
            "oauth2-proxy-secrets-sealed.yaml"
            "s3-connection-sealed.yaml"
            "fineract-redis-credentials-sealed.yaml"
        )

        MISSING_SECRETS=()
        for secret_file in "${REQUIRED_SECRETS[@]}"; do
            if [ ! -f "$REPO_ROOT/secrets/${ENV}/$secret_file" ]; then
                MISSING_SECRETS+=("$secret_file")
            fi
        done

        if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
            log_error "Critical sealed secrets are missing:"
            for secret in "${MISSING_SECRETS[@]}"; do
                echo "  ✗ secrets/${ENV}/$secret"
            done
            echo
            log_error "Fresh deployment requires sealed secrets to be generated first"
            echo
            echo -e "${YELLOW}Options to fix this:${NC}"
            echo "  1. Run option 2 instead (Regenerate all sealed secrets)"
            echo "  2. Manually generate sealed secrets:"
            echo "     ./scripts/regenerate-all-sealed-secrets.sh $ENV"
            echo
            error_exit "Cannot proceed without critical sealed secrets"
        fi

        log "✓ All critical sealed secrets found ($SEALED_COUNT files)"
        log_info "Deployment will use existing sealed secrets"
        ;;
esac

echo
log "✓ Sealed secrets strategy completed"
echo

# ============================================================================
# PHASE 3: Update Configurations with LoadBalancer DNS
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 3: Update Configurations with LoadBalancer DNS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Updating configuration files with LoadBalancer DNS: $LB_DNS"
echo

# Files to update (ingress-config ConfigMaps in Kustomize overlays)
declare -a CONFIG_FILES=(
    "apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml"
    "apps/keycloak/overlays/${ENV}/kustomization.yaml"
    "apps/fineract/overlays/${ENV}/kustomization.yaml"
)

for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Config file not found: $CONFIG_FILE (skipping)"
        continue
    fi

    log_info "Updating: $CONFIG_FILE"

    # Update apps-hostname and auth-hostname with LoadBalancer DNS
    # Use sed to replace the values in the configMapGenerator literals
    sed -i.bak -E \
        -e "s|apps-hostname=.*|apps-hostname=${LB_DNS}|g" \
        -e "s|auth-hostname=.*|auth-hostname=${LB_DNS}|g" \
        "$CONFIG_FILE"

    # Remove backup file
    rm -f "${CONFIG_FILE}.bak"

    log "  ✓ Updated: $CONFIG_FILE"
done

echo
log "✓ All configuration files updated"
echo

# Verify changes
log_info "Verifying configuration changes..."
echo

git diff --stat

echo

# ============================================================================
# PHASE 4: Commit Configuration Changes to Git
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 4: Commit Configuration Changes to Git${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Check if there are changes to commit
if git diff --quiet; then
    log_warn "No configuration changes detected (configs may already be correct)"
else
    log_info "Committing configuration changes..."

    # Add modified config files
    for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
        if [ -f "$CONFIG_FILE" ]; then
            git add "$CONFIG_FILE"
        fi
    done

    # Commit changes
    git commit -m "$(cat <<EOF
chore: update configs with LoadBalancer DNS for ${ENV}

Automated update using LoadBalancer DNS: ${LB_DNS}

This commit was generated automatically by:
./scripts/deploy-k8s-with-loadbalancer-dns.sh ${ENV}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

    log "✓ Configuration changes committed to Git"
fi

echo

# ============================================================================
# PHASE 5: Deploy Secrets
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 5: Deploy Secrets (Sealed Secrets from Terraform)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-3"
if ! make deploy-step-3; then
    error_exit "Secrets deployment failed (deploy-step-3)"
fi

log "✓ Secrets deployed successfully"
echo

# ============================================================================
# PHASE 6: Deploy Applications
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 6: Deploy Applications (Fineract, Keycloak, OAuth2-Proxy)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-4"
if ! make deploy-step-4; then
    error_exit "Applications deployment failed (deploy-step-4)"
fi

log "✓ Applications deployed successfully"
echo

# ============================================================================
# PHASE 7: Wait for Applications to be Ready
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 7: Wait for Applications to be Ready${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Waiting for ArgoCD applications to sync..."
echo

# Wait for all ArgoCD applications to be synced and healthy
NAMESPACE="fineract-${ENV}"
APP_TIMEOUT=600  # 10 minutes
APP_ELAPSED=0

while [ $APP_ELAPSED -lt $APP_TIMEOUT ]; do
    # Check ArgoCD app status
    APPS_STATUS=$(kubectl get applications -n argocd -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.destination.namespace=="'"$NAMESPACE"'") |
               "\(.metadata.name): \(.status.sync.status) / \(.status.health.status)"' 2>/dev/null || echo "")

    if [ -n "$APPS_STATUS" ]; then
        # Check if all apps are Synced and Healthy
        NOT_READY=$(echo "$APPS_STATUS" | grep -v "Synced / Healthy" || true)

        if [ -z "$NOT_READY" ]; then
            echo
            log "✓ All ArgoCD applications are synced and healthy"
            break
        fi
    fi

    # Progress indicator
    APP_REMAINING=$((APP_TIMEOUT - APP_ELAPSED))
    printf "\r${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} Waiting for applications... (${APP_ELAPSED}s elapsed, ${APP_REMAINING}s remaining)"

    sleep 10
    APP_ELAPSED=$((APP_ELAPSED + 10))
done

echo
echo

if [ $APP_ELAPSED -ge $APP_TIMEOUT ]; then
    log_warn "Timed out waiting for all applications to be ready (some may still be initializing)"
    echo
    log_info "Check application status with:"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get pods -n $NAMESPACE"
    echo
else
    log "✓ All applications are ready"
    echo
fi

# ============================================================================
# Deployment Summary
# ============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}              Kubernetes Deployment Complete!                  ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo

echo -e "${BLUE}Environment:${NC} ${ENV}"
echo -e "${BLUE}LoadBalancer DNS:${NC} ${LB_DNS}"
echo

echo -e "${GREEN}Access your applications at:${NC}"
echo -e "  Fineract API:    ${GREEN}https://${LB_DNS}/fineract-provider${NC}"
echo -e "  Keycloak:        ${GREEN}https://${LB_DNS}${NC}"
echo -e "  ArgoCD:          ${GREEN}https://${LB_DNS}/argocd${NC}"
echo

echo -e "${YELLOW}Important Notes:${NC}"
echo "1. SSL Warning: Browser will show 'Not Secure' (self-signed certificate)"
echo "   - Click 'Advanced' → 'Proceed to ${LB_DNS}' (one-time per browser)"
echo "   - This is EXPECTED - the certificate is self-signed but matches the hostname"
echo

echo "2. Default Credentials:"
echo "   Fineract: mifos / password"
echo "   Keycloak: admin / (from AWS Secrets Manager)"
echo "   ArgoCD:   admin / (run: ./scripts/get-endpoints.sh ${ENV})"
echo

echo "3. Next Steps:"
echo "   - Test OAuth login: https://${LB_DNS}/fineract-provider"
echo "   - View ArgoCD apps: https://${LB_DNS}/argocd"
echo "   - Monitor pods: kubectl get pods -n ${NAMESPACE}"
echo

echo -e "${BLUE}Useful Commands:${NC}"
echo "  Get endpoints:       ./scripts/get-endpoints.sh ${ENV}"
echo "  Check pod status:    kubectl get pods -n ${NAMESPACE}"
echo "  View logs:           kubectl logs -n ${NAMESPACE} <pod-name>"
echo "  ArgoCD apps:         kubectl get applications -n argocd"
echo

echo -e "${GREEN}Deployment completed successfully at $(date)${NC}"
