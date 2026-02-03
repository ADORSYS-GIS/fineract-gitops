#!/bin/bash
#
# Update ELB Hostname Script
# Updates all configuration files with the new ELB hostname after nginx-ingress deployment
#
# Usage: ./scripts/update-elb-hostname.sh [environment] [--auto-detect|--hostname <hostname>]
# Example:
#   ./scripts/update-elb-hostname.sh dev --auto-detect
#   ./scripts/update-elb-hostname.sh dev --hostname a325026c475e7412aaa5e3ed3d943f6c-40cd00c83906f85e.elb.eu-central-1.amazonaws.com
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment argument required${NC}"
    echo "Usage: $0 [dev|uat|production] [--auto-detect|--hostname <hostname>]"
    exit 1
fi

ENV=$1
NAMESPACE="fineract-${ENV}"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be dev, uat, or production${NC}"
    exit 1
fi

shift  # Remove first argument

# Parse remaining arguments
AUTO_DETECT=false
NEW_HOSTNAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-detect)
            AUTO_DETECT=true
            shift
            ;;
        --hostname)
            NEW_HOSTNAME="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Update ELB Hostname for: ${ENV}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Auto-detect ELB hostname from kubernetes
if [ "$AUTO_DETECT" = true ]; then
    echo -e "${YELLOW}Auto-detecting ELB hostname from ingress-nginx service...${NC}"

    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl not found${NC}"
        exit 1
    fi

    # Wait for LoadBalancer to be provisioned (max 5 minutes)
    echo "Waiting for LoadBalancer to be ready..."
    for i in {1..60}; do
        NEW_HOSTNAME=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

        if [ -n "$NEW_HOSTNAME" ] && [ "$NEW_HOSTNAME" != "null" ]; then
            break
        fi

        echo "  Attempt $i/60: Waiting for LoadBalancer hostname..."
        sleep 5
    done

    if [ -z "$NEW_HOSTNAME" ] || [ "$NEW_HOSTNAME" = "null" ]; then
        echo -e "${RED}Error: Could not detect LoadBalancer hostname${NC}"
        echo "Make sure ingress-nginx is deployed and LoadBalancer is provisioned."
        exit 1
    fi
fi

if [ -z "$NEW_HOSTNAME" ]; then
    echo -e "${RED}Error: No hostname specified. Use --auto-detect or --hostname <hostname>${NC}"
    exit 1
fi

echo -e "${GREEN}New ELB Hostname: ${NEW_HOSTNAME}${NC}"
echo

# Files to update
declare -a FILES_TO_UPDATE=(
    "apps/ingress/overlays/${ENV}/ingress-config.yaml"
    "apps/keycloak/overlays/${ENV}/kustomization.yaml"
    "config/loadbalancer-dns-configmap.yaml"
    "environments/${ENV}/fineract-oauth2-config-patch.yaml"
    "environments/${ENV}/loadbalancer-config.yaml"
    "operations/fineract-config/overlays/${ENV}/kustomization.yaml"
    "operations/keycloak-config/overlays/${ENV}/kustomization.yaml"
)

# Find current hostname pattern (looks for AWS ELB hostname pattern)
echo -e "${YELLOW}Searching for existing ELB hostname in configuration files...${NC}"
CURRENT_HOSTNAME=$(grep -rho '[a-z0-9-]\{1,\}\.elb\.[a-z0-9-]\{1,\}\.amazonaws\.com' \
    "$ROOT_DIR/apps/ingress/overlays/${ENV}/" 2>/dev/null | head -1 || echo "")

if [ -n "$CURRENT_HOSTNAME" ]; then
    echo -e "${BLUE}Current hostname: ${CURRENT_HOSTNAME}${NC}"
else
    echo -e "${YELLOW}No existing ELB hostname found. Will use placeholder pattern.${NC}"
    CURRENT_HOSTNAME="PLACEHOLDER_ELB_HOSTNAME"
fi

if [ "$CURRENT_HOSTNAME" = "$NEW_HOSTNAME" ]; then
    echo -e "${GREEN}Hostname is already up to date. No changes needed.${NC}"
    exit 0
fi

echo
echo -e "${YELLOW}Updating configuration files...${NC}"
echo

UPDATED_COUNT=0

for file in "${FILES_TO_UPDATE[@]}"; do
    FULL_PATH="$ROOT_DIR/$file"
    if [ -f "$FULL_PATH" ]; then
        if grep -q "$CURRENT_HOSTNAME" "$FULL_PATH" 2>/dev/null || grep -q "PLACEHOLDER_ELB_HOSTNAME" "$FULL_PATH" 2>/dev/null; then
            sed -i '' "s|$CURRENT_HOSTNAME|$NEW_HOSTNAME|g" "$FULL_PATH"
            sed -i '' "s|PLACEHOLDER_ELB_HOSTNAME|$NEW_HOSTNAME|g" "$FULL_PATH"
            echo -e "${GREEN}  ✓ Updated: $file${NC}"
            ((UPDATED_COUNT++))
        else
            echo -e "${BLUE}  - Skipped (no hostname found): $file${NC}"
        fi
    else
        echo -e "${YELLOW}  - File not found: $file${NC}"
    fi
done

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Update Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "Updated ${UPDATED_COUNT} files with hostname: ${NEW_HOSTNAME}"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the changes:"
echo "   git diff"
echo
echo "2. Commit and push:"
echo "   git add ."
echo "   git commit -m 'fix(${ENV}): update ELB hostname to ${NEW_HOSTNAME}'"
echo "   git push"
echo
echo "3. ArgoCD will sync the changes automatically, or force sync:"
echo "   argocd app sync fineract-${ENV}-app-of-apps --force"
echo
echo "4. Verify the changes in Kubernetes:"
echo "   kubectl get ingress -n ${NAMESPACE}"
echo

# Also update Keycloak redirect URIs if cluster is accessible
if command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Updating Keycloak redirect URIs...${NC}"

    # Check if Keycloak is accessible
    KEYCLOAK_POD=$(kubectl get pods -n "$NAMESPACE" -l app=keycloak -o name 2>/dev/null | head -1)
    if [ -n "$KEYCLOAK_POD" ]; then
        echo "  Keycloak pod found. Consider running the Keycloak config job to update redirect URIs."
    fi
fi

echo -e "${GREEN}Done!${NC}"
