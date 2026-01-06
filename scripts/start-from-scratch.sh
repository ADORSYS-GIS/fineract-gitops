#!/usr/bin/env bash
#
# Start from Scratch Script
# Destroys ALL infrastructure and prepares for clean deployment
#
# Usage:
#   ./scripts/start-from-scratch.sh <environment>
#
# This script:
#   1. Shows what will be destroyed
#   2. Destroys all Terraform resources
#   3. Cleans up Kubernetes resources
#   4. Resets Load Balancer DNS configs
#   5. Provides redeployment steps
#
# ⚠️ WARNING: This is DESTRUCTIVE and IRREVERSIBLE!

set -e  # Exit on error (but not for pipes)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging functions
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"; }
log_info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"; }
log_step() { echo -e "${CYAN}▶${NC} $*"; }
log_warning() { echo -e "${RED}⚠${NC} $*"; }

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 <environment>

Completely destroys ALL infrastructure and prepares for clean deployment.

Arguments:
  environment    Target environment (dev, uat, production)

WARNING: This will DELETE:
  - All AWS resources (EKS, RDS, S3, VPC, etc.)
  - All Terraform state
  - All Kubernetes resources
  - ALL DATA in databases and S3 buckets (IRREVERSIBLE!)

Example:
  $0 dev

This will:
  1. Show what will be destroyed
  2. Ask for confirmation
  3. Destroy all Terraform resources
  4. Clean up Kubernetes resources
  5. Reset Load Balancer DNS configs to defaults
  6. Provide redeployment steps

EOF
    exit 1
}

