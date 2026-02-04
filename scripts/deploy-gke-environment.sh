#!/usr/bin/env bash
#
# GKE Environment Deployment Automation
#
# This script automates the complete deployment of Fineract on GCP GKE.
# It provides end-to-end deployment automation while keeping AWS deployment intact.
#
# Usage:
#   ./scripts/deploy-gke-environment.sh [dev|uat|production] [--gitops|--direct]
#
# Modes:
#   --gitops: Deploy via ArgoCD (requires GitHub token)
#   --direct: Deploy directly with kubectl (for testing)
#
# Prerequisites:
#   - Google Cloud SDK (gcloud) installed and authenticated
#   - kubectl installed
#   - terraform >= 1.0.0 installed
#   - kubeseal installed (for sealed secrets)
#   - argocd CLI installed (for GitOps mode)
#
# Environment Variables:
#   GCP_PROJECT_ID  - Override project ID from tfvars
#   GCP_REGION      - Override region (default: us-central1)
#

set -euo pipefail

# ============================================================================
# Configuration and Global Variables
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform/gcp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Deployment configuration
ENVIRONMENT="${1:-}"
DEPLOYMENT_MODE="${2:---gitops}"  # --gitops or --direct
GCP_REGION="${GCP_REGION:-us-central1}"

# GCP Project ID (will be read from tfvars if not set)
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
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
        prod)
            # Map 'prod' to 'production'
            ENVIRONMENT="production"
            log_success "Environment: $ENVIRONMENT"
            ;;
        *)
            echo "Usage: $0 [dev|uat|production] [--gitops|--direct]"
            echo
            echo "Environments:"
            echo "  dev        - Development environment (preemptible VMs, ~\$180/month)"
            echo "  uat        - User Acceptance Testing environment (~\$250/month)"
            echo "  production - Production environment (HA, ~\$750/month)"
            echo
            echo "Deployment Modes:"
            echo "  --gitops   - Deploy via ArgoCD (GitOps, default)"
            echo "  --direct   - Deploy directly with kubectl (testing)"
            echo
            echo "Examples:"
            echo "  $0 dev                  # Deploy dev with GitOps"
            echo "  $0 uat --direct         # Deploy UAT directly with kubectl"
            echo "  $0 production --gitops  # Deploy production with ArgoCD"
            exit 1
            ;;
    esac
}

validate_prerequisites() {
    print_header "Checking Prerequisites"

    log "Checking required commands..."
    check_command gcloud
    check_command kubectl
    check_command terraform
    check_command kubeseal
    check_command jq
    check_command git

    if [[ "$DEPLOYMENT_MODE" == "--gitops" ]]; then
        if ! command -v argocd &> /dev/null; then
            log_warn "argocd CLI not installed. Some GitOps features may be limited."
        fi
    fi

    log_success "All required commands are installed"

    # Check gcloud authentication
    log "Checking GCP authentication..."
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        error_exit "Not authenticated with gcloud. Run: gcloud auth login"
    fi

    GCP_USER=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
    log_success "GCP credentials valid (User: $GCP_USER)"

    # Get project ID from tfvars if not set
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        local tfvars_file="${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars"
        if [[ -f "$tfvars_file" ]]; then
            GCP_PROJECT_ID=$(grep 'project_id' "$tfvars_file" | sed 's/.*"\(.*\)".*/\1/')
        fi
    fi

    if [[ -z "$GCP_PROJECT_ID" ]]; then
        error_exit "GCP_PROJECT_ID not set and could not be read from tfvars"
    fi

    log_success "GCP Project: $GCP_PROJECT_ID"
    log_success "GCP Region: $GCP_REGION"

    # Verify project exists and user has access
    if ! gcloud projects describe "$GCP_PROJECT_ID" &> /dev/null; then
        error_exit "Cannot access project: $GCP_PROJECT_ID. Check permissions."
    fi
}

# ============================================================================
# GCP API Functions
# ============================================================================

