# ArgoCD Applications - Deployment Guide

This directory contains ArgoCD Application definitions for deploying Fineract components across environments.

---

## Directory Structure

```
argocd/applications/
├── dev/                    # Development environment
├── uat/                    # UAT environment
├── production/             # Production environment
├── minimal-profile/        # Minimal deployment (Fineract only)
├── standard-profile/       # Standard deployment (most components)
└── full-profile/           # Full deployment (all components)
```

---

## PostgreSQL Deployment Options

**You have TWO options for PostgreSQL in each environment:**

### Option 1: Standard PostgreSQL (Single Instance)

- **File**: `postgresql.yaml`
- **Architecture**: Single StatefulSet with 1 pod
- **Cost**: $ (baseline)
- **Availability**: Medium (manual failover)
- **Best for**: Development, small deployments
- **Backup**: CronJob → MinIO (daily)

### Option 2: PostgreSQL HA (CloudNativePG)

- **File**: `postgresql-ha.yaml`
- **Architecture**: CloudNativePG cluster (1-3 instances)
- **Cost**: $ - $$$ (environment-dependent)
- **Availability**: High (automatic failover < 30s)
- **Best for**: Production, critical deployments
- **Backup**: Continuous WAL + MinIO (PITR enabled)

**Environment-specific instance counts**:
- **Dev**: 1 instance (cost-optimized)
- **UAT**: 2 instances (balanced)
- **Production**: 3 instances (maximum availability)

---

## How to Choose PostgreSQL Deployment

### For Each Environment:

**Choose ONE of the following**:

#### Deploy Standard PostgreSQL:
```bash
# Apply app-of-apps (includes postgresql.yaml)
kubectl apply -f argocd/applications/dev/app-of-apps.yaml

# The postgresql.yaml will be automatically synced
```

#### Deploy PostgreSQL HA:
```bash
# Option A: Update app-of-apps to exclude standard PostgreSQL
# Edit app-of-apps.yaml, add to directory.exclude:
#   exclude: 'app-of-apps.yaml|postgresql.yaml'

# Option B: Delete standard PostgreSQL app before deploying HA
argocd app delete fineract-dev-postgresql --cascade=false

# Then deploy HA
kubectl apply -f argocd/applications/dev/postgresql-ha.yaml
```

**⚠️ Important**: Do NOT deploy both `postgresql.yaml` and `postgresql-ha.yaml` to the same namespace - they will conflict!

---

## Switching from Standard to PostgreSQL HA

Follow the migration guide:

```bash
# See detailed migration instructions
cat docs/POSTGRESQL_MIGRATION.md

# Summary:
# 1. Install CloudNativePG operator (once per cluster)
# 2. Create sealed secrets for HA cluster
# 3. Deploy PostgreSQL HA alongside standard
# 4. Migrate data
# 5. Update Fineract connection strings
# 6. Decommission standard PostgreSQL
```

---

## Current Applications Per Environment

### Development (`dev/`)

**Database Layer** (Sync Wave 1):
- `postgresql.yaml` - Standard PostgreSQL OR
- `postgresql-ha.yaml` - PostgreSQL HA (choose one)
- `redis.yaml` - Redis cache

**Platform Services** (Sync Wave 2-3):
- `keycloak.yaml` - Identity & access management
- `apache-gateway.yaml` - API gateway & routing
- `message-gateway.yaml` - SMS/email notifications

**Core Application** (Sync Wave 4-5):
- `fineract.yaml` - Core banking platform
- `web-app-*.yaml` - Frontend applications

**Monitoring** (Sync Wave 10):
- `monitoring.yaml` - Prometheus + Grafana
- `logging.yaml` - Loki + Promtail

### UAT (`uat/`)

Same structure as dev, but:
- Syncs from `main` branch (not `develop`)
- Auto-sync enabled
- 2 PostgreSQL instances (if using HA)

### Production (`production/`)

Same structure as dev/uat, but:
- **Manual sync** (requires approval)
- Sync windows for controlled deployments
- 3 PostgreSQL instances (if using HA)
- Enhanced monitoring & alerting

---

