# User Sync Service - Deployment Guide

## Overview

The Fineract-Keycloak User Sync Service is deployed using GitOps with ArgoCD. This guide covers both manual image builds and automated Kubernetes deployment.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Manual Image Build                        │
│  Developer → Docker Build → Docker Push → Registry          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    GitOps Deployment                         │
│  Git Commit → ArgoCD Sync → Kubernetes Deploy              │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Docker installed locally for image builds
- kubectl configured for cluster access
- ArgoCD CLI installed (optional, for manual sync)
- Access to image registry (when configured)

## Deployment Process

### Step 1: Build Docker Image (Manual)

```bash
# Navigate to service directory
cd operations/keycloak-config/user-sync-service

# Build image
docker build -t fineract-keycloak-sync:latest .

# Tag for registry (when configured)
# docker tag fineract-keycloak-sync:latest <registry>/fineract-keycloak-sync:v1.0.0

# Push to registry (when configured)
# docker push <registry>/fineract-keycloak-sync:v1.0.0
```

**Note**: Image registry setup is deferred. Currently using `:latest` tag with local builds.

### Step 2: Deploy via GitOps

#### Option A: Automatic Deployment (Recommended)

```bash
# Commit kustomization changes
git add operations/keycloak-config/user-sync-service/
git add argocd/applications/operations/user-sync-service.yaml
git commit -m "feat: deploy user-sync-service via ArgoCD"
git push origin develop

# ArgoCD will automatically sync within 3 minutes
# Or trigger manual sync:
argocd app sync user-sync-service
```

#### Option B: Manual Deployment (Testing)

```bash
# Test kustomize build
kubectl kustomize operations/keycloak-config/user-sync-service/overlays/dev

# Apply directly (bypasses ArgoCD)
kubectl apply -k operations/keycloak-config/user-sync-service/overlays/dev

# Verify deployment
kubectl get pods -n fineract-dev -l app=fineract-keycloak-sync
```

### Step 3: Verify Deployment

```bash
# Check pod status
kubectl get pods -n fineract-dev -l app.kubernetes.io/name=fineract-keycloak-sync

# Check service
kubectl get svc -n fineract-dev fineract-keycloak-sync

# View logs
kubectl logs -n fineract-dev deployment/fineract-keycloak-sync

# Test health endpoint
kubectl port-forward -n fineract-dev svc/fineract-keycloak-sync 5000:5000
curl http://localhost:5000/health
```

## Configuration

### Environment Variables (ConfigMap)

Configured via `operations/keycloak-config/user-sync-service/overlays/dev/kustomization.yaml`:

