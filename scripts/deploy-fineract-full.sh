#!/bin/bash
#
# Fineract Full Deployment Script
# ================================
# Deploys complete Fineract stack with AWS managed services
#
# Prerequisites:
# - Terraform has provisioned AWS infrastructure
# - kubectl configured with kubeconfig
# - Sealed Secrets controller installed
#
# This script:
# 1. Creates databases in RDS (fineract_tenants, fineract_default)
# 2. Deploys all Fineract components (write, read, batch)
# 3. Deploys platform services (Keycloak, OAuth2 Proxy, Redis)
# 4. Monitors deployment progress
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
NAMESPACE="fineract-${ENVIRONMENT}"
KUBECONFIG_PATH="${KUBECONFIG:-~/.kube/config-fineract-${ENVIRONMENT}-${ENVIRONMENT}}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fineract Full Stack Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Namespace:   ${YELLOW}${NAMESPACE}${NC}"
echo -e "Kubeconfig:  ${YELLOW}${KUBECONFIG_PATH}${NC}"
echo ""

# Export kubeconfig
export KUBECONFIG="${KUBECONFIG_PATH}"

# Function to wait for pods
wait_for_pods() {
  local label=$1
  local namespace=$2
  local timeout=${3:-300}

  echo -e "${YELLOW}Waiting for pods with label ${label} to be ready...${NC}"
  kubectl wait --for=condition=ready pod \
    -l "${label}" \
    -n "${namespace}" \
    --timeout="${timeout}s" || true
}

# Function to check job completion
wait_for_job() {
  local job_name=$1
  local namespace=$2
  local timeout=${3:-300}

  echo -e "${YELLOW}Waiting for job ${job_name} to complete...${NC}"
  kubectl wait --for=condition=complete job/${job_name} \
    -n "${namespace}" \
    --timeout="${timeout}s"
}

# Step 1: Create databases
echo -e "${GREEN}=== Step 1: Creating PostgreSQL Databases ===${NC}"
kubectl apply -f operations/database-init/base/create-databases-job.yaml

# Wait for job to complete
wait_for_job "create-fineract-databases" "${NAMESPACE}" 120

# Show job logs
echo -e "${GREEN}Database creation logs:${NC}"
kubectl logs -n "${NAMESPACE}" job/create-fineract-databases --tail=20

echo -e "${GREEN}✓ Databases created successfully${NC}"
echo ""

# Step 2: Deploy Fineract components
echo -e "${GREEN}=== Step 2: Deploying Fineract Application ===${NC}"
kubectl apply -k environments/${ENVIRONMENT}

echo -e "${YELLOW}Waiting for Fineract write pod to initialize database schema...${NC}"
sleep 30

# Wait for write deployment
wait_for_pods "app=fineract,mode=write" "${NAMESPACE}" 600

echo -e "${GREEN}✓ Fineract write deployment ready${NC}"
echo ""

# Step 3: Deploy platform services via ArgoCD
echo -e "${GREEN}=== Step 3: Deploying Platform Services ===${NC}"

# Check if ArgoCD applications exist, if not create them
if ! kubectl get application fineract-${ENVIRONMENT}-platform-services -n argocd &>/dev/null; then
  echo -e "${YELLOW}Creating ArgoCD applications...${NC}"
  kubectl apply -f argocd/applications/${ENVIRONMENT}/
fi

# Wait for platform services
echo -e "${YELLOW}Waiting for platform services to be ready...${NC}"
sleep 60

# Wait for Keycloak
wait_for_pods "app=keycloak" "${NAMESPACE}" 300

# Wait for OAuth2 Proxy
wait_for_pods "app=oauth2-proxy" "${NAMESPACE}" 300

# Wait for Redis
wait_for_pods "app=fineract-redis" "${NAMESPACE}" 300

echo -e "${GREEN}✓ Platform services deployed${NC}"
echo ""

# Step 4: Deploy read and batch services
echo -e "${GREEN}=== Step 4: Deploying Read and Batch Services ===${NC}"

# Wait for read deployment
wait_for_pods "app=fineract,mode=read" "${NAMESPACE}" 600

# Wait for batch deployment
wait_for_pods "app=fineract,mode=batch" "${NAMESPACE}" 600

echo -e "${GREEN}✓ Read and batch services deployed${NC}"
echo ""

# Step 5: Deployment Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Pod Status:${NC}"
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
echo -e "${YELLOW}Service Status:${NC}"
kubectl get svc -n "${NAMESPACE}"

echo ""
echo -e "${YELLOW}SealedSecrets Status:${NC}"
kubectl get sealedsecrets -n "${NAMESPACE}"

echo ""
echo -e "${YELLOW}Ingress Status:${NC}"
kubectl get ingress -n "${NAMESPACE}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Verify all pods are running: kubectl get pods -n ${NAMESPACE}"
echo "2. Check Fineract logs: kubectl logs -n ${NAMESPACE} -l app=fineract,mode=write"
echo "3. Access Fineract API via ingress"
echo "4. Run data loading jobs if needed: kubectl apply -f operations/fineract-data/jobs/"
echo ""
