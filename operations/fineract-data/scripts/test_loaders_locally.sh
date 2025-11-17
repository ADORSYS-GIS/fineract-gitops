#!/bin/bash
# Local testing script for Fineract data loaders
# This script helps test loaders against a local or dev Fineract instance

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data/dev"
LOADERS_DIR="${SCRIPT_DIR}/loaders"

# Default Fineract configuration (can be overridden)
FINERACT_URL="${FINERACT_URL:-https://api.dev.fineract.com}"
TENANT="${TENANT:-default}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test Fineract data loaders locally

OPTIONS:
    -u, --url URL          Fineract API base URL (default: https://api.dev.fineract.com)
    -t, --tenant TENANT    Tenant identifier (default: default)
    -l, --loader LOADER    Run specific loader only (chart_of_accounts, tax_groups, etc.)
    -h, --help             Show this help message

EXAMPLES:
    # Test all loaders against dev environment
    $0

    # Test specific loader
    $0 --loader chart_of_accounts

    # Test against custom Fineract instance
    $0 --url http://localhost:8443/fineract-provider/api/v1

ENVIRONMENT VARIABLES:
    FINERACT_URL    Base URL for Fineract API
    TENANT          Tenant identifier
    FINERACT_USER   Username for authentication (default: mifos)
    FINERACT_PASS   Password for authentication (default: password)

EOF
    exit 0
}

# Parse command line arguments
SPECIFIC_LOADER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            FINERACT_URL="$2"
            shift 2
            ;;
        -t|--tenant)
            TENANT="$2"
            shift 2
            ;;
        -l|--loader)
            SPECIFIC_LOADER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "========================================================================"
echo "Fineract Data Loaders - Local Testing"
echo "========================================================================"
echo "Fineract URL: ${FINERACT_URL}"
echo "Tenant: ${TENANT}"
echo "Data Directory: ${DATA_DIR}"
echo "========================================================================"
echo ""

# Export credentials for loaders to use
export FINERACT_USER="${FINERACT_USER:-mifos}"
export FINERACT_PASS="${FINERACT_PASS:-password}"

# Function to run a loader
run_loader() {
    local loader_name=$1
    local loader_script="${LOADERS_DIR}/${loader_name}.py"
    local yaml_subdir=$2

    echo -e "${YELLOW}Testing ${loader_name}...${NC}"

    if [ ! -f "$loader_script" ]; then
        echo -e "${RED}✗ Loader script not found: ${loader_script}${NC}"
        return 1
    fi

    local yaml_dir="${DATA_DIR}/${yaml_subdir}"
    if [ ! -d "$yaml_dir" ]; then
        echo -e "${YELLOW}⚠ YAML directory not found: ${yaml_dir} - Skipping${NC}"
        return 0
    fi

    # Count YAML files (excluding kustomization.yaml)
    local yaml_count=$(find "$yaml_dir" -name "*.yaml" -type f | grep -v kustomization.yaml | wc -l | tr -d ' ')
    if [ "$yaml_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠ No YAML files found in: ${yaml_dir} - Skipping${NC}"
        return 0
    fi

    echo "  Found ${yaml_count} YAML files to process"

    # Run the loader
    if python3 "$loader_script" \
        --yaml-dir "$yaml_dir" \
        --fineract-url "$FINERACT_URL" \
        --tenant "$TENANT"; then
        echo -e "${GREEN}✓ ${loader_name} completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ ${loader_name} failed${NC}"
        return 1
    fi
}

# Define loaders to run (in dependency order)
declare -A LOADERS=(
    # Wave 1-3: Foundation
    ["code_values"]="codes-and-values"
    ["offices"]="offices"
    ["staff"]="staff"
    ["roles"]="roles"
    ["currency_config"]="system-config"
    ["working_days"]="system-config"

    # Wave 10-21: Accounting
    ["chart_of_accounts"]="accounting/chart-of-accounts"
    ["tax_groups"]="accounting/tax-groups"
    ["floating_rates"]="floating-rates"
    ["savings_product_accounting"]="accounting/savings-product-accounting"
    ["financial_activity_mappings"]="accounting/financial-activity-mappings"

    # Wave 25-30: Products
    ["charges"]="charges"
    ["loan_products"]="products/loan-products"
    ["savings_products"]="products/savings-products"
)

# If specific loader requested, run only that one
if [ -n "$SPECIFIC_LOADER" ]; then
    if [ -z "${LOADERS[$SPECIFIC_LOADER]}" ]; then
        echo -e "${RED}Error: Unknown loader '${SPECIFIC_LOADER}'${NC}"
        echo "Available loaders: ${!LOADERS[@]}"
        exit 1
    fi

    echo "Running specific loader: ${SPECIFIC_LOADER}"
    echo ""
    run_loader "$SPECIFIC_LOADER" "${LOADERS[$SPECIFIC_LOADER]}"
    exit $?
fi

# Run all loaders in order
FAILED_LOADERS=()
PASSED_LOADERS=()

for loader in code_values offices staff roles currency_config working_days \
              chart_of_accounts tax_groups floating_rates \
              savings_product_accounting financial_activity_mappings \
              charges loan_products savings_products; do
    echo ""
    if run_loader "$loader" "${LOADERS[$loader]}"; then
        PASSED_LOADERS+=("$loader")
    else
        FAILED_LOADERS+=("$loader")
    fi
done

# Summary
echo ""
echo "========================================================================"
echo "Test Summary"
echo "========================================================================"
echo -e "Passed: ${GREEN}${#PASSED_LOADERS[@]}${NC}"
echo -e "Failed: ${RED}${#FAILED_LOADERS[@]}${NC}"

if [ ${#FAILED_LOADERS[@]} -gt 0 ]; then
    echo ""
    echo "Failed loaders:"
    for loader in "${FAILED_LOADERS[@]}"; do
        echo -e "  ${RED}✗ ${loader}${NC}"
    done
    exit 1
else
    echo ""
    echo -e "${GREEN}All loaders passed!${NC}"
    exit 0
fi
