# Quick Deployment Guide - Minimal Commands

**Purpose**: Deploy all infrastructure and platform services with minimal commands after Terraform

**Target**: Operators deploying to Kubernetes cluster after Terraform provisioning

**Time**: ~45 minutes total

---

## Prerequisites (From Terraform)

✅ Kubernetes cluster running (EKS/GKE/AKS)
✅ ArgoCD installed and accessible
✅ kubectl configured
✅ kubeseal CLI installed (`brew install kubeseal`)

**Verify**:
```bash
kubectl cluster-info
kubectl get pods -n argocd
```

---

## 3-Step Deployment

### Step 1: Create Sealed Secrets (5 minutes)

cd fineract-gitops

# Create all sealed secrets for dev
./scripts/create-all-sealed-secrets.sh dev

# Apply sealed secrets
kubectl apply -f secrets/dev/

# Verify
kubectl get sealedsecrets -n fineract-dev
```

**Output**: 8 sealed secrets created with strong random passwords.

---

### Step 2: Deploy Infrastructure (10 minutes)

```bash
# Deploy all cluster-scoped infrastructure
kubectl apply -f argocd/applications/cluster-scoped/infrastructure-app-of-apps.yaml

# Watch deployment
watch kubectl get pods -n cnpg-system,cert-manager,ingress-nginx,backup,velero

# Wait for ready (or wait manually ~10 min)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system \
  --timeout=600s
```

**What gets deployed**:
- Sealed Secrets Controller
- cert-manager
- Ingress Nginx
- CloudNativePG Operator
- MinIO
- Velero

---

### Step 3: Deploy Platform Services (30 minutes)

```bash
# Deploy all platform services (excludes Fineract & Web Apps)
kubectl apply -f argocd/applications/dev/platform-services-app-of-apps.yaml

# Watch deployment
watch kubectl get pods -n fineract-dev

# Or use ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
```

**What gets deployed**:
- Network Policies
- PostgreSQL HA (1 instance for dev)
- Redis
- Keycloak
- Apache Gateway
- Message Gateway
- Monitoring (Prometheus + Grafana)
- Logging (Loki + Promtail)

**What does NOT get deployed**:
- ❌ Fineract (backend) - deployed from fineract repo CI/CD
- ❌ Web Apps (frontend) - deployed from fineract-apps repo CI/CD

---

## Complete Command Sequence

```bash
# Navigate to gitops repo
cd /Users/guymoyo/dev/fineract-gitops

# 1. Create secrets
./scripts/create-all-sealed-secrets.sh dev
kubectl apply -f secrets/dev/

# 2. Deploy infrastructure
kubectl apply -f argocd/applications/cluster-scoped/infrastructure-app-of-apps.yaml

# 3. Wait for infrastructure (~10 min)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system \
  --timeout=600s

# 4. Deploy platform services
kubectl apply -f argocd/applications/dev/platform-services-app-of-apps.yaml

# 5. Watch deployment (~30 min)
watch kubectl get pods -n fineract-dev

# 6. Deploy Fineract backend (from fineract repo CI/CD or manually)
kubectl apply -f argocd/applications/dev/fineract.yaml

# 7. Deploy Web Apps (from fineract-apps repo CI/CD or manually)
kubectl apply -f argocd/applications/dev/fineract-web-apps.yaml
```

**Total Commands**: 6 commands (platform) + 2 commands (apps)
**Total Time**: ~60 minutes

---

## Verification

### Check Infrastructure

```bash
# Operators
kubectl get pods -n cnpg-system
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx

# Storage
kubectl get pods -n backup  # MinIO
kubectl get pods -n velero

# All should be Running
```

### Check Platform Services

```bash
# Database
kubectl get cluster -n fineract-dev
# Expected: STATUS = "Cluster in healthy state"

kubectl get pods -n fineract-dev -l cnpg.io/cluster=fineract-postgres
# Expected: 1 pod Running (dev has 1 instance)

# Cache
kubectl get pods -n fineract-dev -l app=redis
# Expected: 1 pod Running

# Identity
kubectl get pods -n fineract-dev -l app=keycloak
# Expected: 1+ pods Running

# Gateways
kubectl get pods -n fineract-dev -l app=apache-gateway
# Expected: 2+ pods Running

# Monitoring
kubectl get pods -n monitoring
# Expected: Prometheus, Grafana, AlertManager Running

# Logging
kubectl get pods -n logging
# Expected: Loki, Promtail Running
```

### Access Services

```bash
# Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
# Default: admin/admin (or check sealed secrets output)

# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
# User: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## What's Next?

### Platform is Ready For:
✅ Fineract backend deployment (from fineract repo)
✅ Web Apps deployment (from fineract-apps repo)
✅ Monitoring & alerting
✅ Centralized logging
✅ SSL/TLS certificates
✅ High availability databases
✅ Disaster recovery

