#!/usr/bin/env bash
#
# Automated Load Balancer DNS Update Script
# This script is the SINGLE SOURCE OF TRUTH for updating all LoadBalancer DNS references
#
# Usage:
#   ./scripts/auto-update-lb-dns.sh <environment> [--commit] [--push]
#
# Features:
#   - Waits for LoadBalancer to get DNS assignment
#   - Updates ALL files that reference LoadBalancer DNS
#   - Validates consistency across all updated files
#   - Optionally commits and pushes changes to Git
#   - Triggers ArgoCD sync automatically
#
# Files Updated:
#   - config/loadbalancer-dns-configmap.yaml
#   - environments/<env>/loadbalancer-config.yaml
#   - apps/ingress/overlays/<env>/ingress-config.yaml
#   - apps/oauth2-proxy/overlays/<env>/kustomization.yaml
#   - apps/keycloak/overlays/<env>/kustomization.yaml
#   - operations/keycloak-config/overlays/<env>/kustomization.yaml
#   - environments/<env>/fineract-oauth2-config-patch.yaml

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 <environment> [OPTIONS]

Automatically updates LoadBalancer DNS configuration across all configuration files.

Arguments:
  environment    Target environment (dev, uat, production)

Options:
  --commit        Commit changes to Git after updating files
  --push          Push changes to Git after committing
  --skip-wait     Skip waiting for LoadBalancer (use existing value)

Examples:
  # Update and display changes (no commit)
  $0 dev

  # Update, commit, and push
  $0 dev --commit --push

  # Skip waiting (use existing DNS from cluster)
  $0 production --skip-wait

This script will:
  1. Wait for Ingress LoadBalancer to get DNS assigned
  2. Extract the LoadBalancer DNS/hostname
  3. Update ALL configuration files with new DNS
  4. Validate consistency across all files
  5. Optionally commit and push to Git

EOF
    exit 1
}

# Validate arguments
if [ $# -lt 1 ]; then
    log_error "Error: Missing environment argument"
    usage
fi

ENV="$1"
DO_COMMIT=false
DO_PUSH=false
SKIP_WAIT=false

# Parse options
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --commit)
            DO_COMMIT=true
            shift
            ;;
        --push)
            DO_PUSH=true
            shift
            ;;
        --skip-wait)
            SKIP_WAIT=true
            shift
            ;;
        *)
            log_error "Error: Unknown option $1"
            usage
            ;;
    esac
done

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
log "  Automated Load Balancer DNS Update"
log "========================================="
log_info "Environment: $ENV"
log_info "Namespace: $NAMESPACE"
log_info "Kubeconfig: $KUBECONFIG_FILE"
log_info "Skip Wait: $SKIP_WAIT"
log_info "Auto Commit: $DO_COMMIT"
log_info "Auto Push: $DO_PUSH"
echo ""

# Step 1: Get LoadBalancer DNS
get_loadbalancer_dns() {
    log_step "Step 1: Getting LoadBalancer DNS..."

    if [ "$SKIP_WAIT" = true ]; then
        log_info "Skipping wait, using current LoadBalancer DNS..."
        LOADBALANCER_DNS=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get svc -n ingress-nginx ingress-nginx-controller \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

        # Fallback to IP if hostname is not available
        if [ -z "$LOADBALANCER_DNS" ]; then
            LOADBALANCER_DNS=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get svc -n ingress-nginx ingress-nginx-controller \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        fi

        # Add validation
        if [ -z "$LOADBALANCER_DNS" ]; then
            log_error "LoadBalancer DNS not found even with --skip-wait"
            log_info "Check that: 1) Cluster is accessible, 2) Ingress controller is deployed"
            log_info "Run: kubectl --kubeconfig=$KUBECONFIG_FILE get svc -n ingress-nginx"
            exit 1
        fi
    else
        log_info "Waiting for LoadBalancer DNS assignment..."
        local max_attempts=30
        local attempt=0

        while [ $attempt -lt $max_attempts ]; do
            LOADBALANCER_DNS=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get svc -n ingress-nginx ingress-nginx-controller \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

            # Fallback to IP if hostname is not available
            if [ -z "$LOADBALANCER_DNS" ]; then
                LOADBALANCER_DNS=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get svc -n ingress-nginx ingress-nginx-controller \
                    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            fi

            if [ -n "$LOADBALANCER_DNS" ]; then
                log "✓ LoadBalancer DNS: $LOADBALANCER_DNS"
                break
            fi

            attempt=$((attempt + 1))
            log_info "Waiting for LoadBalancer... (attempt $attempt/$max_attempts)"
            sleep 10
        done

        if [ -z "$LOADBALANCER_DNS" ]; then
            log_error "Failed to retrieve LoadBalancer DNS after $max_attempts attempts"
            log_info "Make sure the Nginx Ingress Controller is deployed and the LoadBalancer service is ready"
            exit 1
        fi
    fi

    if [ -z "$LOADBALANCER_DNS" ]; then
        log_error "Failed to retrieve LoadBalancer DNS"
        exit 1
    fi

    log "✓ LoadBalancer DNS: $LOADBALANCER_DNS"
    echo ""
}

