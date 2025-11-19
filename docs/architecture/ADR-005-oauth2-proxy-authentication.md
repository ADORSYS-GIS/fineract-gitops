# ADR-005: OAuth2-Proxy for Frontend Authentication

**Status**: ACCEPTED
**Date**: 2025-01-19
**Decision**: Use OAuth2-Proxy with Keycloak for authenticating frontend applications instead of Apache APISIX or direct OIDC in browsers

---

## Context

The Fineract platform includes multiple frontend applications (Web App, Reporting App, Accounting App) that need user authentication. Users must authenticate with Keycloak (OIDC provider) before accessing these applications.

### Authentication Approaches

When integrating frontend applications with Keycloak (OIDC), there are several architectural patterns:

#### Option 1: Browser-Based OIDC (Public Client)
Frontend apps implement OIDC authorization code flow directly in the browser.

**Pros:**
- No reverse proxy needed
- Simple architecture
- Direct token management in frontend

**Cons:**
- ❌ **Client secret exposed in browser** (security risk)
- ❌ Tokens stored in browser (localStorage/sessionStorage)
- ❌ Vulnerable to XSS attacks
- ❌ Each frontend app needs OIDC implementation
- ❌ Token refresh logic in each app
- ❌ CORS configuration complexity

#### Option 2: Backend-for-Frontend (BFF)
Each frontend has a dedicated backend that handles authentication.

**Pros:**
- Client secret on server-side (secure)
- Tokens not exposed to browser
- Can use httpOnly cookies

**Cons:**
- Must develop/maintain backend for each frontend
- Increased infrastructure complexity
- More code to maintain

#### Option 3: API Gateway with OIDC (Apache APISIX, Kong)
Use a full-featured API gateway with OIDC plugin.

**Pros:**
- Centralized authentication
- Advanced routing capabilities
- Rate limiting, caching, etc.

**Cons:**
- ❌ Heavyweight (many features not needed)
- ❌ Complex configuration
- ❌ Another component to maintain
- ❌ Steeper learning curve

#### Option 4: OAuth2-Proxy (Reverse Proxy with OIDC)
Lightweight reverse proxy specifically for OAuth2/OIDC authentication.

**Pros:**
- ✅ **Purpose-built for OAuth2/OIDC**
- ✅ Client secret on server-side (secure)
- ✅ httpOnly session cookies (XSS protection)
- ✅ Lightweight (minimal resource usage)
- ✅ Simple configuration
- ✅ Single proxy for all frontends
- ✅ Mature, battle-tested project
- ✅ Active community

**Cons:**
- Adds one more component (lightweight)
- Session cookie domain configuration needed

---

## Decision

**Use OAuth2-Proxy as a reverse proxy in front of all frontend applications for handling OIDC authentication with Keycloak.**

### Architecture

```
User → Ingress NGINX → OAuth2-Proxy → Frontend Apps
                             │
                             ↓
                         Keycloak
                        (OIDC Provider)
```

### Authentication Flow

```
1. User navigates to https://app.fineract.com/mifosweb/
   │
2. Ingress routes to OAuth2-Proxy
   │
3. OAuth2-Proxy checks session cookie
   │
4. ┌─ If no session: Redirect to Keycloak login
   │  └─ User authenticates with Keycloak
   │     └─ Keycloak redirects to OAuth2-Proxy callback
   │        └─ OAuth2-Proxy exchanges code for token
   │           └─ OAuth2-Proxy sets httpOnly session cookie
   │
5. ┌─ If valid session: Forward request to backend
   │  └─ Add headers: X-Auth-Request-User, X-Auth-Request-Email
   │     └─ Frontend receives authenticated request
   │
6. Frontend application loads with user context
```

### Key Features

1. **Centralized Authentication**
   - Single OAuth2-Proxy instance handles all frontends
   - No need for OIDC client in each app
   - Consistent authentication behavior

2. **Security**
   - Client secret stored server-side (not in browser)
   - httpOnly session cookies (immune to XSS)
   - Tokens never exposed to browser
   - CSRF protection built-in

