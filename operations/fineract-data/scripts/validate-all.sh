#!/bin/bash
#
# Validate All Fineract YAML Data
#
# This script validates all YAML files in the data directory.
# Run this locally before committing to catch errors early.
#
# Usage:
#   ./scripts/validate-all.sh           # Validate all directories
#   ./scripts/validate-all.sh -v        # Verbose output
#   ./scripts/validate-all.sh --help    # Show help
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
VALIDATOR="$SCRIPT_DIR/validate_yaml_data.py"

# Parse arguments
VERBOSE=""
if [ "$1" == "-v" ] || [ "$1" == "--verbose" ]; then
    VERBOSE="-v"
fi

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Validate all Fineract YAML data files"
    echo ""
    echo "Options:"
    echo "  -v, --verbose    Show details for each file"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Validate all data"
    echo "  $0 -v           # Verbose output"
    echo ""
    exit 0
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Fineract YAML Data Validation${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if data directory exists
if [ ! -d "$DATA_DIR" ]; then
    echo -e "${RED}✗ Data directory not found: $DATA_DIR${NC}"
    exit 1
fi

# Check if validator exists
if [ ! -f "$VALIDATOR" ]; then
    echo -e "${RED}✗ Validator script not found: $VALIDATOR${NC}"
    exit 1
fi

# Make validator executable
chmod +x "$VALIDATOR"

# Count total directories
TOTAL_DIRS=0
VALID_DIRS=0
FAILED_DIRS=0

# Find all data subdirectories
for dir in "$DATA_DIR"/*; do
    if [ -d "$dir" ]; then
        # Check if directory has YAML files
        yaml_count=$(find "$dir" -maxdepth 1 -name "*.yaml" | wc -l)
        if [ $yaml_count -gt 0 ]; then
            TOTAL_DIRS=$((TOTAL_DIRS + 1))

            dir_name=$(basename "$dir")
            echo -e "${BLUE}Validating: ${NC}$dir_name ($yaml_count files)"

            # Run validator on this directory
            if "$VALIDATOR" "$dir" $VERBOSE; then
                VALID_DIRS=$((VALID_DIRS + 1))
                echo -e "${GREEN}✓ $dir_name validated successfully${NC}"
            else
                FAILED_DIRS=$((FAILED_DIRS + 1))
                echo -e "${RED}✗ $dir_name validation failed${NC}"
            fi

            echo ""
        fi
    fi
done

# Print summary
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}VALIDATION SUMMARY${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Total directories:  $TOTAL_DIRS"
echo -e "${GREEN}Valid directories:  $VALID_DIRS${NC}"
echo -e "${RED}Failed directories: $FAILED_DIRS${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

if [ $FAILED_DIRS -gt 0 ]; then
    echo -e "${RED}❌ Validation failed${NC}"
    echo -e "${YELLOW}Please fix the errors above before committing${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All validations passed${NC}"
    echo -e "${YELLOW}Your YAML files are ready to commit!${NC}"
    exit 0
fi
