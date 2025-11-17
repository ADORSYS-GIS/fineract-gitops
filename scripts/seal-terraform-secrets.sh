#!/bin/bash
#
# Seal Terraform Secrets Script
# Creates sealed secrets from Terraform outputs for infrastructure secrets
#
# Usage: ./scripts/seal-terraform-secrets.sh [environment]
# Example: ./scripts/seal-terraform-secrets.sh dev
#
# Environment Variables (optional):
#   SEALED_SECRETS_NAMESPACE  - Namespace where sealed-secrets controller is deployed (default: kube-system)
#   SEALED_SECRETS_CONTROLLER - Name of sealed-secrets controller service (default: sealed-secrets-controller)
#   FINERACT_SERVICE_ACCOUNT  - Name of Fineract service account for IRSA (default: fineract-aws)
#
# Prerequisites:
# 1. Terraform apply completed successfully
# 2. kubectl configured to access the cluster
# 3. kubeseal installed (brew install kubeseal)
# 4. Sealed Secrets controller deployed in cluster
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
FINERACT_SERVICE_ACCOUNT="${FINERACT_SERVICE_ACCOUNT:-fineract-aws}"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be dev, uat, or production${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Sealing Terraform Secrets for: ${ENV}${NC}"
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

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: terraform not found${NC}"
    exit 1
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

# Extract sensitive passwords directly from Terraform state (NOT from outputs)
# This prevents sensitive data from appearing in 'terraform output' commands

# RDS Master Password - extract from random_password.master resource in RDS module
RDS_PASSWORD=$(echo "$TF_STATE_JSON" | jq -r '.values.root_module.child_modules[] | select(.address=="module.rds") | .resources[] | select(.address=="module.rds.random_password.master") | .values.result' 2>/dev/null || echo "")

# Keycloak DB Password - extract from random_password.keycloak resource in RDS module
KEYCLOAK_DB_PASS=$(echo "$TF_STATE_JSON" | jq -r '.values.root_module.child_modules[] | select(.address=="module.rds") | .resources[] | select(.address=="module.rds.random_password.keycloak") | .values.result' 2>/dev/null || echo "")

# SES SMTP Password - extract from SES module if enabled
SES_SMTP_PASS=$(echo "$TF_STATE_JSON" | jq -r '.values.root_module.child_modules[] | select(.address=="module.ses[0]") | .resources[] | select(.type=="aws_iam_access_key") | .values.ses_smtp_password_v4' 2>/dev/null || echo "")

# Get non-sensitive Terraform outputs (these are safe to expose)
RDS_HOST=$(terraform output -raw rds_instance_endpoint 2>/dev/null | cut -d: -f1 || echo "")
RDS_PORT=$(terraform output -raw rds_instance_endpoint 2>/dev/null | cut -d: -f2 || echo "5432")
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "fineract")
RDS_USERNAME=$(terraform output -json rds_master_username 2>/dev/null | jq -r '.' || echo "fineract")
# Fineract uses fineract_tenants as the tenant-store database (not the raw RDS database name)
RDS_JDBC_URL="jdbc:postgresql://${RDS_HOST}:${RDS_PORT}/fineract_tenants"

S3_DOCUMENTS=$(terraform output -raw documents_bucket_name 2>/dev/null || echo "")
S3_BACKUPS=$(terraform output -raw backups_bucket_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -json connection_details 2>/dev/null | jq -r '.aws_region' 2>/dev/null || echo "us-east-2")

SES_SMTP_HOST=$(terraform output -raw ses_smtp_host 2>/dev/null || echo "")
SES_SMTP_PORT=$(terraform output -raw ses_smtp_port 2>/dev/null || echo "587")
SES_SMTP_USER=$(terraform output -raw ses_smtp_username 2>/dev/null || echo "")
SES_SENDER=$(terraform output -raw ses_sender_email 2>/dev/null || echo "")

IRSA_ROLE_ARN=$(terraform output -raw irsa_role_arn 2>/dev/null || echo "")

# Get Keycloak-specific credentials (must fetch before leaving terraform directory)
KEYCLOAK_DB_USER=$(terraform output -raw keycloak_db_username 2>/dev/null || echo "keycloak")

# Validate Terraform state has OAuth2 resources (added after moving OAuth2 to Terraform)
echo -e "${BLUE}→ Validating OAuth2 resources in Terraform state...${NC}"
if ! terraform state list 2>/dev/null | grep -q "random_password.oauth2_client_secret"; then
    echo -e "${RED}✗ OAuth2 secrets not found in Terraform state${NC}"
    echo ""
    echo -e "${YELLOW}Terraform has not been applied or OAuth2 resources don't exist.${NC}"
    echo ""
    echo "Required Terraform resources:"
    echo "  - random_password.oauth2_client_secret"
    echo "  - random_password.oauth2_cookie_secret"
    echo ""
    echo "These resources were added in commit 51a5838 to make OAuth2 secrets persistent."
    echo ""
    echo -e "${BLUE}To fix this, run:${NC}"
    echo "  cd terraform/aws"
    echo "  terraform apply -var-file=environments/${ENV}-eks.tfvars"
    echo ""
    echo "Or if you want auto-approval:"
    echo "  terraform apply -var-file=environments/${ENV}-eks.tfvars -auto-approve"
    exit 1
