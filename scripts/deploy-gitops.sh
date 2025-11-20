#!/bin/bash
#
# Interactive GitOps Deployment Script
# Deploys Fineract platform step-by-step with user confirmation
#
# ════════════════════════════════════════════════════════════════════
# USE CASE: Manual deployments, learning, troubleshooting
# ════════════════════════════════════════════════════════════════════
#
# This script provides an INTERACTIVE deployment experience with:
# - User confirmations between each step
# - Clear progress tracking
# - Easy to pause and resume
# - Helpful for understanding the deployment process
# - Best for manual operations and debugging
#
# For AUTOMATED deployments (CI/CD pipelines), use:
#   ./scripts/deploy-full-stack.sh
#
# See DEPLOYMENT.md for complete guide
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Fineract GitOps Deployment - Interactive Mode${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Define deployment steps
STEPS=(
  "01-validate-prerequisites"
  "02-deploy-infrastructure"
  "03-setup-argocd"
  "04-deploy-apps"
  "05-verify-deployment"
)

STEP_NAMES=(
  "Validate Prerequisites"
  "Deploy Infrastructure"
  "Setup ArgoCD & Secrets"
  "Deploy Applications"
  "Verify Deployment"
)

# Track overall success
OVERALL_SUCCESS=true

# Execute each step
for i in "${!STEPS[@]}"; do
  step="${STEPS[$i]}"
  step_name="${STEP_NAMES[$i]}"
  step_num=$((i + 1))

  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}   STEP $step_num/${#STEPS[@]}: $step_name${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""

  # Execute the step script
  if [ -f "$SCRIPT_DIR/steps/${step}.sh" ]; then
    bash "$SCRIPT_DIR/steps/${step}.sh"
    exit_code=$?

    echo ""
    if [ $exit_code -eq 0 ]; then
      echo -e "${GREEN}✓ Step completed successfully${NC}"
    else
      echo -e "${RED}✗ Step failed with exit code $exit_code${NC}"
      OVERALL_SUCCESS=false

      # Ask user if they want to continue
      echo ""
      read -p "$(echo -e ${YELLOW}Continue anyway? [y/N]:${NC} )" -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deployment aborted${NC}"
        exit 1
      fi
    fi
  else
    echo -e "${RED}✗ Step script not found: $SCRIPT_DIR/steps/${step}.sh${NC}"
    OVERALL_SUCCESS=false
    exit 1
  fi

  # Prompt for continuation (except after last step)
  if [ $step_num -lt ${#STEPS[@]} ]; then
    echo ""
    echo -e "${YELLOW}Press Enter to continue to next step...${NC}"
    read
  fi
done

# Final summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
if [ "$OVERALL_SUCCESS" = true ]; then
  echo -e "${GREEN}   ✓ Deployment completed successfully!${NC}"
else
  echo -e "${YELLOW}   ⚠ Deployment completed with warnings${NC}"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

exit 0
