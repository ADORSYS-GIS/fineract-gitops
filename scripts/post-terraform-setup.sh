#!/bin/bash
# Post-Terraform Setup Script for EKS
# This script configures kubeconfig and creates initial Kubernetes resources
# after Terraform has provisioned the EKS cluster.

set -e  # Exit on error
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Environment (default: dev)
ENV="${1:-dev}"

# Kubeconfig path
KUBECONFIG_PATH="$HOME/.kube/config-fineract-${ENV}"

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

# Step 1: Configure kubectl for EKS
get_eks_kubeconfig() {
    log "Configuring kubectl for EKS cluster..."
    cd "$REPO_ROOT/terraform/aws"

    # Get cluster name and region from Terraform outputs
    local cluster_name=$(terraform output -raw eks_cluster_name)
    local region=$(terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")

    if [ -z "$cluster_name" ]; then
        error_exit "Failed to get EKS cluster name from Terraform"
    fi

    log_info "EKS cluster: $cluster_name"
    log_info "AWS region: $region"

    # Ensure .kube directory exists
    mkdir -p "$HOME/.kube"

    # Configure kubeconfig for EKS
    aws eks update-kubeconfig \
        --name "$cluster_name" \
        --region "$region" \
        --kubeconfig "$KUBECONFIG_PATH"

    log "Kubeconfig saved to: $KUBECONFIG_PATH"
}

# Step 2: Wait for EKS cluster to be ready
wait_for_eks() {
    log "Waiting for EKS cluster to be ready..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if KUBECONFIG="$KUBECONFIG_PATH" kubectl cluster-info &>/dev/null; then
            log "EKS cluster is ready!"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for EKS... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    error_exit "EKS cluster did not become ready in time"
}

# Step 3: Create Kubernetes namespace
create_namespace() {
    log "Creating Kubernetes namespace..."

    KUBECONFIG="$KUBECONFIG_PATH" kubectl create namespace "fineract-${ENV}" \
        --dry-run=client -o yaml | \
        KUBECONFIG="$KUBECONFIG_PATH" kubectl apply -f -

    log "Namespace fineract-${ENV} created/verified"
}

# Step 4: Create secrets from Terraform outputs
create_secrets() {
    log "Creating Kubernetes secrets from Terraform outputs..."

    cd "$REPO_ROOT/terraform/aws"
    local namespace="fineract-${ENV}"

    # Get AWS region
    local region=$(terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")

    # Get RDS credentials
    log_info "Getting RDS credentials..."
    RDS_ENDPOINT=$(terraform output -raw rds_instance_endpoint)
    RDS_HOST=$(echo "$RDS_ENDPOINT" | cut -d: -f1)
    RDS_PORT=$(echo "$RDS_ENDPOINT" | cut -d: -f2)
    RDS_DATABASE=$(terraform output -raw rds_database_name)
    RDS_USERNAME="fineract"
    RDS_PASSWORD=$(terraform state pull | jq -r '.resources[] | select(.module == "module.rds" and .type == "random_password" and .name == "master") | .instances[0].attributes.result')

    log_info "Creating rds-connection secret..."
    KUBECONFIG="$KUBECONFIG_PATH" kubectl create secret generic rds-connection \
        -n "$namespace" \
        --from-literal=jdbc-url="jdbc:postgresql://${RDS_ENDPOINT}/${RDS_DATABASE}" \
        --from-literal=host="$RDS_HOST" \
        --from-literal=port="$RDS_PORT" \
        --from-literal=database="$RDS_DATABASE" \
        --from-literal=username="$RDS_USERNAME" \
        --from-literal=password="$RDS_PASSWORD" \
        --dry-run=client -o yaml | KUBECONFIG="$KUBECONFIG_PATH" kubectl apply -f -

    log_info "Creating fineract-db-credentials secret..."
    KUBECONFIG="$KUBECONFIG_PATH" kubectl create secret generic fineract-db-credentials \
        -n "$namespace" \
        --from-literal=jdbc-url="jdbc:postgresql://${RDS_ENDPOINT}/${RDS_DATABASE}" \
        --from-literal=host="$RDS_HOST" \
        --from-literal=port="$RDS_PORT" \
        --from-literal=database="$RDS_DATABASE" \
        --from-literal=username="$RDS_USERNAME" \
        --from-literal=password="$RDS_PASSWORD" \
        --dry-run=client -o yaml | KUBECONFIG="$KUBECONFIG_PATH" kubectl apply -f -

    # Note: Using in-cluster fineract-redis instead of AWS ElastiCache
    # Redis connection configured via fineract-redis-credentials secret (deployed via ArgoCD)

    # Get S3 bucket names
    log_info "Getting S3 bucket names..."
    DOCUMENTS_BUCKET=$(terraform output -raw documents_bucket_name)
    BACKUPS_BUCKET=$(terraform output -raw backups_bucket_name)

    log_info "Creating s3-connection secret..."
    KUBECONFIG="$KUBECONFIG_PATH" kubectl create secret generic s3-connection \
        -n "$namespace" \
        --from-literal=documents-bucket="$DOCUMENTS_BUCKET" \
        --from-literal=backups-bucket="$BACKUPS_BUCKET" \
        --from-literal=region="$region" \
        --from-literal=acceleration-enabled="false" \
        --dry-run=client -o yaml | KUBECONFIG="$KUBECONFIG_PATH" kubectl apply -f -

    log "All secrets created successfully!"
}

# Step 5: Update Load Balancer DNS (CENTRALIZED APPROACH)
update_hostnames() {
    log "Updating Load Balancer DNS (using centralized approach)..."

    # Use the centralized auto-update script
    log_info "Using centralized Load Balancer DNS management..."
    log_info "This will update ALL configuration files consistently"

    export KUBECONFIG="$KUBECONFIG_PATH"
    if ! "$SCRIPT_DIR/auto-update-lb-dns.sh" "$ENV"; then
        error_exit "Failed to update Load Balancer DNS using centralized script"
    fi

    log "Load Balancer DNS updated successfully in all files!"
}

# Main execution
main() {
    log "=========================================="
    log "  Post-Terraform Setup Script (EKS)"
    log "=========================================="
    log "Environment: $ENV"
    echo ""

    # Execute setup steps
    get_eks_kubeconfig
    wait_for_eks
    create_namespace
    create_secrets
    update_hostnames

    log ""
    log "=========================================="
    log "  Setup Complete!"
    log "=========================================="
    log "Kubeconfig: $KUBECONFIG_PATH"
    log "Namespace: fineract-${ENV}"
    log ""
    log "Next step: Deploy applications"
    log "  KUBECONFIG=$KUBECONFIG_PATH ./scripts/deploy-k8s-with-loadbalancer-dns.sh $ENV"
    echo ""
}

# Run main
main "$@"
