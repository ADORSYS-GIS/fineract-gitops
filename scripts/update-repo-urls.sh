#!/bin/bash
# Update Repository URLs Across All ArgoCD Manifests
#
# This script reads the repository URL from argocd/config/repository-config.yaml
# and updates all ArgoCD Application manifests to use the centralized URL.
#
# Usage:
#   ./scripts/update-repo-urls.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be changed without making changes

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
echo "Repository URL Update Script"
echo "==========================================="
echo ""

# Check if repository-config.yaml exists
CONFIG_FILE="argocd/config/repository-config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Extract repository URL from config file
REPO_URL=$(grep "^REPO_URL:" "$CONFIG_FILE" | sed 's/REPO_URL: *"\(.*\)"/\1/')

if [ -z "$REPO_URL" ]; then
    echo -e "${RED}❌ Could not extract REPO_URL from $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Repository URL: $REPO_URL${NC}"
echo ""

# Find all ArgoCD Application manifests
echo "Finding ArgoCD Application manifests..."
APP_FILES=$(find argocd/applications argocd/bootstrap argocd/projects argocd/config -name "*.yaml" -type f 2>/dev/null | grep -v disabled || true)

if [ -z "$APP_FILES" ]; then
    echo -e "${RED}❌ No ArgoCD manifests found${NC}"
    exit 1
fi

TOTAL_FILES=$(echo "$APP_FILES" | wc -l | tr -d ' ')
echo -e "${BLUE}Found $TOTAL_FILES files to process${NC}"
echo ""

# Counter for updated files
UPDATED_COUNT=0

# Process each file
for file in $APP_FILES; do
    # Check if file contains repoURL field
    if grep -q "repoURL:" "$file" 2>/dev/null; then
        # Check current URL
        CURRENT_URL=$(grep "repoURL:" "$file" | sed 's/.*repoURL: *"\?\([^"]*\)"\?.*/\1/' | head -1)

        # Skip if already correct (ignoring trailing spaces and comments)
        CURRENT_URL_CLEAN=$(echo "$CURRENT_URL" | sed 's/ *#.*//' | tr -d ' ')

        if [ "$CURRENT_URL_CLEAN" != "$REPO_URL" ]; then
            echo -e "${YELLOW}Updating: $file${NC}"
            echo "  Old: $CURRENT_URL_CLEAN"
            echo "  New: $REPO_URL"

            if [ "$DRY_RUN" = false ]; then
                # Update the file
                # Handle various formats:
                # - repoURL: "https://..."
                # - repoURL: https://...
                # - repoURL: https://...  # comment
                # - repoURL: 'https://...'

                sed -i '' "s|repoURL: *[\"'].*github.com/[^\"']*[\"'].*|repoURL: \"$REPO_URL\"|g" "$file"
                sed -i '' "s|repoURL: *https://github.com/[^ ]*.*|repoURL: \"$REPO_URL\"|g" "$file"

                UPDATED_COUNT=$((UPDATED_COUNT + 1))
            fi
            echo ""
        fi
    fi
done

echo "==========================================="
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN COMPLETE${NC}"
    echo "Would have updated files to use: $REPO_URL"
else
    echo -e "${GREEN}✅ Update Complete${NC}"
    echo ""
    echo "Files updated: $UPDATED_COUNT"
    echo "Repository URL: $REPO_URL"
    echo ""
    echo "Next steps:"
    echo "  1. Review changes: git diff"
    echo "  2. Test in dev environment"
    echo "  3. Commit changes: git add -A && git commit -m 'refactor: centralize repository URL management'"
fi
echo "==========================================="

exit 0
