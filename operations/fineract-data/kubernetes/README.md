# Fineract Data Loader - Kubernetes Deployment

Production-ready Kubernetes deployment for Fineract data initialization with **21 automated loaders**.

## ✅ Cleanup Complete

- Old `jobs/` directory removed (backed up to `jobs.backup/`)
- All documentation moved to `kubernetes/docs/`
- Single source of truth maintained
- 21 production-ready loaders available

## Overview

The loaders run as Kubernetes Jobs that:
1. Validate YAML data (init container)
2. Load data into Fineract via REST API (main container)
3. Report success/failure via exit codes
4. Clean up after completion (TTL)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     ArgoCD Application                       │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Kustomization Build                        │
│  • Generates ConfigMaps from scripts and data                │
│  • Applies sync waves for dependency ordering                │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Resources                        │
│                                                              │
│  ConfigMaps:                                                 │
│  ├─ fineract-loader-scripts (Python loaders + validation)   │
│  └─ fineract-data-dev (YAML data files)                     │
│                                                              │
│  Jobs (with sync waves):                                     │
│  ├─ Wave 10: job-chart-of-accounts                          │
│  ├─ Wave 11: job-tax-groups                                 │
│  ├─ Wave 12: job-floating-rates                             │
│  ├─ Wave 20: job-savings-product-accounting                 │
│  └─ Wave 21: job-financial-activity-mappings                │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│               Job Execution (per loader)                     │
│                                                              │
│  Init Container:                                             │
│  └─ validate-yaml: Validates YAML files before loading      │
│                                                              │
│  Main Container:                                             │
│  ├─ Install Python dependencies (pyyaml, requests)          │
│  ├─ Run loader script                                       │
│  └─ Report results                                          │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Fineract API                                │
│  • Creates/updates entities                                  │
│  • Returns success/failure responses                         │
└─────────────────────────────────────────────────────────────┘
```

## Sync Waves

Jobs use ArgoCD sync waves to enforce loading order:

| Wave | Job | Dependencies |
|------|-----|--------------|
| 10 | Chart of Accounts | None |
| 11 | Tax Groups | GL Accounts |
| 12 | Floating Rates | None |
| 20 | Savings Product Accounting | GL Accounts + Products* |
| 21 | Financial Activity Mappings | GL Accounts |

*Note: Products must be created separately before wave 20

## Prerequisites

### 1. Fineract Instance
- Running and accessible Fineract instance
- Admin credentials available

### 2. Kubernetes Secret
Create a secret with Fineract credentials:

```bash
kubectl create secret generic fineract-admin-credentials \
  --namespace fineract-dev \
  --from-literal=username=mifos \
  --from-literal=password=password
```

Or use SealedSecret for GitOps:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: fineract-admin-credentials
  namespace: fineract-dev
spec:
  encryptedData:
    username: <encrypted>
    password: <encrypted>
```

### 3. Update Configuration
Edit job manifests to set your Fineract URL:

```yaml
env:
- name: FINERACT_URL
  value: "https://api.dev.fineract.com"  # Change this
- name: TENANT
  value: "default"  # Change if needed
```

## Deployment Methods

### Method 1: Direct Apply (kubectl)

```bash
# Build and apply with Kustomize
kubectl apply -k .

# Check job status
kubectl get jobs -n fineract-dev -l app=fineract-data-loader

# View logs
kubectl logs -n fineract-dev job/fineract-data-chart-of-accounts

# Delete jobs (if needed)
kubectl delete -k .
```

### Method 2: ArgoCD Application

Create an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract-data-loaders
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fineract-gitops
    targetRevision: main
    path: operations/fineract-data/kubernetes
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - RespectIgnoreDifferences=true
```

Apply:
```bash
kubectl apply -f argocd-application.yaml
```

### Method 3: Helm (Advanced)

Convert to Helm chart for parameterization:

```bash
helm template fineract-data-loaders . \
  --set fineractUrl=https://api.prod.fineract.com \
  --set tenant=production \
  | kubectl apply -f -
```

## Job Configuration

### Resource Limits

Default resource limits per job:
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

Adjust for larger datasets:
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### TTL (Time To Live)

Jobs are automatically cleaned up after 5 minutes:
```yaml
ttlSecondsAfterFinished: 300
```

Adjust if you need logs longer:
```yaml
ttlSecondsAfterFinished: 3600  # 1 hour
```

Or disable cleanup:
```yaml
# ttlSecondsAfterFinished: 300  # Comment out
```

### Retry Policy

Jobs retry up to 3 times on failure:
```yaml
backoffLimit: 3
```

## Monitoring

### Check Job Status

```bash
# List all loader jobs
kubectl get jobs -n fineract-dev -l app=fineract-data-loader

# Watch job progress
kubectl get jobs -n fineract-dev -l app=fineract-data-loader -w

