#!/usr/bin/env bash
# Validate Ingress DNS matches actual LoadBalancer DNS
# Usage: ./scripts/validate-ingress-dns.sh <environment>
# Returns: 0 if match, 1 if mismatch, 2 if error
#
# This script validates that all Ingress resources have the correct hostname
# matching the current LoadBalancer DNS. If a mismatch is detected,
# it provides clear remediation steps.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }

# Validate arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <environment>"
    echo ""
    echo "Validate that Ingress DNS matches LoadBalancer DNS."
    echo ""
    echo "Arguments:"
    echo "  environment    Target environment (dev, uat, production)"
    echo ""
    echo "Exit codes:"
    echo "  0  All ingress hostnames match LoadBalancer DNS"
    echo "  1  One or more ingress hostnames mismatch"
    echo "  2  Error (could not retrieve DNS or ingress resources)"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 production"
    exit 2
fi

ENV="$1"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    log_error "Invalid environment '$ENV'"
    log_info "Valid environments: dev, uat, production"
    exit 2
fi

NAMESPACE="fineract-${ENV}"

# Function to get actual LoadBalancer DNS
get_loadbalancer_dns() {
    local lb_dns=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    # Fallback to IP if hostname is not available
    if [ -z "$lb_dns" ]; then
        lb_dns=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi

    echo "$lb_dns"
}

# Main validation
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Ingress DNS Validation${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    log_info "Environment: $ENV"
    log_info "Namespace: $NAMESPACE"
    echo ""

    # Get actual LoadBalancer DNS
    ACTUAL_DNS=$(get_loadbalancer_dns)

    if [ -z "$ACTUAL_DNS" ]; then
        log_error "Could not retrieve LoadBalancer DNS"
        echo ""
        log_info "Check that:"
        echo "  1. Cluster is accessible (kubectl cluster-info)"
        echo "  2. Ingress controller is deployed (kubectl get svc -n ingress-nginx)"
        echo "  3. LoadBalancer is provisioned (may need to wait)"
        echo ""
        exit 2
    fi

    log_info "LoadBalancer DNS: $ACTUAL_DNS"
    echo ""

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_warn "Namespace $NAMESPACE does not exist"
        log_info "This is normal before initial deployment"
        log_success "Validation skipped (namespace not created yet)"
        exit 0
    fi

    # Get ingress hostnames
    INGRESS_HOSTS=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.rules[0].host}{"\n"}{end}' 2>/dev/null || echo "")

    if [ -z "$INGRESS_HOSTS" ]; then
        log_warn "No Ingress resources found in namespace $NAMESPACE"
        log_info "This is normal before initial deployment"
        log_success "Validation skipped (no ingress resources yet)"
        exit 0
    fi

    echo -e "${BLUE}Validating Ingress Resources...${NC}"
    echo ""

    MISMATCHED_COUNT=0
    MATCHED_COUNT=0

    # Check each ingress
    while IFS=$'\t' read -r ingress_name ingress_host; do
        if [ -z "$ingress_host" ]; then
            # Skip ingress without host (edge case)
            log_warn "Skipping $ingress_name (no hostname configured)"
            continue
        fi

        if [ "$ingress_host" != "$ACTUAL_DNS" ]; then
            echo -e "${RED}❌ MISMATCH:${NC} $ingress_name"
            echo -e "   ${RED}Ingress hostname:${NC} $ingress_host"
            echo -e "   ${GREEN}LoadBalancer DNS:${NC} $ACTUAL_DNS"
            echo ""
            MISMATCHED_COUNT=$((MISMATCHED_COUNT + 1))
        else
            log_success "OK: $ingress_name"
            MATCHED_COUNT=$((MATCHED_COUNT + 1))
        fi
    done <<< "$INGRESS_HOSTS"

    echo ""
    echo -e "${BLUE}Summary${NC}"
    echo "  Matched:   $MATCHED_COUNT"
    echo "  Mismatched: $MISMATCHED_COUNT"
    echo ""

    # Exit with appropriate code
    if [ $MISMATCHED_COUNT -gt 0 ]; then
        echo -e "${RED}❌ Found $MISMATCHED_COUNT ingress(es) with DNS mismatch${NC}"
        echo ""
        echo -e "${YELLOW}To fix this, run:${NC}"
        echo "  ${BLUE}./scripts/auto-update-lb-dns.sh $ENV --commit --push${NC}"
        echo ""
        echo -e "${YELLOW}Or for full deployment:${NC}"
        echo "  ${BLUE}make deploy-k8s-with-loadbalancer-dns-${ENV}${NC}"
        echo ""
        echo -e "${YELLOW}Or validate and fix manually:${NC}"
        echo "  ${BLUE}make validate-ingress-dns ENV=$ENV${NC}"
        echo "  ${BLUE}# Then review changes and commit${NC}"
        echo ""
        exit 1
    else
        echo -e "${GREEN}✅ All ingress resources match LoadBalancer DNS${NC}"
        echo ""
        exit 0
    fi
}

# Run main function
main
