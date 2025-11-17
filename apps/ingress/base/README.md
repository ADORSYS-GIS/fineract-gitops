# Fineract Ingress Configuration

This directory contains the Kubernetes Ingress configuration for the Fineract platform, implementing a **multi-ingress architecture** with OAuth2-based authentication.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Internet / Users                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Ingress NGINX                              │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ 1. fineract-public-ingress (NO AUTH)                           │    │
│  │    → /fineract-provider/actuator/health                        │    │
│  │    → Health checks, monitoring endpoints                       │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ 2. fineract-oauth2-public (NO AUTH)                            │    │
│  │    → /oauth2/*                                                 │    │
│  │    → OAuth2 callback, sign-in, sign-out                        │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ 3. fineract-oauth2-protected (REQUIRES AUTH)                   │    │
│  │    → /fineract-provider/api/*                                  │    │
│  │    → Backend Protocol: HTTPS (port 8443)                       │    │
│  │    → Target: Fineract API                                      │    │
│  │    → Auth: OAuth2-Proxy validation                             │    │
│  │    → Headers: Authorization: Bearer <token>                    │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ 4. fineract-web-app-protected (REQUIRES AUTH)                  │    │
│  │    → / (root and all other paths)                              │    │
│  │    → Backend Protocol: HTTP (port 80)                          │    │
│  │    → Target: Web-App nginx container                           │    │
│  │    → Auth: OAuth2-Proxy validation                             │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                    ↓                                   ↓
        ┌───────────────────────┐       ┌──────────────────────────────────┐
        │  Fineract API         │       │  Web-App nginx                   │
        │  (Port 8443 HTTPS)    │       │  (Port 80 HTTP)                  │
        │  - Business logic     │       │  - Serves Angular SPA            │
        │  - Validates tokens   │       │  - Static files only             │
        └───────────────────────┘       └──────────────────────────────────┘
```

## Why Multiple Ingress Resources?

The architecture uses **4 separate ingress resources** for the following reasons:

### 1. **Different Authentication Requirements**

- **Public endpoints** (health checks, OAuth flow) must be accessible without authentication
- **Protected endpoints** (API and frontend) require OAuth2 authentication
- Separate ingresses allow different `auth-url` annotations

### 2. **Different Backend Protocols**

- **Fineract API** uses HTTPS (port 8443) with TLS certificates
- **Web-App** uses HTTP (port 80) - it's just serving static files
- Kubernetes Ingress requires separate resources for different `backend-protocol` annotations

### 3. **Path Priority and Routing**

- More specific paths (`/fineract-provider/api/`) need higher priority
- Catch-all path (`/`) must be processed last
- Kubernetes Ingress processes rules in order

### 4. **Independent Configuration**

- Each service can have different:
  - Rate limiting
  - Caching policies
  - Header transformations
  - TLS settings

## Ingress Resources Breakdown

### 1. fineract-public-ingress

**Purpose:** Public endpoints that don't require authentication

**Configuration:**
```yaml
nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

**Paths:**
- `/fineract-provider/actuator/health` → Health checks for monitoring

**Use Cases:**
- Kubernetes liveness/readiness probes
- External monitoring systems (Prometheus, Datadog, etc.)
- Load balancer health checks

### 2. fineract-oauth2-public

**Purpose:** OAuth2 authentication flow endpoints

**Configuration:**
```yaml
nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

**Paths:**
- `/oauth2/start` → Initiate OAuth2 flow
- `/oauth2/callback` → OAuth2 callback from Keycloak
- `/oauth2/sign_in` → Sign-in page
- `/oauth2/sign_out` → Sign-out endpoint

**Important:** These endpoints are handled by OAuth2-Proxy service, not Fineract or Web-App

### 3. fineract-oauth2-protected

**Purpose:** Protected API endpoints requiring authentication

**Key Annotations:**
```yaml
# Authentication
nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth"
nginx.ingress.kubernetes.io/auth-signin: "https://$(APPS_HOSTNAME)/oauth2/start?rd=$escaped_request_uri"
nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Roles,X-Auth-Request-Access-Token"

# Backend
nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"

# Performance
nginx.ingress.kubernetes.io/auth-cache-key: "$cookie_oauth2_proxy"
nginx.ingress.kubernetes.io/auth-cache-duration: "200 202 5m"

# Headers
nginx.ingress.kubernetes.io/configuration-snippet: |
  proxy_set_header Authorization "Bearer $http_x_auth_request_access_token";
```

**Paths:**
- `/fineract-provider/api/v1/*` → Fineract REST API

**Authentication Flow:**
1. User requests API endpoint
2. Ingress makes subrequest to OAuth2-Proxy `/oauth2/auth`
3. OAuth2-Proxy validates session (Redis-backed)
4. If valid: Request forwarded with Authorization header
5. If invalid: Redirect to `/oauth2/start?rd=<original-url>`
6. After login: Redirect back to original URL

### 4. fineract-web-app-protected

**Purpose:** Protected web application (Angular SPA)

**Key Differences from API Ingress:**
```yaml
# Same OAuth2 authentication as API
nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth"

# Different backend protocol - web-app uses HTTP
nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
```

**Paths:**
- `/` → Catch-all for web application routes

**Why Separate from API Ingress?**
- API uses HTTPS backend (port 8443)
- Web-app uses HTTP backend (port 80)
- Cannot mix backend protocols in same ingress resource

## OAuth2-Proxy Integration

### How It Works

```
1. User Request → Ingress NGINX
2. Ingress makes auth subrequest → OAuth2-Proxy
3. OAuth2-Proxy checks session → Redis
4. If no session → Redirect to Keycloak
5. User logs in → Keycloak
6. Keycloak redirects → /oauth2/callback
7. OAuth2-Proxy creates session → Redis
8. User redirected → Original URL
9. Subsequent requests use cached session
```

### Session Caching

```yaml
nginx.ingress.kubernetes.io/auth-cache-key: "$cookie_oauth2_proxy"
nginx.ingress.kubernetes.io/auth-cache-duration: "200 202 5m"
```

- **Cache Key:** OAuth2-Proxy session cookie
- **Duration:** 5 minutes for successful auth (200, 202 status)
- **Benefit:** Reduces load on OAuth2-Proxy and Redis

### Headers Passed to Backends

**From OAuth2-Proxy:**
- `X-Auth-Request-User` → Username from Keycloak
- `X-Auth-Request-Email` → User email
- `X-Auth-Request-Roles` → User roles (from Keycloak token)
- `X-Auth-Request-Access-Token` → JWT access token

**Transformed by Ingress:**
- `Authorization: Bearer <token>` → Added via configuration-snippet

**Custom Fineract Headers:**
- `X-Fineract-User-Id` → Mapped from Keycloak user attributes
- `X-Office-Id` → Office identifier
- `X-Employee-Id` → Employee identifier

## TLS/SSL Configuration

### Certificate Management

The ingress uses cert-manager with two issuers:

1. **internal-ca-issuer** (Default)
   - Self-signed certificates
   - Used for development and testing
   - Automatically renewed

2. **letsencrypt-prod** (Production)
   - Let's Encrypt production certificates
   - Automatic renewal via ACME protocol
   - Requires valid DNS and reachable ingress

### TLS Secrets

```yaml
tls:
- hosts:
  - $(APPS_HOSTNAME)
  secretName: fineract-tls-cert
```

- **Secret Name:** `fineract-tls-cert`
- **Generated By:** cert-manager
- **Contains:** TLS certificate and private key
- **Renewal:** Automatic (90 days for Let's Encrypt)

## Environment-Specific Configuration

### Kustomization

The ingress configuration uses Kustomize for environment-specific settings:

```
apps/ingress/
├── base/
│   ├── ingress.yaml          # Base configuration (this file)
│   └── kustomization.yaml    # Base kustomization
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── uat/
    │   └── kustomization.yaml
    └── production/
        └── kustomization.yaml
```

### Variable Substitution

Variables are replaced via Kustomize:

```yaml
vars:
- name: APPS_HOSTNAME
  objref:
    kind: ConfigMap
    name: environment-config
    apiVersion: v1
  fieldref:
    fieldpath: data.apps_hostname
```

**Example Values:**
- **Dev:** `dev.fineract.example.com`
- **UAT:** `uat.fineract.example.com`
- **Production:** `fineract.example.com`

## Security Considerations

### 1. Zero Trust at Ingress

- All requests authenticated before reaching backends
- No credential handling in application code
- Centralized authentication policy

### 2. Defense in Depth

```
Layer 1: Ingress NGINX (auth_request)
Layer 2: OAuth2-Proxy (session validation)
Layer 3: Keycloak (token validation)
Layer 4: Fineract API (business logic authorization)
```

### 3. Network Policies

- OAuth2-Proxy can only communicate with Keycloak and Redis
- Fineract API can only communicate with database
- Web-App has no outbound access (static files only)

### 4. Rate Limiting

```yaml
nginx.ingress.kubernetes.io/limit-rps: "10"
nginx.ingress.kubernetes.io/limit-connections: "5"
```

- Prevents brute force attacks
- Protects against DoS
- Per-IP rate limiting

## Troubleshooting

### Authentication Loop

**Symptoms:** User keeps getting redirected to login

**Causes:**
1. OAuth2-Proxy session cookie not being set
2. Cookie domain mismatch
3. HTTPS not properly configured

**Solutions:**
```bash
# Check OAuth2-Proxy logs
kubectl logs -n fineract-dev -l app=oauth2-proxy

# Verify cookie settings
kubectl get configmap oauth2-proxy-config -n fineract-dev -o yaml

# Check ingress annotations
kubectl describe ingress fineract-oauth2-protected -n fineract-dev
```

### 502 Bad Gateway

**Symptoms:** API calls return 502 error

**Causes:**
1. Backend service not ready
2. Backend protocol mismatch (HTTP vs HTTPS)
3. Backend port incorrect

**Solutions:**
```bash
# Check backend pod status
kubectl get pods -n fineract-dev

# Check service endpoints
kubectl get endpoints -n fineract-dev

# Check ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

### 401 Unauthorized

**Symptoms:** API calls return 401 after successful login

**Causes:**
1. Authorization header not being forwarded
2. Token validation failing in Fineract
3. Token expired

**Solutions:**
```bash
# Check if headers are being forwarded
kubectl exec -n fineract-dev <fineract-pod> -- printenv

# Verify OAuth2-Proxy configuration
kubectl get secret oauth2-proxy-secret -n fineract-dev -o yaml

# Check token in browser developer tools (Application → Cookies)
```

### Certificate Issues

**Symptoms:** Browser shows SSL error

**Causes:**
1. Self-signed certificate not trusted
2. Certificate not yet issued
3. cert-manager not working

**Solutions:**
```bash
# Check certificate status
kubectl get certificate -n fineract-dev

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Describe certificate for details
kubectl describe certificate fineract-tls-cert -n fineract-dev
```

## Monitoring and Observability

### Metrics

Ingress NGINX exports Prometheus metrics:

```
nginx_ingress_controller_requests_total
nginx_ingress_controller_request_duration_seconds
nginx_ingress_controller_response_size
nginx_ingress_controller_ssl_expire_time_seconds
```

### Logs

```bash
# Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f

# OAuth2-Proxy logs
kubectl logs -n fineract-dev -l app=oauth2-proxy -f

# Fineract API logs
kubectl logs -n fineract-dev -l app=fineract-server -f
```

### Health Checks

```bash
# Public health endpoint (no auth)
curl https://dev.fineract.example.com/fineract-provider/actuator/health

# Ingress health
kubectl get ingress -n fineract-dev
kubectl describe ingress fineract-oauth2-protected -n fineract-dev
```

## Related Documentation

- [OAuth2-Proxy Guide](../../docs/OAUTH2-PROXY-NGINX-GUIDE.md)
- [Keycloak Configuration](../keycloak/README.md)
- [Web-App Authentication](https://github.com/guymoyo/web-app/blob/main/AUTHENTICATION.md)
- [Ingress NGINX Documentation](https://kubernetes.github.io/ingress-nginx/)

## Support

For issues related to:

- **Ingress configuration**: Check this documentation or ArgoCD application
- **OAuth2 authentication**: Review OAuth2-Proxy logs and configuration
- **TLS/Certificates**: Check cert-manager status
- **Backend connectivity**: Verify service and endpoint status
