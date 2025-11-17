# Fineract Web App

Frontend web applications for Apache Fineract, providing user interfaces for banking operations, administration, and account management.

## Overview

The web-app deployment serves the Fineract frontend applications as static files through NGINX. All API calls are routed through the Kubernetes Ingress NGINX controller, which handles authentication via OAuth2 Proxy and routing to appropriate Fineract backend services.

**Architecture**:
```
Browser → Ingress NGINX → OAuth2 Proxy → Web App (static files)
                        ↓
                   Fineract API (read/write services)
```

## Included Applications

The web-app container includes multiple Fineract frontend applications:

1. **Admin App** - System administration and configuration
2. **Account Manager** - Client account management
3. **Branch Manager** - Branch operations and reporting
4. **Cashier/Teller App** - Teller operations and cash management

All apps are served from a single NGINX container at different routes.

## Components

### Deployment (deployment.yaml)

**Image**: `ghcr.io/guymoyo/web-app:dev`
- Pinned to specific SHA256 digest for reproducibility
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

The web-app ConfigMap provides environment variables to the NGINX container:

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
configMapGenerator:
  - name: web-app-config
    behavior: merge
    literals:
      - fineractApiUrl=https://dev.fineract.example.com
```

**Production** (`environments/production/kustomization.yaml`):
```yaml
configMapGenerator:
  - name: web-app-config
    behavior: merge
    literals:
      - fineractApiUrl=https://fineract.example.com
```

## Deployment

### GitOps Deployment (ArgoCD)

The web-app is deployed via ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fineract-gitops
    targetRevision: main
    path: apps/web-app/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev
```

### Manual Deployment

```bash
# Deploy to development
kubectl apply -k apps/web-app/overlays/dev

# Deploy to production
kubectl apply -k apps/web-app/overlays/production
```

## Access and Authentication

### Authentication Flow

1. **User accesses** `https://fineract.example.com`
2. **Ingress NGINX** intercepts request
3. **OAuth2 Proxy** checks authentication:
   - If authenticated: Allow request
   - If not: Redirect to Keycloak login
4. **User logs in** via Keycloak (OIDC)
5. **OAuth2 Proxy** sets session cookie
6. **Ingress forwards** to web-app service
7. **Web-app NGINX** serves static files
8. **Frontend JS** makes API calls through Ingress
9. **Ingress routes** to fineract-read or fineract-write

### Session Management

Sessions are managed by OAuth2 Proxy + Keycloak:

- **Cookie lifetime**: 4 hours (`cookie_expire=4h`)
- **Cookie refresh**: 20 minutes (`cookie_refresh=20m`)
- **Idle timeout**: Managed by Keycloak
- **Logout**: `/oauth2/sign_out` → Keycloak logout

The frontend sets `sessionIdleTimeout: "0"` to defer session management to OAuth2 Proxy.

## Routing

### Static File Serving

NGINX in the web-app container serves:
- `/` - Default application (admin app)
- `/assets/` - Static assets (JS, CSS, images)
- `/admin/` - Admin application
- `/accounts/` - Account manager app
- `/branch/` - Branch manager app
- `/teller/` - Cashier/teller app

### API Requests

API requests are made by frontend JavaScript to:
```
https://fineract.example.com/fineract-provider/api/v1/*
```

These requests:
1. Go through Ingress NGINX (not web-app NGINX)
2. Are authenticated by OAuth2 Proxy
3. Are routed to fineract-read or fineract-write based on HTTP method
4. Include `X-Fineract-Platform-TenantId: default` header

## Monitoring

### Check Deployment Status

```bash
# Check pods
kubectl get pods -n fineract-dev -l app=web-app

# Check pod logs
kubectl logs -n fineract-dev -l app=web-app -f

# Check service
kubectl get svc web-app -n fineract-dev
```

### Describe Pod

```bash
kubectl describe pod -n fineract-dev -l app=web-app
```

### Test Service Locally

```bash
# Port-forward to test locally
kubectl port-forward -n fineract-dev svc/web-app 8080:80

# Access at http://localhost:8080
```

### Check Configuration

```bash
# View ConfigMap
kubectl get configmap web-app-config -n fineract-dev -o yaml

# Check environment variables in pod
kubectl exec -it -n fineract-dev deploy/web-app -- env | grep fineract
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
   kubectl logs -n fineract-dev deploy/web-app
   ```

