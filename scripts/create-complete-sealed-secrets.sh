#!/bin/bash
#
# Complete Sealed Secrets Generation Script
# Creates ALL 9 required sealed secrets for a Fineract environment
#
# This script creates secrets that are NOT managed by Terraform:
# 1. fineract-redis-secret (in-cluster Redis password)
# 2. keycloak-admin-credentials (Keycloak admin user)
# 3. fineract-admin-credentials (OAuth2 client for data loaders)
# 4. grafana-admin-credentials (Grafana admin user)
# 5. keycloak-client-secrets (placeholder - populated by Keycloak export job)
#
# Terraform-managed secrets (RDS, S3) are created by seal-terraform-secrets.sh
#
# Usage: ./scripts/create-complete-sealed-secrets.sh [environment]
# Example: ./scripts/create-complete-sealed-secrets.sh dev
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment argument required${NC}"
    echo "Usage: $0 [dev|uat|production]"
    exit 1
fi

ENV=$1
NAMESPACE="fineract-${ENV}"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_CONTROLLER="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be dev, uat, or production${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating Complete Sealed Secrets for: ${ENV}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo -e "${RED}Error: kubeseal not found${NC}"
    echo "Install with: brew install kubeseal"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: openssl not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo

# Create secrets directory if it doesn't exist
mkdir -p secrets/${ENV}

# Function to generate strong password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Function to create sealed secret
create_sealed_secret() {
    local secret_name=$1
    local namespace=$2
    shift 2
    local literals=("$@")

    echo -e "${YELLOW}→ Creating sealed secret: ${secret_name}${NC}"

    # Build kubectl command
    local cmd="kubectl create secret generic ${secret_name} --namespace=${namespace} --dry-run=client -o yaml"

    for literal in "${literals[@]}"; do
        cmd+=" --from-literal=${literal}"
    done

    # Create and seal
    if eval $cmd | kubeseal --controller-namespace="${SEALED_SECRETS_NAMESPACE}" --controller-name="${SEALED_SECRETS_CONTROLLER}" -o yaml > secrets/${ENV}/${secret_name}-sealed.yaml 2>&1; then
        echo -e "${GREEN}  ✓ Created: secrets/${ENV}/${secret_name}-sealed.yaml${NC}"
        return 0
    else
        echo -e "${RED}  ✗ Failed to create ${secret_name}${NC}"
        return 1
    fi
}

echo "Generating application secrets for ${ENV} environment..."
echo

# 1. Fineract Redis Secret (in-cluster Redis)
echo "1. Fineract Redis Secret (in-cluster Redis)..."
REDIS_PASSWORD=$(generate_password 32)

create_sealed_secret "fineract-redis-secret" "${NAMESPACE}" \
    "redis-password=${REDIS_PASSWORD}"

echo

# 2. Keycloak Admin Credentials
echo "2. Keycloak Admin Credentials..."
if [ "$ENV" = "dev" ]; then
    KEYCLOAK_ADMIN_USER="admin"
    KEYCLOAK_ADMIN_PASSWORD="admin"  # Weak password OK for dev
else
    KEYCLOAK_ADMIN_USER="admin"
    KEYCLOAK_ADMIN_PASSWORD=$(generate_password 32)
fi

create_sealed_secret "keycloak-admin-credentials" "${NAMESPACE}" \
    "username=${KEYCLOAK_ADMIN_USER}" \
    "password=${KEYCLOAK_ADMIN_PASSWORD}"

echo

# 3. Fineract Admin Credentials - DEPRECATED
echo "3. Fineract Admin Credentials..."
echo -e "${YELLOW}  SKIPPED: OAuth client credentials are now managed by seal-terraform-secrets.sh${NC}"

echo

# 4. Grafana Admin Credentials
echo "4. Grafana Admin Credentials..."
if [ "$ENV" = "dev" ]; then
    GRAFANA_ADMIN_USER="admin"
    GRAFANA_ADMIN_PASSWORD="admin"  # Weak password OK for dev
else
    GRAFANA_ADMIN_USER="admin"
    GRAFANA_ADMIN_PASSWORD=$(generate_password 32)
fi

