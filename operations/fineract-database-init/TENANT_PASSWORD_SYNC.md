# Fineract Tenant Password Synchronization

## Problem

Schema migration fails with:
```
FATAL: password authentication failed for user "fineract"
```

Yet the `create-fineract-databases` job succeeds.

## Root Cause

Fineract uses a **two-level credential system**:

1. **Tenant Store DB** (`fineract_tenants`): Connected using credentials from Kubernetes secret (`fineract-db-credentials`)
2. **Individual Tenant DBs** (`fineract_default`): Connected using credentials **stored inside** the `fineract_tenants.tenants` table

```
┌─────────────────────────────────────────────────────────────────┐
│                     Fineract Startup                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Connect to fineract_tenants                                 │
│     └── Uses: FINERACT_HIKARI_USERNAME/PASSWORD (from secret)   │
│                                                                 │
│  2. Read tenant configs from tenants table                      │
│     └── SELECT * FROM tenants                                   │
│                                                                 │
│  3. Connect to each tenant DB (e.g., fineract_default)          │
│     └── Uses: schema_username/schema_password FROM tenants table│
│               NOT from environment variables!                   │
└─────────────────────────────────────────────────────────────────┘
```

When the database password is changed in the Kubernetes secret but the `tenants` table still has the old password, the schema migration fails.

## Solution

### Automated Fix (Applied)

The `create-fineract-databases` job now syncs credentials to the `tenants` table:

```yaml
# In create-databases-job.yaml
# After creating databases, update tenant credentials if table exists
UPDATE tenants
SET schema_password = '${PGPASSWORD}',
    schema_server = '${PGHOST}',
    schema_server_port = '${PGPORT}',
    schema_username = '${PGUSER}'
WHERE identifier = 'default';
```

This runs on every deployment (sync-wave: -1), ensuring credentials are synced before schema migration (sync-wave: 6).

### Manual Fix (One-time)

If you need to fix an existing deployment immediately:

**Option A**: Update the password
```sql
-- Connect to your RDS instance
UPDATE fineract_tenants.tenants
SET schema_password = 'YOUR_PASSWORD_FROM_SECRET'
WHERE identifier = 'default';
```

**Option B**: Delete and let Fineract recreate
```sql
DELETE FROM fineract_tenants.tenants WHERE identifier = 'default';
```
Then redeploy - Fineract will recreate the tenant record using environment variables.

**Option C**: Use cleanup script to drop all databases (recommended for full reset)
```bash
# This drops keycloak, fineract_tenants, and fineract_default databases
# Databases will be recreated with correct credentials on next deployment
make cleanup-cluster ENV=dev
```

## Related Files

| File | Purpose |
|------|---------|
| `create-databases-job.yaml` | Creates DBs and syncs tenant credentials (sync-wave: -1) |
| `fineract-schema-migration-job.yaml` | Runs Liquibase migrations (sync-wave: 6) |
| `fineract-db-credentials` secret | Source of truth for DB credentials |
| `scripts/cleanup-cluster.sh` | Drops all Fineract databases for clean reset |

## Deployment Order

```
sync-wave: -1  → create-fineract-databases (creates DBs, syncs tenant password)
sync-wave:  6  → fineract-schema-migration (runs Liquibase)
sync-wave: 10  → fineract application pods
```