- `KEYCLOAK_URL`: Keycloak server URL (default: http://keycloak-service.keycloak.svc.cluster.local:8080)
- `KEYCLOAK_REALM`: Realm name (default: fineract)
- `ADMIN_CLI_CLIENT_ID`: Admin CLI client ID (default: admin-cli)
- `PORT`: Service port (default: 5000)

### Secrets (Required)

The service requires two Kubernetes secrets:

```bash
# keycloak-client-secrets (admin-cli key)
kubectl create secret generic keycloak-client-secrets \
  --from-literal=admin-cli=<your-admin-cli-secret> \
  -n fineract-dev

# keycloak-admin-credentials (username/password)
kubectl create secret generic keycloak-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=<your-admin-password> \
  -n fineract-dev
```

**Production**: Use External Secrets or Sealed Secrets for secret management.

## Directory Structure

```
operations/keycloak-config/user-sync-service/
├── app/
│   └── sync_service.py           # Flask application
├── base/
│   ├── kustomization.yaml        # Base configuration
│   └── deployment.yaml           # Deployment, Service, ServiceAccount
├── overlays/
│   └── dev/
│       └── kustomization.yaml    # Dev environment overrides
├── Dockerfile                    # Image build configuration
├── requirements.txt              # Python dependencies
├── README.md                     # Service documentation
└── DEPLOYMENT.md                 # This file
```

## Kustomization Structure

### Base Configuration

- **Namespace**: fineract
- **Replicas**: 2 (overridden to 1 in dev)
- **Image**: fineract-keycloak-sync:latest
- **Resources**:
  - Memory: 256Mi request, 512Mi limit
  - CPU: 100m request, 500m limit

### Dev Overlay

- **Namespace**: fineract-dev
- **Replicas**: 1 (reduced for dev)
- **Image Pull Policy**: IfNotPresent
- **Keycloak URL**: Fully qualified cluster DNS

## ArgoCD Integration

### Application Configuration

- **Name**: user-sync-service
- **Source**: `operations/keycloak-config/user-sync-service/overlays/dev`
- **Destination**: fineract-dev namespace
- **Sync Policy**: Automated with self-heal
- **Prune**: Enabled
- **Retry**: 5 attempts with exponential backoff

### ArgoCD Commands

```bash
# Get application status
argocd app get user-sync-service

# Sync application
argocd app sync user-sync-service

# View application resources
argocd app resources user-sync-service

# View application logs
argocd app logs user-sync-service

# Delete application (does not delete resources)
argocd app delete user-sync-service --cascade=false
```

## Updating the Service

### Code Changes

```bash
# 1. Make changes to app/sync_service.py or Dockerfile
# 2. Build new image
docker build -t fineract-keycloak-sync:latest .

# 3. Push to registry (when configured)
# docker push <registry>/fineract-keycloak-sync:v1.0.1

# 4. Update kustomization if needed
# Edit overlays/dev/kustomization.yaml to change image tag

# 5. Commit and push
git add .
git commit -m "feat: update user-sync-service"
git push

# 6. ArgoCD syncs automatically or trigger manually
argocd app sync user-sync-service
```

### Configuration Changes

```bash
# 1. Edit overlays/dev/kustomization.yaml
# 2. Commit and push
git add overlays/dev/kustomization.yaml
git commit -m "config: update user-sync-service config"
git push

# 3. ArgoCD syncs automatically
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -n fineract-dev -l app=fineract-keycloak-sync

# Check logs
kubectl logs -n fineract-dev deployment/fineract-keycloak-sync

# Common issues:
# - ImagePullBackOff: Image not found in registry
# - CrashLoopBackOff: Check logs for Python errors
# - Secret not found: Create required secrets
```

### Image Pull Errors

```bash
# Issue: ImagePullBackOff or ErrImagePull
# Cause: Image not available in registry

# Solution 1: Build image locally on each node
# Solution 2: Push image to registry and update deployment
# Solution 3: Use imagePullPolicy: Never for local testing
```

### Health Check Failures

```bash
# Check health endpoint directly
kubectl port-forward -n fineract-dev svc/fineract-keycloak-sync 5000:5000
curl http://localhost:5000/health

# Expected response:
# {"status": "healthy", "keycloak": "connected"}

# If failing, check Keycloak connectivity and credentials
```

### ArgoCD Sync Issues

```bash
# Check sync status
argocd app get user-sync-service

# Check sync errors
argocd app get user-sync-service --show-operation

# Force sync
argocd app sync user-sync-service --force

# Refresh without sync
argocd app refresh user-sync-service
```

## Scaling

### Manual Scaling

```bash
# Scale deployment
kubectl scale deployment fineract-keycloak-sync -n fineract-dev --replicas=3

# Note: ArgoCD will revert to Git-defined replica count (1 for dev)
```

### GitOps Scaling

```bash
# Edit overlays/dev/kustomization.yaml
# Change replica count in patches section
# Commit and push - ArgoCD will apply changes
```

## Monitoring

### Logs

```bash
# Follow logs
kubectl logs -f -n fineract-dev deployment/fineract-keycloak-sync

# View logs from all replicas
kubectl logs -n fineract-dev -l app=fineract-keycloak-sync --tail=100

# Filter by log level
kubectl logs -n fineract-dev deployment/fineract-keycloak-sync | grep ERROR
```

### Metrics

```bash
# Pod resource usage
kubectl top pod -n fineract-dev -l app=fineract-keycloak-sync

# Service endpoints
kubectl get endpoints -n fineract-dev fineract-keycloak-sync
```

## Rollback

### ArgoCD Rollback

```bash
# List history
argocd app history user-sync-service

# Rollback to previous version
argocd app rollback user-sync-service <revision-id>
```

### Git Rollback

```bash
# Revert commit
git revert <commit-hash>
git push

# ArgoCD syncs automatically
```

## Future Enhancements

- [ ] Image registry integration (ECR, GCR, or GHCR)
- [ ] CI/CD pipeline for automated image builds
- [ ] Image versioning and tagging strategy
- [ ] Production and UAT overlays
- [ ] Horizontal Pod Autoscaler (HPA)
- [ ] Service mesh integration (Istio/Linkerd)
- [ ] External Secrets integration
- [ ] Prometheus metrics export
- [ ] Grafana dashboard

## Support

- Service README: `README.md`
- API Documentation: See `README.md` Section 3
- Keycloak Config: `operations/keycloak-config/`
- Issues: Report at https://github.com/ADORSYS-GIS/fineract-gitops/issues
