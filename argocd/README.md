# ArgoCD GitOps Automation for Fineract

This directory contains ArgoCD configurations for automated GitOps deployment of Fineract using the app-of-apps pattern.

## Directory Structure

```
argocd/
├── projects/                      # AppProject definitions
│   ├── project-dev.yaml          # Development environment project
│   ├── project-uat.yaml          # UAT environment project
│   └── project-production.yaml   # Production environment project
├── applications/                  # Application manifests
│   ├── minimal-profile/          # Minimal deployment (PostgreSQL + Fineract)
│   │   ├── app-of-apps.yaml     # App-of-apps for minimal profile
│   │   ├── postgresql.yaml       # PostgreSQL application
│   │   └── fineract.yaml         # Fineract application
│   ├── standard-profile/         # Standard deployment (+ Redis)
│   │   ├── app-of-apps.yaml     # App-of-apps for standard profile
│   │   ├── postgresql.yaml       # PostgreSQL application
│   │   ├── redis.yaml            # Redis application
│   │   └── fineract.yaml         # Fineract application
│   └── full-profile/             # Full deployment (+ Kafka + MinIO + Gateway)
│       ├── app-of-apps.yaml     # App-of-apps for full profile
│       ├── postgresql.yaml       # PostgreSQL application
│       ├── redis.yaml            # Redis application
│       ├── kafka.yaml            # Kafka application
│       ├── minio.yaml            # MinIO application
│       ├── apache-gateway.yaml   # Apache Gateway application
│       ├── fineract.yaml         # Fineract application
│       └── fineract-data.yaml    # Data loader (manual sync)
├── config/                        # ArgoCD configuration
│   ├── argocd-cm.yaml            # ArgoCD ConfigMap
│   ├── argocd-rbac-cm.yaml       # RBAC policies
│   └── README.md                 # Configuration documentation
└── README.md                      # This file
```

## Deployment Profiles

### Minimal Profile

**Components**: PostgreSQL + Fineract

**Use cases**:
- Development environments
- Testing
- Minimal resource constraints
- Quick deployments (~5 minutes)

**Resources**: 5 CPUs, 13Gi RAM

**Deploy**:
```bash
kubectl apply -f argocd/applications/minimal-profile/app-of-apps.yaml
```

### Standard Profile (Recommended)

**Components**: PostgreSQL + Redis + Fineract

**Use cases**:
- Production deployments (recommended)
- High-performance requirements
- 60-80% faster than minimal
- Moderate resource availability

**Resources**: 5.5 CPUs, 14Gi RAM

**Deploy**:
```bash
kubectl apply -f argocd/applications/standard-profile/app-of-apps.yaml
```

### Full Profile

**Components**: PostgreSQL + Redis + Kafka + MinIO + Apache Gateway + Fineract

**Use cases**:
- Production with all features
- Event-driven integrations
- Document storage
- OIDC authentication
- Complete observability

**Resources**: 14.5 CPUs, 40Gi RAM

**Deploy**:
```bash
kubectl apply -f argocd/applications/full-profile/app-of-apps.yaml
```

## Quick Start

### Prerequisites

1. **Kubernetes cluster** (v1.24+)
2. **kubectl** configured and working
3. **ArgoCD installed** (see installation below)

### Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Apply Configuration

```bash
# Apply ArgoCD configuration
kubectl apply -f argocd/config/argocd-cm.yaml
kubectl apply -f argocd/config/argocd-rbac-cm.yaml

# Apply projects
kubectl apply -f argocd/projects/

# Restart ArgoCD server to apply config changes
kubectl rollout restart deployment/argocd-server -n argocd
```

### Deploy Fineract

Choose your deployment profile:

```bash
# Option 1: Minimal (development)
kubectl apply -f argocd/applications/minimal-profile/app-of-apps.yaml

# Option 2: Standard (recommended for production)
kubectl apply -f argocd/applications/standard-profile/app-of-apps.yaml

# Option 3: Full (all features)
kubectl apply -f argocd/applications/full-profile/app-of-apps.yaml
```

### Access ArgoCD UI

```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Open browser to https://localhost:8080
# Username: admin
# Password: (from previous command)
```

## App-of-Apps Pattern

The app-of-apps pattern is used to manage multiple applications as a single unit:

```
fineract-minimal (app-of-apps)
├── fineract-postgresql
└── fineract-app
```

```
fineract-standard (app-of-apps)
├── fineract-postgresql
├── fineract-redis
└── fineract-app
```

```
fineract-full (app-of-apps)
├── fineract-postgresql
├── fineract-redis
├── fineract-kafka
├── fineract-minio
├── fineract-gateway
├── fineract-app
└── fineract-data-loader (manual sync)
```

### Sync Waves

Components are deployed in order using sync waves:

1. **Wave 0**: PostgreSQL (foundation)
2. **Wave 5**: Redis (caching layer)
3. **Wave 6**: Kafka (event streaming)
4. **Wave 7**: MinIO (object storage)
5. **Wave 8**: Apache Gateway (routing)
6. **Wave 10**: Fineract application (main app)
7. **Wave 20**: Data loader (manual sync required)

## Projects and RBAC

### Development Project (`fineract-dev`)

