#!/usr/bin/env bash
#
# Wait for Load Balancer and Sync Script
# This script orchestrates complete automated deployment with Load Balancer DNS management
#
# Usage:
#   ./scripts/wait-for-lb-and-sync.sh <environment>
#
# Features:
#   - Waits for Ingress LoadBalancer to get DNS assignment
#   - Updates ALL configuration files with LoadBalancer DNS
#   - Commits and pushes changes to Git
#   - Monitors ArgoCD sync completion
#   - Runs comprehensive health checks
#   - Validates application endpoints
#
# This is the "one-stop" script for complete automated deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging functions
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"; }
log_info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"; }
log_step() { echo -e "${CYAN}▶${NC} $*"; }
log_success() { echo -e "${MAGENTA}✓${NC} $*"; }

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 <environment>

Complete automated deployment with Load Balancer DNS management and health checks.

Arguments:
  environment    Target environment (dev, uat, production)

Features:
  1. Wait for Ingress LoadBalancer to get DNS assignment
  2. Update ALL configuration files with LoadBalancer DNS
  3. Commit and push changes to Git
  4. Monitor ArgoCD sync completion
  5. Run comprehensive health checks
  6. Validate application endpoints

Example:
  $0 dev

This script provides a COMPLETE automated deployment flow from
LoadBalancer assignment to verified application health.

EOF
    exit 1
}

# Validate arguments
if [ $# -ne 1 ]; then
    log_error "Error: Missing environment argument"
    usage
fi

ENV="$1"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    log_error "Error: Invalid environment '$ENV'"
    log_info "Valid environments: dev, uat, production"
    exit 1
fi

# Set namespace based on environment
NAMESPACE="fineract-${ENV}"

# Set kubeconfig based on environment
KUBECONFIG_FILE="${HOME}/.kube/config-fineract-${ENV}"

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_FILE" ]; then
    log_error "Kubeconfig not found: $KUBECONFIG_FILE"
    log_info "Run: aws eks update-kubeconfig --name apache-fineract-${ENV} --region eu-central-1 --kubeconfig $KUBECONFIG_FILE"
    exit 1
fi

log "========================================="
log "  Wait for LB and Sync Script"
log "========================================="
log_info "Environment: $ENV"
log_info "Namespace: $NAMESPACE"
log_info "Kubeconfig: $KUBECONFIG_FILE"
echo ""

# Step 1: Wait for Ingress Controller
wait_for_ingress() {
    log_step "Step 1/7: Waiting for Ingress Controller..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n ingress-nginx ingress-nginx-controller &>/dev/null; then
            # Wait for deployment to be ready
            if KUBECONFIG="$KUBECONFIG_FILE" kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=30s &>/dev/null; then
                log_success "Ingress Controller is ready"
                echo ""
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for Ingress Controller... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    log_error "Ingress Controller did not become ready in time"
    exit 1
}

# Step 2: Wait for LoadBalancer DNS
wait_for_loadbalancer() {
    log_step "Step 2/7: Waiting for LoadBalancer DNS..."

    local max_attempts=60
    local attempt=0
    local LOADBALANCER_DNS=""

    while [ $attempt -lt $max_attempts ]; do
        LOADBALANCER_DNS=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get svc -n ingress-nginx ingress-nginx-controller \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

        # Fallback to IP if hostname is not available
        if [ -z "$LOADBALANCER_DNS" ]; then
            LOADBALANCER_DNS=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get svc -n ingress-nginx ingress-nginx-controller \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        fi

        if [ -n "$LOADBALANCER_DNS" ]; then
            log_success "LoadBalancer DNS: $LOADBALANCER_DNS"
            echo "$LOADBALANCER_DNS" > /tmp/lb-dns-${ENV}.txt
            echo ""
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for LoadBalancer DNS... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    log_error "LoadBalancer did not get DNS assignment in time"
    exit 1
}

# Step 3: Update Load Balancer DNS in configuration files
update_lb_dns() {
    log_step "Step 3/7: Updating Load Balancer DNS in configuration files..."

    if ! "$SCRIPT_DIR/auto-update-lb-dns.sh" "$ENV"; then
        log_error "Failed to update Load Balancer DNS"
        exit 1
    fi

    log_success "Load Balancer DNS updated in all files"
    echo ""
}

# Step 4: Commit and push changes
commit_and_push() {
    log_step "Step 4/7: Committing and pushing changes..."

    # Check if there are changes
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes detected, skipping commit/push"
        echo ""
        return 0
    fi

    # Add all updated files
    git add config/loadbalancer-dns-configmap.yaml
    git add environments/${ENV}/loadbalancer-config.yaml
    git add environments/${ENV}/fineract-oauth2-config-patch.yaml
    git add apps/ingress/overlays/${ENV}/ingress-config.yaml
    git add apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml
    git add apps/keycloak/overlays/${ENV}/kustomization.yaml
    git add operations/keycloak-config/overlays/${ENV}/kustomization.yaml
    git add operations/fineract-config/overlays/${ENV}/kustomization.yaml

    local LOADBALANCER_DNS=$(cat /tmp/lb-dns-${ENV}.txt)
    git commit -m "chore: auto-update LoadBalancer DNS for ${ENV} environment (${LOADBALANCER_DNS})"

    log_success "Changes committed"

    # Get current branch
    local branch=$(git rev-parse --abbrev-ref HEAD)
    git push origin "$branch"

    log_success "Changes pushed to origin/$branch"
    echo ""
}

# Step 5: Wait for ArgoCD sync
wait_for_argocd_sync() {
    log_step "Step 5/7: Waiting for ArgoCD sync completion..."

    # ArgoCD will automatically detect changes and sync
    log_info "ArgoCD will automatically detect changes and sync..."
    log_info "Waiting 30 seconds for ArgoCD to start sync..."
    sleep 30

    local max_attempts=120  # 10 minutes max
    local attempt=0
    local synced_count=0
    local total_apps=0

    # Get total applications
    total_apps=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' | wc -w)

    if [ "$total_apps" -eq 0 ]; then
        log_warn "No ArgoCD applications found"
        log_info "Deployments will proceed via manual kubectl apply"
        echo ""
        return 0
    fi

    log_info "Total ArgoCD applications: $total_apps"

    while [ $attempt -lt $max_attempts ]; do
        # Count synced and healthy applications
        synced_count=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get applications -n argocd \
            -o jsonpath='{.items[?(@.status.sync.status=="Synced")].metadata.name}' | wc -w)

        if [ "$synced_count" -eq "$total_apps" ]; then
            log_success "All ArgoCD applications synced ($synced_count/$total_apps)"
            echo ""
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for ArgoCD sync... ($synced_count/$total_apps synced, attempt $attempt/$max_attempts)"
        sleep 5
    done

    log_warn "ArgoCD sync not complete within timeout"
    log_info "Current status: $synced_count/$total_apps synced"
    log_info "Check manually: kubectl get applications -n argocd"
    echo ""
}

