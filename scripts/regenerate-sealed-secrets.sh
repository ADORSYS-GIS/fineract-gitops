#!/bin/bash
# Regenerate all sealed secrets with current Sealed Secrets controller key
# Run this after reinstalling Sealed Secrets controller

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Regenerate Sealed Secrets${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if [ -z "$KUBECONFIG" ]; then
    echo -e "${RED}✗ KUBECONFIG not set${NC}"
    exit 1
fi

if ! command -v kubeseal &>/dev/null; then
    echo -e "${RED}✗ kubeseal not found${NC}"
    echo "Install with: brew install kubeseal"
    exit 1
fi

# Check sealed-secrets-controller is running
if ! kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
    echo -e "${RED}✗ Sealed Secrets controller not found${NC}"
    echo "Run: make deploy-step-2"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites validated"
echo ""

# Fetch the new public key
echo -e "${BLUE}→ Fetching Sealed Secrets controller public key...${NC}"
kubeseal --fetch-cert > /tmp/sealed-secrets-cert.pem
echo -e "${GREEN}✓${NC} Public key fetched"
echo ""

echo -e "${YELLOW}This will regenerate sealed secrets from Terraform outputs and AWS Secrets Manager${NC}"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""

# Change to terraform directory
cd terraform/aws || exit 1

# Check if terraform state exists
if ! terraform show &>/dev/null; then
    echo -e "${RED}✗ No Terraform state found${NC}"
    echo "Run 'terraform apply' first to create infrastructure"
    exit 1
fi

echo -e "${BLUE}→ Regenerating secrets from Terraform outputs...${NC}"
echo ""

# Run the existing seal script with new cert
export SEALED_SECRETS_CERT=/tmp/sealed-secrets-cert.pem

# Go back to repo root
cd ../..

# Run seal-terraform-secrets script
if [ -f "scripts/seal-terraform-secrets.sh" ]; then
    echo -e "${YELLOW}Running seal-terraform-secrets.sh...${NC}"
    SEALED_SECRETS_CERT=/tmp/sealed-secrets-cert.pem ./scripts/seal-terraform-secrets.sh dev
    echo -e "${GREEN}✓${NC} Terraform-managed secrets regenerated"
else
    echo -e "${YELLOW}⚠ seal-terraform-secrets.sh not found, skipping${NC}"
fi

echo ""

# Run create-complete-sealed-secrets script
if [ -f "scripts/create-complete-sealed-secrets.sh" ]; then
    echo -e "${YELLOW}Running create-complete-sealed-secrets.sh...${NC}"
    SEALED_SECRETS_CERT=/tmp/sealed-secrets-cert.pem ./scripts/create-complete-sealed-secrets.sh dev
    echo -e "${GREEN}✓${NC} Application secrets regenerated"
else
    echo -e "${YELLOW}⚠ create-complete-sealed-secrets.sh not found, skipping${NC}"
fi

echo ""

# ArgoCD SSH credentials
echo -e "${BLUE}→ Regenerating ArgoCD SSH credentials...${NC}"
SSH_DEPLOY_KEY="${HOME}/.ssh/argocd-dev/fineract-deployment"
if [ ! -f "$SSH_DEPLOY_KEY" ]; then
    echo -e "${YELLOW}⚠ SSH deploy key not found at $SSH_DEPLOY_KEY, skipping ArgoCD credentials${NC}"
    echo "Generate key with: ssh-keygen -t ed25519 -C \"argocd-fineract-gitops\" -f $SSH_DEPLOY_KEY -N \"\""
else
    if [ -f "scripts/seal-argocd-ssh-credentials.sh" ]; then
        SEALED_SECRETS_CERT=/tmp/sealed-secrets-cert.pem ./scripts/seal-argocd-ssh-credentials.sh
        echo -e "${GREEN}✓${NC} ArgoCD SSH credentials regenerated"
    else
        echo -e "${YELLOW}⚠ seal-argocd-ssh-credentials.sh not found, skipping${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ All sealed secrets regenerated!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Review generated secrets in secrets/dev/"
echo "  2. Commit to Git:"
echo "     git add secrets/ && git commit -m 'Regenerate sealed secrets with new key'"
echo "  3. Continue deployment:"
echo "     make deploy-step-3"
echo ""
echo -e "${YELLOW}Note: Sealed secrets were regenerated because the controller was reinstalled${NC}"
echo -e "${YELLOW}This is normal after running 'make cleanup-cluster'${NC}"
