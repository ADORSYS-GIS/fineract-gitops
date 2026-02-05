#!/bin/bash
# ==============================================================================
# Seal Terraform Secrets for GCP
# ==============================================================================
# This script extracts sensitive values from Terraform outputs and creates
# Sealed Secrets for GitOps deployment.
#
# Prerequisites:
#   - kubeseal CLI installed
#   - kubectl configured for target cluster
#   - Sealed Secrets controller deployed in cluster
#
# Usage:
#   ./seal-terraform-secrets-gcp.sh dev
#   ./seal-terraform-secrets-gcp.sh uat
#   ./seal-terraform-secrets-gcp.sh production
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform/gcp"
SECRETS_DIR="${SCRIPT_DIR}/../secrets"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubeseal &> /dev/null; then
        log_error "kubeseal is not installed."
        log_info "Install with: brew install kubeseal"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed."
        exit 1
    fi

    if ! kubectl get ns sealed-secrets &> /dev/null; then
        log_warn "sealed-secrets namespace not found. Make sure Sealed Secrets is deployed."
    fi
}

get_terraform_output() {
    local key=$1
    cd "${TERRAFORM_DIR}"
    terraform output -raw "${key}" 2>/dev/null || echo ""
}

create_sealed_secret() {
    local name=$1
    local namespace=$2
    local output_file=$3
    shift 3
    local literals=("$@")

    log_info "Creating sealed secret: ${name}"

    # Build kubectl create secret command
    local cmd="kubectl create secret generic ${name} --namespace=${namespace} --dry-run=client -o yaml"
    for literal in "${literals[@]}"; do
        cmd+=" --from-literal=${literal}"
    done

    # Create and seal the secret
    eval "${cmd}" | kubeseal --format yaml > "${output_file}"

    log_info "Sealed secret saved to: ${output_file}"
}

main() {
    local environment="${1:-}"

    if [[ -z "${environment}" ]]; then
        echo "Usage: $0 <environment>"
        echo "  environment: dev, uat, or production"
        exit 1
    fi

    if [[ "${environment}" == "prod" ]]; then
        environment="production"
    fi

    log_info "Sealing Terraform secrets for: ${environment}"

    check_prerequisites

    # Create secrets directory
    local env_secrets_dir="${SECRETS_DIR}/${environment}-gcp"
    mkdir -p "${env_secrets_dir}"

    # Map environment to namespace
    local namespace="fineract-${environment}"
    if [[ "${environment}" == "production" ]]; then
        namespace="fineract-production"
    fi

    # Get Terraform outputs
    cd "${TERRAFORM_DIR}"

    log_info "Extracting Terraform outputs..."

    local db_host=$(get_terraform_output "cloud_sql_private_ip")
    local db_connection=$(get_terraform_output "cloud_sql_connection_name")
    local db_username=$(get_terraform_output "db_master_username")
    local docs_bucket=$(get_terraform_output "documents_bucket_name")
    local backups_bucket=$(get_terraform_output "backups_bucket_name")
    local gcp_sa_email=$(get_terraform_output "fineract_service_account_email")
    local region=$(get_terraform_output "gke_cluster_location" | cut -d'-' -f1-2)  # Extract region from zone

    # Get sensitive outputs from terraform show
    log_info "Extracting sensitive values..."
    local db_password=$(terraform show -json | jq -r '.values.root_module.child_modules[].resources[]? | select(.address == "module.cloud_sql.random_password.master_password") | .values.result' 2>/dev/null | head -1)
    local keycloak_db_password=$(terraform show -json | jq -r '.values.root_module.child_modules[].resources[]? | select(.address == "module.cloud_sql.random_password.keycloak_password") | .values.result' 2>/dev/null | head -1)
    local keycloak_admin_password=$(terraform show -json | jq -r '.values.root_module.resources[]? | select(.address == "random_password.keycloak_admin_password") | .values.result' 2>/dev/null | head -1)
    local redis_password=$(terraform show -json | jq -r '.values.root_module.resources[]? | select(.address == "random_password.redis_password") | .values.result' 2>/dev/null | head -1)
    local oauth2_client_secret=$(terraform show -json | jq -r '.values.root_module.resources[]? | select(.address == "random_password.oauth2_client_secret") | .values.result' 2>/dev/null | head -1)
    local oauth2_cookie_secret=$(terraform show -json | jq -r '.values.root_module.resources[]? | select(.address == "random_password.oauth2_cookie_secret") | .values.result' 2>/dev/null | head -1)

    # Create sealed secrets
    log_info "Creating sealed secrets..."

    # Database credentials (Fineract)
    if [[ -n "${db_password}" ]]; then
        # Build JDBC URL
        local jdbc_url="jdbc:postgresql://${db_host}:5432/fineract_tenants"

        create_sealed_secret "fineract-db-credentials" "${namespace}" \
            "${env_secrets_dir}/fineract-db-credentials.yaml" \
            "host=${db_host}" \
            "port=5432" \
            "username=${db_username}" \
            "password=${db_password}" \
            "jdbc-url=${jdbc_url}" \
            "connection-name=${db_connection}"
    fi

    # Keycloak database credentials
    if [[ -n "${keycloak_db_password}" ]]; then
        create_sealed_secret "keycloak-db-credentials" "${namespace}" \
            "${env_secrets_dir}/keycloak-db-credentials.yaml" \
            "host=${db_host}" \
            "port=5432" \
            "database=keycloak" \
            "username=keycloak" \
            "password=${keycloak_db_password}"
    fi

    # Keycloak admin credentials
    if [[ -n "${keycloak_admin_password}" ]]; then
        create_sealed_secret "keycloak-admin-credentials" "${namespace}" \
            "${env_secrets_dir}/keycloak-admin-credentials.yaml" \
            "username=admin" \
            "password=${keycloak_admin_password}"
    fi

    # Redis secret
    if [[ -n "${redis_password}" ]]; then
        create_sealed_secret "fineract-redis-secret" "${namespace}" \
            "${env_secrets_dir}/fineract-redis-secret.yaml" \
            "redis-password=${redis_password}"
    fi

    # GCS/S3 connection
    create_sealed_secret "s3-connection" "${namespace}" \
        "${env_secrets_dir}/s3-connection.yaml" \
        "documents-bucket=${docs_bucket}" \
        "backups-bucket=${backups_bucket}" \
        "region=${region:-us-central1}"

    # OAuth2 proxy secrets
    if [[ -n "${oauth2_cookie_secret}" ]]; then
        create_sealed_secret "oauth2-proxy-secrets" "${namespace}" \
            "${env_secrets_dir}/oauth2-proxy-secrets.yaml" \
            "cookie-secret=${oauth2_cookie_secret}"
    fi

    # Keycloak client secrets (for OAuth2 Proxy)
    if [[ -n "${oauth2_client_secret}" ]]; then
        create_sealed_secret "keycloak-client-secrets" "${namespace}" \
            "${env_secrets_dir}/keycloak-client-secrets.yaml" \
            "oauth2-proxy-client-id=fineract-oauth2-proxy" \
            "oauth2-proxy-client-secret=${oauth2_client_secret}"
    fi

    log_info "=== Sealed secrets created successfully ==="
    log_info "Files saved to: ${env_secrets_dir}"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review the generated sealed secrets"
    log_info "  2. Commit them to Git"
    log_info "  3. Apply via ArgoCD or kubectl apply -f ${env_secrets_dir}/"
}

main "$@"