fi
echo -e "${GREEN}✓ OAuth2 resources found in Terraform state${NC}"
echo ""

# Get OAuth2 Proxy secrets (must fetch before leaving terraform directory)
OAUTH2_CLIENT_SECRET=$(terraform output -raw oauth2_client_secret 2>/dev/null || echo "")
OAUTH2_COOKIE_SECRET=$(terraform output -raw oauth2_cookie_secret 2>/dev/null || echo "")

# Validate required values
if [ -z "$RDS_PASSWORD" ] || [ -z "$RDS_HOST" ]; then
    echo -e "${RED}Error: Could not fetch RDS credentials from Terraform${NC}"
    exit 1
fi

if [ -z "$OAUTH2_CLIENT_SECRET" ] || [ -z "$OAUTH2_COOKIE_SECRET" ]; then
    echo -e "${RED}Error: Could not fetch OAuth2 secrets from Terraform${NC}"
    echo -e "${YELLOW}OAuth2 secrets are now managed by Terraform.${NC}"
    echo -e "${YELLOW}Please run 'terraform apply' first to generate the random passwords.${NC}"
    echo ""
    echo "Expected Terraform resources:"
    echo "  - random_password.oauth2_client_secret"
    echo "  - random_password.oauth2_cookie_secret"
    echo ""
    echo "Expected Terraform outputs:"
    echo "  - oauth2_client_secret"
    echo "  - oauth2_cookie_secret"
    exit 1
fi

