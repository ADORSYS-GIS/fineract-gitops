#!/bin/bash
# Wait for LoadBalancer
# Waits for AWS Network Load Balancer to be provisioned and retrieves DNS name
#
# Usage: ./scripts/wait-for-loadbalancer.sh [environment] [namespace] [service-name]
# Example: ./scripts/wait-for-loadbalancer.sh dev ingress-nginx ingress-nginx-controller
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. Ingress NGINX deployed
# 3. AWS CLI configured (optional, for additional verification)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENV="${1:-dev}"
NAMESPACE="${2:-ingress-nginx}"
SERVICE_NAME="${3:-ingress-nginx-controller}"
MAX_WAIT=600  # 10 minutes
CHECK_INTERVAL=10  # Check every 10 seconds

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

# Header
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Wait for LoadBalancer Provisioning${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}Service: ${SERVICE_NAME}${NC}"
echo -e "${BLUE}Max Wait: ${MAX_WAIT}s${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    error_exit "kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/"
fi

log "✓ Prerequisites met"
echo

# Verify cluster access
log_info "Verifying cluster access..."
if ! kubectl cluster-info &> /dev/null; then
    error_exit "Cannot access Kubernetes cluster. Configure kubectl first."
fi

CURRENT_CONTEXT=$(kubectl config current-context)
log "✓ Connected to cluster: $CURRENT_CONTEXT"
echo

# Check if namespace exists
log_info "Checking namespace: $NAMESPACE"
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    error_exit "Namespace not found: $NAMESPACE"
fi

log "✓ Namespace exists"
echo

# Check if service exists
log_info "Checking service: $SERVICE_NAME"
if ! kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" &> /dev/null; then
    error_exit "Service not found: $SERVICE_NAME in namespace $NAMESPACE"
fi

# Check if service is of type LoadBalancer
SERVICE_TYPE=$(kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.spec.type}')
if [ "$SERVICE_TYPE" != "LoadBalancer" ]; then
    error_exit "Service is not of type LoadBalancer (type: $SERVICE_TYPE)"
fi

log "✓ Service exists and is type LoadBalancer"
echo

# ============================================================================
# Wait for LoadBalancer
# ============================================================================

log_info "Waiting for LoadBalancer DNS name..."
echo

