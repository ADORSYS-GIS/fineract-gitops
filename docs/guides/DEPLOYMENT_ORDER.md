# Deployment Order - Fineract GitOps

**Quick Reference**: Component deployment sequence with dependencies

---

## Quick Start

```bash
# 1. Deploy infrastructure
kubectl apply -f argocd/applications/cluster-scoped/infrastructure-app-of-apps.yaml

# 2. Create sealed secrets (see docs/CREATE_SEALED_SECRETS.md)

# 3. Deploy environment
kubectl apply -f argocd/applications/dev/app-of-apps.yaml
```

---

## Deployment Layers

```
┌────────────────────────────────────────────────────────────┐
│  Layer 4: Applications (Wave 4-9)                           │
│  Fineract read/write/batch, Web Apps                       │
└──────────┬─────────────────────────────────────────────────┘
           │ requires ↓
┌──────────▼─────────────────────────────────────────────────┐
│  Layer 3: Platform Services (Wave 2-3)                      │
│  Keycloak, Apache Gateway, Message Gateway                 │
└──────────┬─────────────────────────────────────────────────┘
           │ requires ↓
┌──────────▼─────────────────────────────────────────────────┐
│  Layer 2: Data Services (Wave 1)                            │
│  PostgreSQL HA, Redis                                       │
└──────────┬─────────────────────────────────────────────────┘
           │ requires ↓
┌──────────▼─────────────────────────────────────────────────┐
│  Layer 1: Infrastructure (Wave -1 to 0)                     │
│  Operators, Ingress, cert-manager, MinIO, Network Policies │
└────────────────────────────────────────────────────────────┘
```

---

## Sync Wave Details

| Wave | Component | Namespace | Time | Critical? |
|------|-----------|-----------|------|-----------|
| **-1** | Sealed Secrets Controller | kube-system | 2 min | ✅ CRITICAL |
| **-1** | cert-manager | cert-manager | 2 min | ✅ HIGH |
| **-1** | Ingress Nginx | ingress-nginx | 3 min | ✅ HIGH |
| **-1** | CloudNativePG Operator | cnpg-system | 2 min | ✅ CRITICAL (for PG HA) |
| **0** | MinIO | backup | 2 min | ✅ HIGH (for backups) |
| **0** | Velero | velero | 3 min | ⚠️ MEDIUM |
| **0** | Network Policies | per-environment | 1 min | ⚠️ MEDIUM |
| **1** | PostgreSQL HA | per-environment | 5 min | ✅ CRITICAL |
| **1** | Redis | per-environment | 2 min | ✅ HIGH |
| **2** | Keycloak | per-environment | 5 min | ✅ HIGH |
| **3** | Apache Gateway | per-environment | 2 min | ✅ HIGH |
| **3** | Message Gateway | per-environment | 2 min | ⚠️ MEDIUM |
| **4** | Fineract Read | per-environment | 3 min | ✅ CRITICAL |
| **5** | Fineract Write | per-environment | 3 min | ✅ CRITICAL |
| **5** | Fineract Batch | per-environment | 2 min | ⚠️ MEDIUM |
| **6-9** | Web Applications | per-environment | 5 min | ⚠️ LOW |
| **10** | Monitoring (Prometheus, Grafana) | monitoring | 5 min | ⚠️ MEDIUM |
| **10** | Logging (Loki, Promtail) | logging | 3 min | ⚠️ MEDIUM |

**Total Bootstrap Time**: 30-60 minutes per environment

---

## Dependency Matrix

| Component | Depends On |
|-----------|------------|
| PostgreSQL HA | CloudNativePG Operator, MinIO, minio-credentials secret, fineract-postgres-credentials secret |
| Redis | Network Policies (optional) |
| Keycloak | PostgreSQL HA |
| Apache Gateway | Keycloak, Fineract, cert-manager (for SSL) |
| Fineract Read | PostgreSQL HA, Redis, Keycloak |
| Fineract Write | PostgreSQL HA, Redis, Keycloak |
| Fineract Batch | PostgreSQL HA, Redis, Keycloak |
| Web Apps | Apache Gateway |
| Monitoring | All components (to scrape metrics) |
| Logging | All components (to collect logs) |

---

## Deployment Commands

