#!/usr/bin/env bash
# Update LoadBalancer DNS configuration from cluster
#
# This script automatically extracts the LoadBalancer DNS from the cluster
# and updates the centralized configuration file.
#
# Usage:
#   ./scripts/update-loadbalancer-dns.sh <environment>
#
# Examples:
#   ./scripts/update-loadbalancer-dns.sh dev
#   ./scripts/update-loadbalancer-dns.sh uat
#   ./scripts/update-loadbalancer-dns.sh production

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 <environment>

Automatically updates LoadBalancer DNS configuration from the cluster.

Arguments:
  environment    Target environment (dev, uat, production)

Examples:
  $0 dev
  $0 uat
  $0 production

This script will:
1. Query the cluster for the Nginx Ingress LoadBalancer service
2. Extract the LoadBalancer DNS/hostname
3. Update environments/<env>/loadbalancer-config.yaml
4. Optionally commit the change to Git

EOF
    exit 1
}

# Validate arguments
if [ $# -ne 1 ]; then
    print_error "Error: Missing environment argument"
    usage
fi

ENV="$1"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    print_error "Error: Invalid environment '$ENV'"
    print_info "Valid environments: dev, uat, production"
    exit 1
fi

# Set namespace based on environment
NAMESPACE="fineract-${ENV}"

# Set kubeconfig based on environment
KUBECONFIG_FILE="${HOME}/.kube/config-fineract-${ENV}"

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_FILE" ]; then
    print_error "Kubeconfig not found: $KUBECONFIG_FILE"
    print_info "Run: ./scripts/setup-eks-kubeconfig.sh $ENV"
    exit 1
fi

print_info "Environment: $ENV"
print_info "Namespace: $NAMESPACE"
print_info "Kubeconfig: $KUBECONFIG_FILE"
echo ""

# Query LoadBalancer service
print_info "Querying Nginx Ingress LoadBalancer service..."

# Get LoadBalancer hostname/DNS
LOADBALANCER_DNS=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

# Fallback to IP if hostname is not available
if [ -z "$LOADBALANCER_DNS" ]; then
    LOADBALANCER_DNS=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
fi

# Check if we got a value
if [ -z "$LOADBALANCER_DNS" ]; then
    print_error "Failed to retrieve LoadBalancer DNS"
    print_info "Make sure the Nginx Ingress Controller is deployed and the LoadBalancer service is ready"
    exit 1
fi

print_success "LoadBalancer DNS: $LOADBALANCER_DNS"
echo ""

# Update configuration file
CONFIG_FILE="${REPO_ROOT}/environments/${ENV}/loadbalancer-config.yaml"

print_info "Updating configuration file: $CONFIG_FILE"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Create backup
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
print_info "Created backup: $BACKUP_FILE"

# Update the file using sed
# Replace LOADBALANCER_DNS, APPS_HOSTNAME, and AUTH_HOSTNAME values
sed -i.tmp "s|LOADBALANCER_DNS: \".*\"|LOADBALANCER_DNS: \"${LOADBALANCER_DNS}\"|g" "$CONFIG_FILE"
sed -i.tmp "s|APPS_HOSTNAME: \".*\"|APPS_HOSTNAME: \"${LOADBALANCER_DNS}\"|g" "$CONFIG_FILE"
sed -i.tmp "s|AUTH_HOSTNAME: \".*\"|AUTH_HOSTNAME: \"${LOADBALANCER_DNS}\"|g" "$CONFIG_FILE"
rm -f "${CONFIG_FILE}.tmp"

print_success "Updated configuration file"
echo ""

# Show diff
print_info "Changes made:"
diff -u "$BACKUP_FILE" "$CONFIG_FILE" || true
echo ""

# Check if running in CI or if user wants to commit
print_info "Configuration file has been updated."
print_warning "Next steps:"
echo "  1. Review the changes above"
echo "  2. Run: git add $CONFIG_FILE"
echo "  3. Run: git commit -m 'chore: update LoadBalancer DNS for $ENV environment'"
echo "  4. Run: git push origin <branch>"
echo ""
print_info "The configuration will be applied when ArgoCD syncs the changes from Git."

# Cleanup old backups (keep only last 5)
print_info "Cleaning up old backups (keeping last 5)..."
ls -t "${REPO_ROOT}/environments/${ENV}/loadbalancer-config.yaml.backup."* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

print_success "Done!"
