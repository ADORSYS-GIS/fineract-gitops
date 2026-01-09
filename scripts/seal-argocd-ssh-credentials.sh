#!/bin/bash
#
# Seal ArgoCD GitHub Repository Credentials (SSH Deploy Key)
# Creates a SealedSecret for ArgoCD to access the GitHub repository via SSH
#
# Usage:
#   ./seal-argocd-ssh-credentials.sh [SSH_KEY_PATH]
#
# If SSH_KEY_PATH is not provided, defaults to: ~/.ssh/argocd-dev/fineract-deployment
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="git@github.com:ADORSYS-GIS/fineract-gitops.git"
SECRET_NAME="repo-fineract-gitops"
NAMESPACE="argocd"
SSH_KEY_PATH="${1:-$HOME/.ssh/argocd-dev/fineract-deployment}"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_CONTROLLER="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Seal ArgoCD SSH Repository Credentials${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Validate SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗ Error: SSH private key not found at: $SSH_KEY_PATH${NC}"
    echo ""
    echo -e "${YELLOW}Generate a new deploy key with:${NC}"
    echo "  ssh-keygen -t ed25519 -C 'argocd-fineract-gitops' -f ~/.ssh/argocd-dev/fineract-deployment -N ''"
    echo ""
    echo -e "${YELLOW}Then add the public key to GitHub:${NC}"
    echo "  1. Copy public key: cat ~/.ssh/argocd-dev/fineract-deployment.pub"
    echo "  2. Go to: https://github.com/ADORSYS-GIS/fineract-gitops/settings/keys"
    echo "  3. Click 'Add deploy key'"
    echo "  4. Paste the public key"
    echo "  5. Uncheck 'Allow write access' (read-only is safer)"
    echo "  6. Click 'Add key'"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Found SSH private key at: $SSH_KEY_PATH${NC}"

# Check if public key exists and display it
if [ -f "${SSH_KEY_PATH}.pub" ]; then
    echo -e "${BLUE}Public key fingerprint:${NC}"
    ssh-keygen -lf "${SSH_KEY_PATH}.pub" 2>/dev/null || echo "  (fingerprint not available)"
fi
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "Install with: brew install kubectl"
    exit 1
fi
echo -e "${GREEN}✓ kubectl installed${NC}"

if ! command -v kubeseal &> /dev/null; then
    echo -e "${RED}✗ kubeseal not found${NC}"
    echo "Install with: brew install kubeseal"
    exit 1
fi
echo -e "${GREEN}✓ kubeseal installed${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠ jq not found (optional but recommended)${NC}"
    echo "Install with: brew install jq"
    USE_JQ=false
else
    echo -e "${GREEN}✓ jq installed${NC}"
    USE_JQ=true
fi
echo ""

# Create secrets directory if it doesn't exist
mkdir -p secrets/system

echo -e "${YELLOW}Creating SealedSecret for ArgoCD SSH repository credentials...${NC}"
echo -e "${BLUE}Repository URL:${NC} $REPO_URL"
echo -e "${BLUE}Secret name:${NC} $SECRET_NAME"
echo -e "${BLUE}Namespace:${NC} $NAMESPACE"
echo ""

# Create the secret with ArgoCD's expected format for SSH
if [ "$USE_JQ" = true ]; then
    # With jq - cleaner approach
    kubectl create secret generic "${SECRET_NAME}" \
      --namespace="${NAMESPACE}" \
      --from-literal=type=git \
      --from-literal=url="${REPO_URL}" \
      --from-file=sshPrivateKey="${SSH_KEY_PATH}" \
      --dry-run=client -o json | \
    jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' | \
    kubeseal --controller-namespace="${SEALED_SECRETS_NAMESPACE}" \
             --controller-name="${SEALED_SECRETS_CONTROLLER}" \
             --format yaml \
             > secrets/system/argocd-repo-credentials-sealed.yaml
else
    # Without jq - use kubectl label
    kubectl create secret generic "${SECRET_NAME}" \
      --namespace="${NAMESPACE}" \
      --from-literal=type=git \
      --from-literal=url="${REPO_URL}" \
      --from-file=sshPrivateKey="${SSH_KEY_PATH}" \
      --dry-run=client -o yaml | \
    kubectl label -f- --dry-run=client -o yaml --local argocd.argoproj.io/secret-type=repository | \
    kubeseal --controller-namespace="${SEALED_SECRETS_NAMESPACE}" \
             --controller-name="${SEALED_SECRETS_CONTROLLER}" \
             --format yaml \
             > secrets/system/argocd-repo-credentials-sealed.yaml
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Created: secrets/system/argocd-repo-credentials-sealed.yaml${NC}"
else
    echo -e "${RED}✗ Failed to create sealed secret${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} ArgoCD SSH Credentials Sealed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Created sealed secret:"
echo "  ✓ secrets/system/argocd-repo-credentials-sealed.yaml"
echo ""
echo "This secret contains:"
echo "  • Repository URL: ${REPO_URL}"
echo "  • SSH Private Key: (encrypted)"
echo "  • Type: git"
echo "  • ArgoCD label: argocd.argoproj.io/secret-type=repository"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Review the sealed secret:"
echo "   cat secrets/system/argocd-repo-credentials-sealed.yaml"
echo ""
echo "2. Commit to Git:"
echo "   git add secrets/system/argocd-repo-credentials-sealed.yaml"
echo "   git commit -m 'feat: add ArgoCD SSH deploy key sealed secret'"
echo "   git push"
echo ""
echo "3. Apply to cluster (after infrastructure deployment):"
echo "   kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml"
echo ""
echo "4. Restart ArgoCD components:"
echo "   kubectl rollout restart deployment argocd-repo-server -n argocd"
echo "   kubectl rollout restart deployment argocd-application-controller -n argocd"
echo ""
echo "5. Verify ArgoCD can access the repository:"
echo "   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50"
echo ""
echo -e "${BLUE}Testing SSH connection (optional):${NC}"
echo "  ssh -T git@github.com -i ${SSH_KEY_PATH}"
echo "  Expected: 'Hi ADORSYS-GIS/fineract-gitops! You've successfully authenticated...'"
echo ""
echo -e "${GREEN}Done!${NC}"
