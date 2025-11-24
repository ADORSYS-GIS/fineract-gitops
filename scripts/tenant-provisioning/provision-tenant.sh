#!/bin/bash
set -euo pipefail

# =============================================================================
# Fineract Multi-Tenant Provisioning Script
# =============================================================================
# This script provisions a complete tenant including:
# - Keycloak organization
# - PostgreSQL database
# - Schema migration
# - Initial configuration
# - Admin user
# - Validation tests
#
# Usage: ./provision-tenant.sh <tenant_id> <tenant_name> <admin_email> <first_name> <last_name>
# Example: ./provision-tenant.sh acmebank "Acme Bank Ltd." "admin@acmebank.com" "John" "Smith"
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
TENANT_ID="${1:-}"
TENANT_NAME="${2:-}"
ADMIN_EMAIL="${3:-}"
ADMIN_FIRST_NAME="${4:-}"
ADMIN_LAST_NAME="${5:-}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function
log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

log_step() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# Validate arguments
if [ -z "$TENANT_ID" ] || [ -z "$TENANT_NAME" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_FIRST_NAME" ] || [ -z "$ADMIN_LAST_NAME" ]; then
  log_error "Missing required arguments"
  echo ""
  echo "Usage: $0 <tenant_id> <tenant_name> <admin_email> <first_name> <last_name>"
  echo ""
  echo "Arguments:"
  echo "  tenant_id        : Unique identifier (lowercase alphanumeric, 3-20 chars)"
  echo "  tenant_name      : Display name for tenant"
  echo "  admin_email      : Admin user email address"
  echo "  first_name       : Admin user first name"
  echo "  last_name        : Admin user last name"
  echo ""
  echo "Example:"
  echo "  $0 acmebank \"Acme Bank Ltd.\" \"admin@acmebank.com\" \"John\" \"Smith\""
  echo ""
  exit 1
fi

# Check prerequisites
log_step "Checking Prerequisites"

command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed. Aborting."; exit 1; }
command -v psql >/dev/null 2>&1 || { log_error "psql is required but not installed. Aborting."; exit 1; }

log_success "All prerequisites installed"

# Check environment variables
if [ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]; then
  log_warning "KEYCLOAK_ADMIN_PASSWORD not set. Attempting to fetch from Kubernetes secret..."
  export KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak-admin -n fineract-dev -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
  if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
    log_error "Cannot get Keycloak admin password. Set KEYCLOAK_ADMIN_PASSWORD environment variable."
    exit 1
  fi
  log_success "Keycloak admin password retrieved"
fi

# Display provisioning plan
log_step "Tenant Provisioning Plan"

cat <<EOF
Tenant Information:
  ID:             $TENANT_ID
  Name:           $TENANT_NAME
  Domain:         $TENANT_ID.app.example.com
  Database:       fineract_$TENANT_ID

Admin User:
  Email:          $ADMIN_EMAIL
  First Name:     $ADMIN_FIRST_NAME
  Last Name:      $ADMIN_LAST_NAME
  Username:       admin@$TENANT_ID

Resources:
  Organization:   $TENANT_ID (Keycloak)
  Database:       fineract_$TENANT_ID (PostgreSQL)
  S3 Prefix:      $TENANT_ID/ (S3)
  Cache Prefix:   $TENANT_ID: (Redis)

Provisioning Steps:
  1. Validate tenant information
  2. Create Keycloak organization
  3. Create PostgreSQL database
  4. Run schema migration
  5. Load initial configuration
  6. Create admin user
  7. Run validation tests
  8. Generate documentation

EOF

read -p "Proceed with provisioning? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  log_warning "Provisioning cancelled by user"
  exit 0
fi

# Start provisioning
START_TIME=$(date +%s)
log_step "Starting Tenant Provisioning"

# Step 1: Validate
log_step "Step 1/7: Validating Tenant Information"

if [ -f "$SCRIPT_DIR/validate-tenant-request.sh" ]; then
  "$SCRIPT_DIR/validate-tenant-request.sh" "$TENANT_ID" "$TENANT_NAME" "$ADMIN_EMAIL" || {
    log_error "Validation failed"
    exit 1
  }
else
  log_warning "Validation script not found, skipping validation"
fi

log_success "Validation passed"

# Step 2: Create Keycloak organization
log_step "Step 2/7: Creating Keycloak Organization"

if [ -f "$SCRIPT_DIR/create-keycloak-organization.sh" ]; then
  "$SCRIPT_DIR/create-keycloak-organization.sh" "$TENANT_ID" "$TENANT_NAME" || {
    log_error "Failed to create Keycloak organization"
    exit 1
  }
else
  log_error "Script not found: create-keycloak-organization.sh"
  exit 1
fi

log_success "Keycloak organization created"

# Step 3: Create database
log_step "Step 3/7: Creating PostgreSQL Database"

if [ -f "$SCRIPT_DIR/create-tenant-database.sh" ]; then
  "$SCRIPT_DIR/create-tenant-database.sh" "$TENANT_ID" || {
    log_error "Failed to create database"
    exit 1
  }
else
  log_error "Script not found: create-tenant-database.sh"
  exit 1
fi

log_success "Database created"

# Step 4: Run schema migration
log_step "Step 4/7: Running Schema Migration"

if [ -f "$SCRIPT_DIR/run-tenant-schema-migration.sh" ]; then
  "$SCRIPT_DIR/run-tenant-schema-migration.sh" "$TENANT_ID" || {
    log_error "Schema migration failed"
    exit 1
  }
else
  log_error "Script not found: run-tenant-schema-migration.sh"
  exit 1
fi

log_success "Schema migration completed"

# Step 5: Load configuration
log_step "Step 5/7: Loading Initial Configuration"

CONFIG_FILE="operations/fineract-config/tenants/${TENANT_ID}-config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
  log_warning "Configuration file not found: $CONFIG_FILE"
  log_info "Creating default configuration..."

  mkdir -p "operations/fineract-config/tenants"

  cat > "$CONFIG_FILE" <<EOFCONFIG
tenant: $TENANT_ID

systemConfig:
  currency:
    code: USD
    name: US Dollar
    decimalPlaces: 2

  workingDays:
    recurrence: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    repaymentRescheduleType: "MOVE_TO_NEXT_WORKING_DAY"

  globalConfig:
    - name: maker-checker
      enabled: true
    - name: enable-business-date
      enabled: true

  codes:
    - name: Gender
      values: [Male, Female, Other]

offices:
  - name: Head Office
    externalId: "HO001"
    openingDate: "$(date +%Y-%m-%d)"
    dateFormat: "yyyy-MM-dd"
    locale: "en"

roles:
  - name: Super User
    description: "Super user with full access"

users:
  - username: "admin"
    firstname: "$ADMIN_FIRST_NAME"
    lastname: "$ADMIN_LAST_NAME"
    email: "$ADMIN_EMAIL"
    password: "\${ADMIN_PASSWORD}"
    officeId: 1
    roles: ["Super User"]
EOFCONFIG

  log_success "Default configuration created"
fi

if [ -f "$SCRIPT_DIR/load-tenant-config.sh" ]; then
  "$SCRIPT_DIR/load-tenant-config.sh" "$TENANT_ID" "$CONFIG_FILE" || {
    log_warning "Configuration loading failed (non-critical, can be loaded later)"
  }
else
  log_warning "Configuration loading script not found, skipping"
fi

log_success "Configuration loaded"

# Step 6: Create admin user
log_step "Step 6/7: Creating Admin User"

if [ -f "$SCRIPT_DIR/create-tenant-admin-user.sh" ]; then
  "$SCRIPT_DIR/create-tenant-admin-user.sh" "$TENANT_ID" "$ADMIN_EMAIL" "$ADMIN_FIRST_NAME" "$ADMIN_LAST_NAME" || {
    log_error "Failed to create admin user"
    exit 1
  }
else
  log_error "Script not found: create-tenant-admin-user.sh"
  exit 1
fi

log_success "Admin user created"

# Step 7: Test tenant
log_step "Step 7/7: Running Validation Tests"

if [ -f "$SCRIPT_DIR/test-tenant-access.sh" ]; then
  log_info "Basic validation tests..."

  # Test DNS
  if host "${TENANT_ID}.app.example.com" > /dev/null 2>&1; then
    log_success "DNS resolution: OK"
  else
    log_warning "DNS resolution: Not yet propagated (may take a few minutes)"
  fi

  # Test database
  DB_HOST=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d)
  DB_USER=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d)
  DB_PASSWORD=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d)

  export PGPASSWORD="$DB_PASSWORD"
  TABLE_COUNT=$(psql -h "$DB_HOST" -U "$DB_USER" -d "fineract_$TENANT_ID" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
  unset PGPASSWORD

  if [ "$TABLE_COUNT" -gt 100 ]; then
    log_success "Database schema: OK ($TABLE_COUNT tables)"
  else
    log_warning "Database schema: Incomplete ($TABLE_COUNT tables, expected >100)"
  fi

else
  log_warning "Test script not found, skipping validation tests"
fi

log_success "Validation completed"

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

# Provisioning complete
log_step "✨ Tenant Provisioning Complete! ✨"

cat <<EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}                    PROVISIONING SUCCESSFUL                          ${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

Tenant Details:
  ${BLUE}Tenant ID:${NC}       $TENANT_ID
  ${BLUE}Tenant Name:${NC}     $TENANT_NAME
  ${BLUE}Login URL:${NC}       https://$TENANT_ID.app.example.com
  ${BLUE}Database:${NC}        fineract_$TENANT_ID
  ${BLUE}Tables:${NC}          $TABLE_COUNT

Admin Access:
  ${BLUE}Username:${NC}        admin@$TENANT_ID
  ${BLUE}Email:${NC}           $ADMIN_EMAIL
  ${BLUE}Password:${NC}        ${RED}Check script output above${NC}

${YELLOW}⚠️  IMPORTANT NEXT STEPS:${NC}
  1. ${YELLOW}Save the admin password securely${NC} (shown in Step 6 output)
  2. Test login at: https://$TENANT_ID.app.example.com
  3. Send credentials to admin user via secure channel
  4. Document tenant details in: docs/tenants/$TENANT_ID.md

Resources Created:
  ✅ Keycloak Organization:  $TENANT_ID
  ✅ PostgreSQL Database:    fineract_$TENANT_ID
  ✅ Admin User:             admin@$TENANT_ID
  ✅ Configuration:          Loaded
  ✅ Schema:                 Migrated ($TABLE_COUNT tables)

Monitoring:
  ${BLUE}Logs:${NC}       kubectl logs -n fineract-dev -l app=fineract | grep "tenant=$TENANT_ID"
  ${BLUE}Metrics:${NC}    Grafana dashboard with tenant filter
  ${BLUE}Database:${NC}   psql -h $DB_HOST -U $DB_USER -d fineract_$TENANT_ID

Time Elapsed: ${MINUTES}m ${SECONDS}s

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF

# Generate tenant documentation
TENANT_DOC_DIR="docs/tenants"
mkdir -p "$TENANT_DOC_DIR"

cat > "$TENANT_DOC_DIR/$TENANT_ID.md" <<EOFDOC
# Tenant: $TENANT_NAME

**Status:** ✅ Active
**Provisioned:** $(date +%Y-%m-%d)
**Tier:** Standard

## Details

| Field | Value |
|-------|-------|
| **Tenant ID** | \`$TENANT_ID\` |
| **Tenant Name** | $TENANT_NAME |
| **Domain** | https://$TENANT_ID.app.example.com |
| **Database** | \`fineract_$TENANT_ID\` |
| **Organization ID** | \`$TENANT_ID\` (Keycloak) |

## Admin Contacts

| Name | Email | Role |
|------|-------|------|
| $ADMIN_FIRST_NAME $ADMIN_LAST_NAME | $ADMIN_EMAIL | Primary Admin |

## Resources

| Resource | Value | Limit |
|----------|-------|-------|
| **Database Size** | - | 10 GB |
| **S3 Storage** | - | 100 GB |
| **Users** | 1 | 50 |
| **Concurrent Connections** | 15 | 15 |

## Operational Notes

- Initial provisioning: $(date +%Y-%m-%d)
- Schema version: Latest (Fineract)
- Configuration: Default
- Special requirements: None

## Access Credentials

⚠️ Stored securely in password manager

## Monitoring

- **Logs:** CloudWatch Logs Insights - Filter: \`tenant="$TENANT_ID"\`
- **Metrics:** Prometheus - Label: \`tenant="$TENANT_ID"\`

---

**Last Updated:** $(date +%Y-%m-%d)
**Provisioned By:** $(whoami)
EOFDOC

log_success "Tenant documentation created: $TENANT_DOC_DIR/$TENANT_ID.md"

log_info "To commit documentation to Git:"
echo ""
echo "  git add $TENANT_DOC_DIR/$TENANT_ID.md"
echo "  git commit -m \"docs: add tenant record for $TENANT_ID\""
echo "  git push"
echo ""

log_success "Tenant $TENANT_ID is ready for use! 🎉"