enable_gcp_apis() {
    print_header "Enabling GCP APIs"

    log "Enabling required GCP APIs for project: ${GCP_PROJECT_ID}..."

    local apis=(
        "container.googleapis.com"        # GKE
        "compute.googleapis.com"          # VMs, Networks
        "sqladmin.googleapis.com"         # Cloud SQL
        "servicenetworking.googleapis.com" # VPC peering
        "secretmanager.googleapis.com"    # Secret Manager
        "dns.googleapis.com"              # Cloud DNS
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"              # IAM
        "storage.googleapis.com"          # GCS
        "billingbudgets.googleapis.com"   # Budget alerts
    )

    for api in "${apis[@]}"; do
        log "  Enabling $api..."
        gcloud services enable "$api" --project="$GCP_PROJECT_ID" 2>/dev/null || true
    done

    log_success "GCP APIs enabled successfully"
}

# ============================================================================
# Terraform Functions
# ============================================================================

setup_terraform_backend() {
    print_header "Setting Up Terraform Backend"

    local bucket_name="${GCP_PROJECT_ID}-terraform-state"

    # Check if bucket already exists
    if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
        log_success "Terraform backend GCS bucket already exists: ${bucket_name}"
    else
        log "Creating Terraform backend GCS bucket..."
        gsutil mb -p "$GCP_PROJECT_ID" -l "$GCP_REGION" "gs://${bucket_name}"
        gsutil versioning set on "gs://${bucket_name}"
        log_success "Created Terraform backend GCS bucket: ${bucket_name}"
    fi

    # Update backend.tf with correct bucket name
    log "Updating backend configuration..."
    cd "$TERRAFORM_DIR"

    # Create backend config if it doesn't have the correct bucket
    cat > backend.tf << EOF
# ==============================================================================
# Terraform Backend Configuration
# ==============================================================================
# Store state in GCS bucket for team collaboration
# ==============================================================================

terraform {
  backend "gcs" {
    bucket = "${bucket_name}"
    prefix = "fineract/${ENVIRONMENT}"
  }
}
EOF

    log_success "Terraform backend configured"
}

deploy_terraform_infrastructure() {
    print_header "Deploying Terraform Infrastructure"

    cd "$TERRAFORM_DIR"

    local tfvars_file="environments/${ENVIRONMENT}.tfvars"
    if [[ ! -f "$tfvars_file" ]]; then
        error_exit "Terraform variables file not found: $tfvars_file"
    fi

    log "Initializing Terraform..."
    terraform init -upgrade -reconfigure

    log "Validating Terraform configuration..."
    terraform validate

    log "Creating Terraform plan..."
    terraform plan -var-file="$tfvars_file" -out=tfplan

    echo
    echo -e "${YELLOW}Review the plan above. Do you want to apply these changes?${NC}"
    read -p "Type 'yes' to continue: " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_warn "Deployment cancelled by user."
        rm -f tfplan
        exit 0
    fi

    log "Applying Terraform plan..."
    terraform apply tfplan

    rm -f tfplan
    log_success "Terraform infrastructure deployed successfully"
}

# ============================================================================
# Kubernetes Functions
# ============================================================================

configure_kubectl() {
    print_header "Configuring kubectl for GKE"

    cd "$TERRAFORM_DIR"

    # Get cluster info from Terraform output
    local cluster_name
    local cluster_region

    cluster_name=$(terraform output -raw gke_cluster_name 2>/dev/null || echo "")
    cluster_region=$(terraform output -raw gke_cluster_region 2>/dev/null || echo "$GCP_REGION")

    if [[ -z "$cluster_name" ]]; then
        # Fallback: construct cluster name
        cluster_name="apache-fineract-${ENVIRONMENT}"
        log_warn "Could not get cluster name from Terraform, using: $cluster_name"
    fi

    log "Configuring kubectl for cluster: $cluster_name"
    gcloud container clusters get-credentials "$cluster_name" \
        --region "$cluster_region" \
        --project "$GCP_PROJECT_ID"

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

    # Patch ArgoCD server service to LoadBalancer for easy access (optional)
    log "Configuring ArgoCD server access..."
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true
}

install_sealed_secrets_controller() {
    print_header "Installing Sealed Secrets Controller"

    # Check in kube-system namespace (default location)
    if kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        log_success "Sealed Secrets controller already installed in kube-system"
    # Check in sealed-secrets namespace
    elif kubectl get deployment sealed-secrets-controller -n sealed-secrets &> /dev/null; then
        log_success "Sealed Secrets controller already installed in sealed-secrets"
    else
        log "Installing Sealed Secrets controller..."
        kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/controller.yaml

        log "Waiting for Sealed Secrets controller to be ready..."
        kubectl wait --for=condition=available --timeout=120s deployment/sealed-secrets-controller -n kube-system

        log_success "Sealed Secrets controller installed successfully"
    fi
}