# Check specific job
kubectl get job fineract-data-chart-of-accounts -n fineract-dev
```

### View Logs

```bash
# View logs from completed job
kubectl logs -n fineract-dev job/fineract-data-chart-of-accounts

# View logs from running job
kubectl logs -n fineract-dev -l loader=chart-of-accounts -f

# View validation logs (init container)
kubectl logs -n fineract-dev job/fineract-data-chart-of-accounts -c validate-yaml

# View loader logs (main container)
kubectl logs -n fineract-dev job/fineract-data-chart-of-accounts -c loader
```

### Check Events

```bash
kubectl get events -n fineract-dev --sort-by='.lastTimestamp'
```

## Troubleshooting

### Job Failed - Validation Error

Check init container logs:
```bash
kubectl logs -n fineract-dev job/fineract-data-chart-of-accounts -c validate-yaml
```

Common issues:
- YAML syntax errors
- Missing required fields
- Invalid field values

Fix: Correct YAML files and re-deploy

### Job Failed - Loader Error

Check main container logs:
```bash
kubectl logs -n fineract-dev job/fineract-data-chart-of-accounts -c loader
```

Common issues:
- Authentication failure (check credentials)
- Network connectivity (check Fineract URL)
- Missing dependencies (check GL accounts loaded first)
- Fineract API errors (check Fineract logs)

### Job Stuck in Pending

Check pod status:
```bash
kubectl describe pod -n fineract-dev -l loader=chart-of-accounts
```

Common issues:
- ConfigMap not found
- Secret not found
- Insufficient resources
- Image pull errors

### Re-run Failed Job

```bash
# Delete failed job
kubectl delete job fineract-data-chart-of-accounts -n fineract-dev

# Re-apply
kubectl apply -f job-chart-of-accounts.yaml
```

Or with ArgoCD:
```bash
argocd app sync fineract-data-loaders --resource batch:Job:fineract-data-chart-of-accounts
```

## ConfigMap Size Limits

Kubernetes ConfigMaps have a 1MB size limit. For large datasets:

### Option 1: Split into Multiple ConfigMaps

```yaml
configMapGenerator:
- name: fineract-data-gl-accounts
  files:
  - ../data/dev/accounting/chart-of-accounts/*.yaml

- name: fineract-data-products
  files:
  - ../data/dev/products/*.yaml
```

### Option 2: Use Persistent Volumes

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: fineract-data-pvc
```

### Option 3: Build Custom Image

Create a Docker image with data baked in:

```dockerfile
FROM python:3.11-slim
COPY scripts /scripts
COPY data /data
RUN pip install pyyaml requests
```

## Security Considerations

### 1. Credentials
- ✅ Use Kubernetes Secrets (not ConfigMaps)
- ✅ Use SealedSecrets for GitOps
- ✅ Rotate credentials regularly
- ✅ Use service accounts with minimal permissions

### 2. Network Policies
Restrict loader pods to only access Fineract API:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fineract-data-loader-policy
spec:
  podSelector:
    matchLabels:
      app: fineract-data-loader
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: fineract-api
    ports:
    - protocol: TCP
      port: 8443
```

### 3. RBAC
Use minimal service account permissions (see serviceaccount.yaml)

## Production Checklist

- [ ] Update Fineract URL to production endpoint
- [ ] Update tenant ID if using multi-tenancy
- [ ] Create production credentials secret
- [ ] Test all jobs in staging environment
- [ ] Review resource limits for production scale
- [ ] Configure monitoring and alerting
- [ ] Set appropriate TTL for job cleanup
- [ ] Review sync waves for dependency order
- [ ] Test rollback procedures
- [ ] Document runbooks for failures

## Advanced: Custom Loader Image

For production, consider building a custom image:

```dockerfile
FROM python:3.11-slim

# Install dependencies
RUN pip install --no-cache-dir pyyaml requests

# Copy scripts
COPY scripts/loaders /app/loaders
COPY scripts/validate_yaml_data.py /app/

# Copy data
COPY data/dev /app/data/dev

# Set working directory
WORKDIR /app

# Default command
CMD ["python3", "loaders/chart_of_accounts.py", "--yaml-dir", "/app/data/dev/accounting/chart-of-accounts"]
```

Build and push:
```bash
docker build -t your-registry/fineract-data-loader:v1.0.0 .
docker push your-registry/fineract-data-loader:v1.0.0
```

Update job manifests:
```yaml
containers:
- name: loader
  image: your-registry/fineract-data-loader:v1.0.0
  command:
  - python3
  - loaders/chart_of_accounts.py
  - --yaml-dir
  - /app/data/dev/accounting/chart-of-accounts
```

## Support

For issues:
1. Check job logs
2. Validate YAML files locally
3. Test loader scripts locally
4. Check Fineract API health
5. Review ArgoCD sync status