2. **Check init container logs** (if pod is CrashLooping):
   ```bash
   kubectl logs -n fineract-dev deploy/web-app -c copy-assets
   ```

3. **Verify configuration**:
   ```bash
   kubectl get configmap web-app-config -n fineract-dev -o yaml
   ```

4. **Test from within pod**:
   ```bash
   kubectl exec -it -n fineract-dev deploy/web-app -- curl http://localhost/
   ```

5. **Check Ingress**:
   ```bash
   kubectl describe ingress -n fineract-dev
   ```

6. **Verify OAuth2 Proxy**:
   ```bash
   kubectl logs -n fineract-dev -l app=oauth2-proxy
   ```

### Browser Console Errors

**Error**: `Failed to load resource: net::ERR_NAME_NOT_RESOLVED`
- **Cause**: DNS not resolving `fineractApiUrl`
- **Fix**: Ensure `$(APPS_HOSTNAME)` is set correctly in environment overlay

**Error**: `Access to fetch at '...' from origin '...' has been blocked by CORS`
- **Cause**: CORS misconfiguration
- **Fix**: Ensure Fineract is configured to allow requests from the frontend origin

**Error**: `Unexpected token '<' in JSON`
- **Cause**: API returning HTML (likely error page) instead of JSON
- **Fix**: Check Fineract backend logs, verify authentication

## Security

### Security Features

1. **Read-only root filesystem** - Prevents runtime modifications
2. **Non-root user** - Runs as UID 1000 (not root)
3. **No privilege escalation** - Cannot gain elevated privileges
4. **Seccomp profile** - Restricts system calls
5. **Dropped capabilities** - Removes all Linux capabilities
6. **OAuth2 authentication** - All requests authenticated via Keycloak
7. **Image digest pinning** - Uses SHA256 digest (not mutable tags)

### Security Best Practices

1. **Always use HTTPS** - Never serve over HTTP in production
2. **Keep images updated** - Regularly update to latest security patches
3. **Monitor logs** - Watch for suspicious access patterns
4. **Limit resource usage** - Prevent resource exhaustion attacks
5. **Use network policies** - Restrict pod-to-pod communication

## CI/CD Integration

### Building New Images

The web-app image is built from the frontend application repository:

```bash
# Build image
docker build -t ghcr.io/guymoyo/web-app:dev .

# Get SHA256 digest
docker inspect ghcr.io/guymoyo/web-app:dev --format='{{index .RepoDigests 0}}'

# Update deployment.yaml with new digest
```

### Automated Deployment

When a new image is pushed:
1. CI pipeline builds and pushes image to ghcr.io
2. Update `deployment.yaml` with new SHA256 digest
3. Commit changes to Git
4. ArgoCD detects change and auto-deploys (if auto-sync enabled)

For detailed CI/CD setup, see:
- **[Frontend CI/CD Complete Guide](../../docs/development/FRONTEND_CI_CD_COMPLETE_GUIDE.md)**
- **[Frontend Implementation Guide](../../docs/development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md)**

## Integration with Other Components

### Required Dependencies

- **OAuth2 Proxy** (`apps/oauth2-proxy`) - Authentication
- **Keycloak** (`apps/keycloak`) - Identity provider
- **Ingress NGINX** (`apps/ingress-nginx`) - External access
- **Fineract** (`apps/fineract`) - Backend API
- **Cert-Manager** (`apps/cert-manager`) - TLS certificates

### Optional Integrations

- **Monitoring** - Prometheus metrics from NGINX
- **Logging** - Access logs to Loki/ELK
- **Alerting** - Alert on pod failures or high error rates

## References

- **[Frontend Implementation Guide](../../docs/development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md)**
- **[Frontend CI/CD Guide](../../docs/development/FRONTEND_CI_CD_COMPLETE_GUIDE.md)**
- **[OAuth2 Proxy Documentation](../oauth2-proxy/base/README.md)**
- **[Ingress NGINX Documentation](../ingress-nginx/base/README.md)**
- **[Fineract Documentation](https://fineract.apache.org/)**

---

**Namespace**: `fineract-dev` (dev), `fineract-uat` (uat), `fineract-production` (production)
**Component**: Frontend
**Managed by**: ArgoCD
**Access**: Via Ingress NGINX with OAuth2 authentication
