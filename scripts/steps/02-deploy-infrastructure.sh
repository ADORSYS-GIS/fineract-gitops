#!/bin/bash
# Step 2: Deploy Infrastructure

set -e
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo "Deploying core infrastructure..."
echo ""

# Function to check if namespace is stuck in Terminating
check_namespace_stuck() {
    local ns=$1
    local phase=$(kubectl get namespace $ns -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [ "$phase" = "Terminating" ]; then
        echo "stuck"
    elif [ "$phase" = "Active" ]; then
        echo "active"
    else
        echo "notfound"
    fi
}

# Function to wait for namespace to be ready (or not exist)
wait_for_namespace_ready() {
    local ns=$1
    local timeout=60
    local count=0

    while [ $count -lt $timeout ]; do
        local status=$(check_namespace_stuck $ns)

        if [ "$status" = "notfound" ]; then
            return 0  # Namespace doesn't exist, safe to create
        elif [ "$status" = "active" ]; then
            echo -e "${YELLOW}  ⚠ Namespace $ns already exists and is active${NC}"
            return 0  # Namespace exists and is ready
        elif [ "$status" = "stuck" ]; then
            echo -ne "${YELLOW}  Waiting for namespace $ns to finish terminating... ($count/$timeout)${NC}\r"
            sleep 1
            count=$((count + 1))
        fi
    done

    # Namespace still stuck after timeout
    echo -e "\n${RED}✗ Namespace $ns stuck in Terminating state${NC}"
    echo -e "${YELLOW}Run: make cleanup-cluster${NC}"
    exit 1
}

# Pre-flight check: Detect stuck namespaces
echo -e "${BLUE}→ Pre-flight check: Checking for stuck namespaces...${NC}"
STUCK_NAMESPACES=()

for ns in argocd ingress-nginx cert-manager fineract-dev; do
    status=$(check_namespace_stuck $ns)
    if [ "$status" = "stuck" ]; then
        STUCK_NAMESPACES+=($ns)
    fi
done

if [ ${#STUCK_NAMESPACES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found stuck namespaces: ${STUCK_NAMESPACES[@]}${NC}"
    echo ""
    echo -e "${BLUE}→ Auto-fixing stuck namespaces...${NC}"

    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Run the cleanup script in stuck-only mode
    if [ -f "$SCRIPT_DIR/../cleanup-cluster.sh" ]; then
        "$SCRIPT_DIR/../cleanup-cluster.sh" --stuck-only

        # Verify fix worked
        sleep 2
        STILL_STUCK=()
        for ns in "${STUCK_NAMESPACES[@]}"; do
            status=$(check_namespace_stuck $ns)
            if [ "$status" = "stuck" ]; then
                STILL_STUCK+=($ns)
            fi
        done

        if [ ${#STILL_STUCK[@]} -gt 0 ]; then
            echo -e "${RED}✗ Some namespaces still stuck: ${STILL_STUCK[@]}${NC}"
            echo ""
            echo -e "${YELLOW}Try running manually:${NC}"
            echo -e "${BLUE}  make cleanup-cluster${NC}"
            echo ""
            exit 1
        else
            echo -e "${GREEN}✓${NC} All stuck namespaces fixed!"
            echo ""
        fi
    else
        echo -e "${RED}✗ cleanup-cluster.sh not found${NC}"
        echo -e "${YELLOW}Run manually: make cleanup-cluster${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} No stuck namespaces detected"
echo ""

# gp3 StorageClass
echo "→ Creating gp3 StorageClass..."
kubectl apply -f infrastructure/storage-class-gp3.yaml
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
echo -e "${GREEN}✓${NC} gp3 StorageClass created"

# Sealed Secrets Controller
echo "→ Installing Sealed Secrets Controller..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/controller.yaml
echo "  Waiting for controller..."
kubectl wait --for=condition=available --timeout=120s deployment/sealed-secrets-controller -n kube-system
echo -e "${GREEN}✓${NC} Sealed Secrets ready"

# ArgoCD
echo "→ Installing ArgoCD..."
wait_for_namespace_ready argocd
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "  Waiting for ArgoCD server..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
echo -e "${GREEN}✓${NC} ArgoCD ready"

# Ingress NGINX
echo "→ Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml
echo "  Waiting for ingress controller..."
sleep 10
kubectl wait --for=condition=available --timeout=180s deployment/ingress-nginx-controller -n ingress-nginx
LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")
echo -e "${GREEN}✓${NC} Ingress controller ready (LB: $LB_DNS)"

# cert-manager
echo "→ Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
echo "  Waiting for webhook..."
sleep 15
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager-webhook -n cert-manager
kubectl apply -f infrastructure/selfsigned-cluster-issuer.yaml
echo -e "${GREEN}✓${NC} cert-manager and self-signed issuer ready"

echo -e "${GREEN}Infrastructure deployment complete!${NC}"
