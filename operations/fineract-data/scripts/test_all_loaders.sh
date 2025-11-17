#!/usr/bin/env bash

# Test All Fineract Data Loaders
# Tests all 39 loaders in dependency-ordered sync waves

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FINERACT_URL="${FINERACT_URL:-http://localhost:8443/fineract-provider/api/v1}"
TENANT="${TENANT:-default}"
DRY_RUN=false
CLEANUP=false
VERBOSE=false
SPECIFIC_LOADER=""

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --url URL          Fineract API URL (default: http://localhost:8443/fineract-provider/api/v1)"
    echo "  --tenant TENANT    Tenant identifier (default: default)"
    echo "  --loader LOADER    Test specific loader only"
    echo "  --dry-run          Preview changes without applying (requires dry-run support in loaders)"
    echo "  --cleanup          Remove test entities after loading"
    echo "  --verbose          Show detailed output"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test all loaders"
    echo "  $0 --loader code_values               # Test specific loader"
    echo "  $0 --dry-run --verbose                # Dry run with verbose output"
    echo "  $0 --cleanup                          # Clean up after testing"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            FINERACT_URL="$2"
            shift 2
            ;;
        --tenant)
            TENANT="$2"
            shift 2
            ;;
        --loader)
            SPECIFIC_LOADER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Test if Fineract is accessible
test_fineract_connection() {
    echo -e "${BLUE}Testing Fineract connection...${NC}"
    if curl -f -k -s "${FINERACT_URL}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Fineract is accessible at ${FINERACT_URL}${NC}"
        return 0
    else
        echo -e "${RED}✗ Cannot connect to Fineract at ${FINERACT_URL}${NC}"
        echo -e "${YELLOW}  Make sure Fineract is running. Try: docker-compose up -d${NC}"
        return 1
    fi
}

# Run a loader
run_loader() {
    local loader=$1
    local yaml_dir=$2
    local description=$3

    echo -e "\n${BLUE}Testing: ${loader} (${description})${NC}"

    if [ ! -f "scripts/loaders/${loader}.py" ]; then
        echo -e "${YELLOW}  ⊘ SKIPPED: Loader script not found${NC}"
        ((SKIPPED++))
        return
    fi

    if [ ! -d "${yaml_dir}" ]; then
        echo -e "${YELLOW}  ⊘ SKIPPED: Data directory not found: ${yaml_dir}${NC}"
        ((SKIPPED++))
        return
    fi

    # Build command
    local cmd="python3 scripts/loaders/${loader}.py --yaml-dir ${yaml_dir} --fineract-url ${FINERACT_URL} --tenant ${TENANT}"

    if [ "$DRY_RUN" = true ]; then
        cmd="${cmd} --dry-run"
    fi

    # Execute
    if [ "$VERBOSE" = true ]; then
        if eval "$cmd"; then
            echo -e "${GREEN}  ✓ PASSED${NC}"
            ((PASSED++))
        else
            echo -e "${RED}  ✗ FAILED${NC}"
            ((FAILED++))
        fi
    else
        if eval "$cmd" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ PASSED${NC}"
            ((PASSED++))
        else
            echo -e "${RED}  ✗ FAILED (run with --verbose for details)${NC}"
            ((FAILED++))
        fi
    fi
}

