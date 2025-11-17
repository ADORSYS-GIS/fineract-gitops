# Fineract Reporting App

Read-only reporting and audit trail application for Apache Fineract, providing comprehensive reporting interfaces and audit log access.

## Overview

The reporting-app deployment serves the Fineract reporting frontend application as static files through NGINX. All API calls are routed through the Kubernetes Ingress NGINX controller, which handles authentication via OAuth2 Proxy and routing to appropriate Fineract backend services.

**Architecture**:
```
Browser → Ingress NGINX → OAuth2 Proxy → Reporting App (static files)
                        ↓
                   Fineract API (read-only services)
```

## Purpose

The Reporting App provides:

1. **Audit Trail** - Comprehensive audit logging and tracking
2. **Read-only Reports** - Financial and operational reports
3. **Data Export** - Export capabilities for reporting data
4. **Analytics** - Business intelligence and analytics interfaces

This app is strictly read-only and does not allow any write operations to the Fineract system.

## Components

### Deployment (deployment.yaml)

**Image**: `ghcr.io/adorsys-gis/fineract-reporting-app:latest`
- Built from fineract-apps repository (Dockerfile.reporting)
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

Configuration for connecting to Fineract API and OAuth2 Proxy:

```yaml
fineractApiUrl: "https://$(APPS_HOSTNAME)"
fineractApiProvider: "/fineract-provider/api"
fineractApiVersion: "/v1"
fineractPlatformTenantId: "default"
oauth2ProxyLogoutUrl: "/oauth2/sign_out"
defaultLanguage: "en-US"
sessionIdleTimeout: "0"  # Managed by OAuth2-Proxy
```

**Key Configuration**:
- **API URL**: Uses environment variable `$(APPS_HOSTNAME)` set per environment
- **Tenant ID**: Multi-tenancy support (default tenant = "default")
- **Session timeout**: Disabled (0) - OAuth2-Proxy handles sessions
- **OAuth2 logout**: Redirects to `/oauth2/sign_out` for full logout

### Service (service.yaml)

**Type**: ClusterIP
- **Port**: 80 (HTTP)
- **Internal only** - Not exposed directly to internet
- **Accessed via**: Ingress NGINX with OAuth2 authentication

## Configuration

### Environment Variables

The reporting-app ConfigMap provides environment variables to the NGINX container:

| Variable | Default | Description |
|----------|---------|-------------|
| `fineractApiUrl` | `https://$(APPS_HOSTNAME)` | Fineract API base URL |
| `fineractApiProvider` | `/fineract-provider/api` | API provider path |
| `fineractApiVersion` | `/v1` | API version |
| `fineractPlatformTenantId` | `default` | Tenant identifier |
| `oauth2ProxyLogoutUrl` | `/oauth2/sign_out` | Logout endpoint |
| `defaultLanguage` | `en-US` | Default UI language |
| `sessionIdleTimeout` | `0` | Session timeout (0=managed by OAuth2) |

### Per-Environment Configuration

Configure `$(APPS_HOSTNAME)` in environment overlays:

**Development** (`environments/dev/kustomization.yaml`):
```yaml
images:
  - name: ghcr.io/adorsys-gis/fineract-reporting-app
    newTag: latest
```

**Production** (`environments/production/kustomization.yaml`):
```yaml
images:
  - name: ghcr.io/adorsys-gis/fineract-reporting-app
    newTag: v1.0.0  # Use specific version tags
```

## Deployment

### GitOps Deployment (ArgoCD)

The reporting-app is deployed via ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract-dev-reporting-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "7"
spec:
  project: fineract-dev
  source:
    repoURL: https://github.com/ADORSYS-GIS/fineract-gitops.git
    targetRevision: eks
    path: apps/reporting-app/base
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Manual Deployment

```bash
# Deploy to development
kubectl apply -k apps/reporting-app/base

# Verify deployment
kubectl get pods -n fineract-dev -l app=reporting-app
```

## Access and Authentication

### Authentication Flow

1. **User accesses** `https://fineract.example.com/reporting`
2. **Ingress NGINX** intercepts request
3. **OAuth2 Proxy** checks authentication:
   - If authenticated: Allow request
   - If not: Redirect to Keycloak login
4. **User logs in** via Keycloak (OIDC)
5. **OAuth2 Proxy** sets session cookie
6. **Ingress forwards** to reporting-app service
7. **Reporting-app NGINX** serves static files
8. **Frontend JS** makes API calls through Ingress
9. **Ingress routes** to fineract-read (read-only)

### Session Management

Sessions are managed by OAuth2 Proxy + Keycloak:

- **Cookie lifetime**: 4 hours (`cookie_expire=4h`)
- **Cookie refresh**: 20 minutes (`cookie_refresh=20m`)
- **Idle timeout**: Managed by Keycloak
- **Logout**: `/oauth2/sign_out` → Keycloak logout

The frontend sets `sessionIdleTimeout: "0"` to defer session management to OAuth2 Proxy.

## Routing

### Access URL

The reporting app is accessible at:
```
https://fineract.example.com/reporting
```

The Ingress configuration routes `/reporting(/|$)(.*)` to the reporting-app service.

### API Requests

