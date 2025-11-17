#!/bin/bash
# Validate that no plain text secrets exist in the repository
#
# This script checks for:
# 1. Plain text passwords, API keys, tokens
# 2. Unencrypted Secret manifests (kind: Secret without SealedSecret)
# 3. Common secret patterns in code and configs
#
# Exit codes:
#   0 - No secrets found
#   1 - Plain text secrets detected

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "==========================================="
echo "Secret Validation - Plain Text Detection"
echo "==========================================="
echo ""

SECRETS_FOUND=0

# Exclude patterns for known safe files
EXCLUDE_PATTERNS=(
    "*.md"
    "*.example"
    ".git/*"
    "docs/*"
    "scripts/validate-secrets.sh"
)

# Build exclude arguments for grep
EXCLUDE_ARGS=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=$pattern"
done

echo "🔍 Checking for plain text secrets..."
echo ""

# Check 1: Look for kind: Secret (should be SealedSecret instead)
echo "1. Checking for unencrypted Secret manifests..."
UNENCRYPTED_SECRETS=$(find apps environments operations -name "*.yaml" -type f 2>/dev/null | \
    xargs grep -l "kind: Secret" 2>/dev/null | \
    xargs grep -L "SealedSecret" 2>/dev/null || true)

if [ -n "$UNENCRYPTED_SECRETS" ]; then
    echo -e "${RED}❌ Found unencrypted Secret manifests:${NC}"
    echo "$UNENCRYPTED_SECRETS"
    SECRETS_FOUND=1
else
    echo -e "${GREEN}✓ No unencrypted Secret manifests${NC}"
fi
echo ""

# Check 2: Look for common secret patterns
echo "2. Checking for common secret patterns..."

# Password patterns
PASSWORDS=$(grep -r $EXCLUDE_ARGS -E "(password|passwd|pwd):\s*['\"]?[a-zA-Z0-9!@#$%^&*]{8,}" . 2>/dev/null | \
    grep -v "password: \"\"" | \
    grep -v "password: changeme" | \
    grep -v "password: your-password" | \
    grep -v "password: \${" | \
    grep -v "# password:" || true)

if [ -n "$PASSWORDS" ]; then
    echo -e "${RED}❌ Found potential plain text passwords:${NC}"
    echo "$PASSWORDS"
    SECRETS_FOUND=1
else
    echo -e "${GREEN}✓ No plain text passwords detected${NC}"
fi
echo ""

# API Key patterns
echo "3. Checking for API keys and tokens..."
API_KEYS=$(grep -r $EXCLUDE_ARGS -E "(api[_-]?key|apikey|api[_-]?secret|token):\s*['\"]?[a-zA-Z0-9_-]{20,}" . 2>/dev/null | \
    grep -v "apikey: \"\"" | \
    grep -v "api_key: changeme" | \
    grep -v "token: \${" | \
    grep -v "# api" || true)

if [ -n "$API_KEYS" ]; then
    echo -e "${RED}❌ Found potential API keys or tokens:${NC}"
    echo "$API_KEYS"
    SECRETS_FOUND=1
else
    echo -e "${GREEN}✓ No API keys or tokens detected${NC}"
fi
echo ""

# Check 4: AWS/GCP/Azure credentials
echo "4. Checking for cloud provider credentials..."
CLOUD_CREDS=$(grep -r $EXCLUDE_ARGS -E "(aws_access_key_id|aws_secret_access_key|gcp_service_account|azure_client_secret):\s*[a-zA-Z0-9/+=]{20,}" . 2>/dev/null | \
    grep -v ": \"\"" | \
    grep -v ": \${" || true)

if [ -n "$CLOUD_CREDS" ]; then
    echo -e "${RED}❌ Found potential cloud credentials:${NC}"
    echo "$CLOUD_CREDS"
    SECRETS_FOUND=1
else
    echo -e "${GREEN}✓ No cloud credentials detected${NC}"
fi
echo ""

# Check 5: Private keys
echo "5. Checking for private keys..."
PRIVATE_KEYS=$(find . -name "*.pem" -o -name "*.key" -o -name "*_rsa" 2>/dev/null | \
    grep -v ".example" | \
    grep -v "docs/" || true)

if [ -n "$PRIVATE_KEYS" ]; then
    echo -e "${YELLOW}⚠ Found private key files:${NC}"
    echo "$PRIVATE_KEYS"
    echo -e "${YELLOW}Note: Ensure these are not committed to version control${NC}"
else
    echo -e "${GREEN}✓ No private key files found${NC}"
fi
echo ""

# Check 6: Database connection strings
echo "6. Checking for database connection strings with embedded credentials..."
DB_CREDS=$(grep -r $EXCLUDE_ARGS -E "(postgres|mysql|mongodb)://[^:]+:[^@]+@" . 2>/dev/null | \
    grep -v "://user:password@" | \
    grep -v "://\${" || true)

if [ -n "$DB_CREDS" ]; then
    echo -e "${RED}❌ Found database connection strings with credentials:${NC}"
    echo "$DB_CREDS"
    SECRETS_FOUND=1
else
    echo -e "${GREEN}✓ No database connection strings with embedded credentials${NC}"
fi
echo ""

# Summary
echo "==========================================="
if [ $SECRETS_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ Validation PASSED - No plain text secrets detected${NC}"
    echo ""
    echo "All secrets appear to be properly managed using:"
    echo "  - SealedSecrets for Kubernetes secrets"
    echo "  - Environment variables for dynamic values"
    echo "  - Terraform outputs for infrastructure secrets"
    exit 0
else
    echo -e "${RED}❌ Validation FAILED - Plain text secrets detected${NC}"
    echo ""
    echo "Action Required:"
    echo "  1. Remove or encrypt all plain text secrets"
    echo "  2. Use SealedSecrets for Kubernetes secrets"
    echo "  3. Use .example files for templates"
    echo "  4. Reference external secret stores"
    echo ""
    echo "See: docs/SECRETS-MANAGEMENT.md for guidance"
    exit 1
fi
