# OAuth2 Proxy for Fineract

## Overview

OAuth2 Proxy provides OIDC authentication for the Fineract platform, replacing the Apache Gateway's mod_auth_openidc functionality. It integrates with Keycloak for authentication and authorization.

## Architecture

```
Nginx Ingress Controller
  ↓ (auth_request subrequest)
OAuth2 Proxy
  ↓ (validates JWT with Keycloak)
Backend Services (Fineract, Frontend Apps)
```

## Key Features

- **OIDC Authentication**: Integrates with Keycloak realm `fineract`
- **Session Management**: Redis-backed sessions (4-hour max, 30-min idle timeout)
- **Claim Extraction**: Extracts user info, roles, custom claims from JWT
- **Header Injection**: Passes authentication headers to backend services
- **Role-Based Access Control**: Validates user roles before forwarding requests

## Components

### 1. OAuth2 Proxy Deployment
- **Image**: `quay.io/oauth2-proxy/oauth2-proxy:v7.5.1`
- **Replicas**: 2 (HA with pod anti-affinity)
- **Resources**: 128Mi memory, 100m CPU (per pod)

### 2. Redis Session Store
- **Purpose**: Shared session storage across OAuth2 Proxy replicas
- **Type**: Separate Redis deployment or AWS ElastiCache
- **TTL**: 4 hours (matching session max duration)

### 3. Secrets
- **oauth2-proxy-config**: Client secret, cookie secret, Redis password
- **Referenced from**: Kubernetes secrets or AWS Secrets Manager

## Configuration

### Keycloak Integration

- **Realm**: `fineract`
- **Client ID**: `oauth2-proxy`
- **Client Type**: Confidential
- **Valid Redirect URIs**: `https://apps.fineract.example.com/oauth2/callback`
- **Scopes**: `openid profile email roles`

### Custom Claims

OAuth2 Proxy extracts these claims from JWT and passes as headers:

| Claim | Header | Description |
|-------|--------|-------------|
| `preferred_username` | `X-Auth-Request-User` | Username |
| `email` | `X-Auth-Request-Email` | User email |
| `roles` | `X-Auth-Request-Groups` | User roles (admin, accountant, etc.) |
| `fineract_user_id` | `X-Fineract-User-ID` | Fineract internal user ID |
| `office_id` | `X-Fineract-Office-ID` | User's office ID |
| `employee_id` | `X-Fineract-Employee-ID` | User's employee ID |

### Session Configuration

- **Session Max Duration**: 14400 seconds (4 hours)
- **Session Idle Timeout**: 1800 seconds (30 minutes)
- **Session Store**: Redis (for HA)
- **Cookie Settings**:
  - Name: `_oauth2_proxy`
  - HttpOnly: true
  - Secure: true (production)
  - SameSite: Lax

## Deployment

### Prerequisites

1. **Keycloak** must be running with `fineract` realm configured
2. **Redis** (optional but recommended for HA)
3. **Nginx Ingress Controller** must be deployed

### Deploy OAuth2 Proxy

```bash
# Deploy to dev environment
kubectl apply -k environments/dev

# Verify deployment
kubectl get pods -n fineract-dev -l app=oauth2-proxy

# Check logs
kubectl logs -n fineract-dev -l app=oauth2-proxy --tail=50
```

### Create Keycloak Client

```bash
# Use the Keycloak config script
kubectl exec -n fineract-dev keycloak-0 -- /opt/keycloak/bin/kcadm.sh create clients \
  -r fineract \
  -s clientId=oauth2-proxy \
  -s enabled=true \
  -s clientAuthenticatorType=client-secret \
  -s secret=<GENERATED_SECRET> \
  -s 'redirectUris=["https://apps.fineract.example.com/oauth2/callback"]' \
  -s protocol=openid-connect
```

## Testing

### Test Authentication Flow

```bash
# 1. Access the application
curl -I https://apps.fineract.example.com/

# Should redirect to OAuth2 Proxy login
# Location: https://apps.fineract.example.com/oauth2/start

# 2. Complete OAuth flow (browser or API)
# After successful auth, check headers passed to backend

# 3. Verify headers in backend service logs
kubectl logs -n fineract-dev -l app=fineract-read | grep X-Auth-Request
```

### Test Session Management

