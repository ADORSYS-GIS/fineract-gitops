#!/bin/bash
# Post-Terraform Setup Script
# This script handles tasks that Terraform's Kubernetes provider fails to do
# due to IP caching issues when K3s instances are replaced.

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

# Step 1: Get K3s server IP from Terraform
get_k3s_server_ip() {
    log "Getting K3s server IP from Terraform..."
    cd "$REPO_ROOT/terraform/aws"

    K3S_SERVER_IP=$(terraform output -json k3s_server_public_ips | jq -r '.[0]')

    if [ -z "$K3S_SERVER_IP" ] || [ "$K3S_SERVER_IP" = "null" ]; then
        error_exit "Failed to get K3s server IP from Terraform"
    fi

    log "K3s server IP: $K3S_SERVER_IP"
    echo "$K3S_SERVER_IP"
}

# Step 2: Wait for K3s to be ready
wait_for_k3s() {
    local server_ip="$1"
    log "Waiting for K3s API server to be ready..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sk "https://${server_ip}:6443/healthz" --connect-timeout 5 | grep -q "ok"; then
            log "K3s API server is ready!"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for K3s... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    error_exit "K3s API server did not become ready in time"
}

# Step 3: Get kubeconfig directly from K3s server
get_kubeconfig() {
    local server_ip="$1"
    log "Getting kubeconfig directly from K3s server..."

    local kubeconfig_path="$HOME/.kube/config-fineract-${ENV}-${ENV}"

    # Ensure .kube directory exists
    mkdir -p "$HOME/.kube"

    # Get kubeconfig via SSH and replace 127.0.0.1 with actual IP
    if ssh -i ~/.ssh/fineract-k3s -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        ubuntu@"${server_ip}" "sudo cat /etc/rancher/k3s/k3s.yaml" | \
        sed "s/127.0.0.1/${server_ip}/g" > "$kubeconfig_path"; then

        log "Kubeconfig saved to: $kubeconfig_path"

        # Verify it works
        if KUBECONFIG="$kubeconfig_path" kubectl cluster-info &> /dev/null; then
            log "Kubeconfig is working correctly!"
            return 0
        else
            error_exit "Kubeconfig verification failed"
        fi
    else
        error_exit "Failed to get kubeconfig from K3s server"
    fi
}

# Step 4: Create Kubernetes namespace
create_namespace() {
    log "Creating Kubernetes namespace..."

    local kubeconfig_path="$HOME/.kube/config-fineract-${ENV}-${ENV}"

    KUBECONFIG="$kubeconfig_path" kubectl create namespace "fineract-${ENV}" \
        --dry-run=client -o yaml | \
        KUBECONFIG="$kubeconfig_path" kubectl apply -f -

    log "Namespace fineract-${ENV} created/verified"
}

# Step 5: Create secrets from Terraform outputs
create_secrets() {
    log "Creating Kubernetes secrets from Terraform outputs..."

    cd "$REPO_ROOT/terraform/aws"
    local kubeconfig_path="$HOME/.kube/config-fineract-${ENV}-${ENV}"
    local namespace="fineract-${ENV}"

    # Get RDS credentials
    log_info "Getting RDS credentials..."
    RDS_ENDPOINT=$(terraform output -raw rds_instance_endpoint)
    RDS_HOST=$(echo "$RDS_ENDPOINT" | cut -d: -f1)
    RDS_PORT=$(echo "$RDS_ENDPOINT" | cut -d: -f2)
    RDS_DATABASE=$(terraform output -raw rds_database_name)
    RDS_USERNAME="fineract"
    RDS_PASSWORD=$(terraform state pull | jq -r '.resources[] | select(.module == "module.rds" and .type == "random_password" and .name == "master") | .instances[0].attributes.result')

    log_info "Creating rds-connection secret..."
    KUBECONFIG="$kubeconfig_path" kubectl create secret generic rds-connection \
        -n "$namespace" \
        --from-literal=jdbc-url="jdbc:postgresql://${RDS_ENDPOINT}/${RDS_DATABASE}" \
        --from-literal=host="$RDS_HOST" \
        --from-literal=port="$RDS_PORT" \
        --from-literal=database="$RDS_DATABASE" \
        --from-literal=username="$RDS_USERNAME" \
        --from-literal=password="$RDS_PASSWORD" \
        --dry-run=client -o yaml | KUBECONFIG="$kubeconfig_path" kubectl apply -f -

    log_info "Creating fineract-db-credentials secret..."
    KUBECONFIG="$kubeconfig_path" kubectl create secret generic fineract-db-credentials \
        -n "$namespace" \
        --from-literal=jdbc-url="jdbc:postgresql://${RDS_ENDPOINT}/${RDS_DATABASE}" \
        --from-literal=host="$RDS_HOST" \
        --from-literal=port="$RDS_PORT" \
        --from-literal=database="$RDS_DATABASE" \
        --from-literal=username="$RDS_USERNAME" \
        --from-literal=password="$RDS_PASSWORD" \
        --dry-run=client -o yaml | KUBECONFIG="$kubeconfig_path" kubectl apply -f -

    # Note: Using in-cluster fineract-redis instead of AWS ElastiCache
    # Redis connection configured via fineract-redis-credentials secret (deployed via ArgoCD)

    # Get S3 bucket names
    log_info "Getting S3 bucket names..."
    DOCUMENTS_BUCKET=$(terraform output -raw documents_bucket_name)
    BACKUPS_BUCKET=$(terraform output -raw backups_bucket_name)
    AWS_REGION="us-east-2"

    log_info "Creating s3-connection secret..."
    KUBECONFIG="$kubeconfig_path" kubectl create secret generic s3-connection \
        -n "$namespace" \
        --from-literal=documents-bucket="$DOCUMENTS_BUCKET" \
        --from-literal=backups-bucket="$BACKUPS_BUCKET" \
        --from-literal=region="$AWS_REGION" \
        --from-literal=acceleration-enabled="false" \
        --dry-run=client -o yaml | KUBECONFIG="$kubeconfig_path" kubectl apply -f -

    log "All secrets created successfully!"
}

