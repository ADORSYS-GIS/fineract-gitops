# NGINX Ingress Controller

Enterprise-grade ingress controller for routing external traffic to Fineract services with TLS termination, OAuth2 authentication, and intelligent read/write separation.

## Overview

The NGINX Ingress Controller manages external access to services in the Kubernetes cluster. This deployment includes:

- **Read/Write routing** - Automatic routing based on HTTP method and endpoint
- **OAuth2 authentication** - Integration with OAuth2 Proxy for OIDC authentication
- **RBAC enforcement** - Role-based access control at the ingress level
- **TLS termination** - SSL/TLS handling with cert-manager integration
- **Rate limiting** - Protection against abuse and DoS attacks
- **Security headers** - HSTS, CSP, and other security headers

## Components

### Installation

- **Version**: v1.10.0
- **Provider**: Cloud (AWS ELB, Azure LB, GCP LB)
- **Namespace**: `ingress-nginx`

The controller is installed from the official Kubernetes ingress-nginx repository.

### Configuration

**configmap.yaml** - Custom configuration for:
- Security settings (TLS, HSTS, headers)
- Read/write routing logic
- OAuth2 Proxy integration
- RBAC endpoint categorization
- Performance tuning
- Rate limiting

## Key Features

### 1. Read/Write Routing

Intelligent routing based on HTTP method and endpoint:

```
GET, HEAD, OPTIONS  → fineract-read-service
POST, PUT, DELETE   → fineract-write-service
Admin endpoints     → fineract-write-service (always)
```

**Admin endpoints** (always routed to write service):
- `/api/v1/users` - User management
- `/api/v1/permissions` - Permission management
- `/api/v1/roles` - Role management
- `/api/v1/codes` - Code management
- `/api/v1/hooks` - Hook configuration
- `/api/v1/jobs` - Job scheduler
- `/api/v1/configurations` - System configuration
- `/api/v1/systemconfig` - System configuration
- `/api/v1/audits` - Audit logs
- `/api/v1/datatables` - Custom data tables

### 2. RBAC Endpoint Categorization

Four levels of access control:

#### Level 4: Admin-Only Endpoints
- User management (`/api/v1/users`)
- Staff management (`/api/v1/staff`)
- Permissions (`/api/v1/permissions`)
- Roles (`/api/v1/roles`)
- System configuration (`/api/v1/systemconfig`)
- Code management (`/api/v1/codes`)
- Hooks (`/api/v1/hooks`)
- Jobs (`/api/v1/jobs`)

**Access**: Admin role only

#### Level 3: Accounting Endpoints
- GL accounts (`/api/v1/glaccounts`)
- Journal entries (`/api/v1/journalentries`)
- Accounting rules (`/api/v1/accountingrules`)

**Access**: Admin or Accountant roles

#### Level 2: Management Endpoints
- Offices (`/api/v1/offices`)
- Clients (`/api/v1/clients`)
- Groups (`/api/v1/groups`)
- Centers (`/api/v1/centers`)
- Loan products (`/api/v1/loanproducts`)
- Savings products (`/api/v1/savingsproducts`)

**Access**: Admin or Branch Manager roles

#### Level 1: Teller Operations
- Teller operations (`/api/v1/teller`)
- Cashiers (`/api/v1/cashiers`)

**Access**: Admin, Branch Manager, or Teller roles

### 3. OAuth2 Proxy Integration

OAuth2 Proxy provides:
- OIDC authentication with Keycloak
- Session management
- Role extraction from JWT tokens
- Single sign-on (SSO)

The ingress controller integrates via:
```nginx
map $request_uri $oauth2_proxy_auth_url {
    default "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth";
}
```

### 4. Security Configuration

#### TLS/SSL
```yaml
ssl-protocols: "TLSv1.2 TLSv1.3"
ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:..."
ssl-prefer-server-ciphers: "true"
```

#### HSTS (HTTP Strict Transport Security)
```yaml
hsts: "true"
hsts-max-age: "31536000"        # 1 year
hsts-include-subdomains: "true"
hsts-preload: "true"
```

#### Security Headers
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- X-XSS-Protection: 1; mode=block
- Referrer-Policy: strict-origin-when-cross-origin

### 5. Rate Limiting

Two rate limit zones:

```nginx
# API rate limiting
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

# Auth endpoint rate limiting (stricter)
limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=10r/s;
```

Apply in Ingress annotations:
```yaml
nginx.ingress.kubernetes.io/limit-rps: "100"
nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
```

## Usage

### Basic Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract
  namespace: fineract-dev
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - fineract.example.com
      secretName: fineract-tls
  rules:
    - host: fineract.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fineract-write
                port:
                  number: 8080
```

### Ingress with OAuth2 Authentication

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract
  annotations:
    # OAuth2 Proxy integration
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://fineract.example.com/oauth2/start?rd=$scheme://$host$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Roles"
spec:
  # ... same as above
```

### Ingress with Read/Write Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-api
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      # Use $final_backend variable from configmap http-snippet
      proxy_pass http://$final_backend$request_uri;
