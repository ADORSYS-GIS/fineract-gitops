#!/bin/bash
#
# Seal Payment Gateway Secrets Script
# Creates sealed secrets for the Payment Gateway Service from Terraform outputs
#
# Usage: ./scripts/seal-payment-gateway-secrets.sh [environment]
# Example: ./scripts/seal-payment-gateway-secrets.sh dev
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
TERRAFORM_DIR="terraform/aws"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_CONTROLLER="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be dev, uat, or production${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Sealing Payment Gateway Secrets for: ${ENV}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: terraform not found${NC}"
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo -e "${YELLOW}kubeseal not found. Attempting to install...${NC}"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep tag_name | cut -d '"' -f 4)
        wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz"
        tar -xvzf kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz kubeseal
        sudo install -m 755 kubeseal /usr/local/bin/kubeseal
        rm kubeseal kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz
        echo -e "${GREEN}kubeseal installed successfully${NC}"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install kubeseal
        echo -e "${GREEN}kubeseal installed successfully${NC}"
    else
        echo -e "${RED}Error: Unsupported OS. Please install kubeseal manually.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo

# Change to terraform directory
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo -e "${RED}Error: Terraform directory not found: $TERRAFORM_DIR${NC}"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Verify Terraform state exists
if ! terraform state list &> /dev/null; then
    echo -e "${RED}Error: No Terraform state found. Run 'terraform apply' first.${NC}"
    exit 1
fi

echo "Fetching Terraform state and outputs..."

# Get Terraform state JSON (for sensitive values not in outputs)
TF_STATE_JSON=$(terraform show -json 2>/dev/null)

if [ -z "$TF_STATE_JSON" ]; then
    echo -e "${RED}Error: Could not fetch Terraform state${NC}"
    exit 1
fi

# Extract sensitive passwords directly from Terraform state
# RDS Master Password - extract from random_password.master resource in RDS module
RDS_PASSWORD=$(echo "$TF_STATE_JSON" | jq -r '.values.root_module.child_modules[] | select(.address=="module.rds") | .resources[] | select(.address=="module.rds.random_password.master") | .values.result' 2>/dev/null || echo "")

# Get non-sensitive Terraform outputs
RDS_HOST=$(terraform output -raw rds_instance_endpoint 2>/dev/null | cut -d: -f1 || echo "")
RDS_PORT=$(terraform output -raw rds_instance_endpoint 2>/dev/null | cut -d: -f2 || echo "5432")
RDS_USERNAME=$(terraform output -json rds_master_username 2>/dev/null | jq -r '.' || echo "fineract")

# Validate required values
if [ -z "$RDS_PASSWORD" ] || [ -z "$RDS_HOST" ]; then
    echo -e "${RED}Error: Could not fetch RDS credentials from Terraform${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Terraform outputs fetched successfully${NC}"
echo

# Go back to root directory
cd ../..

# Create secrets directory if it doesn't exist
mkdir -p secrets/${ENV}

echo -e "${YELLOW}Creating sealed secrets...${NC}"
echo

# Function to create sealed secret
create_sealed_secret() {
    local secret_name=$1
    local namespace=$2
    shift 2
    local literals=("$@")

    echo -e "${BLUE}→ Creating sealed secret: ${secret_name}${NC}"

    # Build kubectl command as array to properly handle special characters
    local cmd_args=(
        "create" "secret" "generic" "${secret_name}"
        "--namespace=${namespace}"
        "--dry-run=client"
        "-o" "yaml"
    )

    for literal in "${literals[@]}"; do
        cmd_args+=("--from-literal=${literal}")
    done

    # Create and seal using array expansion (no eval needed)
    if kubectl "${cmd_args[@]}" | kubeseal --controller-namespace="${SEALED_SECRETS_NAMESPACE}" --controller-name="${SEALED_SECRETS_CONTROLLER}" -o yaml > secrets/${ENV}/${secret_name}-sealed.yaml 2>&1; then
        echo -e "${GREEN}  ✓ Created: secrets/${ENV}/${secret_name}-sealed.yaml${NC}"
    else
        echo -e "${RED}  ✗ Failed to create ${secret_name}${NC}"
        return 1
    fi
}

# Payment Gateway DB Credentials
# Uses the same RDS instance but connects to 'payment_gateway' database
PAYMENT_GATEWAY_DB_NAME="payment_gateway"
PAYMENT_GATEWAY_JDBC_URL="jdbc:postgresql://${RDS_HOST}:${RDS_PORT}/${PAYMENT_GATEWAY_DB_NAME}"

echo "Payment Gateway DB Credentials..."
create_sealed_secret "payment-gateway-db-credentials" "${NAMESPACE}" \
    "username=${RDS_USERNAME}" \
    "password=${RDS_PASSWORD}" \
    "host=${RDS_HOST}" \
    "port=${RDS_PORT}" \
    "database=${PAYMENT_GATEWAY_DB_NAME}" \
    "jdbc-url=${PAYMENT_GATEWAY_JDBC_URL}"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Payment Gateway Secrets Sealed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Created sealed secret in: secrets/${ENV}/payment-gateway-db-credentials-sealed.yaml"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review generated sealed secret:"
echo "   cat secrets/${ENV}/payment-gateway-db-credentials-sealed.yaml"
echo
echo "2. Commit sealed secret to Git:"
echo "   git add secrets/${ENV}/payment-gateway-db-credentials-sealed.yaml"
echo "   git commit -m \"Add sealed secret for Payment Gateway Service in ${ENV}\""
echo "   git push"
echo
