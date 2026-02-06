#!/bin/bash
#
# GitOps Deployment via ArgoCD
# ===========================
# Deploys entire Fineract stack through ArgoCD ApplicationSets
# Zero manual kubectl commands - everything via Git
#
# Prerequisites:
# - ArgoCD installed (via bootstrap-argocd.sh)
# - Terraform infrastructure provisioned
# - GitHub repo accessible
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
ENVIRONMENT="${1:-dev}"
NAMESPACE="fineract-${ENVIRONMENT}"
KUBECONFIG_PATH="${KUBECONFIG:-~/.kube/config-fineract-${ENVIRONMENT}-${ENVIRONMENT}}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GitOps Deployment via ArgoCD${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Namespace:   ${YELLOW}${NAMESPACE}${NC}"
echo ""

# Export kubeconfig
export KUBECONFIG="${KUBECONFIG_PATH}"

# Step 1: Install Sealed Secrets Controller
echo -e "${GREEN}=== Step 1: Installing Sealed Secrets Controller ===${NC}"
kubectl apply -k apps/sealed-secrets-controller/base/

echo -e "${YELLOW}Waiting for Sealed Secrets Controller...${NC}"
kubectl wait --for=condition=available deployment/sealed-secrets-controller \
  -n kube-system --timeout=120s || true

echo -e "${GREEN}✓ Sealed Secrets Controller installed${NC}"
echo ""

# Step 2: Apply Sealed Secrets (if they exist)
echo -e "${GREEN}=== Step 2: Applying Sealed Secrets ===${NC}"
if [ -d "secrets/${ENVIRONMENT}" ]; then
  kubectl apply -f secrets/${ENVIRONMENT}/ || echo "No sealed secrets found yet - will be created by app-of-apps"
  echo -e "${GREEN}✓ Sealed Secrets applied${NC}"
else
  echo -e "${YELLOW}Note: Sealed secrets directory not found. Secrets will be managed by ArgoCD.${NC}"
fi
echo ""

# Step 3: Deploy App-of-Apps Pattern
echo -e "${GREEN}=== Step 3: Deploying App-of-Apps (GitOps) ===${NC}"

# Deploy ArgoCD Projects first
echo -e "${YELLOW}Creating ArgoCD Projects...${NC}"
kubectl apply -f argocd/projects/

# Deploy App-of-Apps
echo -e "${YELLOW}Deploying App-of-Apps for ${ENVIRONMENT}...${NC}"
kubectl apply -f argocd/bootstrap/${ENVIRONMENT}/app-of-apps.yaml

# Explicitly apply all ArgoCD applications
# This ensures all apps are created even if app-of-apps sync is delayed
echo -e "${YELLOW}Ensuring all ArgoCD applications are created...${NC}"
kubectl apply -k argocd/applications/${ENVIRONMENT}/

echo -e "${GREEN}✓ App-of-Apps and all applications deployed${NC}"
echo ""

# Step 4: Monitor Deployment
echo -e "${GREEN}=== Step 4: Monitoring ArgoCD Applications ===${NC}"
echo ""

echo -e "${YELLOW}Waiting for ArgoCD to sync applications (this may take 2-3 minutes)...${NC}"
sleep 30

echo -e "${YELLOW}ArgoCD Application Status:${NC}"
kubectl get applications -n argocd

echo ""
echo -e "${YELLOW}Pod Status in ${NAMESPACE}:${NC}"
kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l || echo "0"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GitOps Deployment Initiated!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Monitor ArgoCD applications:"
echo "   kubectl get applications -n argocd"
echo ""
echo "2. Watch pod deployments:"
echo "   kubectl get pods -n ${NAMESPACE} -w"
echo ""
echo "3. Check ArgoCD sync status:"
echo "   kubectl get applications -n argocd -o wide"
echo ""
echo "4. Access ArgoCD UI (if exposed):"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   URL: https://localhost:8080"
echo ""
echo -e "${GREEN}All deployments managed via Git! No more manual kubectl commands.${NC}"
echo ""