# Step 2: Update central ConfigMap
update_central_configmap() {
    log_step "Step 2: Updating central Load Balancer DNS ConfigMap..."

    local config_file="${REPO_ROOT}/config/loadbalancer-dns-configmap.yaml"

    if [ ! -f "$config_file" ]; then
        log_error "ConfigMap file not found: $config_file"
        exit 1
    fi

    # Update lb-dns value
    sed -i.tmp "s|lb-dns: \".*\"|lb-dns: \"${LOADBALANCER_DNS}\"|g" "$config_file"
    rm -f "${config_file}.tmp"

    # Update environment
    sed -i.tmp "s|environment: \".*\"|environment: \"${ENV}\"|g" "$config_file"
    rm -f "${config_file}.tmp"

    # Update timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    sed -i.tmp "s|last-updated: \".*\"|last-updated: \"${timestamp}\"|g" "$config_file"
    rm -f "${config_file}.tmp"

    log "✓ Updated: $config_file"
    echo ""
}

# Step 3: Update environment-specific config files
update_environment_configs() {
    log_step "Step 3: Updating environment-specific configurations..."

    local env_dir="${REPO_ROOT}/environments/${ENV}"
    local files_updated=0

    # Update loadbalancer-config.yaml
    local lb_config="${env_dir}/loadbalancer-config.yaml"
    if [ -f "$lb_config" ]; then
        sed -i.tmp "s|LOADBALANCER_DNS: \".*\"|LOADBALANCER_DNS: \"${LOADBALANCER_DNS}\"|g" "$lb_config"
        sed -i.tmp "s|APPS_HOSTNAME: \".*\"|APPS_HOSTNAME: \"${LOADBALANCER_DNS}\"|g" "$lb_config"
        sed -i.tmp "s|AUTH_HOSTNAME: \".*\"|AUTH_HOSTNAME: \"${LOADBALANCER_DNS}\"|g" "$lb_config"
        rm -f "${lb_config}.tmp"
        log "  ✓ Updated: environments/${ENV}/loadbalancer-config.yaml"
        ((++files_updated))
    fi

    # Update fineract-oauth2-config-patch.yaml
    local oauth_patch="${env_dir}/fineract-oauth2-config-patch.yaml"
    if [ -f "$oauth_patch" ]; then
        # Update OIDC issuer URL with new LoadBalancer DNS
        sed -i.tmp "s|oidc-issuer-url: \".*\"|oidc-issuer-url: \"https://${LOADBALANCER_DNS}/auth/realms/fineract\"|g" "$oauth_patch"
        rm -f "${oauth_patch}.tmp"
        log "  ✓ Updated: environments/${ENV}/fineract-oauth2-config-patch.yaml"
        ((++files_updated))
    fi

    log "✓ Updated $files_updated file(s) in environments/${ENV}/"
    echo ""
}

