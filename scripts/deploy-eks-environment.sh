#!/usr/bin/env bash
#
# EKS Environment Deployment Automation
#
# This script automates the complete deployment of Fineract on AWS EKS.
# It codifies all manual steps performed during the initial EKS migration.
#
# Usage:
#   ./scripts/deploy-eks-environment.sh [dev|uat|production] [--gitops|--direct]
#
# Modes:
#   --gitops: Deploy via ArgoCD (requires GitHub token)
#   --direct: Deploy directly with kubectl (for testing)
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - kubectl installed
#   - terraform installed
#   - kubeseal installed (for sealed secrets)
#   - argocd CLI installed (for GitOps mode)
#

set -euo pipefail

# ============================================================================
# Configuration and Global Variables
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform/aws"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Deployment configuration
ENVIRONMENT="${1:-}"
DEPLOYMENT_MODE="${2:---gitops}"  # --gitops or --direct
AWS_REGION="${AWS_REGION:-us-east-2}"
TERRAFORM_BACKEND_BUCKET="fineract-gitops-terraform-state"
TERRAFORM_BACKEND_TABLE="fineract-gitops-terraform-lock"

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✓ $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✗ $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠ $*"
}

error_exit() {
    log_error "$1"
    exit 1
}

print_header() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "$1 is not installed. Please install it first."
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_environment() {
    case "$ENVIRONMENT" in
        dev|uat|production)
            log_success "Environment: $ENVIRONMENT"
            ;;
        *)
            echo "Usage: $0 [dev|uat|production] [--gitops|--direct]"
            echo
            echo "Environments:"
            echo "  dev        - Development environment"
            echo "  uat        - User Acceptance Testing environment"
            echo "  production - Production environment"
            echo
            echo "Deployment Modes:"
            echo "  --gitops   - Deploy via ArgoCD (GitOps, default)"
            echo "  --direct   - Deploy directly with kubectl (testing)"
            exit 1
            ;;
    esac
}

validate_prerequisites() {
    print_header "Checking Prerequisites"

    log "Checking required commands..."
    check_command aws
    check_command kubectl
    check_command terraform
    check_command kubeseal
    check_command jq
    check_command git

    if [[ "$DEPLOYMENT_MODE" == "--gitops" ]]; then
        check_command argocd
    fi

    log_success "All required commands are installed"

    # Check AWS credentials
    log "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure'"
    fi

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')
    log_success "AWS credentials valid (Account: $AWS_ACCOUNT_ID, User: $AWS_USER)"

    # Check AWS region
    CURRENT_REGION=$(aws configure get region || echo "us-east-2")
    if [[ "$CURRENT_REGION" != "$AWS_REGION" ]]; then
        log_warn "Current AWS region is $CURRENT_REGION, but deployment uses $AWS_REGION"
        export AWS_REGION="$AWS_REGION"
    fi
    log_success "AWS region: $AWS_REGION"
}

# ============================================================================
# Terraform Functions
# ============================================================================

setup_terraform_backend() {
    print_header "Setting Up Terraform Backend"

    cd "$TERRAFORM_DIR"

    # Check if backend already exists
    if aws s3api head-bucket --bucket "$TERRAFORM_BACKEND_BUCKET" 2>/dev/null; then
        log_success "Terraform backend S3 bucket already exists"
    else
        log "Creating Terraform backend S3 bucket..."
        aws s3api create-bucket \
            --bucket "$TERRAFORM_BACKEND_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"

        aws s3api put-bucket-versioning \
            --bucket "$TERRAFORM_BACKEND_BUCKET" \
            --versioning-configuration Status=Enabled

        aws s3api put-bucket-encryption \
            --bucket "$TERRAFORM_BACKEND_BUCKET" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'

        log_success "Created Terraform backend S3 bucket"
    fi

    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$TERRAFORM_BACKEND_TABLE" &> /dev/null; then
        log_success "Terraform backend DynamoDB table already exists"
    else
        log "Creating Terraform backend DynamoDB table..."
        aws dynamodb create-table \
            --table-name "$TERRAFORM_BACKEND_TABLE" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$AWS_REGION"

        log_success "Created Terraform backend DynamoDB table"
    fi
}

deploy_terraform_infrastructure() {
    print_header "Deploying Terraform Infrastructure"

    cd "$TERRAFORM_DIR"

    local tfvars_file="environments/${ENVIRONMENT}-eks.tfvars"
    if [[ ! -f "$tfvars_file" ]]; then
        error_exit "Terraform variables file not found: $tfvars_file"
    fi

    log "Initializing Terraform..."
    terraform init

    log "Validating Terraform configuration..."
    terraform validate

    log "Planning Terraform changes..."
    terraform plan -var-file="$tfvars_file" -out=tfplan

    log "Applying Terraform changes..."
    terraform apply tfplan

    rm -f tfplan
    log_success "Terraform infrastructure deployed successfully"
}