ELAPSED=0
DOTS=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get LoadBalancer hostname/IP
    LB_HOSTNAME=$(kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    LB_IP=$(kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$LB_HOSTNAME" ] || [ -n "$LB_IP" ]; then
        echo
        log "✓ LoadBalancer provisioned!"
        break
    fi

    # Progress indicator
    DOTS="${DOTS}."
    if [ ${#DOTS} -gt 3 ]; then
        DOTS="."
    fi

    # Calculate remaining time
    REMAINING=$((MAX_WAIT - ELAPSED))
    printf "\r${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} Waiting for LoadBalancer${DOTS} (${ELAPSED}s elapsed, ${REMAINING}s remaining)"

    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo
echo

# Check if we timed out
if [ $ELAPSED -ge $MAX_WAIT ]; then
    log_error "Timed out waiting for LoadBalancer after ${MAX_WAIT}s"
    echo
    echo "Troubleshooting steps:"
    echo "1. Check service status:"
    echo "   kubectl describe service -n $NAMESPACE $SERVICE_NAME"
    echo
    echo "2. Check ingress-nginx controller logs:"
    echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=ingress-nginx"
    echo
    echo "3. Check AWS ELB events in AWS console"
    echo
    exit 1
fi

# ============================================================================
# Retrieve LoadBalancer Information
# ============================================================================

log_info "Retrieving LoadBalancer details..."
echo

# Get LoadBalancer information
if [ -n "$LB_HOSTNAME" ]; then
    ENDPOINT="$LB_HOSTNAME"
    ENDPOINT_TYPE="Hostname"
else
    ENDPOINT="$LB_IP"
    ENDPOINT_TYPE="IP Address"
fi

# Get service details
EXTERNAL_PORT=$(kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" \
    -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null || echo "443")

HTTP_PORT=$(kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" \
    -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || echo "80")

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LoadBalancer Information${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}$ENDPOINT_TYPE:${NC} $ENDPOINT"
echo -e "${BLUE}HTTPS Port:${NC} $EXTERNAL_PORT"
echo -e "${BLUE}HTTP Port:${NC} $HTTP_PORT"
echo

# ============================================================================
# Verify LoadBalancer Accessibility (Optional)
# ============================================================================

log_info "Testing LoadBalancer connectivity..."
echo

# Test HTTP endpoint
if timeout 10 curl -s -o /dev/null -w "%{http_code}" "http://${ENDPOINT}:${HTTP_PORT}" > /dev/null 2>&1; then
    HTTP_STATUS=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" "http://${ENDPOINT}:${HTTP_PORT}")
    echo -e "${GREEN}  ✓ HTTP endpoint accessible (Status: $HTTP_STATUS)${NC}"
else
    echo -e "${YELLOW}  ⚠ HTTP endpoint not accessible yet (may still be initializing)${NC}"
fi

# Test HTTPS endpoint (allow self-signed certs)
if timeout 10 curl -k -s -o /dev/null -w "%{http_code}" "https://${ENDPOINT}:${EXTERNAL_PORT}" > /dev/null 2>&1; then
    HTTPS_STATUS=$(timeout 10 curl -k -s -o /dev/null -w "%{http_code}" "https://${ENDPOINT}:${EXTERNAL_PORT}")
    echo -e "${GREEN}  ✓ HTTPS endpoint accessible (Status: $HTTPS_STATUS)${NC}"
else
    echo -e "${YELLOW}  ⚠ HTTPS endpoint not accessible yet (may still be initializing)${NC}"
fi

echo

# ============================================================================
# AWS LoadBalancer Details (if AWS CLI available)
# ============================================================================

if command -v aws &> /dev/null && [ -n "$LB_HOSTNAME" ]; then
    log_info "Retrieving AWS LoadBalancer details..."
    echo

    # Extract LB name from hostname
    LB_NAME=$(echo "$LB_HOSTNAME" | cut -d- -f1)
    AWS_REGION="${AWS_REGION:-us-east-2}"

    # Get ELB details
    LB_ARN=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(DNSName, '${LB_HOSTNAME}')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$LB_ARN" ]; then
        LB_STATE=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$LB_ARN" \
            --region "$AWS_REGION" \
            --query "LoadBalancers[0].State.Code" \
            --output text 2>/dev/null || echo "unknown")

        LB_TYPE=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$LB_ARN" \
            --region "$AWS_REGION" \
            --query "LoadBalancers[0].Type" \
            --output text 2>/dev/null || echo "unknown")

        LB_SCHEME=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$LB_ARN" \
            --region "$AWS_REGION" \
            --query "LoadBalancers[0].Scheme" \
            --output text 2>/dev/null || echo "unknown")

        echo -e "${BLUE}AWS LoadBalancer Details:${NC}"
        echo -e "  Type: ${LB_TYPE}"
        echo -e "  State: ${LB_STATE}"
        echo -e "  Scheme: ${LB_SCHEME}"
        echo -e "  ARN: ${LB_ARN}"
        echo
    else
        echo -e "${YELLOW}  ⚠ Could not retrieve AWS LoadBalancer details${NC}"
        echo
    fi
fi

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LoadBalancer Ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Access your applications at:"
echo -e "  ${GREEN}http://${ENDPOINT}${NC}"
echo -e "  ${GREEN}https://${ENDPOINT}${NC}"
echo

echo -e "${YELLOW}Next Steps:${NC}"
echo

if [ -n "$(kubectl get ingress -A 2>/dev/null)" ]; then
    echo "1. View all ingress resources:"
    echo "   kubectl get ingress -A"
    echo
    echo "2. Test application endpoints:"
    echo "   curl -k https://${ENDPOINT}"
    echo
else
    log_warn "No ingress resources found yet"
    echo
    echo "1. Create ingress resources to expose applications"
    echo
fi

echo "3. (Optional) Configure DNS:"
echo "   Create CNAME record pointing to: ${ENDPOINT}"
echo
echo "4. (Optional) Configure TLS certificates:"
echo "   ./scripts/setup-letsencrypt.sh ${ENV}"
echo

echo -e "${BLUE}Save this endpoint for your DNS/configuration:${NC}"
echo -e "${GREEN}${ENDPOINT}${NC}"
echo

echo -e "${GREEN}Done!${NC}"