# Step 6: Health checks
run_health_checks() {
    log_step "Step 6/7: Running health checks..."

    local health_passed=0
    local health_total=0

    # Check if namespace exists
    ((health_total++))
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_success "Namespace $NAMESPACE exists"
        ((health_passed++))
    else
        log_warn "Namespace $NAMESPACE not found"
    fi

    # Check Redis StatefulSet
    ((health_total++))
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get statefulset -n "$NAMESPACE" fineract-redis &>/dev/null; then
        local redis_ready=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get statefulset -n "$NAMESPACE" fineract-redis -o jsonpath='{.status.readyReplicas}')
        if [ "$redis_ready" -ge 1 ]; then
            log_success "Redis is ready ($redis_ready/1 replica)"
            ((health_passed++))
        else
            log_warn "Redis not ready (ready: $redis_ready/1)"
        fi
    else
        log_warn "Redis StatefulSet not found"
    fi

    # Check Keycloak deployment
    ((health_total++))
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" keycloak &>/dev/null; then
        local keycloak_ready=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" keycloak -o jsonpath='{.status.readyReplicas}')
        if [ "$keycloak_ready" -ge 1 ]; then
            log_success "Keycloak is ready ($keycloak_ready/1 replica)"
            ((health_passed++))
        else
            log_warn "Keycloak not ready (ready: $keycloak_ready/1)"
        fi
    else
        log_warn "Keycloak deployment not found"
    fi

    # Check Fineract deployments
    for deployment in fineract-write fineract-read fineract-batch; do
        ((health_total++))
        if KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" "$deployment" &>/dev/null; then
            local replicas=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.spec.replicas}')
            local ready=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.status.readyReplicas}')
            if [ "$ready" -eq "$replicas" ]; then
                log_success "$deployment is ready ($ready/$replicas replicas)"
                ((health_passed++))
            else
                log_warn "$deployment not ready (ready: $ready/$replicas)"
            fi
        else
            log_warn "$deployment not found"
        fi
    done

    # Check OAuth2 Proxy
    ((health_total++))
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" oauth2-proxy &>/dev/null; then
        local oauth_ready=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get deployment -n "$NAMESPACE" oauth2-proxy -o jsonpath='{.status.readyReplicas}')
        if [ "$oauth_ready" -ge 1 ]; then
            log_success "OAuth2 Proxy is ready ($oauth_ready/1 replica)"
            ((health_passed++))
        else
            log_warn "OAuth2 Proxy not ready (ready: $oauth_ready/1)"
        fi
    else
        log_warn "OAuth2 Proxy not found"
    fi

    log ""
    log_info "Health Check Results: $health_passed/$health_total passed"

    if [ "$health_passed" -eq "$health_total" ]; then
        log_success "All health checks passed!"
    else
        log_warn "Some health checks failed, but deployment may still be functional"
    fi
    echo ""
}

