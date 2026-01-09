#!/bin/bash
# Step 3: Setup ArgoCD and Secrets

set -e
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Get repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV="${ENV:-dev}"

echo "Setting up ArgoCD and sealed secrets..."
echo ""

# Wait for SealedSecrets CRD to be ready
echo -e "${BLUE}→ Waiting for SealedSecrets CRD to be ready...${NC}"
CRD_READY=false
for i in {1..60}; do
    if kubectl get crd sealedsecrets.bitnami.com &>/dev/null; then
        # Check if CRD is established
        CRD_STATUS=$(kubectl get crd sealedsecrets.bitnami.com -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "")
        if [ "$CRD_STATUS" = "True" ]; then
            CRD_READY=true
            echo -e "${GREEN}✓${NC} SealedSecrets CRD is ready"
            break
        fi
    fi
    echo -ne "${BLUE}  Waiting for CRD... ($i/60)${NC}\r"
    sleep 1
done

if [ "$CRD_READY" = false ]; then
    echo -e "\n${RED}✗ SealedSecrets CRD not ready after 60s${NC}"
    echo -e "${YELLOW}Run: kubectl get crd sealedsecrets.bitnami.com${NC}"
    exit 1
fi

echo ""

# Create GitHub credentials for ArgoCD using SSH deploy key
echo "→ Creating ArgoCD repository credentials..."

# Check if SSH key exists
SSH_KEY_PATH="${HOME}/.ssh/argocd-dev/fineract-deployment"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗${NC} SSH deploy key not found at $SSH_KEY_PATH"
    echo -e "${YELLOW}Generate one with:${NC}"
    echo -e "${YELLOW}  ssh-keygen -t ed25519 -C \"argocd-fineract-gitops\" -f $SSH_KEY_PATH -N \"\"${NC}"
    echo -e "${YELLOW}  Then add ${SSH_KEY_PATH}.pub to GitHub repository deploy keys${NC}"
    exit 1
fi

kubectl create secret generic repo-fineract-gitops \
  --namespace=argocd \
  --from-literal=type=git \
  --from-literal=url=git@github.com:ADORSYS-GIS/fineract-gitops.git \
  --from-file=sshPrivateKey="$SSH_KEY_PATH" \
  --dry-run=client -o yaml | \
  kubectl label -f- --dry-run=client -o yaml --local argocd.argoproj.io/secret-type=repository | \
  kubeseal --format=yaml | \
  kubectl apply -f-

echo "  Waiting for secret to unseal..."
sleep 5
kubectl get secret repo-fineract-gitops -n argocd &>/dev/null || (echo -e "${RED}✗${NC} Secret not unsealed"; exit 1)
echo -e "${GREEN}✓${NC} ArgoCD repository credentials created (SSH)"

# Create namespaces
echo "→ Creating namespaces..."
kubectl create namespace fineract-dev || true
echo -e "${GREEN}✓${NC} Namespaces created"

# Apply sealed secrets with retry logic
echo "→ Applying sealed secrets..."
APPLY_SUCCESS=false
for attempt in {1..3}; do
    if [ $attempt -gt 1 ]; then
        echo -e "${YELLOW}  Retry attempt $attempt/3...${NC}"
        sleep 5
    fi

    # Try to apply sealed secrets
    if kubectl apply -f secrets/dev/ 2>&1 | tee /tmp/sealed-apply.log | grep -v "environment-info.yaml\|grafana-admin"; then
        # Check if there were any CRD errors
        if ! grep -q "resource mapping not found" /tmp/sealed-apply.log; then
            APPLY_SUCCESS=true
            break
        fi
    fi
done

if [ "$APPLY_SUCCESS" = false ]; then
    echo -e "${RED}✗ Failed to apply sealed secrets after 3 attempts${NC}"
    echo -e "${YELLOW}Check CRD: kubectl get crd sealedsecrets.bitnami.com${NC}"
    exit 1
fi

echo "  Waiting for secrets to unseal..."
sleep 10
UNSEALED=$(kubectl get sealedsecrets -n fineract-dev --no-headers 2>/dev/null | wc -l || echo "0")
READY=$(kubectl get secrets -n fineract-dev --no-headers 2>/dev/null | grep -v default-token | wc -l || echo "0")
echo -e "${GREEN}✓${NC} Sealed secrets applied ($UNSEALED SealedSecrets, $READY secrets ready)"

