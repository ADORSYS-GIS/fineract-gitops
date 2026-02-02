#!/bin/bash
# ==============================================================================
# GCP Cluster Deployment Script
# ==============================================================================
# This script deploys the GCP infrastructure using Terraform
#
# Prerequisites:
#   - Google Cloud SDK (gcloud) installed and authenticated
#   - Terraform >= 1.0.0 installed
#   - GCP project created with billing enabled
#
# Usage:
#   ./deploy-gcp-cluster.sh dev     # Deploy dev environment
#   ./deploy-gcp-cluster.sh uat     # Deploy UAT environment
#   ./deploy-gcp-cluster.sh prod    # Deploy production environment
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform/gcp"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Check terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform >= 1.0.0"
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    log_info "All prerequisites met."
}

enable_apis() {
    local project_id=$1
    log_info "Enabling required GCP APIs for project: ${project_id}..."

    gcloud services enable \
        container.googleapis.com \
        compute.googleapis.com \
        sqladmin.googleapis.com \
        servicenetworking.googleapis.com \
        secretmanager.googleapis.com \
        dns.googleapis.com \
        cloudresourcemanager.googleapis.com \
        iam.googleapis.com \
        --project="${project_id}"

    log_info "APIs enabled successfully."
}

deploy_terraform() {
    local environment=$1
    local tfvars_file="${TERRAFORM_DIR}/environments/${environment}.tfvars"

    if [[ ! -f "${tfvars_file}" ]]; then
        log_error "Environment file not found: ${tfvars_file}"
        exit 1
    fi

    log_info "Deploying ${environment} environment..."

    cd "${TERRAFORM_DIR}"

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -upgrade

    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate

    # Plan
    log_info "Creating Terraform plan..."
    terraform plan -var-file="${tfvars_file}" -out=tfplan

    # Confirm deployment
    echo ""
    read -p "Do you want to apply this plan? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_warn "Deployment cancelled."
        exit 0
    fi

    # Apply
    log_info "Applying Terraform plan..."
    terraform apply tfplan

    # Clean up plan file
    rm -f tfplan

    log_info "Deployment completed successfully!"
}

configure_kubectl() {
    local environment=$1
    log_info "Configuring kubectl..."

    # Get cluster info from Terraform output
    cd "${TERRAFORM_DIR}"
    local kubeconfig_cmd=$(terraform output -raw kubeconfig_command 2>/dev/null || echo "")

    if [[ -n "${kubeconfig_cmd}" ]]; then
        log_info "Running: ${kubeconfig_cmd}"
        eval "${kubeconfig_cmd}"
        log_info "kubectl configured successfully."
    else
        log_warn "Could not get kubeconfig command from Terraform output."
        log_warn "Run the gcloud command manually to configure kubectl."
    fi
}

print_outputs() {
    log_info "Terraform outputs:"
    cd "${TERRAFORM_DIR}"
    terraform output
}

# Main
main() {
    local environment="${1:-}"

    if [[ -z "${environment}" ]]; then
        echo "Usage: $0 <environment>"
        echo "  environment: dev, uat, or production"
        exit 1
    fi

    # Map 'prod' to 'production'
    if [[ "${environment}" == "prod" ]]; then
        environment="production"
    fi

    # Validate environment
    if [[ ! "${environment}" =~ ^(dev|uat|production)$ ]]; then
        log_error "Invalid environment: ${environment}"
        echo "Valid environments: dev, uat, production"
        exit 1
    fi

    log_info "Deploying Fineract GCP infrastructure for: ${environment}"
    echo ""

    check_prerequisites

    # Get project ID from tfvars
    local tfvars_file="${TERRAFORM_DIR}/environments/${environment}.tfvars"
    local project_id=$(grep 'project_id' "${tfvars_file}" | sed 's/.*"\(.*\)".*/\1/')

    log_info "Target GCP Project: ${project_id}"

    # Set project
    gcloud config set project "${project_id}"

    # Enable APIs
    enable_apis "${project_id}"

    # Deploy
    deploy_terraform "${environment}"

    # Configure kubectl
    configure_kubectl "${environment}"

    # Print outputs
    print_outputs

    echo ""
    log_info "=== Deployment Complete ==="
    log_info "Next steps:"
    log_info "  1. Run: kubectl get nodes"
    log_info "  2. Deploy applications via ArgoCD"
    log_info "  3. Run: ./seal-terraform-secrets-gcp.sh ${environment}"
}

main "$@"
