# ArgoCD Sync Waves and Deployment Order

This document describes the ArgoCD sync wave strategy used to orchestrate the Fineract platform deployment, ensuring proper dependency ordering and zero manual intervention.

## Overview

ArgoCD sync waves control the deployment order of applications and resources. Resources are applied in ascending order by sync wave number, with hooks running at specific phases of the sync process.

## Sync Wave Strategy

### Wave -5: Infrastructure Foundation
**ArgoCD Application**: `sealed-secrets`
- **Path**: `infrastructure/sealed-secrets/base`
- **Purpose**: Deploy sealed-secrets controller for secret management
- **Why First**: All other applications depend on sealed secrets for credentials

**Resources**:
- Sealed-secrets controller Deployment
- RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- Sealed-secrets CRD

### Wave -1: Database Infrastructure
**ArgoCD Application**: `fineract-dev-database-init`
- **Path**: `operations/fineract-database-init/base`
- **Purpose**: Create databases and run schema migrations before applications start

**Jobs** (within this wave):
1. **PreSync Wave 5**: `create-databases-job`
   - Creates `fineract_tenants` and `fineract_default` databases
   - Creates `keycloak` database
   - Idempotent (safe to run multiple times)

2. **PreSync Wave 6**: `fineract-schema-migration-job`
   - Runs Liquibase migrations on `fineract_default` database
   - Includes automatic Liquibase lock cleanup (init container)
   - Creates all Fineract tables and initial data
   - Increased retry limit (backoffLimit: 4)

**Why This Order**:
- Databases must exist before schema migrations
- Schema must be complete before Fineract pods start
- Using PreSync hooks ensures these run before any applications

### Wave 0 (Default): Core Infrastructure
**ArgoCD Application**: `fineract-dev-keycloak`
- **Path**: `apps/keycloak/overlays/dev`
- **Purpose**: Deploy Keycloak identity provider

**Resources**:
- Keycloak Deployment
- Keycloak Service
- Keycloak Ingress
- Keycloak ConfigMap
- Sealed Secrets (admin credentials, DB credentials)

**Init Container**:
- `wait-for-keycloak-db`: Verifies Keycloak database exists before starting

**PostSync Hook** (Wave 1): `apply-keycloak-config`
- Runs AFTER Keycloak deployment is healthy
- Uses keycloak-config-cli to import Fineract realm
- Creates OIDC clients (fineract-oauth2-proxy, community-app)
- Configures client roles and mappers

### Wave 1: Authentication Layer
**ArgoCD Application**: `fineract-dev-oauth2-proxy`
- **Path**: `apps/oauth2-proxy/base`
- **Purpose**: Deploy OAuth2 Proxy for authentication

**Init Container**:
- `wait-for-fineract-realm`: Polls Keycloak until Fineract realm is accessible
  - Checks `/realms/fineract` endpoint
  - Verifies OIDC configuration endpoint (.well-known/openid-configuration)
  - Max retries: 60 (5 minutes)

**Why After Keycloak**:
- Requires Fineract realm to exist (created by PostSync hook)
- Needs OIDC client configuration

### Wave 2: Cache Layer
**ArgoCD Application**: `fineract-dev-redis`
- **Path**: `apps/fineract-redis/base`
- **Purpose**: Deploy Redis for Fineract caching

**Resources**:
- Redis StatefulSet
- Redis Service
- Redis ConfigMap
- Sealed Secret (Redis password)

### Wave 3: Application Layer
**ArgoCD Applications**:
- `fineract-dev-write`
- `fineract-dev-read`
- `fineract-dev-batch`

**Paths**: `apps/fineract/overlays/dev`

**Init Container** (All Deployments):
- `wait-for-schema-migration`: Verifies database schema is ready
  - Checks DATABASECHANGELOG table exists
  - Verifies Liquibase lock is NOT held
  - Max retries: 60 (10 minutes)

**Startup Probes**:
- `initialDelaySeconds: 60`
- `periodSeconds: 30`
- `failureThreshold: 80` (40-minute window)
- Allows time for schema migration job to complete

