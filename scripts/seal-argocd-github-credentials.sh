#!/bin/bash
#
# Seal ArgoCD GitHub Repository Credentials
# Creates a SealedSecret for ArgoCD to access the GitHub repository
#
# Usage:
#   ./scripts/seal-argocd-github-credentials.sh <github_token>
#   ./scripts/seal-argocd-github-credentials.sh --from-aws-secrets <secret-name>
#
# Examples:
#   # Provide token directly (not recommended for production)
#   ./scripts/seal-argocd-github-credentials.sh ghp_xxxxxxxxxxxxxxxxxxxx
#
#   # Fetch from AWS Secrets Manager (recommended)
#   ./scripts/seal-argocd-github-credentials.sh --from-aws-secrets /fineract/dev/github-token
#
# Prerequisites:
# 1. Sealed Secrets controller must be deployed in kube-system
# 2. kubeseal CLI must be installed (brew install kubeseal)
# 3. kubectl must be configured to access the cluster
# 4. For AWS Secrets Manager: AWS CLI configured with appropriate permissions
#
# Security Best Practice:
#   Store GitHub tokens in AWS Secrets Manager instead of passing as CLI arguments
#   to avoid exposing them in shell history or process lists.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: GitHub token or --from-aws-secrets argument required${NC}"
    echo "Usage:"
    echo "  $0 <github_token>"
    echo "  $0 --from-aws-secrets <secret-name>"
    echo
    echo "Examples:"
    echo "  $0 ghp_xxxxxxxxxxxxxxxxxxxx"
    echo "  $0 --from-aws-secrets /fineract/dev/github-token"
    echo
    echo "To create a GitHub Personal Access Token:"
    echo "  1. Go to: https://github.com/settings/tokens"
    echo "  2. Click 'Generate new token (classic)'"
    echo "  3. Select scopes: 'repo' (full control of private repositories)"
    echo "  4. Generate token and copy it"
    echo
    echo "To store in AWS Secrets Manager (recommended):"
    echo "  aws secretsmanager create-secret \\"
    echo "    --name /fineract/dev/github-token \\"
    echo "    --description 'GitHub PAT for ArgoCD' \\"
    echo "    --secret-string 'ghp_your_token_here'"
    echo
    exit 1
fi

# Fetch token from AWS Secrets Manager or use provided value
if [ "$1" = "--from-aws-secrets" ]; then
    if [ -z "$2" ]; then
        echo -e "${RED}Error: Secret name required when using --from-aws-secrets${NC}"
        exit 1
    fi

    SECRET_NAME_ARG="$2"
    echo -e "${BLUE}Fetching GitHub token from AWS Secrets Manager: ${SECRET_NAME_ARG}${NC}"

    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI not found${NC}"
        echo "Install with: brew install awscli"
        exit 1
    fi

    GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
        --secret-id "${SECRET_NAME_ARG}" \
        --query SecretString \
        --output text 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to fetch secret from AWS Secrets Manager${NC}"
        echo "${GITHUB_TOKEN}"
        exit 1
    fi

    echo -e "${GREEN}✓ Successfully fetched token from AWS Secrets Manager${NC}"
else
    GITHUB_TOKEN="$1"
    echo -e "${YELLOW}Warning: Passing token via CLI argument is not recommended for production${NC}"
    echo -e "${YELLOW}Consider using AWS Secrets Manager: --from-aws-secrets /fineract/dev/github-token${NC}"
fi
REPO_URL="https://github.com/ADORSYS-GIS/fineract-gitops.git"
SECRET_NAME="repo-fineract-gitops"
NAMESPACE="argocd"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_CONTROLLER="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Sealing ArgoCD GitHub Credentials${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo -e "${RED}Error: kubeseal not found${NC}"
    echo "Install with: brew install kubeseal"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo

# Create secrets directory if it doesn't exist
mkdir -p secrets/system

echo -e "${YELLOW}Creating SealedSecret for ArgoCD repository credentials...${NC}"
echo

# Create the secret with ArgoCD's expected format
# ArgoCD expects these specific keys for repository credentials
kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --from-literal=username=not-used \
  --dry-run=client -o json | \
jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' | \
kubeseal --controller-namespace="${SEALED_SECRETS_NAMESPACE}" \
         --controller-name="${SEALED_SECRETS_CONTROLLER}" \
         --format yaml \
         > secrets/system/argocd-repo-credentials-sealed.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Created: secrets/system/argocd-repo-credentials-sealed.yaml${NC}"
else
    echo -e "${RED}✗ Failed to create sealed secret${NC}"
    exit 1
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ArgoCD GitHub Credentials Sealed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Created sealed secret:"
echo "  ✓ secrets/system/argocd-repo-credentials-sealed.yaml"
echo
echo "This secret contains:"
echo "  • Repository URL: ${REPO_URL}"
echo "  • GitHub Token: (encrypted)"
echo "  • ArgoCD label: argocd.argoproj.io/secret-type=repository"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the sealed secret:"
echo "   cat secrets/system/argocd-repo-credentials-sealed.yaml"
echo
echo "2. Commit to Git:"
echo "   git add secrets/system/argocd-repo-credentials-sealed.yaml"
echo "   git commit -m \"Add ArgoCD GitHub repository credentials (sealed)\""
echo "   git push"
echo
echo "3. Apply to cluster (or let ArgoCD sync it):"
echo "   kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml"
echo
echo "4. Verify ArgoCD can access the repository:"
echo "   argocd repo list"
echo
echo -e "${BLUE}Security Note:${NC}"
echo "The sealed secret is encrypted and safe to commit to Git."
echo "Only the Sealed Secrets controller in your cluster can decrypt it."
echo
echo "For better security, consider using a GitHub App instead of a PAT:"
echo "  https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/#github-app"
echo
echo -e "${GREEN}Done!${NC}"
