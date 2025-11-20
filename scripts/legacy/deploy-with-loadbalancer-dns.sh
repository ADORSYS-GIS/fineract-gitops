#!/bin/bash
#
# ╔═════════════════════════════════════════════════════════════════════╗
# ║                     ⚠️  DEPRECATED SCRIPT  ⚠️                        ║
# ╚═════════════════════════════════════════════════════════════════════╝
#
# This script is DEPRECATED as of 2025-11-20
# Removal planned: 2026-05-20
#
# REASON: Requires manual kubeconfig setup, monolithic design
#
# RECOMMENDED ALTERNATIVES:
#   1. Two-phase deployment (for fresh infrastructure):
#      make deploy-infrastructure-dev
#      make deploy-k8s-with-loadbalancer-dns-dev
#
#   2. Interactive GitOps deployment:
#      make deploy-gitops
#
# See DEPRECATIONS.md for migration guide
# ========================================================================
#
# Automated Deployment Script - LoadBalancer DNS Mode
# Fully automated deployment using AWS LoadBalancer DNS (no custom DNS required)
#
# Usage: ./scripts/deploy-with-loadbalancer-dns.sh [environment]
# Example: ./scripts/deploy-with-loadbalancer-dns.sh dev
#
# This script performs ZERO manual steps:
# 1. Deploys infrastructure (Terraform, EKS, RDS, S3)
# 2. Deploys GitOps tools (ArgoCD, Sealed Secrets)
# 3. Waits for LoadBalancer DNS to be provisioned
# 4. Automatically updates all configurations with actual LoadBalancer DNS
# 5. Commits configuration changes to Git
# 6. Deploys applications (Fineract, Keycloak, OAuth2-Proxy)
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

# Display deprecation warning
echo ""
echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    ⚠️  DEPRECATION WARNING  ⚠️                         ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}This script (deploy-with-loadbalancer-dns.sh) is DEPRECATED.${NC}"
echo ""
echo -e "Deprecated: ${YELLOW}2025-11-20${NC}"
echo -e "Removal planned: ${RED}2026-05-20${NC}"
echo ""
echo -e "${GREEN}Recommended alternatives:${NC}"
echo -e "  1. Two-phase deployment (for fresh infrastructure):"
echo -e "     ${BLUE}make deploy-infrastructure-dev${NC}"
echo -e "     ${BLUE}make deploy-k8s-with-loadbalancer-dns-dev${NC}"
echo ""
echo -e "  2. Interactive GitOps deployment:"
echo -e "     ${BLUE}make deploy-gitops${NC}"
echo ""
echo -e "See ${BLUE}DEPRECATIONS.md${NC} for migration guide."
echo ""
echo -e "${RED}════════════════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "Continue using deprecated script? [y/N]: " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${GREEN}Good choice! Use one of the recommended alternatives above.${NC}"
    exit 0
fi
echo ""
log_warn "Continuing with deprecated script..."
echo ""

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

echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║        Fineract GitOps - Automated Deployment                  ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║        Mode: LoadBalancer DNS (No Custom DNS)                  ║${NC}"
echo -e "${BLUE}║        Environment: ${ENV}                                        ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# ============================================================================
# PHASE 1: Deploy Infrastructure
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 1: Deploy Infrastructure (Terraform, EKS, RDS, S3)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-1"
if ! make deploy-step-1; then
    error_exit "Infrastructure deployment failed (deploy-step-1)"
fi

log "✓ Infrastructure deployed successfully"
echo

# ============================================================================
# PHASE 2: Deploy GitOps Tools
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 2: Deploy GitOps Tools (ArgoCD, Sealed Secrets)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-2"
if ! make deploy-step-2; then
    error_exit "GitOps deployment failed (deploy-step-2)"
fi

log "✓ GitOps tools deployed successfully"
echo

# ============================================================================
# PHASE 2.5: Backup Sealed Secrets Keys
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 2.5: Backup Sealed Secrets Controller Keys${NC}"
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
# PHASE 3: Wait for LoadBalancer DNS
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 3: Wait for LoadBalancer DNS Provisioning${NC}"
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
# PHASE 4: Update Configurations with LoadBalancer DNS
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 4: Update Configurations with LoadBalancer DNS${NC}"
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
# PHASE 5: Commit Configuration Changes
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 5: Commit Configuration Changes to Git${NC}"
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
./scripts/deploy-with-loadbalancer-dns.sh ${ENV}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

    log "✓ Configuration changes committed to Git"
fi

echo

# ============================================================================
# PHASE 6: Deploy Secrets
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 6: Deploy Secrets (Sealed Secrets from Terraform)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-3"
if ! make deploy-step-3; then
    error_exit "Secrets deployment failed (deploy-step-3)"
fi

log "✓ Secrets deployed successfully"
echo

# ============================================================================
# PHASE 7: Deploy Applications
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 7: Deploy Applications (Fineract, Keycloak, OAuth2-Proxy)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Running: make deploy-step-4"
if ! make deploy-step-4; then
    error_exit "Applications deployment failed (deploy-step-4)"
fi

log "✓ Applications deployed successfully"
echo

# ============================================================================
# PHASE 8: Wait for Applications to be Ready
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 8: Wait for Applications to be Ready${NC}"
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
echo -e "${GREEN}                    Deployment Complete!                       ${NC}"
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
echo