**Why This Order**:
- Requires completed database schema (Wave -1)
- Requires Keycloak realm for OAuth2 (Wave 0 + PostSync)
- Requires Redis for caching (Wave 2)

### Wave 4: Frontend Applications
**ArgoCD Application**: `fineract-dev-community-app`
- **Path**: `apps/fineract-community-app/base`
- **Purpose**: Deploy Mifos Community App (web UI)

**Why Last**:
- Requires Fineract API to be running (Wave 3)
- Requires OAuth2 Proxy for authentication (Wave 1)

## Visual Deployment Flow

```
Wave -5: sealed-secrets controller
           ↓
Wave -1: database-init
         ├─ PreSync Wave 5: create-databases
         └─ PreSync Wave 6: schema-migration (with lock cleanup)
           ↓
Wave  0: keycloak
         └─ PostSync Wave 1: keycloak-config (import realm)
           ↓
Wave  1: oauth2-proxy (waits for realm)
Wave  2: redis
           ↓
Wave  3: fineract-write, fineract-read, fineract-batch
         (all wait for schema migration completion)
           ↓
Wave  4: community-app
```

## Dependency Enforcement Mechanisms

### 1. ArgoCD Sync Waves
- Enforces application-level ordering
- Higher-numbered waves wait for lower-numbered waves to sync

### 2. Init Containers
- Enforces pod-level dependencies
- Pod won't start main container until init container succeeds

**Examples**:
- Fineract pods: `wait-for-schema-migration`
- OAuth2 Proxy: `wait-for-fineract-realm`
- Keycloak: `wait-for-keycloak-db`

### 3. ArgoCD Hooks
- Run at specific sync lifecycle phases
- **PreSync**: Before resources are applied
- **Sync**: During resource application
- **PostSync**: After resources are healthy

**Example**:
- Keycloak realm creation: PostSync (ensures Keycloak is ready first)

### 4. Startup Probes
- Extended failure threshold for long-running initialization
- Prevents pod restart during schema migration
- Example: 80 failures × 30s = 40-minute window

## Best Practices Implemented

### Database Initialization
1. **Separate databases created first** (PreSync Wave 5)
2. **Schema migrations run second** (PreSync Wave 6)
3. **Automatic lock cleanup** (init container in migration job)
4. **Idempotent operations** (safe to retry)
5. **Applications wait** (init container checks schema completion)

### Secrets Management
1. **Sealed-secrets deployed first** (Wave -5)
2. **All secrets sealed in Git** (encrypted, safe to commit)
3. **Automated regeneration** (scripts/regenerate-all-sealed-secrets-automated.sh)
4. **No manual secret creation** (full automation)

### OAuth2/OIDC Flow
1. **Keycloak deployed** (Wave 0)
2. **Realm created when ready** (PostSync hook)
3. **OAuth2 Proxy waits** (init container)
4. **Fineract configured** (JWT issuer, JWK set URI)

### Error Recovery
1. **Increased retry limits** (backoffLimit: 4 for jobs)
2. **Automatic lock cleanup** (Liquibase locks)
3. **Extended timeouts** (startup probes)
4. **Health checks** (init containers verify readiness)

## Troubleshooting

### Schema Migration Issues

**Problem**: Job fails with "Could not acquire change log lock"

**Solution**:
- Init container automatically clears locks before migration
- If manual intervention needed:
  ```sql
  UPDATE DATABASECHANGELOGLOCK
  SET LOCKED = FALSE, LOCKGRANTED = NULL, LOCKEDBY = NULL
  WHERE ID = 1;
  ```

**Check**:
```bash
kubectl logs -n fineract-dev job/fineract-schema-migration
kubectl describe job -n fineract-dev fineract-schema-migration
```

### Fineract Pods Not Starting

**Problem**: Pods stuck in Init:0/1

