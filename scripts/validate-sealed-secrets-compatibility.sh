#!/bin/bash
#
# Validate Sealed Secrets Compatibility
# Tests if sealed secrets in Git can be decrypted by current cluster
#
# Exit codes:
#   0 = Compatible (secrets can be decrypted)
#   1 = Incompatible (key mismatch - regeneration needed)
#   2 = Controller not ready or not found
#   3 = No sealed secrets found to test

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"; }
log_info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"; }

ENV="${1:-dev}"
NAMESPACE="fineract-${ENV}"

echo
log_info "Validating sealed secrets compatibility for ${ENV}..."
echo

# Check prerequisites
if ! command -v kubeseal &> /dev/null; then
    log_error "kubeseal not found"
    exit 2
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot access cluster"
    exit 2
fi

# Check if controller is running
if ! kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
    log_error "Sealed Secrets Controller not found"
    exit 2
fi

READY=$(kubectl get deployment sealed-secrets-controller -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$READY" -eq 0 ]; then
    log_error "Sealed Secrets Controller not ready"
    exit 2
fi

log "✓ Controller is ready"

# Check if any sealed secrets exist in namespace
if ! kubectl get sealedsecrets -n "$NAMESPACE" &> /dev/null 2>&1; then
    log_warn "No sealed secrets found in ${NAMESPACE} (fresh deployment?)"
    exit 3
fi

SEALED_COUNT=$(kubectl get sealedsecrets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SEALED_COUNT" -eq 0 ]; then
    log_warn "No sealed secrets found to validate"
    exit 3
fi

log "Found ${SEALED_COUNT} sealed secrets to validate"
echo

# Test critical sealed secrets for decryption errors
CRITICAL_SECRETS=(
    "fineract-db-credentials"
    "keycloak-admin-credentials"
    "keycloak-client-secrets"
    "oauth2-proxy-secrets"
)

FAILED_COUNT=0
TESTED_COUNT=0

for secret in "${CRITICAL_SECRETS[@]}"; do
    if kubectl get sealedsecret "$secret" -n "$NAMESPACE" &> /dev/null; then
        TESTED_COUNT=$((TESTED_COUNT + 1))

        # Check if the sealed secret has decryption errors
        ERROR_MSG=$(kubectl get sealedsecret "$secret" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Synced")].message}' 2>/dev/null)

        if [[ "$ERROR_MSG" == *"no key could decrypt"* ]]; then
            echo -e "${RED}✗${NC} $secret: Cannot decrypt (key mismatch)"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        else
            # Check if actual secret exists (successfully unsealed)
            if kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
                echo -e "${GREEN}✓${NC} $secret: Successfully decrypted"
            else
                echo -e "${YELLOW}⚠${NC} $secret: Pending decryption..."
            fi
        fi
    fi
done

echo

if [ "$TESTED_COUNT" -eq 0 ]; then
    log_warn "No critical sealed secrets found to test"
    exit 3
fi

if [ "$FAILED_COUNT" -gt 0 ]; then
    log_error "${FAILED_COUNT} sealed secret(s) cannot be decrypted"
    log_error "This typically means sealed secrets were encrypted with a different cluster's key"
    echo
    log_info "Solutions:"
    echo "  1. Regenerate sealed secrets: ./scripts/regenerate-all-sealed-secrets.sh ${ENV}"
    echo "  2. Restore backed-up keys: ./scripts/restore-sealed-secrets-keys.sh"
    exit 1
fi

log "✓ All tested sealed secrets are compatible with current cluster"
exit 0
