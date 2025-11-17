#!/bin/bash
# Validate ArgoCD Application manifests
#
# This script checks:
# 1. All Application manifests are valid YAML
# 2. Required fields are present
# 3. Sync waves are properly configured
# 4. Project references exist
# 5. Source paths exist in repository
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation failures detected

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "ArgoCD Application Validation"
echo "========================================="
echo ""

VALIDATION_FAILED=0
TOTAL_APPS=0
VALID_APPS=0

# Find all ArgoCD Application manifests
APP_FILES=$(find argocd/applications -name "*.yaml" -not -path "*/disabled/*" 2>/dev/null || true)

if [ -z "$APP_FILES" ]; then
    echo -e "${RED}❌ No ArgoCD Application manifests found${NC}"
    exit 1
fi

echo "Found $(echo "$APP_FILES" | wc -l | tr -d ' ') ArgoCD Applications"
echo ""

# Function to validate a single application
validate_app() {
    local file=$1
    local app_name=$(basename "$file" .yaml)

    echo -e "${BLUE}Validating: $file${NC}"

    # Check 1: Valid YAML
    if ! yq eval '.' "$file" > /dev/null 2>&1; then
        echo -e "${RED}  ❌ Invalid YAML syntax${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Valid YAML${NC}"

    # Check 2: Is it an ArgoCD Application?
    local kind=$(yq eval '.kind' "$file")
    if [ "$kind" != "Application" ]; then
        echo -e "${YELLOW}  ⚠ Not an Application manifest (kind: $kind)${NC}"
        return 0
    fi

    # Check 3: Has metadata.name
    local name=$(yq eval '.metadata.name' "$file")
    if [ "$name" == "null" ] || [ -z "$name" ]; then
        echo -e "${RED}  ❌ Missing metadata.name${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Has metadata.name: $name${NC}"

    # Check 4: Has spec.project
    local project=$(yq eval '.spec.project' "$file")
    if [ "$project" == "null" ] || [ -z "$project" ]; then
        echo -e "${RED}  ❌ Missing spec.project${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Project: $project${NC}"

    # Check 5: Verify project exists
    local project_file="argocd/projects/project-${project#fineract-}.yaml"
    if [ "$project" != "default" ] && [ ! -f "$project_file" ]; then
        echo -e "${YELLOW}  ⚠ Project file not found: $project_file${NC}"
    fi

    # Check 6: Has source configuration
    local repo=$(yq eval '.spec.source.repoURL' "$file")
    if [ "$repo" == "null" ] || [ -z "$repo" ]; then
        echo -e "${RED}  ❌ Missing spec.source.repoURL${NC}"
        return 1
    fi

    local path=$(yq eval '.spec.source.path' "$file")
    if [ "$path" == "null" ] || [ -z "$path" ]; then
        echo -e "${RED}  ❌ Missing spec.source.path${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Source path: $path${NC}"

    # Check 7: Verify source path exists (if local repo)
    if [[ "$repo" == *"fineract-gitops"* ]]; then
        if [ ! -d "$path" ]; then
            echo -e "${YELLOW}  ⚠ Source path does not exist: $path${NC}"
        else
            echo -e "${GREEN}  ✓ Source path exists${NC}"
        fi
    fi

    # Check 8: Has destination
    local server=$(yq eval '.spec.destination.server' "$file")
    local namespace=$(yq eval '.spec.destination.namespace' "$file")

    if [ "$server" == "null" ] || [ -z "$server" ]; then
        echo -e "${RED}  ❌ Missing spec.destination.server${NC}"
        return 1
    fi

    if [ "$namespace" == "null" ] || [ -z "$namespace" ]; then
        echo -e "${YELLOW}  ⚠ Missing spec.destination.namespace${NC}"
    else
        echo -e "${GREEN}  ✓ Destination: $namespace${NC}"
    fi

    # Check 9: Check sync wave annotation
    local sync_wave=$(yq eval '.metadata.annotations."argocd.argoproj.io/sync-wave"' "$file")
    if [ "$sync_wave" == "null" ] || [ -z "$sync_wave" ]; then
        echo -e "${YELLOW}  ⚠ No sync-wave annotation (will default to wave 0)${NC}"
    else
        echo -e "${GREEN}  ✓ Sync wave: $sync_wave${NC}"
    fi

    # Check 10: Verify syncPolicy is defined
    local sync_policy=$(yq eval '.spec.syncPolicy' "$file")
    if [ "$sync_policy" == "null" ]; then
        echo -e "${YELLOW}  ⚠ No syncPolicy defined (manual sync required)${NC}"
    else
        local automated=$(yq eval '.spec.syncPolicy.automated' "$file")
        if [ "$automated" != "null" ]; then
            echo -e "${GREEN}  ✓ Automated sync enabled${NC}"
        else
            echo -e "${YELLOW}  ⚠ Manual sync required${NC}"
        fi
    fi

    echo ""
    return 0
}

# Validate all applications
for file in $APP_FILES; do
    TOTAL_APPS=$((TOTAL_APPS + 1))
    if validate_app "$file"; then
        VALID_APPS=$((VALID_APPS + 1))
    else
        VALIDATION_FAILED=1
    fi
done

# Check for common issues across all apps
echo "========================================="
echo "Cross-Application Checks"
echo "========================================="
echo ""

# Check for duplicate application names
echo "Checking for duplicate application names..."
DUPLICATE_NAMES=$(find argocd/applications -name "*.yaml" -not -path "*/disabled/*" -exec yq eval '.metadata.name' {} \; 2>/dev/null | sort | uniq -d)

if [ -n "$DUPLICATE_NAMES" ]; then
    echo -e "${RED}❌ Duplicate application names found:${NC}"
    echo "$DUPLICATE_NAMES"
    VALIDATION_FAILED=1
else
    echo -e "${GREEN}✓ No duplicate application names${NC}"
fi
echo ""

# Check sync wave distribution
echo "Sync wave distribution:"
find argocd/applications -name "*.yaml" -not -path "*/disabled/*" -exec yq eval '.metadata.annotations."argocd.argoproj.io/sync-wave"' {} \; 2>/dev/null | grep -v "null" | sort -n | uniq -c | sed 's/^/  /'
echo ""

# Summary
echo "========================================="
echo "Summary"
echo "========================================="
echo "Total Applications: $TOTAL_APPS"
echo "Valid Applications: $VALID_APPS"
echo "Failed Validations: $((TOTAL_APPS - VALID_APPS))"
echo ""

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All ArgoCD Applications are valid${NC}"
    exit 0
else
    echo -e "${RED}❌ Validation failed - please fix the errors above${NC}"
    exit 1
fi
