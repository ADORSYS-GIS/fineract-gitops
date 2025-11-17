#!/bin/bash
# Update ArgoCD Repository Configuration
#
# This script reads the centralized repository configuration from
# argocd/config/repository-config.yaml and updates all ArgoCD Application
# manifests to use the configured repository URL and target revisions.
#
# This is the single source of truth for ArgoCD Git configuration.
#
# Usage:
#   ./scripts/update-argocd-config.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be changed without making changes
#
# Configuration:
#   Edit argocd/config/repository-config.yaml to change:
#   - REPO_URL: GitHub repository URL
#   - TARGET_REVISION_DEV: Branch for dev environment
#   - TARGET_REVISION_UAT: Branch for UAT environment
#   - TARGET_REVISION_PRODUCTION: Branch for production environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
if [ "$1" == "--dry-run" ]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No files will be modified${NC}"
    echo ""
fi

echo "==========================================="
echo "ArgoCD Configuration Update Script"
echo "==========================================="
echo ""

# Check if repository-config.yaml exists
CONFIG_FILE="argocd/config/repository-config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Extract configuration from config file
REPO_URL=$(grep "^REPO_URL:" "$CONFIG_FILE" | sed 's/REPO_URL: *"\(.*\)"/\1/')
TARGET_REV_DEV=$(grep "^TARGET_REVISION_DEV:" "$CONFIG_FILE" | sed 's/TARGET_REVISION_DEV: *"\(.*\)"/\1/')
TARGET_REV_UAT=$(grep "^TARGET_REVISION_UAT:" "$CONFIG_FILE" | sed 's/TARGET_REVISION_UAT: *"\(.*\)"/\1/')
TARGET_REV_PROD=$(grep "^TARGET_REVISION_PRODUCTION:" "$CONFIG_FILE" | sed 's/TARGET_REVISION_PRODUCTION: *"\(.*\)"/\1/')

# Validate extracted values
if [ -z "$REPO_URL" ]; then
    echo -e "${RED}❌ Could not extract REPO_URL from $CONFIG_FILE${NC}"
    exit 1
fi

if [ -z "$TARGET_REV_DEV" ]; then
    echo -e "${RED}❌ Could not extract TARGET_REVISION_DEV from $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Repository URL: $REPO_URL${NC}"
echo -e "${GREEN}✓ Dev Branch: $TARGET_REV_DEV${NC}"
echo -e "${GREEN}✓ UAT Branch: $TARGET_REV_UAT${NC}"
echo -e "${GREEN}✓ Production Branch: $TARGET_REV_PROD${NC}"
echo ""

# Counters
UPDATED_URL_COUNT=0
UPDATED_BRANCH_COUNT=0

# Function to update repository URL in a file
update_repo_url() {
    local file="$1"
    local current_url
    current_url=$(grep "repoURL:" "$file" | sed 's/.*repoURL: *"\?\([^"]*\)"\?.*/\1/' | head -1 | sed 's/ *#.*//' | tr -d ' ')

    if [ "$current_url" != "$REPO_URL" ]; then
        echo -e "${YELLOW}Updating URL in: $file${NC}"
        echo "  Old: $current_url"
        echo "  New: $REPO_URL"

        if [ "$DRY_RUN" = false ]; then
            sed -i '' "s|repoURL: *[\"'].*github.com/[^\"']*[\"'].*|repoURL: \"$REPO_URL\"|g" "$file"
            sed -i '' "s|repoURL: *https://github.com/[^ ]*.*|repoURL: \"$REPO_URL\"|g" "$file"
            UPDATED_URL_COUNT=$((UPDATED_URL_COUNT + 1))
        fi
        echo ""
        return 0
    fi
    return 1
}

