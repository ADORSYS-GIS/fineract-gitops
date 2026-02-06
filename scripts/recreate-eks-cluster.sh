#!/bin/bash
# EKS Cluster Destroy and Recreate Script
#
# This script destroys only the EKS cluster and node groups (preserving VPC, RDS, S3)
# and recreates them. Much faster and cleaner than trying to clean resources inside the cluster.
#
# Usage: ./scripts/recreate-eks-cluster.sh [dev|uat|production]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform/aws"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV="${1:-dev}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}EKS Cluster Destroy and Recreate${NC}"
echo -e "${BLUE}Environment: $ENV${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Validate environment
case "$ENV" in
    dev|uat|production)
        ;;
    *)
        echo -e "${RED}Invalid environment: $ENV${NC}"
        echo "Usage: $0 [dev|uat|production]"
        exit 1
        ;;
esac

# Confirmation
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}WARNING: This will:${NC}"
echo -e "${YELLOW}  - DESTROY the EKS cluster and node groups${NC}"
echo -e "${YELLOW}  - PRESERVE VPC, subnets (required by RDS)${NC}"
echo -e "${YELLOW}  - PRESERVE RDS database (your data is safe)${NC}"
echo -e "${YELLOW}  - PRESERVE S3 buckets (your files are safe)${NC}"
echo -e "${YELLOW}  - Recreate the EKS cluster from scratch${NC}"
echo -e "${YELLOW}  - Redeploy all applications${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""

# ============================================================================
# Step 1: Destroy EKS cluster and node groups (not VPC)
# ============================================================================

echo -e "${BLUE}Step 1: Destroying EKS cluster and node groups...${NC}"
echo -e "${BLUE}  This may take 10-15 minutes...${NC}"
cd "$TERRAFORM_DIR"

TFVARS_FILE="environments/${ENV}-eks.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}✗ tfvars file not found: $TFVARS_FILE${NC}"
    exit 1
fi

# Initialize terraform if needed
terraform init -upgrade

# Destroy EKS resources in correct order (node groups first, then cluster, then addons/IRSA)
# Do NOT destroy VPC, subnets, NAT gateway - these are needed by RDS

echo -e "${BLUE}  → Destroying node groups...${NC}"
terraform destroy \
    -target='module.eks.aws_eks_node_group.main' \
    -var-file="$TFVARS_FILE" -auto-approve 2>/dev/null || true

echo -e "${BLUE}  → Destroying EKS addons...${NC}"
terraform destroy \
    -target='module.eks.aws_eks_addon.coredns' \
    -target='module.eks.aws_eks_addon.kube_proxy' \
    -target='module.eks.aws_eks_addon.vpc_cni' \
    -target='module.eks.aws_eks_addon.pod_identity_agent' \
    -target='module.eks.aws_eks_addon.cloudwatch_observability' \
    -var-file="$TFVARS_FILE" -auto-approve 2>/dev/null || true

echo -e "${BLUE}  → Destroying EKS cluster...${NC}"
terraform destroy \
    -target='module.eks.aws_eks_cluster.main' \
    -var-file="$TFVARS_FILE" -auto-approve 2>/dev/null || true

echo -e "${BLUE}  → Destroying IRSA resources...${NC}"
terraform destroy \
    -target='module.eks.aws_iam_openid_connect_provider.eks' \
    -target='module.eks.aws_iam_role.fineract_app_irsa' \
    -target='module.eks.aws_iam_role_policy.fineract_app_s3_access' \
    -var-file="$TFVARS_FILE" -auto-approve 2>/dev/null || true

echo -e "${GREEN}✓ EKS cluster destroyed (VPC preserved)${NC}"
echo ""

# ============================================================================
# Step 2: Recreate EKS cluster
# ============================================================================

echo -e "${BLUE}Step 2: Recreating EKS cluster...${NC}"
echo -e "${BLUE}  This may take 15-20 minutes...${NC}"

# Apply full terraform to recreate EKS cluster, node groups, addons, IRSA
# VPC already exists, so only EKS resources will be created
terraform apply -var-file="$TFVARS_FILE" -auto-approve

echo -e "${GREEN}✓ EKS cluster recreated${NC}"
echo ""

# ============================================================================
# Step 3: Update kubeconfig
# ============================================================================

echo -e "${BLUE}Step 3: Updating kubeconfig...${NC}"

CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# Verify cluster access
if kubectl get nodes &>/dev/null; then
    echo -e "${GREEN}✓ kubeconfig updated and cluster accessible${NC}"
    kubectl get nodes
else
    echo -e "${RED}✗ Failed to access cluster${NC}"
    exit 1
fi
echo ""

# ============================================================================
# Step 4: Wait for nodes to be ready
# ============================================================================

echo -e "${BLUE}Step 4: Waiting for nodes to be ready...${NC}"

# Wait for at least one node to be Ready
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
    if [ "$READY_NODES" -gt 0 ]; then
        echo -e "${GREEN}✓ $READY_NODES node(s) ready${NC}"
        break
    fi
    echo -e "${BLUE}  Waiting for nodes... ($ELAPSED/$TIMEOUT seconds)${NC}"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${YELLOW}⚠ Timeout waiting for nodes, continuing anyway...${NC}"
fi
echo ""

# ============================================================================
# Step 5: Deploy infrastructure and applications
# ============================================================================

echo -e "${BLUE}Step 5: Deploying infrastructure and applications...${NC}"

# Export ENV for step scripts
export ENV

# Run step scripts in order
if [ -f "$REPO_ROOT/scripts/steps/01-validate-prerequisites.sh" ]; then
    echo -e "${BLUE}→ Running 01-validate-prerequisites.sh...${NC}"
    "$REPO_ROOT/scripts/steps/01-validate-prerequisites.sh" || true
fi

if [ -f "$REPO_ROOT/scripts/steps/02-deploy-infrastructure.sh" ]; then
    echo -e "${BLUE}→ Running 02-deploy-infrastructure.sh...${NC}"
    "$REPO_ROOT/scripts/steps/02-deploy-infrastructure.sh"
fi

if [ -f "$REPO_ROOT/scripts/steps/03-setup-argocd.sh" ]; then
    echo -e "${BLUE}→ Running 03-setup-argocd.sh...${NC}"
    "$REPO_ROOT/scripts/steps/03-setup-argocd.sh"
fi

if [ -f "$REPO_ROOT/scripts/steps/04-deploy-apps.sh" ]; then
    echo -e "${BLUE}→ Running 04-deploy-apps.sh...${NC}"
    "$REPO_ROOT/scripts/steps/04-deploy-apps.sh"
fi

if [ -f "$REPO_ROOT/scripts/steps/05-verify-deployment.sh" ]; then
    echo -e "${BLUE}→ Running 05-verify-deployment.sh...${NC}"
    "$REPO_ROOT/scripts/steps/05-verify-deployment.sh" || true
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}EKS Cluster Recreation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  Environment: $ENV"
echo "  Cluster: $CLUSTER_NAME"
echo "  Region: $AWS_REGION"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Check ArgoCD applications: argocd app list"
echo "  2. Check pods: kubectl get pods -n fineract-$ENV"
echo "  3. Wait for LoadBalancer DNS, then run:"
echo "     ./scripts/auto-update-lb-dns.sh"
echo ""
