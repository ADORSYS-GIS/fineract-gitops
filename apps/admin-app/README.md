# Fineract Admin App

System administration and configuration application for Apache Fineract, providing interfaces for managing the overall platform.

## Overview

The admin-app deployment serves the Fineract admin frontend application as static files through NGINX. All API calls are routed through the Kubernetes Ingress NGINX controller, which handles authentication via OAuth2 Proxy and routing to appropriate Fineract backend services.

**Architecture**:
```
Browser → Ingress NGINX → OAuth2 Proxy → Admin App (static files)
                        ↓
                   Fineract API (read/write services)
```

## Purpose

The Admin App provides:

1.  **System Configuration** - Manage global settings and parameters.
2.  **Product Management** - Configure loan and savings products.
3.  **Charge Management** - Define fees and penalties.
4.  **Scheduler Jobs** - View and manage automated background jobs.
5.  **Data Import/Export** - Perform bulk data operations.

This app is intended for system administrators and supports critical configuration operations.

## Components

### Deployment (deployment.yaml)

**Image**: `ghcr.io/adorsys-gis/fineract-apps/admin-app:df657e7`
- Built from fineract-apps repository
- NGINX-based container serving static files
- Read-only root filesystem for security
- Non-root user (UID 1000)

**Security**:
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- Drops all Linux capabilities
- Seccomp profile: `RuntimeDefault`

**Resources**:
```yaml
requests:
  memory: "128Mi"
  cpu: "50m"
limits:
  memory: "256Mi"
  cpu: "200m"
```

**Init Container**: `copy-assets`
- Copies static assets to writable emptyDir volume
- Enables read-only root filesystem while serving assets
- Resources: 64Mi/128Mi memory, 50m/100m CPU

**Health Checks**:
- **Liveness probe**: HTTP GET / on port 80 (every 10s)
- **Readiness probe**: HTTP GET / on port 80 (every 5s)

### ConfigMap (configmap.yaml)

Configuration for connecting to Fineract API and OAuth2 Proxy is managed in `admin-app-config`.

### Service (service.yaml)

**Type**: ClusterIP
- **Port**: 80 (HTTP)
- **Internal only** - Not exposed directly to internet
- **Accessed via**: Ingress NGINX with OAuth2 authentication

## Deployment

### GitOps Deployment (ArgoCD)

The admin-app is deployed via an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract-dev-admin-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "7"
spec:
  project: fineract-dev
  source:
    repoURL: https://github.com/ADORSYS-GIS/fineract-gitops.git
    targetRevision: eks # Or your target branch
    path: apps/admin-app/base
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Access and Authentication

### Authentication Flow

1.  **User accesses** `https://fineract.example.com/admin`
2.  **Ingress NGINX** intercepts request
3.  **OAuth2 Proxy** handles authentication via Keycloak
4.  **Ingress forwards** to admin-app service
5.  **Frontend JS** makes API calls through Ingress to Fineract backend

### Session Management

Sessions are managed centrally by OAuth2 Proxy and Keycloak.

## Routing

### Access URL

The admin app is accessible at a path like:
```
https://fineract.example.com/admin
```
The Ingress configuration routes `/admin(/|$)(.*)` to the admin-app service.

---

**Namespace**: `fineract-dev` (dev), `fineract-uat` (uat), `fineract-production` (production)
**Component**: Frontend - Admin App
**Managed by**: ArgoCD
**Access**: Via Ingress NGINX with OAuth2 authentication at `/admin`