# Function to update target revision in a file
update_target_revision() {
    local file="$1"
    local target_branch="$2"

    if ! grep -q "targetRevision:" "$file" 2>/dev/null; then
        return 1
    fi

    local current_branch
    current_branch=$(grep "targetRevision:" "$file" | sed 's/.*targetRevision: *"\?\([^"#]*\)"\?.*/\1/' | head -1 | tr -d ' ')

    if [ "$current_branch" != "$target_branch" ]; then
        echo -e "${YELLOW}Updating branch in: $file${NC}"
        echo "  Old: $current_branch"
        echo "  New: $target_branch"

        if [ "$DRY_RUN" = false ]; then
            # Update targetRevision, preserving comments if any
            sed -i '' "s|targetRevision: *[\"'].*[\"'].*|targetRevision: $target_branch|g" "$file"
            sed -i '' "s|targetRevision: *[a-zA-Z0-9_/-]*.*#|targetRevision: $target_branch  #|g" "$file"
            sed -i '' "s|targetRevision: *[a-zA-Z0-9_/-]*\$|targetRevision: $target_branch|g" "$file"
            UPDATED_BRANCH_COUNT=$((UPDATED_BRANCH_COUNT + 1))
        fi
        echo ""
        return 0
    fi
    return 1
}

# Process Dev Environment
echo "==========================================="
echo "Processing Dev Environment"
echo "==========================================="
echo ""

DEV_FILES=$(find argocd/applications/dev argocd/bootstrap/dev -name "*.yaml" -type f 2>/dev/null | grep -v disabled || true)

for file in $DEV_FILES; do
    if grep -q "repoURL:" "$file" 2>/dev/null; then
        update_repo_url "$file" || true
        update_target_revision "$file" "$TARGET_REV_DEV" || true
    fi
done

# Process UAT Environment
if [ -n "$TARGET_REV_UAT" ]; then
    echo "==========================================="
    echo "Processing UAT Environment"
    echo "==========================================="
    echo ""

    UAT_FILES=$(find argocd/applications/uat argocd/bootstrap/uat -name "*.yaml" -type f 2>/dev/null | grep -v disabled || true)

    for file in $UAT_FILES; do
        if grep -q "repoURL:" "$file" 2>/dev/null; then
            update_repo_url "$file" || true
            update_target_revision "$file" "$TARGET_REV_UAT" || true
        fi
    done
fi

# Process Production Environment
if [ -n "$TARGET_REV_PROD" ]; then
    echo "==========================================="
    echo "Processing Production Environment"
    echo "==========================================="
    echo ""

    PROD_FILES=$(find argocd/applications/prod argocd/applications/production argocd/bootstrap/prod -name "*.yaml" -type f 2>/dev/null | grep -v disabled || true)

    for file in $PROD_FILES; do
        if grep -q "repoURL:" "$file" 2>/dev/null; then
            update_repo_url "$file" || true
            update_target_revision "$file" "$TARGET_REV_PROD" || true
        fi
    done
fi

# Summary
echo "==========================================="
echo "Summary"
echo "==========================================="
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN - No changes made${NC}"
    echo ""
fi

echo -e "${GREEN}✓ Repository URLs updated: $UPDATED_URL_COUNT${NC}"
echo -e "${GREEN}✓ Target revisions updated: $UPDATED_BRANCH_COUNT${NC}"
echo ""

if [ "$DRY_RUN" = false ] && [ $((UPDATED_URL_COUNT + UPDATED_BRANCH_COUNT)) -gt 0 ]; then
    echo "Next steps:"
    echo "  1. Review changes: git diff argocd/"
    echo "  2. Test in dev: kubectl apply -f argocd/bootstrap/dev/app-of-apps.yaml"
    echo "  3. Commit changes: git add argocd/ && git commit -m 'Update ArgoCD configuration'"
    echo ""
fi

if [ $((UPDATED_URL_COUNT + UPDATED_BRANCH_COUNT)) -eq 0 ]; then
    echo -e "${GREEN}✓ All configurations are up to date!${NC}"
    echo ""
fi

echo "==========================================="
echo "Complete!"
echo "==========================================="