### Option 1: Full Stack (Recommended)

```bash
# Deploy infrastructure
kubectl apply -f argocd/applications/cluster-scoped/infrastructure-app-of-apps.yaml

# Wait for infrastructure (5-10 minutes)
kubectl wait --for=condition=ready pod \
  -l app=sealed-secrets -n kube-system --timeout=300s
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg -n cnpg-system --timeout=300s

# Create secrets (see docs/CREATE_SEALED_SECRETS.md)
# ...

# Deploy dev environment
kubectl apply -f argocd/applications/dev/app-of-apps.yaml

# Watch deployment
watch kubectl get pods -n fineract-dev
```

### Option 2: Component-by-Component

```bash
# Wave -1: Infrastructure operators
kubectl apply -f argocd/applications/cluster-scoped/sealed-secrets-controller.yaml
kubectl apply -f argocd/applications/cluster-scoped/cert-manager.yaml
kubectl apply -f argocd/applications/cluster-scoped/ingress-nginx.yaml
kubectl apply -f argocd/applications/cluster-scoped/cloudnative-pg-operator.yaml

# Wave 0: Storage & networking
kubectl apply -f argocd/applications/cluster-scoped/minio.yaml
kubectl apply -f argocd/applications/cluster-scoped/velero.yaml
kubectl apply -f argocd/applications/dev/network-policies.yaml

# Wave 1: Databases
kubectl apply -f argocd/applications/dev/postgresql-ha.yaml
kubectl apply -f argocd/applications/dev/redis.yaml

# Wave 2: Identity
kubectl apply -f argocd/applications/dev/keycloak.yaml

# Wave 3: Gateways
kubectl apply -f argocd/applications/dev/apache-gateway.yaml
kubectl apply -f argocd/applications/dev/message-gateway.yaml

# Wave 4-5: Fineract
kubectl apply -f argocd/applications/dev/fineract.yaml

# Wave 6-9: Web apps
kubectl apply -f argocd/applications/dev/fineract-web-apps.yaml

# Wave 10: Observability
kubectl apply -f argocd/applications/dev/monitoring.yaml
kubectl apply -f argocd/applications/dev/logging.yaml
```

---

## Environment-Specific Notes

### Development
- **Auto-sync**: Enabled
- **PostgreSQL**: 1 instance (cost-optimized)
- **Sync**: Immediate on git push
- **Downtime**: Acceptable

### UAT
- **Auto-sync**: Enabled
- **PostgreSQL**: 2 instances (HA testing)
- **Sync**: Immediate on git push to main
- **Downtime**: Minimal

### Production
- **Auto-sync**: **DISABLED** (manual approval)
- **PostgreSQL**: 3 instances (maximum HA)
- **Sync**: Manual via `argocd app sync`
- **Downtime**: Zero-downtime deployments

---

## Troubleshooting Deployment Order Issues

### PostgreSQL HA Fails: "Operator not found"

**Cause**: CloudNativePG operator not deployed yet

**Fix**:
```bash
kubectl apply -f argocd/applications/cluster-scoped/cloudnative-pg-operator.yaml
# Wait 2 minutes, then retry PostgreSQL HA deployment
```

### Fineract Fails: "Connection refused to postgres"

**Cause**: PostgreSQL HA not ready yet

**Fix**:
```bash
# Check PostgreSQL cluster status
kubectl get cluster -n fineract-dev
# Wait until STATUS = "Cluster in healthy state"
# Then Fineract will auto-heal (if auto-sync enabled)
```

### Sealed Secret Not Decrypting

**Cause**: Sealed Secrets controller not running

**Fix**:
```bash
kubectl get pods -n kube-system -l app=sealed-secrets
# If not running, deploy:
kubectl apply -f argocd/applications/cluster-scoped/sealed-secrets-controller.yaml
```

---

## Related Documentation

- `docs/INFRASTRUCTURE_DEPLOYMENT.md` - Detailed deployment guide
- `docs/POSTGRESQL_HA_DEPLOYMENT.md` - PostgreSQL HA specifics
- `argocd/applications/README.md` - ArgoCD application guide

---

**Created**: 2025-10-26
**Status**: Production Ready
**Bootstrap Time**: 30-60 min per environment