spec:
  # ... ingress rules
```

### Ingress with Rate Limiting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-api
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8"  # Internal traffic exempt
spec:
  # ... ingress rules
```

## Common Annotations

### SSL/TLS
```yaml
cert-manager.io/cluster-issuer: "letsencrypt-prod"
nginx.ingress.kubernetes.io/ssl-redirect: "true"
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

### OAuth2 Authentication
```yaml
nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth"
nginx.ingress.kubernetes.io/auth-signin: "https://fineract.example.com/oauth2/start?rd=$escaped_request_uri"
nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Roles"
```

### Timeouts
```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
```

### Request Size
```yaml
nginx.ingress.kubernetes.io/proxy-body-size: "50m"
```

### Custom Configuration
```yaml
nginx.ingress.kubernetes.io/configuration-snippet: |
  # Custom nginx config here
```

### Server Snippets (Use with Caution)
```yaml
nginx.ingress.kubernetes.io/server-snippet: |
  # Server-level nginx config
```

**⚠️ WARNING**: Server snippets can introduce security vulnerabilities. Only enable `allow-snippet-annotations: "true"` if you trust all users who can create Ingress resources.

## Monitoring

### Check Controller Status

```bash
# Check pods
kubectl get pods -n ingress-nginx

# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# Check admission webhook
kubectl get validatingwebhookconfigurations
```

### View Ingress Resources

```bash
# List all ingresses
kubectl get ingress --all-namespaces

# Describe ingress
kubectl describe ingress <name> -n <namespace>

# Check ingress controller service (LoadBalancer)
kubectl get svc -n ingress-nginx
```

### Access Logs

Logs include detailed request information:
```
$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent
"$http_referer" "$http_user_agent" $request_length $request_time
[$proxy_upstream_name] $upstream_addr $upstream_response_time
$upstream_status $req_id $http_x_auth_request_user
```

View logs:
```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller -f
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| 502 Bad Gateway | Check backend service is running and accessible |
| 503 Service Unavailable | Backend pods not ready or no healthy endpoints |
| 404 Not Found | Ingress path doesn't match or backend service name wrong |
| SSL certificate errors | Check cert-manager Certificate resource status |
| Authentication loops | Check OAuth2 Proxy configuration and cookie domain |
| Rate limit errors (429) | Adjust rate limit annotations or whitelist IPs |

### Debug Mode

Enable debug logging:
```bash
kubectl edit configmap ingress-nginx-controller -n ingress-nginx
```

Add:
```yaml
data:
  error-log-level: "debug"
```

### Test Backend Connectivity

```bash
# From ingress controller pod
kubectl exec -it -n ingress-nginx deploy/ingress-nginx-controller -- curl http://fineract-write.fineract-dev.svc.cluster.local:8080/fineract-provider/actuator/health
```

### Check SSL Certificate

```bash
# Get certificate from LoadBalancer
echo | openssl s_client -servername fineract.example.com -connect <LOAD_BALANCER_IP>:443 2>/dev/null | openssl x509 -noout -dates -subject
```

## Performance Tuning

### Worker Configuration
```yaml
worker-processes: "auto"         # Number of CPU cores
worker-connections: "10240"      # Connections per worker
```

### Keepalive
```yaml
keep-alive: "75"                 # Seconds to keep connection open
keep-alive-requests: "100"       # Requests per connection
```

### Buffers
```yaml
proxy-buffer-size: "128k"
proxy-buffers: "4 256k"
proxy-busy-buffers-size: "256k"
```

### Compression
```yaml
use-gzip: "true"
gzip-level: "5"
gzip-types: "application/json application/javascript text/css text/plain"
```

## Security Best Practices

1. **Disable snippet annotations** in production (unless absolutely needed):
   ```yaml
   allow-snippet-annotations: "false"
   ```

2. **Use TLS 1.2+ only**:
   ```yaml
   ssl-protocols: "TLSv1.2 TLSv1.3"
   ```

3. **Enable HSTS** for all domains:
   ```yaml
   hsts: "true"
   hsts-max-age: "31536000"
   ```

4. **Implement rate limiting** for public endpoints

5. **Use OAuth2 Proxy** for authentication (don't rely on Ingress basic auth)

6. **Monitor logs** for suspicious activity

## Integration with Other Components

### Cert-Manager
- Automatic TLS certificate issuance
- See `apps/cert-manager/base/README.md`

### OAuth2 Proxy
- OIDC authentication
- See `apps/oauth2-proxy/base/README.md`

### Fineract Services
- Read service: `fineract-read-service`
- Write service: `fineract-write-service`
- Batch service: `fineract-batch-service`

## References

- **[NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)**
- **[Annotations Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)**
- **[ConfigMap Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/)**
- **[TLS/HTTPS](https://kubernetes.github.io/ingress-nginx/user-guide/tls/)**

---

**Namespace**: `ingress-nginx`
**Version**: v1.10.0
**Component**: Ingress Controller
**Purpose**: External traffic routing with TLS termination and OAuth2 authentication