# Step 6: Update hostnames in kustomization files
update_hostnames() {
    log "Updating hostnames in kustomization files..."

    local kubeconfig_path="$HOME/.kube/config-fineract-${ENV}-${ENV}"
    local namespace="ingress-nginx"
    local service_name="ingress-nginx-controller"
    local max_attempts=30
    local attempt=0
    local load_balancer_hostname=""

    log_info "Waiting for LoadBalancer hostname..."
    while [ $attempt -lt $max_attempts ]; do
        load_balancer_hostname=$(KUBECONFIG="$kubeconfig_path" kubectl get svc -n "$namespace" "$service_name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ -n "$load_balancer_hostname" ]; then
            log "LoadBalancer hostname found: $load_balancer_hostname"
            break
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for LoadBalancer hostname... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    if [ -z "$load_balancer_hostname" ]; then
        error_exit "Failed to get LoadBalancer hostname"
    fi

    log_info "Updating apps/ingress/overlays/dev/kustomization.yaml..."
    sed -i.bak "s/apps-hostname=.*/apps-hostname=${load_balancer_hostname}/" "$REPO_ROOT/apps/ingress/overlays/dev/kustomization.yaml"
    sed -i.bak "s/auth-hostname=.*/auth-hostname=${load_balancer_hostname}/" "$REPO_ROOT/apps/ingress/overlays/dev/kustomization.yaml"

    log_info "Updating apps/keycloak/overlays/dev/kustomization.yaml..."
    sed -i.bak "s/auth-hostname=.*/auth-hostname=${load_balancer_hostname}/" "$REPO_ROOT/apps/keycloak/overlays/dev/kustomization.yaml"
    # Also update the KC_HOSTNAME value in the patch (match any AWS ELB hostname pattern)
    sed -i.bak "s/value: .*\.elb\..*\.amazonaws\.com/value: ${load_balancer_hostname}/" "$REPO_ROOT/apps/keycloak/overlays/dev/kustomization.yaml"

    log_info "Updating operations/keycloak-config/overlays/dev/kustomization.yaml..."
    sed -i.bak "s/apps-hostname=.*/apps-hostname=${load_balancer_hostname}/" "$REPO_ROOT/operations/keycloak-config/overlays/dev/kustomization.yaml"
    sed -i.bak "s/auth-hostname=.*/auth-hostname=${load_balancer_hostname}/" "$REPO_ROOT/operations/keycloak-config/overlays/dev/kustomization.yaml"

    log "Hostnames updated successfully!"
}

# Main execution
main() {
    log "=========================================="
    log "  Post-Terraform Setup Script"
    log "=========================================="
    log "Environment: $ENV"
    echo ""

    # Execute setup steps
    K3S_IP=$(get_k3s_server_ip)
    wait_for_k3s "$K3S_IP"
    get_kubeconfig "$K3S_IP"
    create_namespace
    create_secrets
    update_hostnames

    log ""
    log "=========================================="
    log "  Setup Complete!"
    log "=========================================="
    log "Kubeconfig: $HOME/.kube/config-fineract-${ENV}-${ENV}"
    log "Namespace: fineract-${ENV}"
    log ""
    log "Next step: Deploy applications"
    log "  kubectl apply -k environments/${ENV}"
    echo ""
}

# Run main
main "$@"