# Validate critical values don't contain ANSI color codes (indicates terraform warning/error output)
if [[ "$KEYCLOAK_DB_USER" =~ \[.*m ]] || [[ "$OAUTH2_CLIENT_SECRET" =~ \[.*m ]] || [[ "$OAUTH2_COOKIE_SECRET" =~ \[.*m ]]; then
    echo -e "${RED}Error: Terraform output contains ANSI codes (warnings/errors). Check terraform state.${NC}"
    echo "Keycloak DB User: $KEYCLOAK_DB_USER"
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

# 1. Fineract DB Credentials (comprehensive - used by all environments)
echo "1. Fineract DB Credentials..."
create_sealed_secret "fineract-db-credentials" "${NAMESPACE}" \
    "username=${RDS_USERNAME}" \
    "password=${RDS_PASSWORD}" \
    "host=${RDS_HOST}" \
    "port=${RDS_PORT}" \
    "database=${RDS_DATABASE}" \
    "jdbc-url=${RDS_JDBC_URL}"

echo

# 2. Keycloak DB Credentials
echo "2. Keycloak DB Credentials..."
# KEYCLOAK_DB_USER already fetched from Terraform above (before cd ..)
# KEYCLOAK_DB_PASS already extracted from Terraform state above (line 109)
KEYCLOAK_JDBC_URL="jdbc:postgresql://${RDS_HOST}:${RDS_PORT}/keycloak"

if [ -n "$KEYCLOAK_DB_PASS" ]; then
    create_sealed_secret "keycloak-db-credentials" "${NAMESPACE}" \
        "username=${KEYCLOAK_DB_USER}" \
        "password=${KEYCLOAK_DB_PASS}" \
        "host=${RDS_HOST}" \
        "port=${RDS_PORT}" \
        "database=keycloak" \
        "jdbc-url=${KEYCLOAK_JDBC_URL}"
else
    echo -e "${YELLOW}  SKIPPED (Keycloak DB credentials not found in Terraform)${NC}"
fi

echo

# 3. OAuth2 Proxy Secrets
echo "3. OAuth2 Proxy Secrets..."
OAUTH2_CLIENT_ID="fineract-oauth2-proxy"
# OAUTH2_CLIENT_SECRET and OAUTH2_COOKIE_SECRET already fetched from Terraform above (before cd ..)

# Note: Redis password must be provided separately via fineract-redis-secret
# This secret references in-cluster Redis which uses password from fineract-redis-secret
# OAuth2 Proxy ConfigMap references redis://fineract-redis:6379 and reads password from OAUTH2_PROXY_REDIS_PASSWORD env var
create_sealed_secret "oauth2-proxy-secrets" "${NAMESPACE}" \
    "client-id=${OAUTH2_CLIENT_ID}" \
    "client-secret=${OAUTH2_CLIENT_SECRET}" \
    "cookie-secret=${OAUTH2_COOKIE_SECRET}"

echo

# 4. Keycloak Client Secrets (CRITICAL: Must match OAuth2 Proxy client secret)
echo "4. Keycloak Client Secrets..."
echo -e "${YELLOW}  IMPORTANT: Using same OAuth2 client secret to ensure authentication works${NC}"
echo -e "${YELLOW}  This secret is used by Keycloak realm configuration job${NC}"

# Create keycloak-client-secrets with the SAME OAuth2 client secret
# The oauth2-proxy key MUST match the client-secret in oauth2-proxy-secrets
# Otherwise OAuth2 token exchange will fail with 401 Unauthorized
create_sealed_secret "keycloak-client-secrets" "${NAMESPACE}" \
    "oauth2-proxy=${OAUTH2_CLIENT_SECRET}" \
    "admin-cli=" \
    "fineract-api=" \
    "message-gateway=" \
    "payment-gateway=" \
    "data-loader=" \
    "fineract-data-loader="

echo

# 5. S3 Connection Secret
echo "5. S3 Connection Secret..."
create_sealed_secret "s3-connection" "${NAMESPACE}" \
    "documents-bucket=${S3_DOCUMENTS}" \
    "region=${AWS_REGION}"

echo

# 6. SMTP Credentials (if SES enabled)
if [ -n "$SES_SMTP_PASS" ]; then
    echo "6. SMTP Credentials..."
    create_sealed_secret "smtp-credentials" "${NAMESPACE}" \
        "host=${SES_SMTP_HOST}" \
        "port=${SES_SMTP_PORT}" \
        "username=${SES_SMTP_USER}" \
        "password=${SES_SMTP_PASS}" \
        "sender=${SES_SENDER}"
    echo
else
    echo "6. SMTP Credentials... SKIPPED (SES not enabled)"
    echo
fi

# 7. ElastiCache Redis Credentials (for managed Redis)
echo "7. ElastiCache Redis Credentials..."
ELASTICACHE_ENDPOINT=$(terraform output -raw elasticache_primary_endpoint 2>/dev/null || echo "")
ELASTICACHE_PORT=$(terraform output -raw elasticache_primary_port 2>/dev/null || echo "")
ELASTICACHE_AUTH_TOKEN=$(terraform output -raw elasticache_auth_token 2>/dev/null || echo "")

if [ -n "$ELASTICACHE_ENDPOINT" ] && [ -n "$ELASTICACHE_PORT" ]; then
    create_sealed_secret "fineract-redis-credentials" "${NAMESPACE}" \
        "endpoint=${ELASTICACHE_ENDPOINT}" \
        "port=${ELASTICACHE_PORT}"
    if [ -n "$ELASTICACHE_AUTH_TOKEN" ]; then
        # Recreate with auth token if available
        create_sealed_secret "fineract-redis-credentials" "${NAMESPACE}" \
            "endpoint=${ELASTICACHE_ENDPOINT}" \
            "port=${ELASTICACHE_PORT}" \
            "auth-token=${ELASTICACHE_AUTH_TOKEN}"
    fi
    echo -e "${GREEN}  ✓ ElastiCache Redis credentials sealed.${NC}"
else
    echo "  SKIPPED (ElastiCache not provisioned by Terraform). If using in-cluster Redis, use create-all-sealed-secrets.sh."
fi

echo

# 8. Service Account (just a reference file, actual SA created via manifest)
echo "8. Creating Service Account manifest..."
cat > secrets/${ENV}/service-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${FINERACT_SERVICE_ACCOUNT}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: fineract
    app.kubernetes.io/managed-by: terraform
    environment: ${ENV}
  annotations:
    eks.amazonaws.com/role-arn: ${IRSA_ROLE_ARN}
    description: "Service account for Fineract with IRSA (configurable via FINERACT_SERVICE_ACCOUNT env var)"
automountServiceAccountToken: true
EOF

echo -e "${GREEN}  ✓ Created: secrets/${ENV}/service-account.yaml${NC}"
echo

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Sealed Secrets Creation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Created sealed secrets in: secrets/${ENV}/"
echo
echo "Sealed secrets created:"
echo "  ✓ fineract-db-credentials (comprehensive - host, port, jdbc-url, etc.)"
echo "  ✓ keycloak-db-credentials (Keycloak RDS database)"
echo "  ✓ oauth2-proxy-secrets (OAuth2 Proxy client credentials)"
echo "  ✓ keycloak-client-secrets (Keycloak client credentials - MATCHES oauth2-proxy)"
echo "  ✓ s3-connection (S3 buckets and region)"
if [ -n "$SES_SMTP_PASS" ]; then
    echo "  ✓ smtp-credentials (SES email)"
fi
if [ -n "$ELASTICACHE_ENDPOINT" ]; then
    echo "  ✓ fineract-redis-credentials (ElastiCache)"
fi
echo "  ✓ service-account.yaml (IRSA manifest)"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review generated sealed secrets:"
echo "   ls -la secrets/${ENV}/"
echo
echo "2. Commit sealed secrets to Git:"
echo "   git add secrets/${ENV}/"
echo "   git commit -m \"Add sealed secrets for ${ENV} environment\""
echo "   git push"
echo
echo "3. Apply sealed secrets to cluster (if not using ArgoCD):"
echo "   kubectl apply -f secrets/${ENV}/"
echo
echo "4. Or deploy via ArgoCD:"
echo "   kubectl apply -f argocd/bootstrap/${ENV}/app-of-apps.yaml"
echo
echo -e "${GREEN}Done!${NC}"
