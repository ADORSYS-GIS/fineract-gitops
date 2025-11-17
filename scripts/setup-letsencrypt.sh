#!/bin/bash
# Setup Let's Encrypt
# Configures cert-manager with Let's Encrypt for automatic TLS certificates
#
# Usage: ./scripts/setup-letsencrypt.sh [environment] [email]
# Example: ./scripts/setup-letsencrypt.sh dev admin@example.com
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. Domain name configured in DNS pointing to LoadBalancer
# 3. cert-manager installed (or will be installed)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV="${1:-dev}"
LETSENCRYPT_EMAIL="${2}"
CERT_MANAGER_VERSION="v1.14.0"
NAMESPACE="cert-manager"

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

# Validate email
if [ -z "$LETSENCRYPT_EMAIL" ]; then
    echo -e "${RED}Error: Email address required${NC}"
    echo "Usage: $0 [environment] [email]"
    echo "Example: $0 dev admin@example.com"
    exit 1
fi

# Validate email format
if ! echo "$LETSENCRYPT_EMAIL" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' > /dev/null; then
    error_exit "Invalid email format: $LETSENCRYPT_EMAIL"
fi

# Header
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Let's Encrypt Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Email: ${LETSENCRYPT_EMAIL}${NC}"
echo -e "${BLUE}cert-manager Version: ${CERT_MANAGER_VERSION}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    error_exit "kubectl not found"
fi

if ! command -v helm &> /dev/null; then
    log_warn "helm not found - will use kubectl to install cert-manager"
fi

log "✓ Prerequisites met"
echo

# Verify cluster access
log_info "Verifying cluster access..."
if ! kubectl cluster-info &> /dev/null; then
    error_exit "Cannot access Kubernetes cluster"
fi

CURRENT_CONTEXT=$(kubectl config current-context)
log "✓ Connected to cluster: $CURRENT_CONTEXT"
echo

# ============================================================================
# Check if cert-manager is already installed
# ============================================================================

log_info "Checking if cert-manager is installed..."

if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warn "cert-manager namespace already exists"

    if kubectl get deployment -n "$NAMESPACE" cert-manager &> /dev/null; then
        log "cert-manager is already installed"

        # Get version
        INSTALLED_VERSION=$(kubectl get deployment -n "$NAMESPACE" cert-manager \
            -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F':' '{print $NF}')

        echo -e "${BLUE}Installed version:${NC} $INSTALLED_VERSION"
        echo
        echo -e "${YELLOW}Do you want to continue with configuration? (y/n)${NC}"
        read -r CONTINUE

        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            log_info "Skipping cert-manager installation"
        fi
    fi
else
    # ============================================================================
    # Install cert-manager
    # ============================================================================

    log_info "Installing cert-manager..."
    echo

    # Create namespace
    kubectl create namespace "$NAMESPACE" || true

    # Install cert-manager CRDs
    log_info "Installing cert-manager CRDs..."
    kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml"

    log "✓ CRDs installed"
    echo

    # Install cert-manager using kubectl
    log_info "Installing cert-manager components..."
    kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

    log "✓ cert-manager components installed"
    echo

    # Wait for cert-manager to be ready
    log_info "Waiting for cert-manager to be ready..."

    kubectl wait --for=condition=available --timeout=300s \
        deployment/cert-manager -n "$NAMESPACE" || log_warn "Timeout waiting for cert-manager"

    kubectl wait --for=condition=available --timeout=300s \
        deployment/cert-manager-webhook -n "$NAMESPACE" || log_warn "Timeout waiting for cert-manager-webhook"

    kubectl wait --for=condition=available --timeout=300s \
        deployment/cert-manager-cainjector -n "$NAMESPACE" || log_warn "Timeout waiting for cert-manager-cainjector"

    log "✓ cert-manager is ready"
    echo
fi

# ============================================================================
# Create ClusterIssuer for Let's Encrypt (Staging)
# ============================================================================

log_info "Creating Let's Encrypt Staging ClusterIssuer..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
  labels:
    environment: ${ENV}
spec:
  acme:
    # Staging server for testing
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      # HTTP-01 challenge solver
      - http01:
          ingress:
            class: nginx
EOF

log "✓ Staging ClusterIssuer created"
echo

# ============================================================================
# Create ClusterIssuer for Let's Encrypt (Production)
# ============================================================================

log_info "Creating Let's Encrypt Production ClusterIssuer..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  labels:
    environment: ${ENV}
spec:
  acme:
    # Production server - rate limited!
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      # HTTP-01 challenge solver
      - http01:
          ingress:
            class: nginx
EOF

log "✓ Production ClusterIssuer created"
echo

# ============================================================================
# Verify ClusterIssuers
# ============================================================================

log_info "Verifying ClusterIssuers..."
echo

# Wait a moment for ClusterIssuers to be processed
sleep 5