# Note: Grafana namespace is 'monitoring', not 'fineract-dev'
create_sealed_secret "grafana-admin-credentials" "monitoring" \
    "username=${GRAFANA_ADMIN_USER}" \
    "password=${GRAFANA_ADMIN_PASSWORD}"

echo

# 5. Keycloak Client Secrets - MANAGED BY seal-terraform-secrets.sh
echo "5. Keycloak Client Secrets..."
echo -e "${YELLOW}  SKIPPED: This secret is now managed by seal-terraform-secrets.sh${NC}"
echo -e "${YELLOW}  It uses the same OAuth2 client secret as oauth2-proxy-secrets to ensure${NC}"
echo -e "${YELLOW}  authentication works correctly (prevents 401 Unauthorized errors).${NC}"
echo -e "${YELLOW}  Run './scripts/seal-terraform-secrets.sh ${ENV}' to create it.${NC}"

echo

# 6. Keycloak Default Users
echo "6. Keycloak Default Users..."
echo -e "${BLUE}  Creating default user credentials for Keycloak...${NC}"

# Default passwords for dev environment (should be changed for production)
KEYCLOAK_ADMIN_DEFAULT_PASSWORD="${KEYCLOAK_ADMIN_DEFAULT_PASSWORD:-Admin@123}"
KEYCLOAK_MIFOS_DEFAULT_PASSWORD="${KEYCLOAK_MIFOS_DEFAULT_PASSWORD:-Mifos@123}"

create_sealed_secret "keycloak-default-users" "${NAMESPACE}" \
    "admin-password=${KEYCLOAK_ADMIN_DEFAULT_PASSWORD}" \
    "mifos-password=${KEYCLOAK_MIFOS_DEFAULT_PASSWORD}"

echo

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Sealed Secrets Creation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Created sealed secrets in: secrets/${ENV}/"
echo
echo "Application secrets created:"
echo "  ✓ fineract-redis-secret (namespace: ${NAMESPACE})"
echo "  ✓ keycloak-admin-credentials (namespace: ${NAMESPACE})"
echo "  ✓ grafana-admin-credentials (namespace: monitoring)"
echo "  ✓ keycloak-default-users (namespace: ${NAMESPACE})"
echo
echo "NOTE: The following secrets are managed by Terraform:"
echo "Run './scripts/seal-terraform-secrets.sh ${ENV}' to create:"
echo "  • fineract-db-credentials (RDS database)"
echo "  • keycloak-db-credentials (RDS database)"
echo "  • s3-connection (S3 buckets)"
echo "  • oauth2-proxy-secrets (OAuth2 Proxy)"
echo "  • keycloak-client-secrets (Keycloak - matches OAuth2 Proxy secret)"
echo
echo -e "${YELLOW}IMPORTANT: Credentials generated and sealed${NC}"
echo
echo "For ${ENV} environment, credentials have been generated for:"
echo "  • Redis (in-cluster)"
echo "  • Keycloak Admin"
echo "  • Fineract Admin OAuth2 Client"
echo "  • Grafana Admin"
echo
echo -e "${YELLOW}Security Note:${NC}"
echo "Credentials are stored in sealed secrets and can be retrieved from the cluster using:"
echo "  kubectl get secret <secret-name> -n ${NAMESPACE} -o jsonpath='{.data}' | jq -r 'to_entries | .[] | \"\\(.key): \\(.value | @base64d)\"'"
echo
echo "Example:"
echo "  kubectl get secret keycloak-admin-credentials -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Run Terraform to create infrastructure and get outputs:"
echo "   cd terraform/aws"
echo "   terraform apply -var-file=environments/${ENV}.tfvars"
echo
echo "2. Create Terraform-managed sealed secrets:"
echo "   ./scripts/seal-terraform-secrets.sh ${ENV}"
echo
echo "3. Review all generated sealed secrets:"
echo "   ls -la secrets/${ENV}/"
echo
echo "4. Configure Keycloak OAuth2 client with the admin credentials above"
echo
echo "5. Commit sealed secrets to Git:"
echo "   git add secrets/${ENV}/"
echo "   git commit -m \"Add complete sealed secrets for ${ENV} environment\""
echo "   git push"
echo
echo "6. Deploy via ArgoCD or kubectl:"
echo "   kubectl apply -k environments/${ENV}/"
echo
echo -e "${GREEN}Done!${NC}"
