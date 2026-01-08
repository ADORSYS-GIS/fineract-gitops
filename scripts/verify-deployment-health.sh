#!/bin/bash
#
# Fineract Deployment Health Check Script
#
# This script verifies the health of a Fineract deployment on Kubernetes.
# It can be run standalone or called from the deployment script.
#
# Usage:
#   ./scripts/verify-deployment-health.sh [environment] [--quick|--full]
#
# Arguments:
#   environment  - Environment name (dev, uat, prod). Default: dev
#   --quick     - Quick health check (5 minutes)
#   --full      - Full health check (15 minutes). Default mode.
#
# Exit Codes:
#   0 - All health checks passed
#   1 - One or more health checks failed
#   2 - Script usage error
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="${1:-dev}"
MODE="${2:---full}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "${GREEN}✓${NC} $*"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

check_pass() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log "$*"
}

check_fail() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    log_error "$*"
}

check_warn() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    log_warn "$*"
}

# =============================================================================
# Validation
# =============================================================================

if [ "$MODE" != "--quick" ] && [ "$MODE" != "--full" ]; then
    echo "Usage: $0 [environment] [--quick|--full]"
    echo "  environment: dev, uat, prod (default: dev)"
    echo "  --quick: Quick health check (5 minutes)"
    echo "  --full: Full health check (15 minutes, default)"
    exit 2
fi

NAMESPACE="fineract-${ENV}"

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}         Fineract Deployment Health Check                      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
echo "Environment: ${ENV}"
echo "Namespace: ${NAMESPACE}"
echo "Mode: ${MODE}"
echo

# Check KUBECONFIG
if [ -z "${KUBECONFIG:-}" ]; then
    log_error "KUBECONFIG environment variable not set"
    exit 2
fi

if [ ! -f "$KUBECONFIG" ]; then
    log_error "KUBECONFIG file not found: $KUBECONFIG"
    exit 2
fi

# Check cluster connectivity
log_info "Checking cluster connectivity..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 2
fi
check_pass "Connected to Kubernetes cluster"