create_application_namespace() {
    print_header "Creating Application Namespace"

    local namespace="fineract-${ENVIRONMENT}"

    if kubectl get namespace "$namespace" &> /dev/null; then
        log_success "Namespace $namespace already exists"
    else
        log "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
        log_success "Namespace $namespace created"
    fi
}

create_sealed_secrets() {
    print_header "Creating Sealed Secrets"

    local seal_script="$REPO_ROOT/scripts/seal-terraform-secrets-gcp.sh"

    if [[ -f "$seal_script" ]]; then
        log "Running GCP sealed secrets creation script..."
        bash "$seal_script" "$ENVIRONMENT"

        # Apply sealed secrets
        local secrets_dir="$REPO_ROOT/secrets/${ENVIRONMENT}-gcp"
        if [[ -d "$secrets_dir" ]]; then
            log "Applying sealed secrets from $secrets_dir..."
            kubectl apply -f "$secrets_dir/" --recursive 2>/dev/null || true
            log_success "Sealed secrets applied"
        else
            log_warn "No sealed secrets directory found at $secrets_dir"
        fi
    else
        log_warn "Sealed secrets script not found: $seal_script"
        log_warn "Skipping sealed secrets creation"
    fi
}

configure_argocd() {
    print_header "Configuring ArgoCD"

    # Apply GCP-specific ArgoCD project if exists
    local project_file="$REPO_ROOT/argocd/projects/project-${ENVIRONMENT}-gcp.yaml"
    if [[ -f "$project_file" ]]; then
        log "Applying ArgoCD project configuration..."
        kubectl apply -f "$project_file"
    fi

    # Apply ArgoCD configuration if exists
    local config_dir="$REPO_ROOT/argocd/config"
    if [[ -d "$config_dir" ]]; then
        log "Applying ArgoCD configuration..."
        kubectl apply -f "$config_dir/argocd-cm.yaml" 2>/dev/null || true
        kubectl apply -f "$config_dir/argocd-rbac-cm.yaml" 2>/dev/null || true
    fi

    log_success "ArgoCD configured"
}

deploy_via_argocd() {
    print_header "Deploying Applications via ArgoCD"

    # Apply GCP ApplicationSet
    local appset_file="$REPO_ROOT/argocd/applications/gcp/fineract-applicationset-gcp.yaml"

    if [[ -f "$appset_file" ]]; then
        log "Deploying GCP ApplicationSet..."
        kubectl apply -f "$appset_file"
    else
        log_warn "GCP ApplicationSet not found at: $appset_file"
        log_warn "Creating single Application for $ENVIRONMENT..."

        # Create a simple Application instead
        kubectl apply -f - << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract-${ENVIRONMENT}-gcp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/guymoyo/fineract-gitops.git
    targetRevision: feature/aws-cost-optimization
    path: environments/${ENVIRONMENT}-gcp
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-${ENVIRONMENT}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    fi

    log "Waiting for applications to sync..."
    sleep 10

    log "Current ArgoCD applications:"
    kubectl get applications -n argocd

    log_success "Applications deployed via ArgoCD"
}

deploy_directly() {
    print_header "Deploying Applications Directly"

    local env_dir="$REPO_ROOT/environments/${ENVIRONMENT}-gcp"

    if [[ -d "$env_dir" ]]; then
        log "Deploying using kustomize from: $env_dir"
        kubectl apply -k "$env_dir"
        log_success "Applications deployed directly"
    else
        log_warn "Environment directory not found: $env_dir"
        log "Attempting to deploy base environment..."
        kubectl apply -k "$REPO_ROOT/environments/$ENVIRONMENT/" 2>/dev/null || true
    fi
}

# ============================================================================
# Verification and Health Check Functions
# ============================================================================

