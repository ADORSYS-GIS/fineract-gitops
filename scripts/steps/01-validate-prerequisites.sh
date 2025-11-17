#!/bin/bash
# Step 1: Validate Prerequisites

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Validating prerequisites..."
echo ""

FAILED=0

# Check kubectl
if command -v kubectl &> /dev/null; then
    VERSION=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4 || echo "unknown")
    echo -e "${GREEN}✓${NC} kubectl installed ($VERSION)"
else
    echo -e "${RED}✗${NC} kubectl not found"
    FAILED=1
fi

# Check kustomize
if command -v kustomize &> /dev/null; then
    VERSION=$(kustomize version 2>/dev/null | head -1 || echo "unknown")
    echo -e "${GREEN}✓${NC} kustomize installed ($VERSION)"
else
    echo -e "${RED}✗${NC} kustomize not found"
    FAILED=1
fi

# Check kubeseal
if command -v kubeseal &> /dev/null; then
    VERSION=$(kubeseal --version 2>&1 | grep -o 'v[0-9.]*' | head -1 || echo "unknown")
    echo -e "${GREEN}✓${NC} kubeseal installed ($VERSION)"
else
    echo -e "${RED}✗${NC} kubeseal not found"
    FAILED=1
fi

# Check AWS CLI
if command -v aws &> /dev/null; then
    echo -e "${GREEN}✓${NC} AWS CLI installed"
else
    echo -e "${RED}✗${NC} AWS CLI not found"
    FAILED=1
fi

# Check KUBECONFIG
if [ -z "$KUBECONFIG" ]; then
    echo -e "${RED}✗${NC} KUBECONFIG environment variable not set"
    FAILED=1
else
    echo -e "${GREEN}✓${NC} KUBECONFIG set: $KUBECONFIG"
fi

# Check cluster connectivity (non-blocking for fresh deployments)
if kubectl cluster-info &> /dev/null; then
    CLUSTER=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓${NC} Cluster connectivity OK ($CLUSTER)"
else
    echo -e "${YELLOW}⚠${NC} Cannot connect to cluster (will be created during deployment)"
fi

# Check SSH deploy key for ArgoCD
SSH_DEPLOY_KEY="${HOME}/.ssh/argocd-deploy-key"
if [ ! -f "$SSH_DEPLOY_KEY" ]; then
    echo -e "${RED}✗${NC} SSH deploy key not found at $SSH_DEPLOY_KEY"
    echo "   Generate with: ssh-keygen -t ed25519 -C \"argocd-fineract-gitops\" -f $SSH_DEPLOY_KEY -N \"\""
    echo "   Then add ${SSH_DEPLOY_KEY}.pub to GitHub repository deploy keys"
    FAILED=1
else
    echo -e "${GREEN}✓${NC} SSH deploy key found at $SSH_DEPLOY_KEY"
fi

# Check Terraform outputs (non-blocking for fresh deployments)
if [ -d "terraform/aws" ] && [ -f "terraform/aws/.terraform/terraform.tfstate" ]; then
    echo -e "${GREEN}✓${NC} Terraform state found"
else
    echo -e "${YELLOW}⚠${NC} Terraform not initialized (will be initialized during deployment)"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All prerequisites met!${NC}"
    exit 0
else
    echo -e "${RED}Some prerequisites are missing. Please fix the above issues.${NC}"
    exit 1
fi