### Fineract Backend Deployment

**From fineract repo**:
1. Developer merges code to `develop` branch
2. GitHub Actions builds Docker image
3. GitHub Actions updates `environments/dev/fineract-image-version.yaml` in gitops repo
4. GitHub Actions commits and pushes to gitops repo
5. ArgoCD detects change and deploys Fineract

**Manual trigger** (if needed):
```bash
# Apply Fineract ArgoCD application
kubectl apply -f argocd/applications/dev/fineract.yaml

# Watch deployment
kubectl get pods -n fineract-dev -l app.kubernetes.io/name=fineract -w
```

### Web Apps Deployment

**From fineract-apps repo**:
1. Developer merges code to `develop` branch
2. GitHub Actions builds frontend Docker images
3. GitHub Actions updates `environments/dev/web-apps-image-version.yaml` in gitops repo
4. GitHub Actions commits and pushes to gitops repo
5. ArgoCD detects change and deploys Web Apps

**Manual trigger** (if needed):
```bash
# Apply Web Apps ArgoCD application
kubectl apply -f argocd/applications/dev/fineract-web-apps.yaml

# Watch deployment
kubectl get pods -n fineract-dev -l app.kubernetes.io/name=fineract-web-app -w
```

---

## UAT Deployment

Same process, different environment:

```bash
# 1. Create secrets
./scripts/create-all-sealed-secrets.sh uat
kubectl apply -f secrets/uat/

# 2. Infrastructure (already deployed - cluster-scoped)

# 3. Deploy platform services
kubectl apply -f argocd/applications/uat/platform-services-app-of-apps.yaml

# Watch
watch kubectl get pods -n fineract-uat
```

**Note**: UAT uses 2 PostgreSQL instances for HA testing.

---

## Production Deployment

**IMPORTANT**: Production uses manual sync for safety.

```bash
# 1. Create secrets
./scripts/create-all-sealed-secrets.sh production
kubectl apply -f secrets/production/

# 2. Infrastructure (already deployed - cluster-scoped)

# 3. Deploy platform services app-of-apps
kubectl apply -f argocd/applications/production/platform-services-app-of-apps.yaml

# 4. Manually sync each app via ArgoCD UI or CLI
argocd app sync fineract-production-network-policies
argocd app sync fineract-production-postgresql-ha
argocd app sync fineract-production-redis
argocd app sync fineract-production-keycloak
argocd app sync fineract-production-apache-gateway
argocd app sync fineract-production-message-gateway
argocd app sync fineract-production-monitoring
argocd app sync fineract-production-logging
```

**Note**: Production uses 3 PostgreSQL instances for maximum HA.

---

## Troubleshooting

### Sealed Secrets Not Decrypting

```bash
# Check controller
kubectl get pods -n kube-system -l app=sealed-secrets

# Check logs
kubectl logs -n kube-system -l app=sealed-secrets

# Recreate secret
kubectl delete sealedsecret <name> -n fineract-dev
./scripts/create-all-sealed-secrets.sh dev
kubectl apply -f secrets/dev/<name>-sealed.yaml
```

### PostgreSQL Cluster Not Starting

```bash
# Check operator
kubectl get pods -n cnpg-system

# Check cluster status
kubectl describe cluster fineract-postgres -n fineract-dev

# Check for missing secrets
kubectl get secret fineract-postgres-credentials -n fineract-dev
kubectl get secret minio-credentials -n fineract-dev
```

### ArgoCD App Stuck

```bash
# Check app status
argocd app get fineract-dev-platform-services

# Sync manually
argocd app sync fineract-dev-platform-services

# Check specific resource
kubectl describe pod <pod-name> -n fineract-dev
```

---

## Time Breakdown

| Step | Time | Cumulative |
|------|------|------------|
| Create sealed secrets | 5 min | 5 min |
| Deploy infrastructure | 10 min | 15 min |
| Deploy platform services | 30 min | 45 min |
| **Total** | **45 min** | |

**After completion**:
- Platform is ready for Fineract backend
- Platform is ready for Web Apps
- Monitoring & logging operational
- All dependencies satisfied

---

## Related Documentation

- `DEPLOYMENT_ORDER.md` - Detailed deployment order with sync waves
- `docs/INFRASTRUCTURE_DEPLOYMENT.md` - Comprehensive infrastructure guide
- `POSTGRESQL_HA_DEPLOYMENT.md` - PostgreSQL HA details
- `docs/CREATE_SEALED_SECRETS.md` - Manual secret creation

---

**Created**: 2025-10-26
**Deployment Method**: GitOps with ArgoCD
**Total Commands**: 6 commands
**Total Time**: ~45 minutes
**Fineract & Web Apps**: Deployed separately from their repos