validate_terraform_outputs() {
    print_header "Validating Terraform Outputs"

    cd "$TERRAFORM_DIR"

    log "Running Terraform output validation..."
    "$REPO_ROOT/scripts/validate-terraform-outputs.sh" "$ENVIRONMENT"

    log_success "Terraform outputs validated successfully"
}

# ============================================================================
# Kubernetes Functions
# ============================================================================

configure_kubectl() {
    print_header "Configuring kubectl for EKS"

    cd "$TERRAFORM_DIR"

    local cluster_name
    cluster_name=$(terraform output -raw eks_cluster_name)

    log "Updating kubeconfig for cluster: $cluster_name"
    aws eks update-kubeconfig --name "$cluster_name" --region "$AWS_REGION"

    log "Verifying cluster access..."
    kubectl get nodes

    log_success "kubectl configured successfully"
}

install_argocd() {
    print_header "Installing ArgoCD"

    if kubectl get namespace argocd &> /dev/null; then
        log_success "ArgoCD namespace already exists"
    else
        log "Creating ArgoCD namespace..."
        kubectl create namespace argocd
    fi

    if kubectl get deployment argocd-server -n argocd &> /dev/null; then
        log_success "ArgoCD already installed"
    else
        log "Installing ArgoCD..."
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

        log "Waiting for ArgoCD to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

        log_success "ArgoCD installed successfully"
    fi
}

install_sealed_secrets_controller() {
    print_header "Installing Sealed Secrets Controller"

    if kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        log_success "Sealed Secrets controller already installed"
    else
        log "Installing Sealed Secrets controller..."
        kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/controller.yaml

        log "Waiting for Sealed Secrets controller to be ready..."
        kubectl wait --for=condition=available --timeout=120s deployment/sealed-secrets-controller -n kube-system

        log_success "Sealed Secrets controller installed successfully"
    fi
}

create_sealed_secrets() {
    print_header "Creating Sealed Secrets"

    log "Running enhanced sealed secrets creation script..."
    "$REPO_ROOT/scripts/seal-terraform-secrets-enhanced.sh" "$ENVIRONMENT"

    log "Applying sealed secrets to cluster..."
    kubectl apply -f "$REPO_ROOT/secrets/$ENVIRONMENT/namespace.yaml"
    kubectl apply -f "$REPO_ROOT/secrets/$ENVIRONMENT/" --recursive

    log_success "Sealed secrets created and applied"
}

configure_argocd() {
    print_header "Configuring ArgoCD"

    log "Applying ArgoCD projects..."
    kubectl apply -f "$REPO_ROOT/argocd/projects/project-$ENVIRONMENT.yaml"

    log "Applying ArgoCD configuration..."
    kubectl apply -f "$REPO_ROOT/argocd/config/argocd-cm.yaml"
    kubectl apply -f "$REPO_ROOT/argocd/config/argocd-rbac-cm.yaml"

    log "Restarting ArgoCD server to apply configuration..."
    kubectl rollout restart deployment/argocd-server -n argocd
    kubectl rollout status deployment/argocd-server -n argocd --timeout=120s

    log_success "ArgoCD configured successfully"
}

configure_github_credentials() {
    print_header "Configuring GitHub Repository Credentials"

    if kubectl get secret repo-fineract-gitops -n argocd &> /dev/null; then
        log_success "GitHub repository credentials already configured"
    else
        log "GitHub repository credentials not found"
        log_warn "Run: ./scripts/seal-argocd-github-credentials.sh"
        log_warn "Then: kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml"
        log_warn "See: docs/GITHUB_TOKEN_SETUP.md for details"
    fi
}

deploy_via_argocd() {
    print_header "Deploying Applications via ArgoCD"

    log "Deploying app-of-apps..."
    kubectl apply -f "$REPO_ROOT/argocd/bootstrap/$ENVIRONMENT/app-of-apps.yaml"

    log "Waiting for applications to sync..."
    sleep 10

    log "Current ArgoCD applications:"
    kubectl get applications -n argocd

    log_success "Applications deployed via ArgoCD"
}

deploy_directly() {
    print_header "Deploying Applications Directly"

    log "Deploying using kustomize..."
    kubectl apply -k "$REPO_ROOT/environments/$ENVIRONMENT/"

    log_success "Applications deployed directly"
}

# ============================================================================
# Monitoring and Verification Functions
# ============================================================================