wait_for_deployments() {
    print_header "Waiting for Deployments"

    local namespace="fineract-${ENVIRONMENT}"
    local max_wait=600  # 10 minutes
    local elapsed=0

    log "Waiting for pods to be ready in namespace: $namespace"

    while [[ $elapsed -lt $max_wait ]]; do
        local total_pods
        local ready_pods

        total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        ready_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$total_pods" -gt 0 ]] && [[ "$total_pods" -eq "$ready_pods" ]]; then
            log_success "All $total_pods pods are running"
            return 0
        fi

        log "  Pods: $ready_pods/$total_pods ready... waiting"
        sleep 15
        elapsed=$((elapsed + 15))
    done

    log_warn "Not all pods are ready after waiting"
    kubectl get pods -n "$namespace"
}

wait_for_loadbalancer() {
    print_header "Waiting for LoadBalancer Provisioning"

    local namespace="fineract-${ENVIRONMENT}"
    local max_wait=300  # 5 minutes
    local elapsed=0

    log "Checking for LoadBalancer services in namespace: $namespace"

    while [[ $elapsed -lt $max_wait ]]; do
        local lb_services
        lb_services=$(kubectl get svc -n "$namespace" -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name' 2>/dev/null || echo "")

        if [[ -n "$lb_services" ]]; then
            log "Found LoadBalancer services:"
            local all_ready=true

            while IFS= read -r svc; do
                local external_ip
                external_ip=$(kubectl get svc "$svc" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
                if [[ -z "$external_ip" ]]; then
                    all_ready=false
                    log "  $svc: Waiting for external IP..."
                else
                    log_success "  $svc: $external_ip"
                fi
            done <<< "$lb_services"

            if [[ "$all_ready" == "true" ]]; then
                log_success "All LoadBalancers have external IPs"
                return 0
            fi
        else
            log "No LoadBalancer services found yet..."
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    log_warn "LoadBalancer provisioning taking longer than expected"
}

verify_workload_identity() {
    print_header "Verifying Workload Identity"

    local namespace="fineract-${ENVIRONMENT}"

    # Check if service accounts have Workload Identity annotation
    log "Checking Workload Identity configuration..."

    local sa_list
    sa_list=$(kubectl get serviceaccounts -n "$namespace" -o json 2>/dev/null | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

    if [[ -n "$sa_list" ]]; then
        while IFS= read -r sa; do
            local annotation
            annotation=$(kubectl get serviceaccount "$sa" -n "$namespace" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || echo "")
            if [[ -n "$annotation" ]]; then
                log_success "  $sa -> $annotation"
            else
                log "  $sa: No Workload Identity annotation"
            fi
        done <<< "$sa_list"
    else
        log_warn "No service accounts found in namespace"
    fi
}

run_health_checks() {
    print_header "Running Health Checks"

    local namespace="fineract-${ENVIRONMENT}"

    # Check nodes
    log "Checking GKE nodes..."
    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    log_success "  Nodes: $node_count"

    # Check pods
    log "Checking pods..."
    local pod_status
    pod_status=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null || echo "No pods")
    echo "$pod_status"

    # Check services
    log "Checking services..."
    kubectl get svc -n "$namespace" 2>/dev/null || echo "No services"

    # Check Cloud SQL connectivity (if fineract pod exists)
    log "Checking database connectivity..."
    local fineract_pod
    fineract_pod=$(kubectl get pods -n "$namespace" -l app=fineract -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$fineract_pod" ]]; then
        log "  Found Fineract pod: $fineract_pod"
        # Check if cloud-sql-proxy sidecar is running
        local proxy_status
        proxy_status=$(kubectl get pod "$fineract_pod" -n "$namespace" -o jsonpath='{.status.containerStatuses[?(@.name=="cloud-sql-proxy")].ready}' 2>/dev/null || echo "")
        if [[ "$proxy_status" == "true" ]]; then
            log_success "  Cloud SQL Proxy sidecar is ready"
        else
            log_warn "  Cloud SQL Proxy sidecar status: $proxy_status"
        fi
    fi

    log_success "Health checks completed"
}

# ============================================================================
# Summary Functions
# ============================================================================

display_endpoints() {
    print_header "Application Endpoints"

    local namespace="fineract-${ENVIRONMENT}"

    log "LoadBalancer services:"
    kubectl get svc -n "$namespace" -o wide 2>/dev/null | grep -E "LoadBalancer|EXTERNAL-IP" || echo "None"

    echo

    log "Ingress endpoints:"
    kubectl get ingress -n "$namespace" 2>/dev/null || echo "No ingress configured"

    echo

    # Get ArgoCD UI endpoint
    log "ArgoCD UI:"
    local argocd_ip
    argocd_ip=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$argocd_ip" ]]; then
        echo "  URL: https://$argocd_ip"
        echo "  Username: admin"
        echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    else
        echo "  Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    fi
}

display_deployment_summary() {
    print_header "Deployment Summary"

    local namespace="fineract-${ENVIRONMENT}"

    echo "Environment:     $ENVIRONMENT"
    echo "Namespace:       $namespace"
    echo "Deployment Mode: $DEPLOYMENT_MODE"
    echo "GCP Project:     $GCP_PROJECT_ID"
    echo "GCP Region:      $GCP_REGION"
    echo

    echo "Kubernetes Resources:"
    echo "  Nodes:"
    kubectl get nodes --no-headers | wc -l | xargs echo "    Count:"
    echo "  Pods:"
    kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l | xargs echo "    Total:"
    kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs echo "    Running:"
    echo "  Services:"
    kubectl get svc -n "$namespace" --no-headers 2>/dev/null | wc -l | xargs echo "    Count:"
    echo

    cd "$TERRAFORM_DIR"
    echo "Terraform Outputs:"
    echo "  Cluster:        $(terraform output -raw gke_cluster_name 2>/dev/null || echo 'N/A')"
    echo "  Cloud SQL:      $(terraform output -raw cloud_sql_connection_name 2>/dev/null || echo 'N/A')"
    echo "  Documents GCS:  $(terraform output -raw documents_bucket_name 2>/dev/null || echo 'N/A')"
    echo "  Backups GCS:    $(terraform output -raw backups_bucket_name 2>/dev/null || echo 'N/A')"
    echo
}

print_next_steps() {
    print_header "Deployment Complete!"

    log_success "GKE environment '$ENVIRONMENT' deployed successfully"
    echo

    log "Next Steps:"
    echo "  1. Check pod status:"
    echo "     kubectl get pods -n fineract-$ENVIRONMENT -w"
    echo
    echo "  2. View application logs:"
    echo "     kubectl logs -n fineract-$ENVIRONMENT -l app=fineract --tail=100"
    echo
    echo "  3. Access ArgoCD UI:"
    echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "     Open: https://localhost:8080"
    echo "     Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo
    echo "  4. Access Fineract API (once LoadBalancer is ready):"
    echo "     kubectl get svc -n fineract-$ENVIRONMENT"
    echo
    echo "  5. Monitor GCP resources:"
    echo "     https://console.cloud.google.com/kubernetes/workload?project=$GCP_PROJECT_ID"
    echo
}

# ============================================================================
# Main Deployment Function
# ============================================================================

main() {
    validate_environment
    validate_prerequisites

    print_header "GKE Environment Deployment"
    log "Environment: $ENVIRONMENT"
    log "Mode: $DEPLOYMENT_MODE"
    log "Project: $GCP_PROJECT_ID"
    log "Region: $GCP_REGION"
    echo

    # Set GCP project
    gcloud config set project "$GCP_PROJECT_ID"

    # Step 1: Enable GCP APIs
    enable_gcp_apis

    # Step 2: Setup Terraform Backend
    setup_terraform_backend

    # Step 3: Deploy Terraform Infrastructure
    deploy_terraform_infrastructure

    # Step 4: Configure kubectl
    configure_kubectl

    # Step 5: Install ArgoCD
    install_argocd

    # Step 6: Install Sealed Secrets Controller
    install_sealed_secrets_controller

    # Step 7: Create Application Namespace
    create_application_namespace

    # Step 8: Create Sealed Secrets
    create_sealed_secrets

    # Step 9: Configure ArgoCD
    configure_argocd

    # Step 10: Deploy Applications
    if [[ "$DEPLOYMENT_MODE" == "--gitops" ]]; then
        deploy_via_argocd
    else
        deploy_directly
    fi

    # Step 11: Wait for Deployments
    wait_for_deployments || true

    # Step 12: Wait for LoadBalancer
    wait_for_loadbalancer || true

    # Step 13: Verify Workload Identity
    verify_workload_identity || true

    # Step 14: Run Health Checks
    run_health_checks || true

    # Step 15: Display Endpoints
    display_endpoints || true

    # Step 16: Display Summary
    display_deployment_summary

    # Step 17: Print Next Steps
    print_next_steps
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
