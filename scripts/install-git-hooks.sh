#!/bin/bash

# Install Git Hooks for Fineract GitOps
#
# This script configures Git to use custom hooks from the .githooks directory.
# It enables local validation before commits and pushes.
#
# Usage:
#   ./scripts/install-git-hooks.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Git Hooks Installation${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$PROJECT_ROOT"

# Check if .githooks directory exists
if [ ! -d ".githooks" ]; then
    echo -e "${RED}Error: .githooks directory not found${NC}"
    echo -e "${YELLOW}Expected location: ${PROJECT_ROOT}/.githooks${NC}"
    exit 1
fi

# Check if hooks exist
if [ ! -f ".githooks/pre-commit" ] || [ ! -f ".githooks/pre-push" ]; then
    echo -e "${RED}Error: Git hook files not found${NC}"
    echo -e "${YELLOW}Expected files:${NC}"
    echo -e "${YELLOW}  - .githooks/pre-commit${NC}"
    echo -e "${YELLOW}  - .githooks/pre-push${NC}"
    exit 1
fi

# Make hooks executable
echo -e "${BLUE}Making hooks executable...${NC}"
chmod +x .githooks/pre-commit
chmod +x .githooks/pre-push
echo -e "${GREEN}✓ Hooks are now executable${NC}"
echo ""

# Configure Git to use .githooks directory
echo -e "${BLUE}Configuring Git to use .githooks directory...${NC}"
git config core.hooksPath .githooks

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Git configured successfully${NC}"
else
    echo -e "${RED}✗ Failed to configure Git${NC}"
    exit 1
fi

echo ""

# Verify configuration
echo -e "${BLUE}Verifying configuration...${NC}"
HOOKS_PATH=$(git config core.hooksPath)

if [ "$HOOKS_PATH" = ".githooks" ]; then
    echo -e "${GREEN}✓ Git hooks path: ${HOOKS_PATH}${NC}"
else
    echo -e "${RED}✗ Unexpected hooks path: ${HOOKS_PATH}${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${GREEN}✓ Git hooks installed successfully!${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

echo -e "${BLUE}Installed hooks:${NC}"
echo -e "  ${GREEN}✓${NC} pre-commit  - Secret detection, :latest validation, kustomize builds"
echo -e "  ${GREEN}✓${NC} pre-push    - ArgoCD application validation"
echo ""

echo -e "${BLUE}What happens now:${NC}"
echo -e "  • Hooks will run automatically before commits and pushes"
echo -e "  • You'll get immediate feedback on issues"
echo -e "  • To bypass hooks (not recommended): use --no-verify flag"
echo ""

echo -e "${YELLOW}Example:${NC}"
echo -e "  git commit -m 'Your message'     ${GREEN}# Runs pre-commit hook${NC}"
echo -e "  git push origin main              ${GREEN}# Runs pre-push hook${NC}"
echo -e "  git commit --no-verify            ${YELLOW}# Bypasses hooks (not recommended)${NC}"
echo ""

echo -e "${BLUE}To uninstall hooks:${NC}"
echo -e "  ${YELLOW}git config --unset core.hooksPath${NC}"
echo ""

echo -e "${BLUE}=====================================${NC}"