## Cost Comparison Table

| Environment | Standard PostgreSQL | PostgreSQL HA | Savings with Standard |
|-------------|---------------------|---------------|----------------------|
| **Dev** | 1 pod (50Gi) | 1 pod (50Gi) | Same cost |
| **UAT** | 1 pod (50Gi) | 2 pods (150Gi) | 50% cheaper |
| **Production** | 1 pod (50Gi) | 3 pods (300Gi) | 67% cheaper |

**But consider**:
- Standard PostgreSQL: Higher operational risk (manual failover, downtime during failures)
- PostgreSQL HA: Higher availability, automatic recovery, PITR

---

## Deployment Order (Sync Waves)

Applications are deployed in order using ArgoCD sync waves:

```
Wave 1:  PostgreSQL, Redis (databases)
Wave 2:  Keycloak (identity)
Wave 3:  Apache Gateway, Message Gateway (platform services)
Wave 4:  Fineract core (application backend)
Wave 5:  Fineract batch (scheduled jobs)
Wave 6-9: Web applications (frontends)
Wave 10: Monitoring & logging (observability)
Wave 11: Backups & utilities
```

This ensures dependencies are available before dependent services start.

---

## Quick Start

### Deploy Development Environment with PostgreSQL HA

```bash
# 1. Install CloudNativePG operator (once)
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.0.yaml

# 2. Create sealed secrets
./scripts/replace-placeholders.sh
# Follow docs/CREATE_SEALED_SECRETS.md

# 3. Deploy app-of-apps
kubectl apply -f argocd/applications/dev/app-of-apps.yaml

# 4. Switch to PostgreSQL HA
argocd app delete fineract-dev-postgresql --cascade=false
kubectl apply -f argocd/applications/dev/postgresql-ha.yaml

# 5. Watch deployment
argocd app list
kubectl get pods -n fineract-dev -w
```

### Deploy Production with Standard PostgreSQL

```bash
# 1. Create sealed secrets
./scripts/replace-placeholders.sh
# Follow docs/CREATE_SEALED_SECRETS.md for production

# 2. Deploy app-of-apps
kubectl apply -f argocd/applications/production/app-of-apps.yaml

# 3. Manually sync each app (production is manual)
argocd app sync fineract-production-postgresql
argocd app sync fineract-production-redis
# ... etc
```

---

## Monitoring Deployments

```bash
# List all applications
argocd app list

# Get application details
argocd app get fineract-dev-postgresql-ha

# View sync status
argocd app sync-status fineract-dev-postgresql-ha

# Watch live updates
argocd app watch fineract-dev-postgresql-ha
```

---

## Troubleshooting

### PostgreSQL and PostgreSQL HA both deployed

**Error**: Services conflict, both trying to use same namespace

**Fix**:
```bash
# Delete one of them
argocd app delete fineract-dev-postgresql

# Or delete both and redeploy just one
argocd app delete fineract-dev-postgresql fineract-dev-postgresql-ha
kubectl apply -f argocd/applications/dev/postgresql-ha.yaml
```

### CloudNativePG operator not found

**Error**: `error: unable to recognize "postgresql-ha.yaml": no matches for kind "Cluster"`

**Fix**:
```bash
# Install operator
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.0.yaml

# Wait for operator
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system --timeout=300s
```

### Sealed secrets not decrypting

**Error**: `MountVolume.SetUp failed: secret "fineract-postgres-credentials" not found`

**Fix**:
```bash
# Check sealed-secrets controller
kubectl get pods -n kube-system -l app=sealed-secrets

# Recreate sealed secret
# Follow docs/CREATE_SEALED_SECRETS.md
```

---

## Related Documentation

- `docs/POSTGRESQL_MIGRATION.md` - Migration from standard to HA
- `docs/POSTGRESQL_HA_SETUP.md` - PostgreSQL HA detailed setup
- `docs/CREATE_SEALED_SECRETS.md` - Secret management
- `docs/GETTING_STARTED.md` - Initial setup guide

---

**Last Updated**: 2025-10-26
**Maintainer**: Platform Team
**Support**: See docs/ directory for detailed guides