# Step 4: Update app overlay configurations
update_app_overlays() {
    log_step "Step 4: Updating app overlay configurations..."

    local files_updated=0

    # Update ingress config
    # Check if ingress-config.yaml exists (All environments now use this format)
    local ingress_config_yaml="${REPO_ROOT}/apps/ingress/overlays/${ENV}/ingress-config.yaml"
    if [ -f "$ingress_config_yaml" ]; then
        sed -i.tmp "s|apps-hostname: .*|apps-hostname: ${LOADBALANCER_DNS}|g" "$ingress_config_yaml"
        sed -i.tmp "s|auth-hostname: .*|auth-hostname: ${LOADBALANCER_DNS}|g" "$ingress_config_yaml"
        # Match both ELB hostnames and PENDING placeholders
        sed -i.tmp "s|auth-signin-url: https://[^/]*/oauth2/start|auth-signin-url: https://${LOADBALANCER_DNS}/oauth2/start|g" "$ingress_config_yaml"
        sed -i.tmp "s|cors-allow-origin-url: https://.*|cors-allow-origin-url: https://${LOADBALANCER_DNS}|g" "$ingress_config_yaml"
        rm -f "${ingress_config_yaml}.tmp"
        log "  ✓ Updated: apps/ingress/overlays/${ENV}/ingress-config.yaml"
        ((++files_updated))
    else
        # Fallback: This should not be needed anymore as all environments use ingress-config.yaml
        local ingress_kustomization="${REPO_ROOT}/apps/ingress/overlays/${ENV}/kustomization.yaml"
        if [ -f "$ingress_kustomization" ]; then
            sed -i.tmp "s|- apps-hostname=.*|- apps-hostname=${LOADBALANCER_DNS}|g" "$ingress_kustomization"
            sed -i.tmp "s|- auth-hostname=.*|- auth-hostname=${LOADBALANCER_DNS}|g" "$ingress_kustomization"
            rm -f "${ingress_kustomization}.tmp"
            log "  ✓ Updated: apps/ingress/overlays/${ENV}/kustomization.yaml (configMapGenerator)"
            ((++files_updated))
        else
            log_warn "  ⚠ No ingress config found in apps/ingress/overlays/${ENV}/"
        fi
    fi

    # Update oauth2-proxy config (if configMapGenerator exists with apps-hostname)
    local oauth_config="${REPO_ROOT}/apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml"
    if [ -f "$oauth_config" ]; then
        # Check if file has configMapGenerator with apps-hostname (Dev environment pattern)
        if grep -q "configMapGenerator:" "$oauth_config" && grep -q "apps-hostname=" "$oauth_config"; then
            sed -i.tmp "s|- apps-hostname=.*|- apps-hostname=${LOADBALANCER_DNS}|g" "$oauth_config"
            sed -i.tmp "s|- auth-hostname=.*|- auth-hostname=${LOADBALANCER_DNS}|g" "$oauth_config"
            rm -f "${oauth_config}.tmp"
            log "  ✓ Updated: apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml (configMapGenerator)"
            ((++files_updated))
        else
            log "  ℹ Skipped: apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml (no configMapGenerator to update)"
            log "    OAuth2 Proxy uses ingress-config from apps/ingress/overlays/${ENV}/kustomization.yaml"
        fi
    fi

    # Update keycloak config
    local keycloak_config="${REPO_ROOT}/apps/keycloak/overlays/${ENV}/kustomization.yaml"
    if [ -f "$keycloak_config" ]; then
        sed -i.tmp "s|- auth-hostname=.*|- auth-hostname=${LOADBALANCER_DNS}|g" "$keycloak_config"
        # Only replace KC_HOSTNAME value - match ELB DNS patterns specifically
        # Pattern matches: hex-hex.elb.region.amazonaws.com (LoadBalancer DNS format)
        sed -i.tmp 's|value: [a-f0-9]\{32\}-[a-f0-9]\{16\}\.elb\.[a-z0-9-]*\.amazonaws\.com|value: '"${LOADBALANCER_DNS}"'|g' "$keycloak_config"
        # Also match PENDING placeholder if used
        sed -i.tmp "s|value: PENDING_LOADBALANCER_DNS|value: ${LOADBALANCER_DNS}|g" "$keycloak_config"
        rm -f "${keycloak_config}.tmp"
        log "  ✓ Updated: apps/keycloak/overlays/${ENV}/kustomization.yaml"
        ((++files_updated))
    fi

    log "✓ Updated $files_updated file(s) in apps/"
    echo ""
}