# Validate arguments
if [ $# -ne 1 ]; then
    log_error "Error: Missing environment argument"
    usage
fi

ENV="$1"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    log_error "Error: Invalid environment '$ENV'"
    log_info "Valid environments: dev, uat, production"
    exit 1
fi

# Set namespace based on environment
NAMESPACE="fineract-${ENV}"

log "========================================="
log "  Start from Scratch - $ENV"
log "========================================="
log_warning "This will destroy ALL resources and data!"
echo ""

# Step 1: Check what exists
check_existing_resources() {
    log_step "Step 1/6: Checking existing resources..."

    local terraform_dir="${REPO_ROOT}/terraform/aws"
    cd "$terraform_dir"

    # Check if Terraform is initialized
    if [ -d .terraform ]; then
        log "✓ Terraform initialized"

        # Get resource count
        local resource_count=$(terraform state list 2>/dev/null | wc -l || echo "0")
        log_info "  Terraform resources: $resource_count"

        # Get some key resources (save to temp file to avoid pipe issues)
        if [ "$resource_count" -gt 0 ]; then
            log_info "  Resources found:"
            local tmpfile=$(mktemp)
            terraform state list 2>/dev/null | head -20 > "$tmpfile"
            while IFS= read -r resource; do
                log_info "    - $resource"
            done < "$tmpfile"
            rm -f "$tmpfile"
        fi
    else
        log_warn "  Terraform not initialized (no resources found)"
    fi

    # Check EKS cluster
    local cluster_name="apache-fineract-${ENV}"
    if aws eks describe-cluster --name "$cluster_name" &>/dev/null; then
        log "  ✓ EKS cluster exists: $cluster_name"
    else
        log_warn "  No EKS cluster found"
    fi

    # Check S3 buckets
    local s3_buckets=$(aws s3 ls 2>/dev/null | grep fineract || echo "")
    if [ -n "$s3_buckets" ]; then
        log "  ✓ S3 buckets found:"
        local tmpfile=$(mktemp)
        echo "$s3_buckets" > "$tmpfile"
        while IFS= read -r line; do
            log_info "    - $line"
        done < "$tmpfile"
        rm -f "$tmpfile"
    fi

    # Check RDS instances
    local rds_instances=$(aws rds describe-db-instances --query "DBInstances[?contains(DBName, 'fineract')].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
    if [ -n "$rds_instances" ]; then
        log "  ✓ RDS instances found:"
        local tmpfile=$(mktemp)
        echo "$rds_instances" > "$tmpfile"
        while IFS= read -r instance; do
            log_info "    - $instance"
        done < "$tmpfile"
        rm -f "$tmpfile"
    fi

    echo ""
}

# Step 2: Show destruction plan
show_destruction_plan() {
    log_step "Step 2/6: Showing destruction plan..."

    echo ""
    log_warning "THE FOLLOWING WILL BE DELETED:"
    echo ""
    log "AWS Resources:"
    log "  • EKS Kubernetes cluster"
    log "  • EC2 worker nodes (if any)"
    log "  • RDS PostgreSQL instances"
    log "  • S3 buckets (and ALL data)"
    log "  • VPC, subnets, security groups"
    log "  • NAT Gateway and Elastic IPs"
    log "  • IAM roles and policies"
    log "  • AWS Secrets Manager secrets"
    log "  • CloudWatch Log Groups"
    echo ""
    log_warning "Kubernetes Resources:"
    log "  • Namespace: $NAMESPACE"
    log "  • All deployments, statefulsets, services"
    log "  • All ConfigMaps, Secrets"
    log "  • All Persistent Volume Claims"
    echo ""
    log_error "DATA LOSS WARNING:"
    log_error "  • ALL database data will be DELETED"
    log_error "  • ALL S3 bucket data will be DELETED"
    log_error "  • This operation is IRREVERSIBLE"
    echo ""
}

# Step 3: Confirm destruction
confirm_destruction() {
    log_step "Step 3/6: Confirming destruction..."

    echo -e "${RED}========================================"
    echo -e "CRITICAL CONFIRMATION REQUIRED!"
    echo -e "========================================${NC}"
    echo ""
    echo -e "To proceed, type: ${YELLOW}DESTROY $ENV${NC}"
    echo -e "To cancel, press: ${YELLOW}Ctrl+C${NC}"
    echo ""

    read -p "Type 'DESTROY $ENV' to confirm: " confirmation

    if [ "$confirmation" != "DESTROY $ENV" ]; then
        log_error "Confirmation failed. Aborting."
        exit 1
    fi

    log "✓ Destruction confirmed"
    echo ""
}

# Remove stale Terraform state locks (DynamoDB)
# This fixes the "Error acquiring state lock" issue from interrupted runs
remove_stale_state_locks() {
    log_step "Removing stale Terraform state locks..."

    local lock_table="fineract-gitops-tf-lock-2026"
    local region="eu-central-1"

    # Scan for locks related to this environment
    local locks=$(aws dynamodb scan \
        --table-name "$lock_table" \
        --region "$region" \
        --output json 2>/dev/null || echo "[]")

    if [ "$locks" = "[]" ] || [ -z "$locks" ]; then
        log_info "  No locks found in DynamoDB"
        return 0
    fi

    # Filter locks for this environment and remove them
    local lock_count=$(echo "$locks" | jq '. | length')
    log_info "  Total locks found: $lock_count"

    local removed_count=0

    # Extract and remove locks matching our environment
    echo "$locks" | jq -r --arg env "fineract/dev" '.[] | select(.LockID.S | contains($env)) | .LockID.S' 2>/dev/null | while read -r lock_id; do
        if [ -n "$lock_id" ]; then
            log_info "  Removing stale lock: $lock_id"

            # Build key for DynamoDB delete
            local lock_key="{\"S\": \"$lock_id\"}"

            # Delete the lock
            if aws dynamodb delete-item \
                --table-name "$lock_table" \
                --region "$region" \
                --key "$lock_key" 2>&1; then
                log_info "    ✓ Successfully deleted"
                ((removed_count++))
            else
                log_warn "    Failed to delete (may already be gone)"
            fi
        fi
    done

    log "  ✓ Removed $removed_count stale lock(s)"
    echo ""
}

# Step 4: Destroy Terraform resources
destroy_terraform() {
    log_step "Step 4/6: Destroying Terraform resources..."

    # Remove stale state locks before destroying
    remove_stale_state_locks

    local terraform_dir="${REPO_ROOT}/terraform/aws"
    cd "$terraform_dir"

    # Check if terraform is initialized
    if [ ! -d .terraform ]; then
        log_warn "  Terraform not initialized, nothing to destroy"
        return 0
    fi

    # Run destroy-all.sh script with --auto-confirmed flag
    if [ -f "scripts/destroy-all.sh" ]; then
        log_info "  Running: ./scripts/destroy-all.sh $ENV --auto-confirmed"
        bash scripts/destroy-all.sh "$ENV" --auto-confirmed
        log "✓ Terraform resources destroyed"
    else
        log_warn "  destroy-all.sh not found, running manual destroy"
        terraform destroy -var-file=environments/${ENV}-eks.tfvars
    fi

    echo ""
}

# Step 5: Clean up Kubernetes resources
cleanup_kubernetes() {
    log_step "Step 5/6: Cleaning up Kubernetes resources..."

    local kubeconfig_file="${HOME}/.kube/config-fineract-${ENV}"

    # Check if kubeconfig exists
    if [ ! -f "$kubeconfig_file" ]; then
        log_warn "  Kubeconfig not found, skipping Kubernetes cleanup"
        return 0
    fi

    export KUBECONFIG="$kubeconfig_file"

    # Check if cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        log_warn "  Cluster not accessible, skipping Kubernetes cleanup"
        return 0
    fi

    # Delete namespace if it exists
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "  Deleting namespace: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --timeout=300s

        # Wait for namespace deletion
        local max_wait=60
        local elapsed=0
        while [ $elapsed -lt $max_wait ]; do
            if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
                log "  ✓ Namespace deleted"
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done

        if [ $elapsed -ge $max_wait ]; then
            log_warn "  Namespace still exists after $max_wait seconds"
        fi
    else
        log_info "  Namespace does not exist: $NAMESPACE"
    fi

    # Remove kubeconfig file
    if [ -f "$kubeconfig_file" ]; then
        log_info "  Removing kubeconfig: $kubeconfig_file"
        rm -f "$kubeconfig_file"
    fi

    echo ""
}

# Step 6: Reset Load Balancer DNS configs
reset_lb_dns_configs() {
    log_step "Step 6/6: Resetting Load Balancer DNS configs..."

    # Reset central ConfigMap
    local central_config="${REPO_ROOT}/config/loadbalancer-dns-configmap.yaml"
    if [ -f "$central_config" ]; then
        cp "$central_config" "${central_config}.backup.$(date +%Y%m%d_%H%M%S)"
        sed -i '' 's|lb-dns: ".*"|lb-dns: "PENDING_UPDATE"|g' "$central_config"
        rm -f "${central_config}.tmp"
        log "  ✓ Reset: config/loadbalancer-dns-configmap.yaml"
    fi

    # Reset environment configs
    local env_configs=(
        "${REPO_ROOT}/environments/${ENV}/loadbalancer-config.yaml"
        "${REPO_ROOT}/environments/${ENV}/fineract-oauth2-config-patch.yaml"
        "${REPO_ROOT}/apps/ingress/overlays/${ENV}/kustomization.yaml"
        "${REPO_ROOT}/apps/oauth2-proxy/overlays/${ENV}/kustomization.yaml"
        "${REPO_ROOT}/apps/keycloak/overlays/${ENV}/kustomization.yaml"
    )

    for config_file in "${env_configs[@]}"; do
        if [ -f "$config_file" ]; then
            # Check if it has actual LB DNS (not PENDING_UPDATE)
            if grep -q -E "elb\.amazonaws\.com|fineract\.com" "$config_file"; then
                cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"

                # Replace actual LB DNS with PENDING_UPDATE
                sed -i '' 's|a[0-9]\+\.elb\.amazonaws\.com|PENDING_UPDATE|g' "$config_file"
                sed -i '' 's|apps\.fineract\.com|PENDING_UPDATE|g' "$config_file"
                sed -i '' 's|auth\.fineract\.com|PENDING_UPDATE|g' "$config_file"

                log "  ✓ Reset: $(basename "$config_file")"
            fi
        fi
    done

    echo ""
}

# Print summary
print_summary() {
    log "========================================="
    log "  Cleanup Complete!"
    log "========================================="
    echo ""
    log_info "Environment: $ENV"
    log_info "Status: Ready for fresh deployment"
    echo ""
    log "Next steps to redeploy:"
    echo ""
    log "  1. Deploy Infrastructure:"
    echo "     cd terraform/aws"
    echo "     terraform init"
    echo "     terraform apply -var-file=environments/${ENV}-eks.tfvars"
    echo ""
    log "  2. Run Post-Terraform Setup:"
    echo "     ./scripts/post-terraform-setup.sh $ENV"
    echo ""
    log "  3. Deploy Applications (Option A - One Command):"
    echo "     ./scripts/wait-for-lb-and-sync.sh $ENV"
    echo ""
    log "  4. Or Deploy Applications (Option B - Manual):"
    echo "     kubectl apply -k environments/${ENV}"
    echo ""
    log "  5. Monitor Deployment:"
    echo "     kubectl get pods -n $NAMESPACE"
    echo "     kubectl get applications -n argocd"
    echo ""
    log "  6. Access Applications:"
    echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""
    log_warning "Important Notes:"
    log_warning "  • Load Balancer DNS will be set automatically on deployment"
    log_warning "  • Use scripts/wait-for-lb-and-sync.sh for fully automated deployment"
    log_warning "  • See docs/AUTOMATED_LB_DNS_MANAGEMENT.md for details"
    echo ""
    log "Cost Savings:"
    local savings=0
    case "$ENV" in
        dev) savings=110 ;;
        uat) savings=300 ;;
        production) savings=700 ;;
    esac
    log_info "  • You've stopped ~\$$savings/month in AWS costs"
    log_info "  • Total savings over 1 year: ~\$$((savings * 12))"
    echo ""
    log "✓ Ready to start from scratch!"
    echo ""
}

# Main execution
main() {
    # Execute steps
    check_existing_resources
    show_destruction_plan
    confirm_destruction
    destroy_terraform
    cleanup_kubernetes
    reset_lb_dns_configs

    # Print summary
    print_summary

    exit 0
}

# Run main
main "$@"