3. **User Context Forwarding**
   - OAuth2-Proxy adds headers:
     - `X-Auth-Request-User`: Username
     - `X-Auth-Request-Email`: Email
     - `X-Auth-Request-Access-Token`: JWT (optional)
   - Frontend apps can read user from headers

4. **Path-Based Routing**
   - Different frontends on same domain
   - `/mifosweb/` → Web App
   - `/reporting/` → Reporting App
   - `/accounting/` → Accounting App

---

## Implementation

### OAuth2-Proxy Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-config
data:
  # OIDC Provider
  OAUTH2_PROXY_PROVIDER: "oidc"
  OAUTH2_PROXY_OIDC_ISSUER_URL: "https://auth.fineract.com/realms/fineract"
  OAUTH2_PROXY_CLIENT_ID: "fineract-oauth2-proxy"
  OAUTH2_PROXY_REDIRECT_URL: "https://app.fineract.com/oauth2/callback"

  # Session
  OAUTH2_PROXY_COOKIE_NAME: "_oauth2_proxy"
  OAUTH2_PROXY_COOKIE_SECURE: "true"
  OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
  OAUTH2_PROXY_COOKIE_SAMESITE: "lax"
  OAUTH2_PROXY_SESSION_COOKIE_MINIMAL: "true"

  # Upstream (backend services)
  OAUTH2_PROXY_UPSTREAMS: |
    http://web-app-service:8080/mifosweb/
    http://reporting-app-service:8080/reporting/
    http://accounting-app-service:8080/accounting/

  # Skip auth for static assets
  OAUTH2_PROXY_SKIP_AUTH_ROUTES: |
    ^/mifosweb/assets/.*
    ^/reporting/assets/.*
    ^/accounting/assets/.*
```

### Ingress Configuration

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-apps
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://$host/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2/start?rd=$escaped_request_uri"
spec:
  rules:
  - host: app.fineract.com
    http:
      paths:
      # OAuth2-Proxy paths
      - path: /oauth2
        pathType: Prefix
        backend:
          service:
            name: oauth2-proxy
            port:
              number: 4180

      # Frontend apps (protected)
      - path: /mifosweb
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 8080

      - path: /reporting
        pathType: Prefix
        backend:
          service:
            name: reporting-app-service
            port:
              number: 8080

      - path: /accounting
        pathType: Prefix
        backend:
          service:
            name: accounting-app-service
            port:
              number: 8080
```

### Keycloak Client Configuration

```yaml
# Keycloak client: fineract-oauth2-proxy
Client ID: fineract-oauth2-proxy
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://app.fineract.com/oauth2/callback
  - https://app-uat.fineract.com/oauth2/callback
  - https://app-dev.fineract.com/oauth2/callback
Web Origins:
  - https://app.fineract.com
  - https://app-uat.fineract.com
  - https://app-dev.fineract.com
```

### Resource Usage

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

**Extremely lightweight** - minimal resource overhead.

---

## Rationale

### Why OAuth2-Proxy over Apache APISIX?

1. **Simplicity**
   - OAuth2-Proxy: Single purpose (authentication)
   - APISIX: Full API gateway (routing, rate limiting, caching, etc.)
   - We only need authentication, not full gateway features

2. **Resource Efficiency**
   - OAuth2-Proxy: ~50-100 MB memory
   - APISIX: ~200-500 MB memory + etcd dependency

3. **Configuration**
   - OAuth2-Proxy: Simple YAML/env vars
   - APISIX: Complex YAML + Lua plugins + etcd

4. **Maintenance**
   - OAuth2-Proxy: Focused codebase, easier to troubleshoot
   - APISIX: Large project, many features we don't use

5. **Learning Curve**
   - OAuth2-Proxy: Learn in 1 day
   - APISIX: Learn in 1-2 weeks

### Why OAuth2-Proxy over Browser-Based OIDC?

1. **Security**
   - OAuth2-Proxy: Client secret server-side, httpOnly cookies
   - Browser OIDC: Client secret exposed, tokens in localStorage