API requests are made by frontend JavaScript to:
```
https://fineract.example.com/fineract-provider/api/v1/*
```

These requests:
1. Go through Ingress NGINX (not reporting-app NGINX)
2. Are authenticated by OAuth2 Proxy
3. Are routed to fineract-read (read-only service)
4. Include `X-Fineract-Platform-TenantId: default` header

## Monitoring

### Check Deployment Status

```bash
# Check pods
kubectl get pods -n fineract-dev -l app=reporting-app

# Check pod logs
kubectl logs -n fineract-dev -l app=reporting-app -f

# Check service
kubectl get svc reporting-app -n fineract-dev
```

### Describe Pod

```bash
kubectl describe pod -n fineract-dev -l app=reporting-app
```

### Test Service Locally

```bash
# Port-forward to test locally
kubectl port-forward -n fineract-dev svc/reporting-app 8080:80

# Access at http://localhost:8080
```

### Check Configuration

```bash
# View ConfigMap
kubectl get configmap reporting-app-config -n fineract-dev -o yaml

# Check environment variables in pod
kubectl exec -it -n fineract-dev deploy/reporting-app -- env | grep fineract
```

## Troubleshooting

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| **White screen** | Blank page loads | Check browser console for errors, verify API URL configuration |
| **Login redirect loop** | Keeps redirecting to login | Check OAuth2 Proxy configuration and cookies |
| **API calls fail** | Network errors in console | Verify Ingress configuration and Fineract backend health |
| **403 Forbidden** | Access denied | Check RBAC and Keycloak roles |
| **Assets not loading** | Missing CSS/JS | Check init container logs, verify assets volume mount |
| **Pod not starting** | CrashLoopBackOff | Check pod logs and resource limits |

### Debug Steps

1. **Check pod logs**:
   ```bash
   kubectl logs -n fineract-dev deploy/reporting-app
   ```

2. **Check init container logs** (if pod is CrashLooping):
   ```bash
   kubectl logs -n fineract-dev deploy/reporting-app -c copy-assets
   ```

3. **Verify configuration**:
   ```bash
   kubectl get configmap reporting-app-config -n fineract-dev -o yaml
   ```

4. **Test from within pod**:
   ```bash
   kubectl exec -it -n fineract-dev deploy/reporting-app -- curl http://localhost/
   ```

5. **Check Ingress**:
   ```bash
   kubectl describe ingress -n fineract-dev
   ```

6. **Verify OAuth2 Proxy**:
   ```bash
   kubectl logs -n fineract-dev -l app=oauth2-proxy
   ```

## Security

### Security Features

1. **Read-only root filesystem** - Prevents runtime modifications
2. **Non-root user** - Runs as UID 1000 (not root)
3. **No privilege escalation** - Cannot gain elevated privileges
4. **Seccomp profile** - Restricts system calls
5. **Dropped capabilities** - Removes all Linux capabilities
6. **OAuth2 authentication** - All requests authenticated via Keycloak
7. **Image digest pinning** - Can use SHA256 digest for reproducibility

### Security Best Practices

1. **Always use HTTPS** - Never serve over HTTP in production
2. **Keep images updated** - Regularly update to latest security patches
3. **Monitor logs** - Watch for suspicious access patterns
4. **Limit resource usage** - Prevent resource exhaustion attacks
5. **Use network policies** - Restrict pod-to-pod communication

## CI/CD Integration

### Building New Images

The reporting-app image is built from the fineract-apps repository:

**Workflow**: `.github/workflows/publish-frontend-images.yml`

```bash
# Image is automatically built on push to develop/main branches
# Manual trigger available via workflow_dispatch
```

**Image Tags**:
- `develop` - Latest from develop branch
- `latest` - Latest from main branch
- `<short-sha>` - Specific commit
- `<long-sha>` - Full commit hash

### Automated Deployment

When a new image is pushed:
1. CI pipeline builds and pushes image to ghcr.io/adorsys-gis/fineract-reporting-app
2. (Optional) Update `environments/dev/kustomization.yaml` with new tag
3. Commit changes to Git
4. ArgoCD detects change and auto-deploys (if auto-sync enabled)

## Integration with Other Components

### Required Dependencies

- **OAuth2 Proxy** (`apps/oauth2-proxy`) - Authentication
- **Keycloak** (`apps/keycloak`) - Identity provider
- **Ingress NGINX** (`apps/ingress`) - External access
- **Fineract** (`apps/fineract`) - Backend API
- **Cert-Manager** - TLS certificates

### Optional Integrations

- **Monitoring** - Prometheus metrics from NGINX
- **Logging** - Access logs to Loki/ELK
- **Alerting** - Alert on pod failures or high error rates

## References

- **[Fineract Apps Repository](https://github.com/ADORSYS-GIS/fineract-apps)**
- **[OAuth2 Proxy Documentation](../oauth2-proxy/README.md)**
- **[Ingress Documentation](../ingress/README.md)**
- **[Fineract Documentation](https://fineract.apache.org/)**

---

**Namespace**: `fineract-dev` (dev), `fineract-uat` (uat), `fineract-production` (production)
**Component**: Frontend - Reporting
**Managed by**: ArgoCD
**Access**: Via Ingress NGINX with OAuth2 authentication at `/reporting`