# Check staging issuer
STAGING_STATUS=$(kubectl get clusterissuer letsencrypt-staging \
    -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")

if [ "$STAGING_STATUS" == "Ready" ]; then
    echo -e "${GREEN}✓ Staging ClusterIssuer is ready${NC}"
else
    echo -e "${YELLOW}⚠ Staging ClusterIssuer status: ${STAGING_STATUS}${NC}"
fi

# Check prod issuer
PROD_STATUS=$(kubectl get clusterissuer letsencrypt-prod \
    -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")

if [ "$PROD_STATUS" == "Ready" ]; then
    echo -e "${GREEN}✓ Production ClusterIssuer is ready${NC}"
else
    echo -e "${YELLOW}⚠ Production ClusterIssuer status: ${PROD_STATUS}${NC}"
fi

echo

# ============================================================================
# Create Example Certificate (for testing)
# ============================================================================

log_info "Creating example certificate template..."

FINERACT_NAMESPACE="fineract-${ENV}"

cat > "/tmp/example-certificate-${ENV}.yaml" <<EOF
# Example Certificate Resource
# Apply this to test Let's Encrypt certificate issuance
#
# Usage:
#   1. Update the dnsNames to match your domain
#   2. kubectl apply -f example-certificate-${ENV}.yaml
#   3. Check status: kubectl describe certificate example-cert -n ${FINERACT_NAMESPACE}

apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-cert
  namespace: ${FINERACT_NAMESPACE}
spec:
  secretName: example-tls
  issuerRef:
    name: letsencrypt-staging  # Use staging for testing!
    kind: ClusterIssuer
  dnsNames:
    - example.${ENV}.fineract.com  # Replace with your actual domain
  # After testing with staging works, change to production:
  # issuerRef:
  #   name: letsencrypt-prod
  #   kind: ClusterIssuer
EOF

echo -e "${GREEN}✓ Example certificate template created${NC}"
echo -e "  ${BLUE}Location:${NC} /tmp/example-certificate-${ENV}.yaml"
echo

# ============================================================================
# Configuration Summary
# ============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configuration Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${BLUE}Email:${NC} ${LETSENCRYPT_EMAIL}"
echo
echo -e "${BLUE}ClusterIssuers:${NC}"
echo "  • letsencrypt-staging (for testing)"
echo "  • letsencrypt-prod (for production)"
echo
echo -e "${BLUE}Challenge Type:${NC} HTTP-01"
echo -e "${BLUE}Ingress Class:${NC} nginx"
echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Let's Encrypt Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo

echo -e "${YELLOW}Next Steps:${NC}"
echo
echo "1. Verify cert-manager is working:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo "   kubectl logs -n ${NAMESPACE} -l app=cert-manager"
echo
echo "2. Check ClusterIssuer status:"
echo "   kubectl get clusterissuer"
echo "   kubectl describe clusterissuer letsencrypt-staging"
echo
echo "3. Add TLS to your Ingress resources:"
echo
echo "   Example ingress annotation:"
echo "   ---"
echo "   apiVersion: networking.k8s.io/v1"
echo "   kind: Ingress"
echo "   metadata:"
echo "     name: example-ingress"
echo "     annotations:"
echo "       cert-manager.io/cluster-issuer: letsencrypt-staging"
echo "   spec:"
echo "     tls:"
echo "       - hosts:"
echo "           - example.${ENV}.fineract.com"
echo "         secretName: example-tls"
echo "     rules:"
echo "       - host: example.${ENV}.fineract.com"
echo "         http:"
echo "           paths:"
echo "             - path: /"
echo "               pathType: Prefix"
echo "               backend:"
echo "                 service:"
echo "                   name: example-service"
echo "                   port:"
echo "                     number: 80"
echo
echo "4. Test with staging issuer first!"
echo "   ${YELLOW}IMPORTANT:${NC} Always test with letsencrypt-staging before using production"
echo "   Production has rate limits: 50 certificates per domain per week"
echo
echo "5. After successful staging test, switch to production:"
echo "   Change annotation to: cert-manager.io/cluster-issuer: letsencrypt-prod"
echo
echo "6. Monitor certificate issuance:"
echo "   kubectl get certificate -n ${FINERACT_NAMESPACE}"
echo "   kubectl describe certificate <cert-name> -n ${FINERACT_NAMESPACE}"
echo
echo "7. Check certificate ready status:"
echo "   kubectl get certificate -n ${FINERACT_NAMESPACE} -w"
echo

echo -e "${BLUE}Troubleshooting:${NC}"
echo
echo "If certificates don't issue:"
echo "  1. Check cert-manager logs:"
echo "     kubectl logs -n ${NAMESPACE} -l app=cert-manager"
echo
echo "  2. Check certificate status:"
echo "     kubectl describe certificate <cert-name> -n ${FINERACT_NAMESPACE}"
echo
echo "  3. Check certificate request:"
echo "     kubectl get certificaterequest -n ${FINERACT_NAMESPACE}"
echo
echo "  4. Verify DNS is pointing to LoadBalancer:"
echo "     dig +short <your-domain>"
echo
echo "  5. Verify HTTP-01 challenge path is accessible:"
echo "     curl http://<your-domain>/.well-known/acme-challenge/"
echo

echo -e "${BLUE}Rate Limits:${NC}"
echo "Let's Encrypt Production:"
echo "  • 50 certificates per registered domain per week"
echo "  • 5 duplicate certificates per week"
echo "  • Use staging for all testing!"
echo

echo -e "${GREEN}Done!${NC}"
