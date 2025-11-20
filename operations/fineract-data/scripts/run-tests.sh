#!/bin/bash
#
# Quick Test Script - Run All Phase Tests
#
# This script runs the most important tests to verify all phases work correctly.
#
# Usage:
#   ./scripts/run-tests.sh           # Run all tests
#   ./scripts/run-tests.sh --quick   # Run only fast tests
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

# Parse arguments
QUICK_MODE=false
if [ "$1" == "--quick" ]; then
    QUICK_MODE=true
fi

# Test results
PASSED=0
FAILED=0
SKIPPED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}TEST: $test_name${NC}"
    echo -e "${BLUE}========================================${NC}"

    if eval "$test_command"; then
        echo -e "${GREEN}✓ PASSED${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Fineract Data Management - Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
if [ "$QUICK_MODE" = true ]; then
    echo -e "${YELLOW}Running in QUICK mode (fast tests only)${NC}"
else
    echo -e "${YELLOW}Running FULL test suite${NC}"
fi
echo ""

cd "$PROJECT_DIR"

# =============================================================================
# PHASE 0: Critical Fixes
# =============================================================================

echo -e "${BLUE}PHASE 0: Critical Fixes${NC}"

# Test 1: Data Quality Tests
run_test "Data Quality Tests (pytest)" \
    "cd tests && python3 -m pytest -v --tb=short && cd .."

# =============================================================================
# PHASE 2: Local Validation
# =============================================================================

echo ""
echo -e "${BLUE}PHASE 2: Local Validation${NC}"

# Test 2: YAML Validation - All Files
run_test "YAML Validation - All Files" \
    "./scripts/validate-all.sh"

# Test 3: YAML Validation - Specific Directory
run_test "YAML Validation - Dev Directory" \
    "./scripts/validate_yaml_data.py data/dev"

# =============================================================================
# PHASE 3: Schema Sync
# =============================================================================

if [ "$QUICK_MODE" = false ]; then
    echo ""
    echo -e "${BLUE}PHASE 3: Schema Sync${NC}"

    # Test 4: Schema Sync Script
    run_test "Schema Sync Script (no rebuild)" \
        "./scripts/sync-fineract-schemas.sh"
else
    echo ""
    echo -e "${YELLOW}Skipping Phase 3 tests in quick mode${NC}"
    SKIPPED=$((SKIPPED + 1))
fi

# =============================================================================
# PHASE 4: Error Handling
# =============================================================================

echo ""
echo -e "${BLUE}PHASE 4: Error Handling${NC}"

# Test 5: Pre-flight Validation (Error Detection)
run_test "Pre-flight Validation - Invalid Directory Detection" \
    "! python3 scripts/loaders/offices.py --yaml-dir /nonexistent --fineract-url http://localhost --tenant default 2>&1 | grep -q 'YAML directory not found'"

echo ""
echo -e "${YELLOW}Note: Full Phase 4 tests require running Fineract instance${NC}"
echo -e "${YELLOW}See TESTING_GUIDE.md for complete Phase 4 tests${NC}"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}TEST SUMMARY${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Tests Passed:  ${GREEN}$PASSED${NC}"
echo -e "Tests Failed:  ${RED}$FAILED${NC}"
if [ $SKIPPED -gt 0 ]; then
    echo -e "Tests Skipped: ${YELLOW}$SKIPPED${NC}"
fi
echo -e "${BLUE}============================================${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run full tests: ./scripts/run-tests.sh"
    echo "  2. Test with Fineract: See TESTING_GUIDE.md"
    echo "  3. Push to remote: git push origin deploy-key"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check test output above"
    echo "  2. Review TESTING_GUIDE.md"
    echo "  3. Fix issues and re-run tests"
    echo ""
    exit 1
fi