# Step 5: Update operations configurations
update_operations_configs() {
    log_step "Step 5: Updating operations configurations..."

    local files_updated=0

    # Update keycloak-config overlay
    local kc_config="${REPO_ROOT}/operations/keycloak-config/overlays/${ENV}/kustomization.yaml"
    if [ -f "$kc_config" ]; then
        sed -i.tmp "s|- apps-hostname=.*|- apps-hostname=${LOADBALANCER_DNS}|g" "$kc_config"
        sed -i.tmp "s|- auth-hostname=.*|- auth-hostname=${LOADBALANCER_DNS}|g" "$kc_config"
        rm -f "${kc_config}.tmp"
        log "  ✓ Updated: operations/keycloak-config/overlays/${ENV}/kustomization.yaml"
        ((++files_updated))
    fi

    # Update fineract-config overlay
    local fineract_config="${REPO_ROOT}/operations/fineract-config/overlays/${ENV}/kustomization.yaml"
    if [ -f "$fineract_config" ]; then
        sed -i.tmp "s|- auth-hostname=.*|- auth-hostname=${LOADBALANCER_DNS}|g" "$fineract_config"
        rm -f "${fineract_config}.tmp"
        log "  ✓ Updated: operations/fineract-config/overlays/${ENV}/kustomization.yaml"
        ((++files_updated))
    fi

    log "✓ Updated $files_updated file(s) in operations/"
    echo ""
}

# Step 6: Validate consistency
validate_consistency() {
    log_step "Step 6: Validating consistency across all files..."

    local inconsistencies=0
    local file_list=(
        "${REPO_ROOT}/environments/${ENV}/loadbalancer-config.yaml"
        "${REPO_ROOT}/apps/ingress/overlays/${ENV}/ingress-config.yaml"
        "${REPO_ROOT}/apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml"
        "${REPO_ROOT}/apps/keycloak/overlays/${ENV}/kustomization.yaml"
    )

    for file in "${file_list[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "  File not found: $file"
            continue
        fi

        # Check if file contains the LoadBalancer DNS
        if grep -q "$LOADBALANCER_DNS" "$file"; then
            log "  ✓ $file - Contains correct DNS"
        else
            log_warn "  ⚠ $file - May not contain correct DNS"
            ((++inconsistencies))
        fi
    done

    if [ $inconsistencies -gt 0 ]; then
        log_warn "⚠ Found $inconsistencies potential inconsistency(ies)"
    else
        log "✓ All files validated successfully"
    fi
    echo ""
}

# Step 7: Restart OAuth2 Proxy to pick up new DNS
restart_oauth2_proxy() {
    log_step "Step 7: Restarting OAuth2 Proxy to pick up new configuration..."

    if kubectl --kubeconfig="$KUBECONFIG_FILE" get deployment -n "$NAMESPACE" oauth2-proxy &>/dev/null; then
        kubectl --kubeconfig="$KUBECONFIG_FILE" rollout restart deployment/oauth2-proxy -n "$NAMESPACE"
        log "✓ OAuth2 Proxy rollout restart triggered"

        # Wait for rollout to complete (timeout 2 minutes)
        if kubectl --kubeconfig="$KUBECONFIG_FILE" rollout status deployment/oauth2-proxy -n "$NAMESPACE" --timeout=120s; then
            log "✓ OAuth2 Proxy rollout completed successfully"
        else
            log_warn "OAuth2 Proxy rollout timed out (pod may still be starting)"
        fi
    else
        log_info "OAuth2 Proxy deployment not found (may not be deployed yet)"
    fi
    echo ""
}