2. **XSS Protection**
   - OAuth2-Proxy: Session cookies immune to XSS
   - Browser OIDC: Tokens vulnerable to XSS attacks

3. **Simplicity**
   - OAuth2-Proxy: No OIDC code in frontend apps
   - Browser OIDC: Must implement OIDC in each app

4. **Token Management**
   - OAuth2-Proxy: Handles refresh automatically
   - Browser OIDC: Must implement token refresh logic

---

## Consequences

### Positive

1. **Improved Security**
   - Client secret never exposed to browser
   - httpOnly cookies protect against XSS
   - Tokens not accessible to malicious scripts

2. **Simplified Frontend Development**
   - No OIDC implementation needed in apps
   - No token management logic
   - Focus on business features, not authentication

3. **Centralized Authentication**
   - Single place to configure OIDC
   - Consistent behavior across all apps
   - Easy to add new frontend apps

4. **Lightweight**
   - Minimal resource usage (~100 MB)
   - Fast authentication checks (<10ms)
   - No heavy dependencies

5. **Battle-Tested**
   - Used by thousands of organizations
   - Active community and support
   - Well-documented

### Negative

1. **Additional Component**
   - One more service to deploy and monitor
   - **Mitigation**: Lightweight, simple, rarely needs changes

2. **Session Cookie Domain**
   - Must configure cookie domain correctly
   - **Mitigation**: Well-documented, easy to configure

3. **Not API-Friendly**
   - OAuth2-Proxy designed for browser sessions
   - APIs must use JWT tokens directly
   - **Mitigation**: Fineract API already uses JWT validation

### Mitigations

1. **High Availability**
   - Deploy multiple OAuth2-Proxy replicas
   - Use Redis for shared session storage (optional)

2. **Monitoring**
   - Prometheus metrics built-in
   - Grafana dashboards for auth metrics

3. **Fallback**
   - If OAuth2-Proxy fails, Ingress returns 503
   - Users see clear error, not broken auth state

---

## Alternatives Considered

### 1. Apache APISIX

**Rejected** - Too heavyweight, complex configuration, many unnecessary features.

### 2. Kong Gateway

**Rejected** - Similar to APISIX, full API gateway when we only need authentication.

### 3. Envoy + ext_authz

**Rejected** - More flexible but requires custom auth server, more complexity.

### 4. Istio Service Mesh

**Rejected** - Too heavyweight, entire service mesh for just authentication.

### 5. Traefik ForwardAuth

**Considered** - Similar to OAuth2-Proxy, but less mature for OIDC specifically.

---

## Related ADRs

- **ADR-003**: Sealed Secrets (how OAuth2-Proxy client secret is stored)
- **Keycloak Configuration**: `/operations/keycloak-config/` (Keycloak realm and client setup)

---

## Migration Notes

### Previous Architecture (if using Apache APISIX)

If migrating from Apache APISIX or direct OIDC in browsers:

1. Deploy OAuth2-Proxy
2. Configure Keycloak client (`fineract-oauth2-proxy`)
3. Update Ingress with auth annotations
4. Test authentication flow
5. Remove old OIDC code from frontend apps
6. Remove Apache APISIX (if deployed)

### Zero-Downtime Migration

```bash
# 1. Deploy OAuth2-Proxy alongside existing setup
kubectl apply -k apps/oauth2-proxy/base/

# 2. Test OAuth2-Proxy with test domain
# Create test ingress: test.fineract.com → oauth2-proxy

# 3. Verify authentication works

# 4. Update production ingress to use OAuth2-Proxy
kubectl apply -f apps/ingress/base/ingress.yaml

# 5. Remove old authentication components
```

---

## References

- [OAuth2-Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [OAuth2-Proxy GitHub](https://github.com/oauth2-proxy/oauth2-proxy)
- [OIDC Authorization Code Flow](https://openid.net/specs/openid-connect-core-1_0.html#CodeFlowAuth)
- [OAuth2-Proxy Configuration](/apps/oauth2-proxy/base/README.md)

---

**Last Updated**: 2025-01-19
**Author**: DevOps Team
**Status**: ACCEPTED