- **Namespaces**: `fineract-dev`, `argocd`
- **Source Repos**: All (`*`)
- **Sync Windows**: None (always allowed)
- **Roles**:
  - `admin`: Full access (dev-leads, platform-admins)
  - `read-only`: Read-only (developers, viewers)

### UAT Project (`fineract-uat`)

- **Namespaces**: `fineract-uat`, `argocd`
- **Source Repos**: Specific Git repository
- **Sync Windows**: Mon-Fri, 9 AM - 5 PM
- **Roles**:
  - `admin`: Full access (platform-admins)
  - `deployer`: Sync + read (dev-leads, qa-leads)
  - `read-only`: Read-only (developers, qa-team, viewers)

### Production Project (`fineract-production`)

- **Namespaces**: `fineract-production`, `argocd`
- **Source Repos**: Specific Git repository only
- **Sync Windows**: Tue-Thu, 10 AM - 4 PM (avoid Mon/Fri)
- **Roles**:
  - `admin`: Full access (platform-admins, sre-team)
  - `deployer`: Sync + read (release-managers)
  - `read-only`: Read-only (all teams)

## Automated Sync

All applications use automated sync with the following policies:

```yaml
syncPolicy:
  automated:
    prune: true       # Delete resources not in Git
    selfHeal: true    # Auto-sync when cluster state drifts
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

**Exception**: `fineract-data-loader` requires manual sync (data safety).

## Health Checks

Custom health checks ensure components are truly ready:

### StatefulSets (PostgreSQL, Redis, Kafka, MinIO)

```lua
if obj.status.readyReplicas == obj.status.replicas then
  hs.status = "Healthy"
end
```

### Deployments (Fineract, Apache Gateway)

```lua
if obj.status.updatedReplicas == obj.spec.replicas and
   obj.status.availableReplicas == obj.spec.replicas then
  hs.status = "Healthy"
end
```

### Jobs (Data Loader)

```lua
if obj.status.succeeded > 0 then
  hs.status = "Healthy"
end
```

## Common Operations

### View All Applications

```bash
kubectl get applications -n argocd
```

### Sync an Application

```bash
# With ArgoCD CLI
argocd app sync fineract-app

# With kubectl
kubectl patch application fineract-app -n argocd \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type merge
```

### View Application Status

```bash
# With ArgoCD CLI
argocd app get fineract-app

# With kubectl
kubectl describe application fineract-app -n argocd
```

### View Logs

```bash
# Application controller logs
kubectl logs -f deployment/argocd-application-controller -n argocd

# Server logs
kubectl logs -f deployment/argocd-server -n argocd
```

### Delete an Application

```bash
# Delete application (keeps resources)
kubectl delete application fineract-app -n argocd

# Delete application and all resources
kubectl patch application fineract-app -n argocd \
  -p '{"metadata":{"finalizers":null}}' --type merge
kubectl delete application fineract-app -n argocd
```

## Troubleshooting

### Application stuck in "Progressing"

**Cause**: Resources not becoming healthy

**Solution**:
```bash
# Check application status
kubectl describe application fineract-app -n argocd

# Check pod status
kubectl get pods -n fineract-dev

# Check events
kubectl get events -n fineract-dev --sort-by='.lastTimestamp'
```

### Sync fails with "resource not found"

**Cause**: Kustomize build error or missing base resources

**Solution**:
```bash
# Test Kustomize build locally
kubectl kustomize environments/minimal/

# Check ArgoCD repo server logs
kubectl logs -f deployment/argocd-repo-server -n argocd
```

### RBAC permission denied

**Cause**: User doesn't have permission

**Solution**:
```bash
# Check RBAC policies
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Test permissions
argocd account can-i sync applications fineract-dev/fineract-app
```

### Application out of sync

**Cause**: Manual changes to cluster or Git changes

**Solution**:
```bash
# View diff
argocd app diff fineract-app

# Sync to match Git
argocd app sync fineract-app
```

## Validation

Test the deployment with validation scripts:

```bash
# Test ArgoCD
./scripts/test-argocd.sh

# Test full deployment
./scripts/validate-deployment.sh

# Test Kafka (full profile only)
./scripts/test-kafka.sh

# Test MinIO (full profile only)
./scripts/test-minio.sh
```

## Best Practices

### 1. Always use Git as source of truth

Never make manual changes to cluster. All changes should go through Git.

### 2. Use sync windows for production

Configure sync windows to prevent deployments during high-traffic hours.

### 3. Test in dev/staging first

Always test changes in dev or staging before deploying to production.

### 4. Use AppProjects for isolation

Keep environments isolated using separate AppProjects.

### 5. Enable SSO for production

Use OIDC/SAML for authentication instead of local users.

### 6. Monitor sync status

Set up alerts for applications that are out of sync or unhealthy.

### 7. Use Sealed Secrets

Store encrypted secrets in Git using Bitnami Sealed Secrets for GitOps-native secret management.

### 8. Enable audit logging

Track who deployed what and when for compliance.

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [Health Checks](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)

## Support

For issues or questions:
1. Check the [ArgoCD troubleshooting guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/)
2. Review ArgoCD logs
3. Check application events in Kubernetes
4. Consult the deployment profile READMEs in `environments/`