# Step 7: Validate endpoints
validate_endpoints() {
    log_step "Step 7/7: Validating application endpoints..."

    local LOADBALANCER_DNS=$(cat /tmp/lb-dns-${ENV}.txt)

    # Test LoadBalancer endpoint
    log_info "Testing LoadBalancer endpoint: https://${LOADBALANCER_DNS}"
    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${LOADBALANCER_DNS}" || echo "000")

    if [ "$http_code" != "000" ]; then
        log_success "LoadBalancer endpoint is accessible (HTTP $http_code)"
    else
        log_warn "LoadBalancer endpoint not accessible (timed out or DNS not propagated)"
    fi

    # Test Keycloak endpoint
    log_info "Testing Keycloak endpoint: https://${LOADBALANCER_DNS}/auth/realms/fineract"
    local kc_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${LOADBALANCER_DNS}/auth/realms/fineract" || echo "000")

    if [ "$kc_code" != "000" ]; then
        log_success "Keycloak endpoint is accessible (HTTP $kc_code)"
    else
        log_warn "Keycloak endpoint not accessible (timed out or DNS not propagated)"
    fi

    # Test Fineract API endpoint (may require authentication, so just check connectivity)
    log_info "Testing Fineract API endpoint: https://${LOADBALANCER_DNS}/fineract-provider/api/v1"
    local api_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${LOADBALANCER_DNS}/fineract-provider/api/v1" || echo "000")

    if [ "$api_code" != "000" ]; then
        log_success "Fineract API endpoint is accessible (HTTP $api_code)"
    else
        log_warn "Fineract API endpoint not accessible (may require authentication)"
    fi

    echo ""
}

# Print summary
print_summary() {
    local LOADBALANCER_DNS=$(cat /tmp/lb-dns-${ENV}.txt)

    log "========================================="
    log "  Deployment Complete!"
    log "========================================="
    echo ""
    log_info "Environment: $ENV"
    log_info "Namespace: $NAMESPACE"
    log_info "LoadBalancer DNS: $LOADBALANCER_DNS"
    echo ""

    log "Access URLs:"
    log "  LoadBalancer: https://${LOADBALANCER_DNS}"
    log "  Keycloak: https://${LOADBALANCER_DNS}/auth/realms/fineract"
    log "  Fineract API: https://${LOADBALANCER_DNS}/fineract-provider/api/v1"
    echo ""

    log "Next steps:"
    log "  1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log "  2. Get ArgoCD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    log "  3. Monitor deployments: kubectl get pods -n $NAMESPACE"
    log "  4. View logs: kubectl logs -n $NAMESPACE -l app=fineract-write -f"
    echo ""

    log "Update /etc/hosts for local access:"
    local lb_ip=$(dig +short $LOADBALANCER_DNS | head -1)
    if [ -n "$lb_ip" ]; then
        log "  $lb_ip  apps.dev.fineract.com"
        log "  $lb_ip  auth.dev.fineract.com"
    fi
    echo ""

    # Cleanup
    rm -f /tmp/lb-dns-${ENV}.txt
}

# Step 8: Validate Ingress DNS configuration
validate_ingress_dns() {
    log_step "Step 8/8: Validating Ingress DNS configuration..."
    echo

    # Run DNS validation script
    if ! ./scripts/validate-ingress-dns.sh "$ENV"; then
        log_warn "Ingress DNS validation failed"
        log_warn "Review validation output above for remediation steps"
        log_warn "Applications may not be accessible"
        echo ""
    else
        log "✓ Ingress DNS validation passed"
    fi
    echo ""
}

# Main execution
main() {
    # Execute steps
    wait_for_ingress
    wait_for_loadbalancer
    update_lb_dns
    commit_and_push
    wait_for_argocd_sync
    run_health_checks
    validate_endpoints
    validate_ingress_dns
 
    # Print summary
    print_summary
 
    exit 0
}

# Run main
main "$@"