**Solution**: Check schema migration job completion
```bash
# Check job status
kubectl get jobs -n fineract-dev fineract-schema-migration

# View init container logs
kubectl logs -n fineract-dev deployment/fineract-write -c wait-for-schema-migration
```

**Expected**: Init container waits for DATABASECHANGELOG table and lock release

### OAuth2 Proxy CrashLoopBackOff

**Problem**: OAuth2 Proxy can't find Keycloak realm

**Solution**: Check Keycloak realm creation
```bash
# Check keycloak-config job
kubectl get jobs -n fineract-dev apply-keycloak-config

# View job logs
kubectl logs -n fineract-dev job/apply-keycloak-config

# Test realm endpoint
kubectl run -n fineract-dev test-realm --rm -it --image=curlimages/curl -- \
  curl -f http://keycloak-service:8080/realms/fineract
```

### Sync Wave Order Issues

**Problem**: Applications deploying in wrong order

**Solution**: Check sync wave annotations
```bash
# List all applications with sync waves
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave
```

## Manual Sync Operations

### Sync Specific Wave
```bash
# Sync only database-init (Wave -1)
argocd app sync fineract-dev-database-init

# Force sync with prune
argocd app sync fineract-dev-database-init --prune
```

### Sync All Applications in Order
```bash
# ArgoCD automatically respects sync waves
argocd app sync -l project=fineract-dev
```

### Re-run Database Initialization
```bash
# Delete and re-create the job
kubectl delete job -n fineract-dev fineract-schema-migration
argocd app sync fineract-dev-database-init
```

## Configuration Reference

### Sync Wave Annotations

**In ArgoCD Application**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

**In Kubernetes Resource**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```

### Hook Annotations

**Job Hooks**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync  # or Sync, PostSync
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/hook-delete-policy: HookSucceeded  # Optional: clean up after success
```

## Complete Application Sync Wave List

| Application | Sync Wave | Dependencies |
|-------------|-----------|--------------|
| sealed-secrets | -5 | None |
| database-init | -1 | sealed-secrets |
| keycloak | 0 | database-init, sealed-secrets |
| oauth2-proxy | 1 | keycloak (PostSync) |
| redis | 2 | sealed-secrets |
| fineract-write | 3 | database-init, keycloak, redis |
| fineract-read | 3 | database-init, keycloak, redis |
| fineract-batch | 3 | database-init, keycloak, redis |
| community-app | 4 | fineract-write, oauth2-proxy |

## Automated Deployment Workflow

1. **Initial Setup**:
   ```bash
   # Deploy Terraform infrastructure
   cd terraform/aws
   terraform apply -auto-approve

   # Regenerate sealed secrets
   ../../scripts/regenerate-all-sealed-secrets-automated.sh
   ```

2. **ArgoCD Auto-Sync**:
   - All applications configured with `automated: {prune: true, selfHeal: true}`
   - ArgoCD monitors Git repository
   - Automatically applies changes in sync wave order
   - Self-heals drift from desired state

3. **Zero Manual Intervention**:
   - Database creation: automatic (PreSync job)
   - Schema migration: automatic (PreSync job with lock cleanup)
   - Realm creation: automatic (PostSync hook)
   - Secret distribution: automatic (sealed-secrets)
   - Dependency waiting: automatic (init containers)

## Testing Deployment Order

### Full Deployment Test
```bash
# Delete all applications
argocd app delete -l project=fineract-dev

# Re-create applications (they will sync in wave order)
kubectl apply -f argocd/applications/dev/

# Watch sync progress
watch -n 2 'argocd app list | grep fineract-dev'
```

### Verify Sync Wave Order
```bash
# Check application sync status with waves
argocd app list -o json | jq -r '.[] |
  select(.metadata.labels.project=="fineract-dev") |
  "\(.metadata.annotations["argocd.argoproj.io/sync-wave"] // "0")\t\(.metadata.name)\t\(.status.sync.status)"' |
  sort -n
```

## References

- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [Liquibase Documentation](https://docs.liquibase.com/)
- [Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