wait_for_loadbalancer() {
    print_header "Waiting for LoadBalancer Provisioning"

    local namespace="fineract-$ENVIRONMENT"

    log "Checking for LoadBalancer services in namespace: $namespace"

    local max_wait=600  # 10 minutes
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local lb_services
        lb_services=$(kubectl get svc -n "$namespace" -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name')

        if [[ -n "$lb_services" ]]; then
            log "Found LoadBalancer services:"
            echo "$lb_services"

            # Check if all have external IPs
            local pending=false
            while IFS= read -r svc; do
                local external_ip
                external_ip=$(kubectl get svc "$svc" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                if [[ -z "$external_ip" ]]; then
                    pending=true
                    log "Service $svc: Waiting for external IP..."
                else
                    log_success "Service $svc: $external_ip"
                fi
            done <<< "$lb_services"

            if [[ "$pending" == "false" ]]; then
                log_success "All LoadBalancers have external IPs"
                return 0
            fi
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    log_warn "LoadBalancer provisioning taking longer than expected"
}

verify_irsa_credentials() {
    print_header "Verifying IRSA Credentials"

    log "Running IRSA verification script..."
    "$REPO_ROOT/scripts/verify-irsa-credentials.sh" "$ENVIRONMENT"

    log_success "IRSA credentials verified"
}

display_endpoints() {
    print_header "Application Endpoints"

    log "Retrieving endpoints..."
    "$REPO_ROOT/scripts/get-endpoints.sh" "$ENVIRONMENT"
}

display_deployment_summary() {
    print_header "Deployment Summary"

    local namespace="fineract-$ENVIRONMENT"

    echo "Environment: $ENVIRONMENT"
    echo "Namespace: $namespace"
    echo "Deployment Mode: $DEPLOYMENT_MODE"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo

    echo "Kubernetes Resources:"
    echo "  Nodes:"
    kubectl get nodes --no-headers | wc -l | xargs echo "    Count:"
    echo "  Pods:"
    kubectl get pods -n "$namespace" --no-headers | wc -l | xargs echo "    Total:"
    kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers | wc -l | xargs echo "    Running:"
    echo "  Services:"
    kubectl get svc -n "$namespace" --no-headers | wc -l | xargs echo "    Count:"
    echo

    cd "$TERRAFORM_DIR"
    echo "Terraform Outputs:"
    echo "  Cluster: $(terraform output -raw eks_cluster_name 2>/dev/null || echo 'N/A')"
    echo "  RDS: $(terraform output -raw rds_instance_endpoint 2>/dev/null || echo 'N/A')"
    echo "  S3 Documents: $(terraform output -raw documents_bucket_name 2>/dev/null || echo 'N/A')"
    echo "  S3 Backups: $(terraform output -raw backups_bucket_name 2>/dev/null || echo 'N/A')"
    echo
}

# ============================================================================
# Main Deployment Function
# ============================================================================

main() {
    validate_environment
    validate_prerequisites

    print_header "EKS Environment Deployment"
    log "Environment: $ENVIRONMENT"
    log "Mode: $DEPLOYMENT_MODE"
    log "Region: $AWS_REGION"
    echo

    # Step 1: Setup Terraform Backend
    setup_terraform_backend

    # Step 2: Deploy Terraform Infrastructure
    deploy_terraform_infrastructure

    # Step 3: Validate Terraform Outputs
    validate_terraform_outputs

    # Step 4: Configure kubectl
    configure_kubectl

    # Step 5: Install ArgoCD
    install_argocd

    # Step 6: Install Sealed Secrets Controller
    install_sealed_secrets_controller

    # Step 7: Create Sealed Secrets
    create_sealed_secrets

    # Step 8: Configure ArgoCD
    configure_argocd

    # Step 9: Configure GitHub Credentials (if GitOps mode)
    if [[ "$DEPLOYMENT_MODE" == "--gitops" ]]; then
        configure_github_credentials
    fi

    # Step 10: Deploy Applications
    if [[ "$DEPLOYMENT_MODE" == "--gitops" ]]; then
        deploy_via_argocd
    else
        deploy_directly
    fi

    # Step 11: Wait for LoadBalancer (if applicable)
    wait_for_loadbalancer || true

    # Step 12: Verify IRSA Credentials
    verify_irsa_credentials || true

    # Step 13: Display Endpoints
    display_endpoints || true

    # Step 14: Display Summary
    display_deployment_summary

    print_header "Deployment Complete!"
    log_success "EKS environment '$ENVIRONMENT' deployed successfully"
    echo
    log "Next Steps:"
    echo "  1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  2. Get ArgoCD admin password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
    echo "  3. Monitor applications: kubectl get pods -n fineract-$ENVIRONMENT -w"
    echo "  4. View logs: kubectl logs -n fineract-$ENVIRONMENT -l app=fineract --tail=100"
    echo

    if [[ "$DEPLOYMENT_MODE" == "--gitops" ]] && ! kubectl get secret repo-fineract-gitops -n argocd &> /dev/null; then
        log_warn "GitHub credentials not configured - ArgoCD won't sync from Git"
        log_warn "See: docs/GITHUB_TOKEN_SETUP.md"
    fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
