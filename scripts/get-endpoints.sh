#!/bin/bash
# Get Endpoints
# Displays all application endpoints, LoadBalancer DNS, and access URLs
#
# Usage: ./scripts/get-endpoints.sh [environment]
# Example: ./scripts/get-endpoints.sh dev
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. Applications deployed
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check arguments
ENV="${1:-dev}"
NAMESPACE="fineract-${ENV}"

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
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    Fineract Application Endpoints     ║${NC}"
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║ Environment: ${ENV}$(printf '%*s' $((26 - ${#ENV})) '')║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    error_exit "kubectl not found"
fi

# Verify cluster access
if ! kubectl cluster-info &> /dev/null; then
    error_exit "Cannot access Kubernetes cluster"
fi

CURRENT_CONTEXT=$(kubectl config current-context)
echo -e "${BLUE}Cluster:${NC} $CURRENT_CONTEXT"
echo

# ============================================================================
# Get LoadBalancer Endpoint
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}LoadBalancer Information${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

LB_HOSTNAME=$(kubectl get service -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

LB_IP=$(kubectl get service -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$LB_HOSTNAME" ]; then
    EXTERNAL_ENDPOINT="$LB_HOSTNAME"
    echo -e "${GREEN}✓ LoadBalancer DNS:${NC} ${EXTERNAL_ENDPOINT}"
elif [ -n "$LB_IP" ]; then
    EXTERNAL_ENDPOINT="$LB_IP"
    echo -e "${GREEN}✓ LoadBalancer IP:${NC} ${EXTERNAL_ENDPOINT}"
else
    echo -e "${RED}✗ LoadBalancer not ready${NC}"
    echo -e "${YELLOW}  Run: ./scripts/wait-for-loadbalancer.sh ${ENV}${NC}"
    EXTERNAL_ENDPOINT="<pending>"
fi

echo

# ============================================================================
# Get Ingress Resources
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Application Endpoints${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Get all ingress resources
INGRESSES=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null || echo "")

if [ -z "$INGRESSES" ] || [ "$INGRESSES" == '{"items":[]}' ]; then
    echo -e "${YELLOW}No ingress resources found in namespace: ${NAMESPACE}${NC}"
    echo
else
    # Parse and display each ingress
    echo "$INGRESSES" | jq -r '.items[] | "\(.metadata.name)|\(.spec.rules[].host)|\(.spec.rules[].http.paths[].path)|\(.spec.rules[].http.paths[].backend.service.name)"' 2>/dev/null | while IFS='|' read -r ingress_name host path service; do
        if [ -n "$host" ]; then
            echo -e "${GREEN}●${NC} ${BLUE}${ingress_name}${NC}"
            echo -e "  Host: ${CYAN}${host}${NC}"
            echo -e "  Path: ${path:-/}"
            echo -e "  Service: ${service}"

            # Generate URLs
            if [ "$EXTERNAL_ENDPOINT" != "<pending>" ]; then
                echo -e "  ${GREEN}➜ https://${host}${path}${NC}"
            else
                echo -e "  ${YELLOW}➜ https://${host}${path} (LoadBalancer pending)${NC}"
            fi
            echo
        fi
    done
fi

# ============================================================================
# Fineract API Endpoints
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Fineract API Endpoints${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Fineract Write Service
FINERACT_WRITE_HOST=$(kubectl get ingress -n "$NAMESPACE" fineract-write-ingress \
    -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$FINERACT_WRITE_HOST" ]; then
    echo -e "${GREEN}●${NC} ${BLUE}Fineract Write API${NC}"
    echo -e "  ${GREEN}➜ https://${FINERACT_WRITE_HOST}/fineract-provider/api/v1${NC}"
    echo -e "  ${CYAN}Test:${NC} curl -k https://${FINERACT_WRITE_HOST}/fineract-provider/actuator/health"
    echo
fi

# Fineract Read Service
FINERACT_READ_HOST=$(kubectl get ingress -n "$NAMESPACE" fineract-read-ingress \
    -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$FINERACT_READ_HOST" ]; then
    echo -e "${GREEN}●${NC} ${BLUE}Fineract Read API${NC}"
    echo -e "  ${GREEN}➜ https://${FINERACT_READ_HOST}/fineract-provider/api/v1${NC}"
    echo -e "  ${CYAN}Test:${NC} curl -k https://${FINERACT_READ_HOST}/fineract-provider/actuator/health"
    echo
fi

# Fineract Batch Service
FINERACT_BATCH_HOST=$(kubectl get ingress -n "$NAMESPACE" fineract-batch-ingress \
    -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$FINERACT_BATCH_HOST" ]; then
    echo -e "${GREEN}●${NC} ${BLUE}Fineract Batch API${NC}"
    echo -e "  ${GREEN}➜ https://${FINERACT_BATCH_HOST}/fineract-provider/api/v1${NC}"
    echo
fi

# ============================================================================
# Keycloak Endpoint
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Identity Provider (Keycloak)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

KEYCLOAK_HOST=$(kubectl get ingress -n "$NAMESPACE" keycloak-ingress \
    -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$KEYCLOAK_HOST" ]; then
    echo -e "${GREEN}●${NC} ${BLUE}Keycloak Admin Console${NC}"
    echo -e "  ${GREEN}➜ https://${KEYCLOAK_HOST}${NC}"
    echo -e "  ${GREEN}➜ https://${KEYCLOAK_HOST}/admin${NC}"
    echo
    echo -e "${GREEN}●${NC} ${BLUE}Keycloak Realm${NC}"
    echo -e "  ${GREEN}➜ https://${KEYCLOAK_HOST}/realms/fineract${NC}"
    echo
    echo -e "${CYAN}Default Credentials (Change immediately!):${NC}"
    echo -e "  Username: admin"
    echo -e "  Password: (check sealed secret: keycloak-admin-credentials)"
    echo
fi

# ============================================================================
# Web Application Endpoint
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Web Application${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

WEB_APP_HOST=$(kubectl get ingress -n "$NAMESPACE" web-app-ingress \
    -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$WEB_APP_HOST" ]; then
    echo -e "${GREEN}●${NC} ${BLUE}Fineract Web App${NC}"
    echo -e "  ${GREEN}➜ https://${WEB_APP_HOST}${NC}"
    echo
    echo -e "${CYAN}Login Credentials:${NC}"
    echo -e "  Uses Keycloak SSO"
    echo -e "  Default user: mifos / password (set in Keycloak)"
    echo
fi

# ============================================================================
# Monitoring & Observability
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Monitoring & Observability${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# ArgoCD
ARGOCD_HOST=$(kubectl get ingress -n argocd argocd-server-ingress \
    -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$ARGOCD_HOST" ]; then
    echo -e "${GREEN}●${NC} ${BLUE}ArgoCD${NC}"
    echo -e "  ${GREEN}➜ https://${ARGOCD_HOST}${NC}"
    echo -e "  ${CYAN}Get admin password:${NC}"
    echo -e "    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo
fi

# CloudWatch (if using AWS)
if [ "$EXTERNAL_ENDPOINT" != "<pending>" ]; then
    EKS_CLUSTER=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' | sed 's/.*\///')
    AWS_REGION="${AWS_REGION:-us-east-2}"

    echo -e "${GREEN}●${NC} ${BLUE}CloudWatch Container Insights${NC}"
    echo -e "  ${GREEN}➜ https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#container-insights:infrastructure/map/EKS:Cluster/${EKS_CLUSTER}${NC}"
    echo
fi

# ============================================================================
# Internal Services
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Internal Services (ClusterIP)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Redis
REDIS_SERVICE=$(kubectl get service -n "$NAMESPACE" fineract-redis-service \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "$REDIS_SERVICE" ]; then
    REDIS_PORT=$(kubectl get service -n "$NAMESPACE" fineract-redis-service \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "6379")
    echo -e "${GREEN}●${NC} ${BLUE}Redis${NC}"
    echo -e "  Internal: redis://${REDIS_SERVICE}:${REDIS_PORT}"
    echo
fi

# PostgreSQL RDS
echo -e "${GREEN}●${NC} ${BLUE}PostgreSQL (RDS)${NC}"
echo -e "  Check secret: kubectl get secret -n $NAMESPACE fineract-db-credentials -o yaml"
echo

# ============================================================================
# DNS Configuration
# ============================================================================

if [ "$EXTERNAL_ENDPOINT" != "<pending>" ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}DNS Configuration${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${CYAN}Create CNAME records pointing to:${NC} ${GREEN}${EXTERNAL_ENDPOINT}${NC}"
    echo
    echo "Required DNS records:"

    if [ -n "$FINERACT_WRITE_HOST" ]; then
        echo -e "  ${FINERACT_WRITE_HOST} → ${EXTERNAL_ENDPOINT}"
    fi
    if [ -n "$FINERACT_READ_HOST" ]; then
        echo -e "  ${FINERACT_READ_HOST} → ${EXTERNAL_ENDPOINT}"
    fi
    if [ -n "$KEYCLOAK_HOST" ]; then
        echo -e "  ${KEYCLOAK_HOST} → ${EXTERNAL_ENDPOINT}"
    fi
    if [ -n "$WEB_APP_HOST" ]; then
        echo -e "  ${WEB_APP_HOST} → ${EXTERNAL_ENDPOINT}"
    fi
    if [ -n "$ARGOCD_HOST" ]; then
        echo -e "  ${ARGOCD_HOST} → ${EXTERNAL_ENDPOINT}"
    fi
    echo
fi

# ============================================================================
# Health Check Commands
# ============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Health Check Commands${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

echo "Check all pods status:"
echo -e "  ${CYAN}kubectl get pods -n ${NAMESPACE}${NC}"
echo

echo "Check all services:"
echo -e "  ${CYAN}kubectl get services -n ${NAMESPACE}${NC}"
echo

echo "Check all ingress resources:"
echo -e "  ${CYAN}kubectl get ingress -n ${NAMESPACE}${NC}"
echo

echo "Test LoadBalancer connectivity:"
if [ "$EXTERNAL_ENDPOINT" != "<pending>" ]; then
    echo -e "  ${CYAN}curl -k https://${EXTERNAL_ENDPOINT}${NC}"
else
    echo -e "  ${YELLOW}(LoadBalancer not ready)${NC}"
fi
echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Summary                   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo

if [ "$EXTERNAL_ENDPOINT" != "<pending>" ]; then
    echo -e "${GREEN}✓ All endpoints are accessible via LoadBalancer${NC}"
    echo -e "${GREEN}✓ LoadBalancer DNS: ${EXTERNAL_ENDPOINT}${NC}"
else
    echo -e "${YELLOW}⚠ LoadBalancer is not ready yet${NC}"
    echo -e "${YELLOW}  Run: ./scripts/wait-for-loadbalancer.sh ${ENV}${NC}"
fi

echo
echo -e "${BLUE}For more information, run:${NC}"
echo -e "  kubectl get all -n ${NAMESPACE}"
echo

echo -e "${GREEN}Done!${NC}"