```bash
# Get OAuth2 Proxy session
curl -I https://apps.fineract.example.com/ \
  -H "Cookie: _oauth2_proxy=<SESSION_COOKIE>"

# Verify session in Redis
kubectl exec -n fineract-dev redis-0 -- redis-cli GET oauth2:<SESSION_ID>
```

### Test RBAC

```bash
# Access admin-only endpoint as accountant (should fail)
curl https://apps.fineract.example.com/fineract-provider/api/v1/users \
  -H "Cookie: _oauth2_proxy=<ACCOUNTANT_SESSION>"

# Expected: 403 Forbidden

# Access as admin (should succeed)
curl https://apps.fineract.example.com/fineract-provider/api/v1/users \
  -H "Cookie: _oauth2_proxy=<ADMIN_SESSION>"

# Expected: 200 OK with user list
```

## Monitoring

### Health Checks

- **Liveness**: `http://localhost:4180/ping`
- **Readiness**: `http://localhost:4180/ready`

### Metrics

OAuth2 Proxy exposes Prometheus metrics at `/metrics`:

- `oauth2_proxy_requests_total`: Total requests
- `oauth2_proxy_authentication_latency_seconds`: Auth latency
- `oauth2_proxy_redis_connection_errors_total`: Redis errors

### Logs

```bash
# View OAuth2 Proxy logs
kubectl logs -n fineract-dev -l app=oauth2-proxy --tail=100 -f

# Check for auth failures
kubectl logs -n fineract-dev -l app=oauth2-proxy | grep "authentication failed"

# Check Redis connection
kubectl logs -n fineract-dev -l app=oauth2-proxy | grep redis
```

## Troubleshooting

### Issue: Authentication Loop

**Symptoms**: Redirects to login repeatedly
**Causes**:
- Cookie domain mismatch
- OIDC redirect URI not whitelisted in Keycloak
- Session store (Redis) unavailable

**Solution**:
```bash
# Check OAuth2 Proxy config
kubectl get configmap oauth2-proxy-config -n fineract-dev -o yaml

# Verify Keycloak client redirect URIs
# Restart OAuth2 Proxy pods
kubectl rollout restart deployment/oauth2-proxy -n fineract-dev
```

### Issue: Headers Not Passed to Backend

**Symptoms**: Backend receives no X-Auth-Request-* headers
**Causes**:
- Nginx auth_request not configured
- OAuth2 Proxy not setting response headers
- Nginx not passing auth_response_headers

**Solution**:
```bash
# Check Nginx Ingress annotation
kubectl get ingress -n fineract-dev -o yaml | grep auth-response-headers

# Verify OAuth2 Proxy header config
kubectl logs -n fineract-dev -l app=oauth2-proxy | grep "set-xauthrequest"
```

### Issue: Session Expired Too Quickly

**Symptoms**: Users logged out before 4 hours
**Causes**:
- Redis TTL too short
- Cookie expiry mismatch
- Keycloak SSO session timeout

**Solution**:
```bash
# Check Redis session TTL
kubectl exec -n fineract-dev redis-0 -- redis-cli TTL oauth2:<SESSION_ID>

# Verify OAuth2 Proxy session duration config
kubectl describe configmap oauth2-proxy-config -n fineract-dev | grep cookie-expire
```

## Migration from Apache Gateway

OAuth2 Proxy is part of the migration from Apache Gateway to Nginx Ingress. Key differences:

| Feature | Apache mod_auth_openidc | OAuth2 Proxy |
|---------|-------------------------|--------------|
| Session Storage | Shared memory (shm) | Redis (recommended) |
| Claim Validation | Apache `Require claim` | OAuth2 Proxy config |
| Header Names | Custom (X-Auth-*) | Standard (X-Auth-Request-*) |
| Integration | Apache config files | Kubernetes resources |

### Migration Checklist

- [ ] Deploy OAuth2 Proxy alongside Apache Gateway
- [ ] Configure Nginx Ingress auth_request to OAuth2 Proxy
- [ ] Update backend services to accept new header names (if needed)
- [ ] Test authentication flow end-to-end
- [ ] Validate RBAC with all roles
- [ ] Performance test under load
- [ ] Cutover traffic to Nginx Ingress
- [ ] Remove Apache Gateway resources

## References

- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Keycloak OIDC Provider](https://www.keycloak.org/docs/latest/securing_apps/#_oidc)
- [Nginx auth_request Module](https://nginx.org/en/docs/http/ngx_http_auth_request_module.html)
