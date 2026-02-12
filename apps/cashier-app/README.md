# Fineract Cashier App

Teller and cashiering operations application for Apache Fineract, providing interfaces for daily branch transactions.

## Overview

The cashier-app deployment serves the Fineract cashier frontend application as static files through NGINX. All API calls are routed through the Kubernetes Ingress NGINX controller, which handles authentication via OAuth2 Proxy and routing to appropriate Fineract backend services.

**Architecture**:
```
Browser → Ingress NGINX → OAuth2 Proxy → Cashier App (static files)
                        ↓
                   Fineract API (read/write services)
```

## Purpose

The Cashier App provides:

1.  **Deposits & Withdrawals** - Handle cash and check transactions.
2.  **Till Management** - Manage cash drawers and daily balancing.
3.  **Client Look-up** - Search for and view client account details.
4.  **Transaction Posting** - Post financial transactions to client accounts.
5.  **End-of-Day Reporting** - Generate reports for daily cashiering activities.

This app supports both read and write operations for teller and cashiering functions.

## Components

### Deployment (deployment.yaml)

**Image**: `ghcr.io/adorsys-gis/fineract-apps/cashier-app:df657e7`
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

Configuration for connecting to Fineract API and OAuth2 Proxy is managed in `cashier-app-config`.

### Service (service.yaml)

**Type**: ClusterIP
- **Port**: 80 (HTTP)
- **Internal only** - Not exposed directly to internet
- **Accessed via**: Ingress NGINX with OAuth2 authentication

## Deployment

### GitOps Deployment (ArgoCD)

The cashier-app is deployed via an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract-dev-cashier-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "7"
spec:
  project: fineract-dev
  source:
    repoURL: https://github.com/ADORSYS-GIS/fineract-gitops.git
    targetRevision: eks # Or your target branch
    path: apps/cashier-app/base
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

1.  **User accesses** `https://fineract.example.com/cashier`
2.  **Ingress NGINX** intercepts request
3.  **OAuth2 Proxy** handles authentication via Keycloak
4.  **Ingress forwards** to cashier-app service
5.  **Frontend JS** makes API calls through Ingress to Fineract backend

### Session Management

Sessions are managed centrally by OAuth2 Proxy and Keycloak.

## Routing

### Access URL

The cashier app is accessible at a path like:
```
https://fineract.example.com/cashier
```
The Ingress configuration routes `/cashier(/|$)(.*)` to the cashier-app service.

---

**Namespace**: `fineract-dev` (dev), `fineract-uat` (uat), `fineract-production` (production)
**Component**: Frontend - Cashier App
**Managed by**: ArgoCD
**Access**: Via Ingress NGINX with OAuth2 authentication at `/cashier`