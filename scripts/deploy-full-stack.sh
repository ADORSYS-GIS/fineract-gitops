#!/bin/bash
#
# Fineract GitOps - Full Stack Automated Deployment
# This script orchestrates the complete deployment of the Fineract platform
#
# ════════════════════════════════════════════════════════════════════
# USE CASE: Automated deployments, CI/CD pipelines
# ════════════════════════════════════════════════════════════════════
#
# This script provides a FULLY AUTOMATED deployment with:
# - No user interaction required
# - All steps run sequentially
# - Comprehensive logging to file
# - Error handling and step tracking
# - Best for CI/CD pipelines and unattended deployments
#
# For INTERACTIVE deployments (manual operations), use:
#   ./scripts/deploy-gitops.sh
#
# See DEPLOYMENT.md for complete guide
#

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure
set -u  # Exit on unset variables

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Environment (default: dev)
ENV="${1:-dev}"

# Log file
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-full-stack-${ENV}-$(date +%Y%m%d-%H%M%S).log"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

# Step tracker
TOTAL_STEPS=8
CURRENT_STEP=0

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    log "========================================"
    log "Step $CURRENT_STEP/$TOTAL_STEPS: $*"
    log "========================================"
}

# Error handler
error_exit() {
    log_error "$1"
    log_error "Deployment failed at step $CURRENT_STEP/$TOTAL_STEPS"
    log_error "Check log file: $LOG_FILE"
    exit 1
}

# Validate prerequisites
validate_prerequisites() {
    step "Validating Prerequisites"

    local missing_tools=()

    # Check required tools
    for tool in aws terraform kubectl ssh; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        error_exit "Missing required tools: ${missing_tools[*]}"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid"
    fi

    # Check SSH key
    if [ ! -f "$HOME/.ssh/fineract-k3s" ]; then
        log_warn "SSH key not found, will be generated"
    fi

    log "Prerequisites validated successfully"
}

# Deploy infrastructure
deploy_infrastructure() {
    step "Deploying AWS Infrastructure (Terraform)"

    log_info "This will deploy:"
    log_info "- VPC with public/private subnets"
    log_info "- K3s cluster (EC2 instances)"
    log_info "- RDS PostgreSQL database"
    log_info "- In-cluster Redis (via Kubernetes manifests)"
    log_info "- S3 buckets"
    log_info "- IAM roles and security groups"

    if ! "$SCRIPT_DIR/deploy-infrastructure.sh" "$ENV" 2>&1 | tee -a "$LOG_FILE"; then
        error_exit "Infrastructure deployment failed"
    fi

    log "Infrastructure deployed successfully"
}

# Setup kubeconfig
setup_kubeconfig() {
    step "Retrieving Kubeconfig from K3s"

    if ! "$SCRIPT_DIR/setup-kubeconfig.sh" "$ENV" 2>&1 | tee -a "$LOG_FILE"; then
        error_exit "Kubeconfig setup failed"
    fi

    # Verify cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi

    log "Kubeconfig configured successfully"
    kubectl get nodes
}

# Bootstrap ArgoCD
bootstrap_argocd() {
    step "Bootstrapping ArgoCD and Platform Components"

    log_info "Installing:"
    log_info "- ArgoCD"
    log_info "- Ingress NGINX Controller"
    log_info "Note: Sealed Secrets Controller will be deployed via ArgoCD"

    if ! "$SCRIPT_DIR/bootstrap-argocd.sh" "$ENV" 2>&1 | tee -a "$LOG_FILE"; then
        error_exit "ArgoCD bootstrap failed"
    fi

    log "ArgoCD bootstrapped successfully"
}

# Wait for ArgoCD
wait_for_argocd() {
    step "Waiting for ArgoCD to be Ready"

    if ! "$SCRIPT_DIR/wait-for-argocd.sh" 2>&1 | tee -a "$LOG_FILE"; then
        error_exit "ArgoCD did not become ready in time"
    fi

    log "ArgoCD is ready"
}

# Deploy applications
deploy_applications() {
    step "Deploying Fineract Applications via ArgoCD"

    log_info "Deploying app-of-apps pattern:"
    log_info "- Sealed Secrets (secrets management)"
    log_info "- Platform Services (PostgreSQL, Redis, Keycloak)"
    log_info "- Fineract backend"
    log_info "- Web Applications"
    log_info "- OAuth2 Proxy (authentication)"
    log_info "Note: Monitoring and Logging are disabled for this deployment"

    if ! "$SCRIPT_DIR/deploy-app-of-apps.sh" "$ENV" 2>&1 | tee -a "$LOG_FILE"; then
        error_exit "Application deployment failed"
    fi

    log "Applications deployed successfully"
}

# Wait for sync
wait_for_sync() {
    step "Waiting for ArgoCD Sync Completion"

    if ! "$SCRIPT_DIR/wait-for-sync.sh" "$ENV" 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "Some applications may not be fully synced"
    else
        log "All applications synced successfully"
    fi
}

# Health check
health_check() {
    step "Running Deployment Health Checks"

    if ! "$SCRIPT_DIR/deployment-health-check.sh" "$ENV" 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "Some health checks failed, but deployment may still be functional"
    else
        log "All health checks passed"
    fi
}

# Print summary
print_summary() {
    echo ""
    log "========================================"
    log "  DEPLOYMENT COMPLETE!"
    log "========================================"
    echo ""
    log_info "Environment: $ENV"
    log_info "Deployment Time: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds"
    log_info "Log file: $LOG_FILE"
    echo ""
    log "Next steps:"
    log "1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log "2. Get ArgoCD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    log "3. Check deployment status: make status ENV=$ENV"
    log "4. Run smoke tests: make test ENV=$ENV"
    echo ""
    log "Access URLs (via port-forward):"
    log "- ArgoCD: https://localhost:8080"
    log "- Fineract API: kubectl port-forward -n fineract-$ENV svc/fineract-write 8443:8443"
    log "- Keycloak: kubectl port-forward -n fineract-$ENV svc/keycloak 8080:8080"
    echo ""
}

# Main deployment flow
main() {
    log "========================================"
    log "  Fineract GitOps - Full Stack Deploy"
    log "========================================"
    log "Environment: $ENV"
    log "Start Time: $(date)"
    log "Log File: $LOG_FILE"
    echo ""

    # Execute deployment steps
    validate_prerequisites
    deploy_infrastructure
    setup_kubeconfig
    bootstrap_argocd
    wait_for_argocd
    deploy_applications
    wait_for_sync
    health_check

    # Print summary
    print_summary

    exit 0
}

# Run main
main "$@"
