#!/bin/bash
# Setup EKS Kubeconfig
# This script retrieves the EKS cluster endpoint from Terraform and configures kubectl

# Temporarily disable exit on error for better debugging
set +e
set -o pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Environment (default: dev)
ENV="${1:-dev}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform/aws"

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

# Step 1: Get EKS cluster name and region from Terraform
get_eks_cluster_info() {
    # Log to stderr to avoid contaminating the return value
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} Getting EKS cluster information from Terraform..." >&2
    cd "$TERRAFORM_DIR"

    # Get cluster name
    local cluster_name
    cluster_name=$(terraform output -raw eks_cluster_name 2>/dev/null)
    if [ -z "$cluster_name" ] || [ "$cluster_name" = "null" ]; then
        echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} Failed to get EKS cluster name from Terraform." >&2
        return 1
    fi

    # Get AWS region - try multiple methods
    local aws_region=""

    # Method 1: Try terraform output (if it exists)
    aws_region=$(terraform output -raw aws_region 2>/dev/null || true)

    # Method 2: Extract from tfvars file
    if [ -z "$aws_region" ] || [ "$aws_region" = "null" ]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} aws_region output not found, checking tfvars file..." >&2
        aws_region=$(grep -oP 'aws_region\s*=\s*"\K[^"]+' "environments/${ENV}-eks.tfvars" 2>/dev/null || true)
    fi

    # Method 3: Get from AWS CLI config
    if [ -z "$aws_region" ]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} Checking AWS CLI config..." >&2
        aws_region=$(aws configure get region 2>/dev/null || true)
    fi

    # Method 4: Default to us-east-2
    if [ -z "$aws_region" ]; then
        echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} Could not determine AWS region, using default: us-east-2" >&2
        aws_region="us-east-2"
    fi

    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} EKS Cluster Name: $cluster_name" >&2
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} AWS Region: $aws_region" >&2

    # Return ONLY the data, no color codes
    echo "$cluster_name:$aws_region"
}

# Step 2: Update kubeconfig using AWS CLI
update_kubeconfig() {
    local cluster_name="$1"
    local region="$2"

    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} Updating kubeconfig for EKS cluster..." >&2
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} Cluster: $cluster_name" >&2
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} Region: $region" >&2

    # Define kubeconfig path
    local kubeconfig_path="$HOME/.kube/config-fineract-$ENV"

    # Ensure .kube directory exists
    mkdir -p "$HOME/.kube"

    # Run aws eks update-kubeconfig with detailed output
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} Running: aws eks update-kubeconfig --name $cluster_name --region $region" >&2

    local aws_output
    if aws_output=$(aws eks update-kubeconfig \
        --name "$cluster_name" \
        --region "$region" \
        --kubeconfig "$kubeconfig_path" 2>&1); then

        echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} Kubeconfig updated successfully: $kubeconfig_path" >&2
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $aws_output" >&2
        # Return ONLY the path, no color codes
        echo "$kubeconfig_path"
    else
        echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} AWS CLI command failed with output:" >&2
        echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $aws_output" >&2
        return 1
    fi
}

# Step 3: Wait for EKS API server to be ready
wait_for_eks_api() {
    local kubeconfig_path="$1"
    log "Waiting for EKS API server to be ready..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if KUBECONFIG="$kubeconfig_path" kubectl cluster-info &> /dev/null; then
            log "EKS API server is ready!"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for EKS API... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    error_exit "EKS API server did not become ready in time"
}

# Step 4: Verify kubectl connectivity
verify_kubectl() {
    local kubeconfig_path="$1"
    log "Verifying kubectl connectivity..."

    # Test cluster-info
    log_info "Testing kubectl cluster-info..."
    local cluster_output
    if cluster_output=$(KUBECONFIG="$kubeconfig_path" kubectl cluster-info 2>&1); then
        log "✓ Cluster info retrieved successfully"
        echo "$cluster_output" | head -3
    else
        log_error "kubectl cluster-info failed:"
        log_error "$cluster_output"
        error_exit "Cannot connect to Kubernetes cluster"
    fi

    echo ""

    # Test get nodes
    log "Checking cluster nodes..."
    local nodes_output
    if nodes_output=$(KUBECONFIG="$kubeconfig_path" kubectl get nodes 2>&1); then
        log "✓ Nodes retrieved successfully:"
        echo "$nodes_output"
    else
        log_error "kubectl get nodes failed:"
        log_error "$nodes_output"
        error_exit "Cannot retrieve cluster nodes"
    fi

    echo ""
    log "kubectl connectivity verified successfully!"
}

# Main execution
main() {
    log "=========================================="
    log " EKS Kubeconfig Setup - $ENV Environment"
    log "=========================================="
    echo ""

    # Get cluster info
    log_info "Step 1: Retrieving cluster information from Terraform..."
    CLUSTER_INFO=$(get_eks_cluster_info)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to get cluster info (exit code: $exit_code)"
        return 1
    fi

    CLUSTER_NAME=$(echo "$CLUSTER_INFO" | cut -d':' -f1)
    AWS_REGION=$(echo "$CLUSTER_INFO" | cut -d':' -f2)

    if [ -z "$CLUSTER_NAME" ] || [ -z "$AWS_REGION" ]; then
        log_error "Cluster name or region is empty"
        log_error "CLUSTER_INFO=$CLUSTER_INFO"
        log_error "CLUSTER_NAME=$CLUSTER_NAME"
        log_error "AWS_REGION=$AWS_REGION"
        return 1
    fi

    # Update kubeconfig
    log_info "Step 2: Updating kubeconfig..."
    KUBECONFIG_PATH=$(update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION")
    exit_code=$?

    if [ $exit_code -ne 0 ] || [ -z "$KUBECONFIG_PATH" ]; then
        log_error "Failed to update kubeconfig (exit code: $exit_code)"
        return 1
    fi

    # Wait for API server
    log_info "Step 3: Waiting for API server..."
    wait_for_eks_api "$KUBECONFIG_PATH"
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to connect to API server (exit code: $exit_code)"
        return 1
    fi

    # Verify connectivity
    log_info "Step 4: Verifying kubectl connectivity..."
    verify_kubectl "$KUBECONFIG_PATH"
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to verify kubectl (exit code: $exit_code)"
        return 1
    fi

    echo ""
    log "=========================================="
    log " ✓ EKS Kubeconfig Setup Complete!"
    log "=========================================="
    echo ""
    log "Kubeconfig saved to: $KUBECONFIG_PATH"
    echo ""
    log_info "Set KUBECONFIG in your shell:"
    echo "  export KUBECONFIG=$KUBECONFIG_PATH"
    echo ""
    log_info "Or for this deployment, it has been set automatically."

    # Export for current script and child processes
    export KUBECONFIG="$KUBECONFIG_PATH"

    # Save to .env file for other scripts
    echo "export KUBECONFIG=$KUBECONFIG_PATH" > "$REPO_ROOT/.kubeconfig-$ENV"

    return 0
}

# Run main function
main
exit $?