# Main test sequence
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Fineract Data Loaders - Comprehensive Test Suite      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Configuration:"
    echo "  Fineract URL: ${FINERACT_URL}"
    echo "  Tenant:       ${TENANT}"
    echo "  Dry Run:      ${DRY_RUN}"
    echo "  Cleanup:      ${CLEANUP}"
    echo "  Verbose:      ${VERBOSE}"
    echo ""

    # Test connection
    if ! test_fineract_connection; then
        exit 1
    fi

    # If specific loader requested
    if [ -n "$SPECIFIC_LOADER" ]; then
        echo -e "\n${BLUE}Testing specific loader: ${SPECIFIC_LOADER}${NC}"
        run_loader "$SPECIFIC_LOADER" "data/dev" "Specific loader test"
        print_summary
        exit 0
    fi

    echo -e "\n${BLUE}═══ WAVE 1-3: Foundation ═══${NC}"
    run_loader "code_values" "data/dev/codes-and-values" "Code Values"
    run_loader "offices" "data/dev/offices" "Offices"
    run_loader "staff" "data/dev/staff" "Staff"
    run_loader "roles" "data/dev/roles" "Roles"
    run_loader "currency_config" "data/dev/system-config" "Currency Config"
    run_loader "working_days" "data/dev/system-config" "Working Days"

    echo -e "\n${BLUE}═══ WAVE 4-9: System Configuration ═══${NC}"
    run_loader "holidays" "data/dev/calendar/holidays" "Holidays"
    run_loader "data_tables" "data/dev/data-tables" "Data Tables"
    run_loader "payment_types" "data/dev/accounting/payment-types" "Payment Types"
    run_loader "notification_templates" "data/dev/notification-templates" "Notification Templates"
    run_loader "reports" "data/dev/reports" "Reports"
    run_loader "maker_checker" "data/dev/system-config" "Maker-Checker"
    run_loader "sms_gateway" "data/dev/system-config" "SMS Gateway"
    run_loader "scheduler_jobs" "data/dev/system-config" "Scheduler Jobs"
    run_loader "account_number_formats" "data/dev/system-config" "Account Number Formats"
    run_loader "tellers" "data/dev/tellers" "Tellers"

    echo -e "\n${BLUE}═══ WAVE 10-14: Accounting ═══${NC}"
    run_loader "chart_of_accounts" "data/dev/accounting/chart-of-accounts" "Chart of Accounts"
    run_loader "tax_groups" "data/dev/accounting/tax-groups" "Tax Groups"
    run_loader "delinquency_buckets" "data/dev/delinquency/buckets" "Delinquency Buckets"
    run_loader "loan_provisioning" "data/dev/accounting/loan-provisioning" "Loan Provisioning"
    run_loader "floating_rates" "data/dev/floating-rates" "Floating Rates"
    run_loader "fund_sources" "data/dev/accounting/fund-sources" "Fund Sources"
    run_loader "collateral_types" "data/dev/collateral-types" "Collateral Types"
    run_loader "guarantor_types" "data/dev/guarantor-types" "Guarantor Types"

    echo -e "\n${BLUE}═══ WAVE 15: Charges ═══${NC}"
    run_loader "charges" "data/dev/charges" "Charges"

    echo -e "\n${BLUE}═══ WAVE 20-21: Products & Accounting ═══${NC}"
    run_loader "loan_products" "data/dev/products/loan-products" "Loan Products"
    run_loader "savings_products" "data/dev/products/savings-products" "Savings Products"
    run_loader "loan_product_accounting" "data/dev/accounting/loan-product-accounting" "Loan Product Accounting"
    run_loader "savings_product_accounting" "data/dev/accounting/savings-product-accounting" "Savings Product Accounting"
    run_loader "financial_activity_mappings" "data/dev/accounting/financial-activity-mappings" "Financial Activity Mappings"
    run_loader "payment_type_accounting" "data/dev/accounting/payment-type-accounting" "Payment Type Accounting"

    echo -e "\n${BLUE}═══ WAVE 30-34: Demo Entities (DEV/UAT ONLY) ═══${NC}"
    run_loader "clients" "data/dev/clients" "Clients (Demo)"
    run_loader "loan_accounts" "data/dev/accounts/loan-accounts" "Loan Accounts (Demo)"
    run_loader "savings_accounts" "data/dev/accounts/savings-accounts" "Savings Accounts (Demo)"
    run_loader "demo_loan_collateral" "data/dev/loans/loan-collateral" "Loan Collateral (Demo)"
    run_loader "demo_loan_guarantors" "data/dev/loans/loan-guarantors" "Loan Guarantors (Demo)"

    echo -e "\n${BLUE}═══ WAVE 40-42: Demo Transactions (DEV/UAT ONLY) ═══${NC}"
    run_loader "demo_savings_deposits" "data/dev/transactions/savings-deposits" "Savings Deposits (Demo)"
    run_loader "demo_savings_withdrawals" "data/dev/transactions/savings-withdrawals" "Savings Withdrawals (Demo)"
    run_loader "demo_loan_repayments" "data/dev/transactions/loan-repayments" "Loan Repayments (Demo)"

    # Cleanup if requested
    if [ "$CLEANUP" = true ]; then
        echo -e "\n${BLUE}═══ Cleanup ═══${NC}"
        echo -e "${YELLOW}Cleanup functionality not yet implemented${NC}"
        echo -e "${YELLOW}Manual cleanup: Delete test entities via Fineract UI${NC}"
    fi

    print_summary
}

# Print summary
print_summary() {
    local total=$((PASSED + FAILED + SKIPPED))
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                         Test Summary                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Total:   ${total}"
    echo -e "  ${GREEN}Passed:  ${PASSED}${NC}"
    echo -e "  ${RED}Failed:  ${FAILED}${NC}"
    echo -e "  ${YELLOW}Skipped: ${SKIPPED}${NC}"
    echo ""

    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}Some tests failed. Review output above for details.${NC}"
        exit 1
    elif [ $PASSED -eq 0 ]; then
        echo -e "${YELLOW}No tests ran successfully.${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Run main
main
