# Complete PostgreSQL Guide for Fineract

This comprehensive guide covers all PostgreSQL deployment options, from standard single-instance to highly available clusters.

---

## Table of Contents

1. [Deployment Options](#deployment-options)
2. [Standard PostgreSQL Setup](#standard-postgresql)
3. [High Availability Setup (CloudNativePG)](#postgresql-high-availability)
4. [Migration Guide](#migration-guide)
5. [Operations & Maintenance](#operations)
6. [Troubleshooting](#troubleshooting)

---

## Deployment Options

Choose the PostgreSQL deployment model that fits your requirements:

### Option 1: Standard PostgreSQL

**Architecture**: Single StatefulSet (1 pod)

**Characteristics**:
- ✅ Simple architecture
- ✅ Lowest cost (baseline)
- ✅ Daily backups to MinIO
- ❌ Single point of failure
- ❌ Manual failover required
- ❌ Downtime during maintenance

**Best for**: Development environments, non-critical workloads

**Deployment**: Already configured in `argocd/applications/*/postgresql.yaml`

### Option 2: PostgreSQL HA (CloudNativePG)

**Architecture**: CloudNativePG cluster with environment-specific scaling

**Characteristics**:
- ✅ Automatic failover (< 30 seconds)
- ✅ Zero-downtime updates
- ✅ Point-in-time recovery (PITR)
- ✅ Connection pooling (PgBouncer)
- ✅ Read scaling (use replicas)
- ✅ Environment-optimized costs
- ⚠️ Requires operator installation
- ⚠️ Higher complexity

**Best for**: Production, UAT, critical workloads

**Deployment**: Available in `argocd/applications/*/postgresql-ha.yaml`

**Environment Configurations**:
- **Development**: 1 instance (cost = 1x baseline)
- **UAT**: 2 instances (cost = 2x baseline)
- **Production**: 3 instances (cost = 3x baseline)

---

## Standard PostgreSQL

### Architecture

```
┌─────────────────┐
│   Fineract      │
│   Applications  │
└────────┬────────┘
         │
         ▼
  ┌──────────────┐
  │ PostgreSQL   │
  │ StatefulSet  │
  │  (1 pod)     │
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │ Persistent   │
  │   Volume     │
  └──────────────┘
```

### Deployment

Standard PostgreSQL is deployed via ArgoCD:

```bash
# Deploy via ArgoCD
kubectl apply -f argocd/applications/dev/postgresql.yaml

# Verify deployment
kubectl get pods -n fineract-dev -l app=postgresql
kubectl get pvc -n fineract-dev
```

### Connection Details

- **Service**: `postgresql.fineract-dev.svc.cluster.local`
- **Port**: `5432`
- **Database**: `fineractdb`
- **User**: From sealed secret `postgresql-credentials`

---

## PostgreSQL High Availability

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Client Applications                    │
│                      (Fineract)                          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
           ┌───────────────────────┐
           │   PgBouncer Pooler    │
           │   (3 replicas)        │
           │   Connection Pooling  │
           └───────────┬───────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
         ▼             ▼             ▼
    ┌────────┐    ┌────────┐    ┌────────┐
    │Primary │◄───│Replica │◄───│Replica │
    │Node 1  │───►│Node 2  │───►│Node 3  │
    └────────┘    └────────┘    └────────┘
         │             │             │
         └─────────────┼─────────────┘
                       │
                       ▼
                 ┌──────────┐
                 │  MinIO   │
                 │ Backups  │
                 └──────────┘

Synchronous Replication: Primary → Replica 1
Asynchronous Replication: Primary → Replica 2
Automatic Failover: < 30 seconds
```

### What is CloudNativePG?

CloudNativePG is a Kubernetes operator that manages PostgreSQL clusters with:
- **Automatic failover**: Promotes replica to primary when primary fails
- **Streaming replication**: Synchronous and asynchronous replication
- **Point-in-time recovery (PITR)**: Restore to any point in time
- **Connection pooling**: Built-in PgBouncer integration
- **Monitoring**: Native Prometheus metrics
- **Backup/restore**: Integrated with S3-compatible storage

### Prerequisites

1. **CloudNativePG Operator** installed in cluster
2. **MinIO** deployed for backups
3. **Sealed Secrets** for credentials
4. **Storage Class** with dynamic provisioning
5. **Monitoring Stack** (optional but recommended)

### Installation Steps

#### Step 1: Install CloudNativePG Operator

**Only needs to be done ONCE per cluster**:

```bash
# Install CloudNativePG operator v1.21
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.0.yaml

# Wait for operator to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system \
  --timeout=300s

# Verify installation
kubectl get pods -n cnpg-system
```

**Expected output**:
```
NAME                                      READY   STATUS    AGE
cloudnative-pg-controller-manager-xxx     1/1     Running   1m
```

#### Step 2: Create Sealed Secrets

```bash
# Application credentials
kubectl create secret generic fineract-postgres-credentials \
  --from-literal=username=fineract \
  --from-literal=password=YOUR_STRONG_PASSWORD \
  --namespace=fineract-dev \
  --dry-run=client -o yaml | \
kubeseal -o yaml > secrets/dev/fineract-postgres-credentials-sealed.yaml

# Superuser credentials
kubectl create secret generic fineract-postgres-superuser \
  --from-literal=username=postgres \
  --from-literal=password=YOUR_SUPERUSER_PASSWORD \
  --namespace=fineract-dev \
  --dry-run=client -o yaml | \
kubeseal -o yaml > secrets/dev/fineract-postgres-superuser-sealed.yaml

# Apply sealed secrets
kubectl apply -f secrets/dev/fineract-postgres-credentials-sealed.yaml
kubectl apply -f secrets/dev/fineract-postgres-superuser-sealed.yaml
```

#### Step 3: Deploy PostgreSQL HA

```bash
# Deploy via ArgoCD
kubectl apply -f argocd/applications/dev/postgresql-ha.yaml

# Watch cluster creation
kubectl get cluster -n fineract-dev -w

# Verify all pods are running
kubectl get pods -n fineract-dev -l cnpg.io/cluster=fineract-postgres
```

### Environment Configurations

#### Development Environment

**Configuration**: 1 instance (cost-optimized)

```yaml
Instances: 1
Storage: 50Gi (data) + 10Gi (WAL)
Memory: 2Gi
CPU: 1000m
PgBouncer: 1 replica
Cost: 1x (same as standard PostgreSQL)
```

**When to use**:
- Development and testing
- Cost is primary concern
- Downtime is acceptable
- No failover needed

#### UAT Environment

**Configuration**: 2 instances (balanced)

```yaml
Instances: 2 (1 primary + 1 replica)
Storage: 75Gi (data) + 15Gi (WAL)
Memory: 3Gi
CPU: 1500m
PgBouncer: 2 replicas
Cost: 2x
```

**When to use**:
- UAT and staging environments
- Need to test failover scenarios
- Balance between cost and availability

#### Production Environment

**Configuration**: 3 instances (full HA)

```yaml
Instances: 3 (1 primary + 2 replicas)
Storage: 100Gi (data) + 20Gi (WAL)
Memory: 4Gi
CPU: 2000m
PgBouncer: 3 replicas
Cost: 3x
```

**When to use**:
- Production workloads
- Maximum availability required
- Read scaling needed
- Zero downtime updates essential

### Service Endpoints

PostgreSQL HA provides multiple service endpoints:

| Service | Purpose | Format |
|---------|---------|--------|
| **rw** | Read-Write (Primary) | `fineract-postgres-rw` |
| **ro** | Read-Only (Any replica) | `fineract-postgres-ro` |
| **r** | Read (Primary or any replica) | `fineract-postgres-r` |
| **pooler** | Connection pooling via PgBouncer | `fineract-postgres-pooler-rw` |

**Connection strings**:
```
# Write operations (via pooler - recommended)
postgresql://fineract-postgres-pooler-rw.fineract-dev.svc.cluster.local:5432/fineractdb

# Direct to primary
postgresql://fineract-postgres-rw.fineract-dev.svc.cluster.local:5432/fineractdb

# Read-only queries
postgresql://fineract-postgres-ro.fineract-dev.svc.cluster.local:5432/fineractdb
```

---

## Migration Guide

### Overview

Migrate from standard PostgreSQL to PostgreSQL HA with minimal downtime.

**Estimated Time**: 2-4 hours per environment
**Risk Level**: Medium (with proper backup and testing)

### What Changes?

| Aspect | Standard PostgreSQL | PostgreSQL HA |
|--------|---------------------|---------------|
| **Architecture** | Single StatefulSet | CloudNativePG Cluster |
| **Instances** | 1 pod | 1-3 pods (environment-dependent) |
| **Failover** | Manual | Automatic (< 30s) |
| **Operator** | None | CloudNativePG operator required |
| **Service Names** | `postgresql` | `fineract-postgres-rw`, `fineract-postgres-ro` |
| **Connection Pooling** | None | PgBouncer (recommended) |
| **Backups** | CronJob → MinIO | CloudNativePG Barman → MinIO |
| **PITR** | No | Yes (any second) |

### Migration Steps

#### Phase 1: Preparation

1. **Verify prerequisites** (see Installation Steps above)
2. **Backup current database**:
   ```bash
   kubectl exec -it postgresql-0 -n fineract-dev -- \
     pg_dumpall -U postgres > backup_$(date +%Y%m%d_%H%M%S).sql
   ```
3. **Create sealed secrets** (if not already done)
4. **Test in dev environment first**

#### Phase 2: Deploy PostgreSQL HA

1. **Deploy PostgreSQL HA** (without touching standard PostgreSQL yet):
   ```bash
   kubectl apply -f argocd/applications/dev/postgresql-ha.yaml
   ```

2. **Wait for cluster to be ready**:
   ```bash
   kubectl get cluster -n fineract-dev -w
   # Wait for status: Ready
   ```

#### Phase 3: Data Migration

1. **Restore backup to new cluster**:
   ```bash
   kubectl exec -it fineract-postgres-1 -n fineract-dev -- \
     psql -U postgres < backup_YYYYMMDD_HHMMSS.sql
   ```

2. **Verify data integrity**:
   ```bash
   # Check table counts
   kubectl exec -it fineract-postgres-1 -n fineract-dev -- \
     psql -U postgres -d fineractdb -c "\dt"

   # Compare row counts
   kubectl exec -it fineract-postgres-1 -n fineract-dev -- \
     psql -U postgres -d fineractdb -c "SELECT COUNT(*) FROM users;"
   ```

#### Phase 4: Update Applications

1. **Update Fineract environment variables** to use new service:
   ```yaml
   # Change from:
   SPRING_DATASOURCE_URL: jdbc:postgresql://postgresql:5432/fineractdb

   # To (with connection pooling):
   SPRING_DATASOURCE_URL: jdbc:postgresql://fineract-postgres-pooler-rw:5432/fineractdb
   ```

2. **Rolling restart Fineract**:
   ```bash
   kubectl rollout restart deployment/fineract-read -n fineract-dev
   kubectl rollout restart deployment/fineract-write -n fineract-dev
   kubectl rollout restart deployment/fineract-batch -n fineract-dev
   ```

3. **Verify connectivity**:
   ```bash
   kubectl logs -n fineract-dev -l app=fineract-write --tail=50
   # Look for successful database connections
   ```

#### Phase 5: Cleanup

1. **Monitor for 24-48 hours** to ensure stability
2. **Remove old PostgreSQL deployment**:
   ```bash
   kubectl delete -f argocd/applications/dev/postgresql.yaml
   ```
3. **Clean up old PVC** (after final backup):
   ```bash
   kubectl delete pvc data-postgresql-0 -n fineract-dev
   ```

### Rollback Plan

If issues occur during migration:

1. **Revert Fineract environment variables** to old service
2. **Restart Fineract pods**
3. **Keep both databases running** until stable
4. **Restore from backup** if data corruption occurs

---

## Operations

### Daily Operations

#### Check Cluster Status

```bash
# Cluster overview
kubectl get cluster -n fineract-dev

# Pod status
kubectl get pods -n fineract-dev -l cnpg.io/cluster=fineract-postgres

# Primary instance
kubectl get cluster fineract-postgres -n fineract-dev -o jsonpath='{.status.currentPrimary}'
```

#### Connection Pooling Stats

```bash
# PgBouncer statistics
kubectl exec -it fineract-postgres-pooler-rw-0 -n fineract-dev -- \
  psql -p 5432 -U postgres -c "SHOW STATS;"
```

#### View Replication Status

```bash
# Check replication lag
kubectl exec -it fineract-postgres-1 -n fineract-dev -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Backup Operations

#### Manual Backup

```bash
# Trigger immediate backup
kubectl create job --from=cronjob/postgresql-backup manual-backup-$(date +%s) -n backup
```

#### Restore from Backup

See CloudNativePG documentation for point-in-time recovery procedures.

### Failover Testing

#### Simulate Primary Failure

```bash
# Delete current primary pod (automatic failover will occur)
CURRENT_PRIMARY=$(kubectl get cluster fineract-postgres -n fineract-dev -o jsonpath='{.status.currentPrimary}')
kubectl delete pod $CURRENT_PRIMARY -n fineract-dev

# Watch failover (should complete in < 30 seconds)
kubectl get cluster fineract-postgres -n fineract-dev -w
```

---

## Troubleshooting

### Common Issues

#### Pods Not Starting

**Symptoms**: Pods stuck in Pending or CrashLoopBackOff

**Solutions**:
1. Check PVC creation:
   ```bash
   kubectl get pvc -n fineract-dev
   ```
2. Check storage class:
   ```bash
   kubectl get storageclass
   ```
3. Review pod events:
   ```bash
   kubectl describe pod fineract-postgres-1 -n fineract-dev
   ```

#### Replication Lag

**Symptoms**: Replicas falling behind primary

**Solutions**:
1. Check replication status:
   ```bash
   kubectl exec -it fineract-postgres-1 -n fineract-dev -- \
     psql -U postgres -c "SELECT * FROM pg_stat_replication;"
   ```
2. Check resource utilization:
   ```bash
   kubectl top pods -n fineract-dev -l cnpg.io/cluster=fineract-postgres
   ```
3. Review CloudNativePG logs:
   ```bash
   kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
   ```

#### Connection Pool Exhaustion

**Symptoms**: Applications getting connection timeouts

**Solutions**:
1. Check PgBouncer stats:
   ```bash
   kubectl exec -it fineract-postgres-pooler-rw-0 -n fineract-dev -- \
     psql -p 5432 -U postgres -c "SHOW POOLS;"
   ```
2. Increase pool size in PgBouncer configuration
3. Review application connection settings

#### Backup Failures

**Symptoms**: Backups not completing or failing

**Solutions**:
1. Check MinIO connectivity:
   ```bash
   kubectl get pods -n backup -l app=minio
   ```
2. Verify MinIO credentials:
   ```bash
   kubectl get secret minio-credentials -n backup
   ```
3. Check backup logs:
   ```bash
   kubectl logs -n fineract-dev -l cnpg.io/cluster=fineract-postgres --tail=100 | grep backup
   ```

### Getting Help

- **CloudNativePG Documentation**: https://cloudnative-pg.io/documentation/
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/
- **PgBouncer Documentation**: https://www.pgbouncer.org/

---

## Reference

### File Locations

- **ArgoCD Applications**: `argocd/applications/*/postgresql-ha.yaml`
- **App Manifests**: `apps/postgresql-ha/`
- **Sealed Secrets**: `secrets/*/fineract-postgres-*-sealed.yaml`
- **Backup Jobs**: `apps/postgresql/base/backup-cronjob.yaml`

### Related Documentation

- [Secrets Management](../SECRETS_MANAGEMENT.md)
- [Getting Started Guide](../GETTING_STARTED.md)
- [Operations Runbooks](../operations/)

---

**Last Updated:** 2025-10-28
**CloudNativePG Version:** 1.21.0
**PostgreSQL Version:** 15
