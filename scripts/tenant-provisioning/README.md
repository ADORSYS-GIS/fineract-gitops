# Tenant Provisioning Scripts

This directory contains helper scripts for provisioning and managing tenants in the Fineract multi-tenant platform.

## Prerequisites

- `kubectl` configured with cluster access
- `jq` installed
- `psql` client (PostgreSQL client tools)
- Environment variables:
  - `KEYCLOAK_ADMIN_PASSWORD`
  - `OAUTH2_PROXY_CLIENT_SECRET` (for testing)

## Quick Start

### Provision a New Tenant

```bash
# 1. Validate tenant request
./validate-tenant-request.sh acmebank "Acme Bank Ltd." "admin@acmebank.com"

# 2. Create complete tenant (all-in-one)
./provision-tenant.sh acmebank "Acme Bank Ltd." "admin@acmebank.com" "John" "Smith"

# Or run individual steps:
# 2a. Create Keycloak organization
./create-keycloak-organization.sh acmebank "Acme Bank Ltd."

# 2b. Create database
./create-tenant-database.sh acmebank

# 2c. Run schema migration
./run-tenant-schema-migration.sh acmebank

# 2d. Load initial configuration
./load-tenant-config.sh acmebank

# 2e. Create admin user
./create-tenant-admin-user.sh acmebank "admin@acmebank.com" "John" "Smith"

# 2f. Test tenant access
./test-tenant-access.sh acmebank "admin@acmebank" "TempPassword123!"
```

## Scripts

### Provisioning Scripts

| Script | Description | Usage |
|--------|-------------|-------|
| `validate-tenant-request.sh` | Validates tenant information before provisioning | `./validate-tenant-request.sh <tenant_id> <tenant_name> <admin_email>` |
| `provision-tenant.sh` | All-in-one script to provision complete tenant | `./provision-tenant.sh <tenant_id> <name> <email> <first> <last>` |
| `create-keycloak-organization.sh` | Creates Keycloak organization | `./create-keycloak-organization.sh <tenant_id> <tenant_name>` |
| `create-tenant-database.sh` | Creates PostgreSQL database for tenant | `./create-tenant-database.sh <tenant_id>` |
| `run-tenant-schema-migration.sh` | Runs Liquibase migrations for tenant | `./run-tenant-schema-migration.sh <tenant_id>` |
| `load-tenant-config.sh` | Loads initial Fineract configuration | `./load-tenant-config.sh <tenant_id> [config_file]` |
| `create-tenant-admin-user.sh` | Creates admin user in Keycloak | `./create-tenant-admin-user.sh <tenant_id> <email> <first> <last>` |
| `test-tenant-access.sh` | Tests complete tenant functionality | `./test-tenant-access.sh <tenant_id> <username> <password>` |

### Management Scripts (see `../tenant-management/`)

| Script | Description |
|--------|-------------|
| `add-user.sh` | Add additional user to tenant |
| `check-tenant-usage.sh` | Check tenant resource usage |
| `backup-tenant.sh` | Backup tenant data |
| `disable-tenant.sh` | Disable tenant access |
| `delete-tenant.sh` | Permanently delete tenant |

## Environment Setup

```bash
# Set Keycloak admin password
export KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak-admin -n fineract-dev -o jsonpath='{.data.password}' | base64 -d)

# Set OAuth2 Proxy client secret (for testing)
export OAUTH2_PROXY_CLIENT_SECRET=$(kubectl get secret oauth2-proxy-secrets -n fineract-dev -o jsonpath='{.data.client-secret}' | base64 -d)

# Optional: Set custom namespace
export NAMESPACE=fineract-dev
```

## Configuration Files

Tenant configuration files should be placed in:
```
operations/fineract-config/tenants/<tenant_id>-config.yml
```

See `operations/fineract-config/tenants/example-config.yml` for template.

## Troubleshooting

### Script Fails with "command not found"

Ensure all prerequisites are installed:
```bash
# Check kubectl
kubectl version --client

# Check jq
jq --version

# Check psql
psql --version

# Install missing tools
brew install jq postgresql  # macOS
apt-get install jq postgresql-client  # Ubuntu
```

### Cannot connect to Keycloak

```bash
# Verify Keycloak is running
kubectl get pods -n fineract-dev -l app=keycloak

# Test port-forward
kubectl port-forward -n fineract-dev svc/keycloak-service 8080:8080
curl http://localhost:8080/auth/realms/fineract
```

### Database connection errors

```bash
# Get database credentials
kubectl get secret fineract-db-credentials -n fineract-dev -o yaml

# Test connection
kubectl run -it --rm psql-test --image=postgres:15-alpine --restart=Never -- \
  psql -h <host> -U <user> -d postgres -c "SELECT version();"
```

## Examples

### Example 1: Provision Test Tenant

```bash
./provision-tenant.sh \
  testbank \
  "Test Bank Ltd." \
  "admin@testbank.com" \
  "Test" \
  "Admin"
```

### Example 2: Provision Production Tenant

```bash
# 1. Validate first
./validate-tenant-request.sh \
  globalfinance \
  "Global Finance Corporation" \
  "admin@globalfinance.com"

# 2. Provision
./provision-tenant.sh \
  globalfinance \
  "Global Finance Corporation" \
  "admin@globalfinance.com" \
  "Jane" \
  "Doe"

# 3. Verify
./test-tenant-access.sh globalfinance "admin@globalfinance" "<password>"
```

## Security Notes

- All passwords are generated automatically and output to console
- **Save passwords securely** immediately after provisioning
- Store credentials in password manager (1Password, Vault, etc.)
- Never commit passwords to Git
- Use temporary passwords that force change on first login

## Support

For issues or questions:
- Check documentation: `docs/multi-tenant/`
- Review logs: `kubectl logs -n fineract-dev -l app=fineract`
- Contact platform team

---

**Last Updated:** 2025-11-24