# =============================================================================
# PHASE 1: Namespace and Basic Resources
# =============================================================================

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 1: Namespace and Basic Resources${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Check namespace exists
if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    check_pass "Namespace $NAMESPACE exists"
else
    check_fail "Namespace $NAMESPACE does not exist"
fi

# Check namespace is active (not terminating)
NS_STATUS=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [ "$NS_STATUS" = "Active" ]; then
    check_pass "Namespace is Active"
elif [ "$NS_STATUS" = "Terminating" ]; then
    check_fail "Namespace is Terminating"
else
    check_warn "Namespace status: $NS_STATUS"
fi

# =============================================================================
# PHASE 2: ArgoCD Applications
# =============================================================================

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 2: ArgoCD Applications${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Checking ArgoCD application status..."

# Get all applications for this environment
APPS=$(kubectl get applications -n argocd -o json 2>/dev/null | \
    jq -r ".items[] | select(.metadata.name | startswith(\"fineract-${ENV}\")) | .metadata.name" || echo "")

if [ -z "$APPS" ]; then
    check_warn "No ArgoCD applications found for environment: $ENV"
else
    APP_COUNT=$(echo "$APPS" | wc -l | tr -d ' ')
    log_info "Found $APP_COUNT ArgoCD applications"

    SYNCED_COUNT=0
    HEALTHY_COUNT=0

    while read -r app; do
        SYNC_STATUS=$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH_STATUS=$(kubectl get application "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        if [ "$SYNC_STATUS" = "Synced" ]; then
            SYNCED_COUNT=$((SYNCED_COUNT + 1))
        fi

        if [ "$HEALTH_STATUS" = "Healthy" ]; then
            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
        fi

        if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
            check_pass "$app: Synced / Healthy"
        elif [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Progressing" ]; then
            check_warn "$app: Synced / Progressing"
        else
            check_fail "$app: $SYNC_STATUS / $HEALTH_STATUS"
        fi
    done <<< "$APPS"

    echo
    log_info "Summary: $SYNCED_COUNT/$APP_COUNT synced, $HEALTHY_COUNT/$APP_COUNT healthy"
fi

# =============================================================================
# PHASE 3: Pod Health
# =============================================================================

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 3: Pod Health${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

log_info "Checking pod status..."

# Get all pods (excluding completed jobs)
PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Succeeded -o json 2>/dev/null || echo '{"items":[]}')

POD_COUNT=$(echo "$PODS" | jq -r '.items | length')
log_info "Found $POD_COUNT active pods"

# Check for CrashLoopBackOff pods
CRASH_PODS=$(echo "$PODS" | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason=="CrashLoopBackOff") | .metadata.name' || echo "")
if [ -z "$CRASH_PODS" ]; then
    check_pass "No pods in CrashLoopBackOff"
else
    CRASH_COUNT=$(echo "$CRASH_PODS" | wc -l | tr -d ' ')
    check_fail "$CRASH_COUNT pod(s) in CrashLoopBackOff: $CRASH_PODS"
fi

# Check for ImagePullBackOff pods
IMAGE_PULL_PODS=$(echo "$PODS" | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason=="ImagePullBackOff") | .metadata.name' || echo "")
if [ -z "$IMAGE_PULL_PODS" ]; then
    check_pass "No pods with ImagePullBackOff"
else
    IMAGE_PULL_COUNT=$(echo "$IMAGE_PULL_PODS" | wc -l | tr -d ' ')
    check_fail "$IMAGE_PULL_COUNT pod(s) with ImagePullBackOff: $IMAGE_PULL_PODS"
fi

# Check running pods
RUNNING_PODS=$(echo "$PODS" | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name' || echo "")
RUNNING_COUNT=$(echo "$RUNNING_PODS" | wc -l | tr -d ' ')
if [ "$RUNNING_COUNT" -gt 0 ]; then
    check_pass "$RUNNING_COUNT pod(s) Running"
fi

# =============================================================================
# PHASE 4: Service Endpoints (Quick Mode)
# =============================================================================

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 4: Service Endpoints${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Get LoadBalancer DNS
log_info "Getting LoadBalancer DNS..."
LB_DNS=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -z "$LB_DNS" ]; then
    LB_DNS=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
fi

if [ -z "$LB_DNS" ]; then
    check_fail "LoadBalancer DNS/IP not found"
else
    check_pass "LoadBalancer DNS: $LB_DNS"
fi

# Test Keycloak (Keycloak 17+ serves from root path - no /auth prefix)
log_info "Testing Keycloak realm endpoint..."
if curl -k -s -o /dev/null -w "%{http_code}" "https://${LB_DNS}/realms/fineract" 2>/dev/null | grep -q "200\|302"; then
    check_pass "Keycloak realm endpoint is responding (HTTPS)"
elif curl -k -s -o /dev/null -w "%{http_code}" "http://${LB_DNS}/realms/fineract" 2>/dev/null | grep -q "200\|302"; then
    check_pass "Keycloak realm endpoint is responding (HTTP)"
else
    check_fail "Keycloak realm endpoint not responding"
fi

# Test OAuth2-Proxy ping
log_info "Testing OAuth2-Proxy /ping endpoint..."
if curl -k -s -f "https://${LB_DNS}/oauth2/ping" > /dev/null 2>&1; then
    check_pass "OAuth2-Proxy /ping endpoint is accessible (HTTPS)"
elif curl -k -s -f "http://${LB_DNS}/oauth2/ping" > /dev/null 2>&1; then
    check_pass "OAuth2-Proxy /ping endpoint is accessible (HTTP)"
else
    check_fail "OAuth2-Proxy /ping endpoint not accessible"
fi

# Test Fineract health
log_info "Testing Fineract actuator health endpoint..."
if curl -k -s "https://${LB_DNS}/fineract-provider/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then
    check_pass "Fineract actuator reports UP (HTTPS)"
elif curl -k -s "http://${LB_DNS}/fineract-provider/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then
    check_pass "Fineract actuator reports UP (HTTP)"
else
    check_warn "Fineract actuator health check did not return UP (may still be initializing)"
fi

# =============================================================================
# PHASE 5: Authentication Flow (Full Mode Only)
# =============================================================================

if [ "$MODE" = "--full" ]; then
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}PHASE 5: Authentication Flow${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo

    log_info "Verifying OAuth2 authentication is enforced..."
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${LB_DNS}/fineract-provider/api/v1/offices" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
        check_pass "Protected endpoint redirects to authentication (HTTP $HTTP_CODE)"
    elif [ "$HTTP_CODE" = "401" ]; then
        check_pass "Protected endpoint requires authentication (HTTP 401)"
    elif [ "$HTTP_CODE" = "200" ]; then
        check_fail "Protected endpoint returned 200 without authentication (OAuth2 not enforcing)"
    else
        check_warn "Unexpected response from protected endpoint (HTTP $HTTP_CODE)"
    fi

    # Test OIDC discovery (Keycloak 17+ serves from root path - no /auth prefix)
    log_info "Testing Keycloak OIDC discovery endpoint..."
    if curl -k -s "https://${LB_DNS}/realms/fineract/.well-known/openid-configuration" 2>/dev/null | jq -e '.authorization_endpoint' > /dev/null 2>&1; then
        check_pass "OIDC discovery endpoint returns valid configuration (HTTPS)"
    elif curl -k -s "http://${LB_DNS}/realms/fineract/.well-known/openid-configuration" 2>/dev/null | jq -e '.authorization_endpoint' > /dev/null 2>&1; then
        check_pass "OIDC discovery endpoint returns valid configuration (HTTP)"
    else
        check_fail "OIDC discovery endpoint not returning valid configuration"
    fi
fi

# =============================================================================
# Summary
# =============================================================================

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Health Check Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

echo "Total Checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}"
echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo

if [ "$FAILED_CHECKS" -eq 0 ]; then
    if [ "$WARNING_CHECKS" -eq 0 ]; then
        echo -e "${GREEN}✓ All health checks passed!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Health checks passed with warnings${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ $FAILED_CHECKS health check(s) failed${NC}"
    echo
    echo "Troubleshooting commands:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl get applications -n argocd | grep fineract-${ENV}"
    echo "  kubectl logs -n $NAMESPACE <pod-name>"
    exit 1
fi