# Step 8: Commit and push
commit_and_push() {
    if [ "$DO_COMMIT" = false ] && [ "$DO_PUSH" = false ]; then
        log_info "Skipping Git commit/push (use --commit and/or --push)"
        return 0
    fi

    log_step "Step 8: Committing and pushing changes..."

    # Check if there are changes
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes detected, skipping commit"
        return 0
    fi

    # Add all updated files
    git add config/loadbalancer-dns-configmap.yaml
    git add environments/${ENV}/loadbalancer-config.yaml
    git add environments/${ENV}/fineract-oauth2-config-patch.yaml

    # Add ingress config (either ingress-config.yaml or kustomization.yaml)
    if [ -f "${REPO_ROOT}/apps/ingress/overlays/${ENV}/ingress-config.yaml" ]; then
        git add apps/ingress/overlays/${ENV}/ingress-config.yaml
    elif [ -f "${REPO_ROOT}/apps/ingress/overlays/${ENV}/kustomization.yaml" ]; then
        git add apps/ingress/overlays/${ENV}/kustomization.yaml
    fi

    # Add OAuth2 Proxy (always updated if configMapGenerator exists)
    git add apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml

    git add apps/keycloak/overlays/${ENV}/kustomization.yaml
    git add operations/keycloak-config/overlays/${ENV}/kustomization.yaml
    git add operations/fineract-config/overlays/${ENV}/kustomization.yaml

    if [ "$DO_COMMIT" = true ]; then
        local commit_message="chore: auto-update LoadBalancer DNS for ${ENV} environment (${LOADBALANCER_DNS})"
        git commit -m "$commit_message"
        log "✓ Changes committed"
    fi

    if [ "$DO_PUSH" = true ]; then
        # Get current branch
        local branch=$(git rev-parse --abbrev-ref HEAD)
        git push origin "$branch"
        log "✓ Changes pushed to origin/$branch"
    fi
    echo ""
}

# Step 9: Trigger ArgoCD sync
trigger_argocd_sync() {
    if [ "$DO_PUSH" = true ]; then
        log_step "Step 9: Triggering ArgoCD sync..."

        # ArgoCD will automatically detect changes and sync
        # Just wait a moment for the webhook to trigger
        sleep 5

        log "✓ ArgoCD will auto-sync within 1-2 minutes"
        log_info "Monitor sync: kubectl get applications -n argocd"
        echo ""
    else
        log_info "Skipping ArgoCD trigger (changes not pushed)"
    fi
}

# Print summary
print_summary() {
    log "========================================="
    log "  Load Balancer DNS Update Complete!"
    log "========================================="
    echo ""
    log_info "Environment: $ENV"
    log_info "LoadBalancer DNS: $LOADBALANCER_DNS"
    log_info "Files Updated: Multiple (see above)"
    echo ""

    if [ "$DO_COMMIT" = true ] && [ "$DO_PUSH" = true ]; then
        log "Next steps:"
        log "  1. Monitor ArgoCD sync: kubectl get applications -n argocd"
        log "  2. Check deployment: kubectl get pods -n $NAMESPACE"
        log "  3. Verify access: curl -k https://${LOADBALANCER_DNS}"
    elif [ "$DO_COMMIT" = true ]; then
        log "Next steps:"
        log "  1. Review changes: git diff HEAD~1"
        log "  2. Push when ready: git push"
        log "  3. ArgoCD will sync automatically after push"
    else
        log "Next steps:"
        log "  1. Review changes: git diff"
        log "  2. Commit changes: git add -A && git commit -m 'chore: update LoadBalancer DNS'"
        log "  3. Push changes: git push"
        log "  4. ArgoCD will sync automatically after push"
    fi
    echo ""
}

# Main execution
main() {
    # Execute steps
    get_loadbalancer_dns
    update_central_configmap
    update_environment_configs
    update_app_overlays
    update_operations_configs
    validate_consistency
    restart_oauth2_proxy
    commit_and_push
    trigger_argocd_sync

    # Print summary
    print_summary

    exit 0
}

# Run main
main "$@"