# Verify critical secrets
echo -e "${BLUE}→ Verifying critical secrets...${NC}"
CRITICAL_SECRETS=(
    "fineract-db-credentials"
    "keycloak-admin-credentials"
    "oauth2-proxy-secrets"
)

MISSING_SECRETS=()
for secret in "${CRITICAL_SECRETS[@]}"; do
    if kubectl get secret $secret -n fineract-dev &>/dev/null; then
        echo -e "${GREEN}  ✓${NC} $secret"
    else
        echo -e "${RED}  ✗${NC} $secret (missing)"
        MISSING_SECRETS+=($secret)
    fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some critical secrets are missing: ${MISSING_SECRETS[@]}${NC}"
    echo -e "${YELLOW}Deployment may fail. Check sealed secrets in secrets/dev/${NC}"
fi

echo ""

# ============================================================================
# Validate Sealed Secrets Compatibility
# ============================================================================

echo -e "${BLUE}→ Validating sealed secrets compatibility...${NC}"
VALIDATION_EXIT_CODE=0
"${REPO_ROOT}/scripts/validate-sealed-secrets-compatibility.sh" "$ENV" || VALIDATION_EXIT_CODE=$?

case $VALIDATION_EXIT_CODE in
    0)
        echo -e "${GREEN}✓${NC} Sealed secrets are compatible with cluster"
        ;;
    1)
        echo -e "${RED}✗${NC} Sealed secrets key mismatch detected!"
        echo ""
        echo -e "${YELLOW}Sealed secrets in Git were encrypted with a different cluster's key${NC}"
        echo ""
        echo "This happens when:"
        echo "  • Deploying to a fresh cluster (new encryption keys)"
        echo "  • Controller was reinstalled (keys regenerated)"
        echo ""
        echo "Options:"
        echo "  1) Auto-regenerate all sealed secrets (recommended for dev)"
        echo "  2) Restore backed-up keys from AWS (for prod/disaster recovery)"
        echo "  3) Continue anyway (applications will fail to start)"
        echo ""
        read -p "Choice [1-3]: " -n 1 -r SEALED_CHOICE
        echo ""

        case $SEALED_CHOICE in
            1)
                echo -e "${BLUE}→ Auto-regenerating sealed secrets...${NC}"
                if "${REPO_ROOT}/scripts/regenerate-all-sealed-secrets.sh" "$ENV"; then
                    echo -e "${GREEN}✓${NC} Sealed secrets regenerated successfully"
                else
                    echo -e "${RED}✗${NC} Failed to regenerate sealed secrets"
                    exit 1
                fi
                ;;
            2)
                echo -e "${BLUE}→ Restoring sealed secrets keys from AWS...${NC}"
                if "${REPO_ROOT}/scripts/restore-sealed-secrets-keys.sh" "$ENV"; then
                    echo -e "${GREEN}✓${NC} Keys restored, reapplying sealed secrets..."
                    kubectl apply -f "${REPO_ROOT}/secrets/${ENV}/" || echo -e "${YELLOW}⚠ Some secrets may have failed${NC}"
                    echo "  Wait a moment for secrets to unseal, then check:"
                    echo "  kubectl get sealedsecrets -n fineract-${ENV}"
                    echo "  kubectl get secrets -n fineract-${ENV}"
                else
                    echo -e "${RED}✗${NC} Failed to restore keys"
                    exit 1
                fi
                ;;
            3)
                echo -e "${YELLOW}⚠ Continuing with incompatible sealed secrets${NC}"
                echo -e "${YELLOW}Applications will likely fail to start${NC}"
                ;;
        esac
        ;;
    2)
        echo -e "${RED}✗${NC} Sealed Secrets Controller not ready"
        exit 1
        ;;
    3)
        echo -e "${YELLOW}⚠${NC} No sealed secrets to validate (fresh deployment)"
        ;;
esac

echo ""
echo -e "${GREEN}ArgoCD setup complete!${NC}"
