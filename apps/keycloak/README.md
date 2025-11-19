# Keycloak Identity and Access Management

Keycloak is the central identity provider and authentication service for the Fineract platform. This directory contains the Kubernetes manifests for deploying Keycloak as an OAuth2/OIDC provider with bank-level security, custom banking themes, and WebAuthn 2FA support.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Database Configuration](#database-configuration)
  - [Hostname Configuration](#hostname-configuration)
  - [Admin Credentials](#admin-credentials)
- [Deployment](#deployment)
  - [Prerequisites](#prerequisites)
  - [ArgoCD Deployment](#argocd-deployment)
  - [Manual Deployment](#manual-deployment)
- [Custom Banking Theme](#custom-banking-theme)
- [Realm and Client Configuration](#realm-and-client-configuration)
- [User Management](#user-management)
- [Monitoring and Health Checks](#monitoring-and-health-checks)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Related Documentation](#related-documentation)

## Overview

This Keycloak deployment provides:

**Key Features:**
- OAuth2/OIDC authentication for Fineract and frontend applications
- Custom banking theme (Webank) with professional UI
- WebAuthn 2FA support (Face ID, Touch ID, Security Keys)
- PostgreSQL database (AWS RDS) for persistent storage
- Bank-level security policies (password complexity, brute force protection)
- User synchronization service (Fineract → Keycloak)
- Prometheus metrics for monitoring
- High availability with pod disruption budgets

**Keycloak Version**: 24.0.5 (Quarkus-based)

**Deployment Strategy**: Single replica with persistent storage (can be scaled with database replication)

## Architecture

### System Context

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet / Users                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                  ┌──────────▼──────────┐
                  │  Ingress NGINX      │
                  │  (TLS Termination)  │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │   OAuth2-Proxy      │
                  │  (Session Manager)  │
                  └──────────┬──────────┘
                             │
                   ┌─────────▼─────────┐
                   │     Keycloak      │
                   │  (Identity Store) │
                   └─────────┬─────────┘
                             │
                   ┌─────────▼─────────┐
                   │  PostgreSQL RDS   │
                   │  (Realm Data)     │
                   └───────────────────┘
```

### Authentication Flow

```
1. User → https://app.fineract.com/
           │
2. OAuth2-Proxy → Redirects to Keycloak login
           │
3. Keycloak → Shows login page (custom Webank theme)
           │
4. User → Enters credentials
           │
5. Keycloak → Validates credentials (PostgreSQL)
           │         Optional: Prompts for WebAuthn 2FA
           │
6. Keycloak → Issues JWT token with user roles
           │
7. OAuth2-Proxy → Sets session cookie
           │
8. User → Accesses application with authenticated session
           │
9. Fineract → Validates JWT using Keycloak's public keys (JWK Set)
```

### Component Overview

The Keycloak application directory contains:

**Base Resources** (`/apps/keycloak/base/`):
- `deployment.yaml` - Keycloak deployment with custom theme initContainer
- `service.yaml` - ClusterIP service with session affinity
- `pvc.yaml` - PersistentVolumeClaim for Keycloak data directory
- `themes-pvc.yaml` - PersistentVolumeClaim for custom themes
- `theme-configmap.yaml` - Custom Webank theme templates and messages
- `theme-css-configmap.yaml` - Custom Webank theme CSS styles
- `pdb.yaml` - PodDisruptionBudget for high availability

**Environment Overlays** (`/apps/keycloak/overlays/`):
- `dev/` - Development environment configuration
- `uat/` - UAT environment configuration (if exists)
- `prod/` - Production environment configuration (if exists)

**Realm Configuration** (`/operations/keycloak-config/`):
- Realm definition (4 clients, 12 roles, WebAuthn)
- Security policies (password complexity, brute force protection)
- User synchronization service (Fineract → Keycloak)
- Monitoring and alerting rules

See [/operations/keycloak-config/README.md](/operations/keycloak-config/README.md) for detailed realm configuration.

## Configuration

### Environment Variables

Keycloak is configured via environment variables and startup arguments.

#### Database Configuration

| Variable | Description | Source | Example |
|----------|-------------|--------|---------|
| `KC_DB` | Database type | ConfigMap | `postgres` |
| `KC_DB_URL_HOST` | Database hostname | Secret | `keycloak-db.cluster-xxx.us-east-1.rds.amazonaws.com` |
| `KC_DB_URL_PORT` | Database port | Secret | `5432` |
| `KC_DB_URL_DATABASE` | Database name | Secret | `keycloak` |
| `KC_DB_USERNAME` | Database username | Secret | `keycloak` |
| `KC_DB_PASSWORD` | Database password | Secret | `<secret>` |
| `KC_DB_URL_PROPERTIES` | JDBC properties | ConfigMap | `?sslmode=require` |

**Secret Name**: `keycloak-db-credentials`

**Database Requirements:**
- PostgreSQL 15+
- Database must be created before deployment: `CREATE DATABASE keycloak;`
- SSL/TLS enabled for RDS (`sslmode=require`)

#### Admin Credentials

| Variable | Description | Source | Example |
|----------|-------------|--------|---------|
| `KEYCLOAK_ADMIN` | Admin username | Secret | `admin` |
| `KEYCLOAK_ADMIN_PASSWORD` | Admin password | Secret | `<strong-password>` |

**Secret Name**: `keycloak-admin-credentials`

**Security Note**: The admin user is created on first startup. Use a strong password (20+ characters, mixed case, numbers, symbols). Store the secret securely.

#### Hostname Configuration

| Variable/Arg | Description | Value | Notes |
|--------------|-------------|-------|-------|
| `--hostname` | Public-facing hostname | `https://auth.fineract.example.com` | Set in overlay |
| `--hostname-backchannel-dynamic` | Allow internal service names | `true` | Set in overlay |
| `--proxy-headers` | Trust X-Forwarded headers | `xforwarded` | Base config |

**Keycloak 24.x Hostname Best Practice:**

Keycloak 24.x+ requires explicit hostname configuration for security. The configuration is done via startup arguments (not environment variables):

**Base Configuration** (`deployment.yaml`):
```yaml
args:
- start
- --http-enabled=true
- --health-enabled=true
- --metrics-enabled=true
- --proxy-headers=xforwarded
```

**Overlay Configuration** (e.g., `overlays/dev/kustomization.yaml`):
```yaml
patches:
- patch: |-
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --hostname=https://auth-dev.fineract.example.com
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --hostname-backchannel-dynamic=true
  target:
    kind: Deployment
    name: keycloak
```

**Why This Matters:**
- `--hostname`: Sets the public URL used in OIDC issuer URLs and JWT tokens
- `--hostname-backchannel-dynamic=true`: Allows internal Kubernetes services to communicate via service names (e.g., `http://keycloak-service:8080`) while browsers use the public URL
- `--proxy-headers=xforwarded`: Trusts `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host` from Ingress NGINX

See: [Keycloak Hostname Documentation](https://www.keycloak.org/server/hostname)

#### HTTP Configuration

| Variable | Description | Value |
|----------|-------------|-------|
| `KC_HTTP_RELATIVE_PATH` | Base path for Keycloak | `/auth` |
| `KC_LOG_LEVEL` | Logging level | `INFO` |
| `KC_HEALTH_ENABLED` | Enable health endpoints | `true` |

**HTTP Relative Path:**
Keycloak is served from `/auth` subpath (e.g., `https://auth.example.com/auth/`). This allows hosting Keycloak behind a reverse proxy with other services.

**Endpoints:**
- Admin Console: `https://auth.example.com/auth/admin/`
- Realm Login: `https://auth.example.com/auth/realms/fineract/`
- Health: `https://auth.example.com/auth/health/`
- Metrics: `https://auth.example.com/auth/metrics/`

#### JVM Configuration

| Variable | Description | Value |
|----------|-------------|-------|
| `JAVA_OPTS` | JVM options | `-Xms192m -Xmx512m -XX:MetaspaceSize=96M -XX:MaxMetaspaceSize=192m` |

**Memory Settings:**
- Heap: 192MB min, 512MB max
- Metaspace: 96MB initial, 192MB max
- Optimized for t3a.large (8GB RAM) or similar instances
- Conservative settings for dev/staging environments

**Production Tuning:**
For production with high user load, increase memory:
```yaml
env:
  - name: JAVA_OPTS
    value: "-Xms512m -Xmx2048m -XX:MetaspaceSize=128M -XX:MaxMetaspaceSize=512m"
resources:
  limits:
    memory: "3Gi"
```

### Database Configuration

Keycloak stores all realm data, users, clients, and sessions in PostgreSQL.

#### AWS RDS PostgreSQL (Recommended)

**Prerequisites:**
1. Create RDS PostgreSQL instance (PostgreSQL 15+)
2. Create database:
   ```sql
   CREATE DATABASE keycloak WITH ENCODING='UTF8';
   ```
3. Enable SSL/TLS connections (RDS default)
4. Configure security group to allow EKS nodes (port 5432)

**Create Sealed Secret:**
```bash
# Create keycloak-db-credentials secret
kubectl create secret generic keycloak-db-credentials \
  --from-literal=host=keycloak-db.cluster-xxx.us-east-1.rds.amazonaws.com \
  --from-literal=port=5432 \
  --from-literal=database=keycloak \
  --from-literal=username=keycloak \
  --from-literal=password=<strong-password> \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > keycloak-db-credentials-sealed.yaml
```

**Database Schema:**
Keycloak automatically creates its schema on first startup. No manual schema initialization required.

**Connection Pooling:**
Keycloak uses HikariCP for connection pooling with sensible defaults. For high-load environments, tune in overlay:
```yaml
env:
  - name: KC_DB_POOL_INITIAL_SIZE
    value: "5"
  - name: KC_DB_POOL_MAX_SIZE
    value: "20"
```

### Hostname Configuration

See [Hostname Configuration](#hostname-configuration) section above for details.

### Admin Credentials

The Keycloak admin user is created on first startup using `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` environment variables.

**Create Admin Secret:**
```bash
# Generate strong password
ADMIN_PASSWORD=$(openssl rand -base64 32)

# Create keycloak-admin-credentials secret
kubectl create secret generic keycloak-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=$ADMIN_PASSWORD \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > keycloak-admin-credentials-sealed.yaml

# Save password securely (e.g., password manager)
echo "Keycloak Admin Password: $ADMIN_PASSWORD"
```

**Access Admin Console:**
1. Navigate to `https://auth.fineract.example.com/auth/admin/`
2. Login with admin credentials
3. Configure realm, clients, and users

**Security Best Practices:**
- Use strong password (20+ characters)
- Enable MFA for admin account after first login
- Create separate admin users (don't share credentials)
- Restrict admin console access via NetworkPolicy in production

## Deployment

### Prerequisites

1. **Kubernetes Cluster**: EKS 1.28+ (or equivalent)
2. **ArgoCD**: Installed and configured (see `/argocd/`)
3. **Sealed Secrets**: Controller installed (see `/apps/sealed-secrets-controller/`)
4. **PostgreSQL Database**: RDS instance with `keycloak` database created
5. **Ingress NGINX**: Installed (see `/apps/ingress-nginx/`)
6. **Cert-Manager**: Installed for TLS certificates (see `/apps/cert-manager/`)
7. **Secrets Created**:
   - `keycloak-db-credentials` (sealed secret)
   - `keycloak-admin-credentials` (sealed secret)

### ArgoCD Deployment

Keycloak is deployed via ArgoCD Application defined in `/argocd/applications/{dev,uat,prod}/keycloak.yaml`.

#### Dev Environment

**ArgoCD Application**: `argocd/applications/dev/keycloak.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fineract-gitops.git
    targetRevision: main
    path: apps/keycloak/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Deployment Order (Sync Waves):**
1. Wave 0: Namespace and RBAC
2. Wave 1: Sealed secrets controller
3. Wave 2: Sealed secrets (database, admin credentials)
4. Wave 3: PVCs, ConfigMaps
5. Wave 8: Keycloak deployment
6. Wave 9: Keycloak service
7. Wave 10: Keycloak realm configuration job
8. Wave 15: Ingress

**Deploy to Dev:**
```bash
# Apply ArgoCD application
kubectl apply -f argocd/applications/dev/keycloak.yaml

# Monitor deployment
argocd app get keycloak -n argocd --watch

# Check sync status
argocd app sync keycloak -n argocd

# View pods
kubectl get pods -n fineract-dev -l app=keycloak
```

**Post-Deployment Verification:**
```bash
# Check pod status
kubectl get pods -n fineract-dev -l app=keycloak

# View logs
kubectl logs -f deployment/keycloak -n fineract-dev

# Check health
kubectl exec -it deployment/keycloak -n fineract-dev -- \
  curl http://localhost:8080/auth/health

# Test admin console (port-forward)
kubectl port-forward svc/keycloak-service 8080:8080 -n fineract-dev
# Open http://localhost:8080/auth/admin/
```

#### UAT/Prod Environments

Same process as Dev, using appropriate ArgoCD application files:
- UAT: `argocd/applications/uat/keycloak.yaml`
- Prod: `argocd/applications/prod/keycloak.yaml`

Each environment has:
- Different hostname (`--hostname` startup arg)
- Different database instance
- Different admin credentials
- Potentially different resource limits

Environment-specific overrides are in `/apps/keycloak/overlays/{dev,uat,prod}/`.

### Manual Deployment

For testing without ArgoCD:

```bash
# Navigate to environment overlay
cd apps/keycloak/overlays/dev

# Apply kustomization
kubectl apply -k .

# Verify deployment
kubectl get all -n fineract-dev -l app=keycloak

# Check pod status
kubectl get pods -n fineract-dev -l app=keycloak

# View logs
kubectl logs -f deployment/keycloak -n fineract-dev
```

**Note**: Manual deployment requires pre-created secrets and PVCs.

## Custom Banking Theme

Keycloak includes a custom "Webank" banking theme with professional UI designed for financial institutions.

### Theme Architecture

**Theme Deployment Strategy**: InitContainer + ConfigMaps

```
┌─────────────────────────────────────────────────────────┐
│                    Keycloak Pod                         │
├─────────────────────────────────────────────────────────┤
│  InitContainer: deploy-webank-theme                     │
│  ├─ Mounts: theme-files ConfigMap (templates, messages) │
│  ├─ Mounts: theme-css ConfigMap (styles)                │
│  ├─ Destination: themes-pvc:/opt/keycloak/themes/webank │
│  └─ Action: Copy theme files from ConfigMaps to PVC     │
├─────────────────────────────────────────────────────────┤
│  Main Container: keycloak                               │
│  └─ Mounts: themes-pvc:/opt/keycloak/themes (readonly)  │
└─────────────────────────────────────────────────────────┘
```

**Why InitContainer + ConfigMaps?**
- **GitOps-friendly**: Theme files managed as ConfigMaps in Git
- **Dynamic updates**: Update theme without rebuilding Keycloak image
- **Separation of concerns**: Theme content separate from Keycloak base image
- **Simplicity**: No custom Docker image build pipeline needed

**Trade-offs:**
- Adds ~5-10s to pod startup time
- Acceptable for dev/staging/small-scale production
- For high-scale production, consider custom Keycloak image with theme baked in

### Theme Components

**ConfigMaps:**
1. `keycloak-webank-theme` (`theme-configmap.yaml`):
   - `theme.properties` - Theme metadata
   - `template.ftl` - Base page template (FreeMarker)
   - `login.ftl` - Login page template
   - `messages_en.properties` - English translations

2. `keycloak-webank-theme-css` (`theme-css-configmap.yaml`):
   - `webank.css` - Banking theme styles (colors, fonts, layout)

**Theme Directory Structure:**
```
/opt/keycloak/themes/webank/
├── theme.properties
├── login/
│   ├── template.ftl
│   ├── login.ftl
│   ├── messages/
│   │   └── messages_en.properties
│   └── resources/
│       └── css/
│           └── webank.css
```

### Theme Customization

To customize the theme:

**1. Edit ConfigMaps:**
```bash
# Edit theme templates
kubectl edit configmap keycloak-webank-theme -n fineract-dev

# Edit theme CSS
kubectl edit configmap keycloak-webank-theme-css -n fineract-dev
```

**2. Restart Keycloak:**
```bash
# Delete pod to trigger initContainer re-deployment
kubectl delete pod -l app=keycloak -n fineract-dev

# Or rollout restart
kubectl rollout restart deployment/keycloak -n fineract-dev
```

**3. Clear Browser Cache:**
Keycloak aggressively caches theme resources. Clear browser cache or use incognito mode to see changes.

### Alternative: Custom Docker Image

For production with strict startup SLAs, build a custom Keycloak image with theme baked in:

**Dockerfile:**
```dockerfile
FROM quay.io/keycloak/keycloak:24.0.5

# Copy theme files
COPY --chown=keycloak:keycloak themes/webank /opt/keycloak/themes/webank

# Build Keycloak with theme
RUN /opt/keycloak/bin/kc.sh build

# Set entrypoint
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
```

**Build and Push:**
```bash
docker build -t your-registry/keycloak-custom:24.0.5 .
docker push your-registry/keycloak-custom:24.0.5
```

**Update Kustomization:**
```yaml
images:
  - name: quay.io/keycloak/keycloak
    newName: your-registry/keycloak-custom
    newTag: "24.0.5"
```

**Remove initContainer** from `deployment.yaml`.

## Realm and Client Configuration

Keycloak realm configuration (realm, clients, roles, users) is managed separately in `/operations/keycloak-config/`.

### Realm Overview

**Realm Name**: `fineract`

**Security Policies:**
- Password policy: 12+ chars, mixed case, 2 digits, special char, history of 5
- Brute force protection: 3 attempts → 2-30 min lockout (exponential backoff)
- Token settings: 15min access tokens, 30min session idle
- WebAuthn 2FA: Face ID, Touch ID, Security Keys (mandatory after password change)

### OAuth2 Clients

| Client ID | Type | Purpose | Grant Type |
|-----------|------|---------|------------|
| `fineract-oauth2-proxy` | Confidential | Server-side proxy for all web frontends | Authorization Code |
| `admin-cli` | Confidential | Keycloak config management + user sync | Client Credentials |
| `fineract-api` | Confidential | Generic backend service account | Client Credentials |
| `fineract-data-loader` | Confidential | Automated data loading | Client Credentials |

**OAuth2-Proxy Architecture:**
- Single OAuth2-Proxy instance handles authentication for all frontend apps
- Client secret stored server-side (never exposed to browser)
- Better security than public SPA clients
- Simplified configuration (one client vs multiple)

### Roles

**12 Fineract Roles:**
- `admin` - System administrator
- `manager` - Branch manager
- `teller` - Teller operations
- `loan_officer` - Loan officer
- `accountant` - Accounting operations
- `data_entry` - Data entry clerk
- `auditor` - Auditor (read-only)
- `relationship_manager` - Customer relationship
- `compliance_officer` - Compliance monitoring
- `treasury_manager` - Treasury operations
- `operations_head` - Operations management
- `viewer` - Read-only access

See `/operations/keycloak-config/ROLE_MAPPING.md` for detailed role mapping.

### Realm Configuration Automation

Realm configuration is applied via Kubernetes Job using `kcadm.sh` (Keycloak Admin CLI):

**Job**: `apply-keycloak-config` (see `/operations/keycloak-config/base/jobs/`)

**How It Works:**
1. Job runs after Keycloak deployment (sync-wave 10)
2. Authenticates with Keycloak admin credentials
3. Applies realm configuration from `realm-fineract.yaml`
4. Creates clients, roles, and default users
5. Completes successfully or fails with error

**Apply Realm Configuration:**
```bash
# Trigger job via ArgoCD
argocd app sync keycloak-config -n argocd

# Or manually
kubectl apply -f operations/keycloak-config/base/jobs/apply-keycloak-config.yaml
```

**Verify Configuration:**
```bash
# Check job status
kubectl get jobs -n fineract-dev | grep apply-keycloak-config

# View job logs
kubectl logs job/apply-keycloak-config -n fineract-dev

# Access admin console
# Navigate to https://auth.fineract.example.com/auth/admin/
# Check realm "fineract" exists with 4 clients
```

See `/operations/keycloak-config/README.md` for comprehensive realm configuration documentation.

## User Management

### Default Users (Dev/UAT Only)

For development and UAT environments, default test users are created:

**Default Users** (see `/operations/keycloak-config/base/config/users-default.yaml`):
- `admin@fineract.com` - Admin role
- `manager@fineract.com` - Manager role
- `teller@fineract.com` - Teller role
- `loan.officer@fineract.com` - Loan Officer role

**⚠️ Production**: Default users are NOT created in production. Users must be created via:
1. User Sync Service (Fineract → Keycloak)
2. Keycloak Admin Console
3. Keycloak User Management API

### User Sync Service

**User Sync Service** (`/operations/keycloak-config/user-sync-service/`):
Automatically synchronizes users from Fineract to Keycloak.

**How It Works:**
1. Fineract sends webhook on user creation/update
2. User Sync Service receives webhook
3. Service calls Keycloak Admin API to create/update user
4. User assigned appropriate roles based on Fineract staff role
5. User can immediately login via Keycloak

**Deployment:**
```bash
# Deploy user sync service
kubectl apply -k operations/keycloak-config/user-sync-service/base/

# Check logs
kubectl logs deployment/user-sync-service -n fineract-dev
```

See `/operations/keycloak-config/user-sync-service/README.md` for detailed setup.

### Manual User Creation

**Via Admin Console:**
1. Navigate to `https://auth.fineract.example.com/auth/admin/`
2. Login with admin credentials
3. Select realm: `fineract`
4. Navigate to Users → Add user
5. Set username, email, first name, last name
6. Navigate to Credentials → Set password
7. Navigate to Role Mappings → Assign realm roles

**Via Keycloak Admin API:**
```bash
# Get admin token
ADMIN_TOKEN=$(curl -X POST "https://auth.fineract.example.com/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

# Create user
curl -X POST "https://auth.fineract.example.com/auth/admin/realms/fineract/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john.doe@fineract.com",
    "email": "john.doe@fineract.com",
    "firstName": "John",
    "lastName": "Doe",
    "enabled": true,
    "credentials": [{
      "type": "password",
      "value": "ChangeMe123!",
      "temporary": true
    }],
    "realmRoles": ["loan_officer"]
  }'
```

## Monitoring and Health Checks

### Health Endpoints

Keycloak 24.x exposes health endpoints on the main HTTP port (8080):

**Endpoints:**
- Health: `/auth/health/`
- Liveness: `/auth/health/live`
- Readiness: `/auth/health/ready`
- Startup: `/auth/health/started`

**Check Health:**
```bash
# From within cluster
kubectl exec -it deployment/keycloak -n fineract-dev -- \
  curl http://localhost:8080/auth/health

# Response:
# {"status":"UP","checks":[{"name":"Keycloak database connection","status":"UP"}]}

# Via port-forward
kubectl port-forward svc/keycloak-service 8080:8080 -n fineract-dev
curl http://localhost:8080/auth/health
```

### Kubernetes Probes

**Startup Probe:**
```yaml
startupProbe:
  httpGet:
    path: /auth/health/started
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 120  # 20 minutes max for initial Quarkus build
```

**Purpose**: Wait for Keycloak initial startup (Quarkus build on first run can take 5-10 minutes)

**Liveness Probe:**
```yaml
livenessProbe:
  httpGet:
    path: /auth/health/live
    port: 8080
  initialDelaySeconds: 120
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
```

**Purpose**: Restart pod if Keycloak becomes unresponsive (after 3 failures = 90 seconds)

**Readiness Probe:**
```yaml
readinessProbe:
  httpGet:
    path: /auth/health/ready
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Purpose**: Remove pod from service load balancer if not ready (after 3 failures = 30 seconds)

### Prometheus Metrics

Keycloak exposes Prometheus metrics at `/metrics` endpoint (enabled via `--metrics-enabled=true` startup arg).

**ServiceMonitor** (if using Prometheus Operator):
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: keycloak
spec:
  selector:
    matchLabels:
      app: keycloak
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

**Key Metrics:**
- `keycloak_sessions_active` - Active user sessions
- `keycloak_logins_total` - Total successful logins
- `keycloak_login_errors_total` - Failed login attempts
- `keycloak_registrations_total` - New user registrations
- `jvm_memory_used_bytes` - JVM memory usage
- `jvm_gc_pause_seconds` - Garbage collection pause time
- `http_server_requests_seconds` - HTTP request latency

**Prometheus Alerts** (see `/operations/keycloak-config/monitoring/prometheus-rules.yaml`):
- High failed login rate (brute force detection)
- High session count
- Database connection failures
- High response latency

**Grafana Dashboard** (see `/operations/keycloak-config/monitoring/grafana-dashboard.json`):
- 12 panels for comprehensive Keycloak monitoring
- Login success/failure rates
- Active sessions
- Response times
- Database connection pool

### Logging

**Log Levels:**
- Default: `INFO`
- Debug: Set `KC_LOG_LEVEL=DEBUG` for troubleshooting

**View Logs:**
```bash
# Tail logs
kubectl logs -f deployment/keycloak -n fineract-dev

# View logs from last hour
kubectl logs deployment/keycloak -n fineract-dev --since=1h

# Search for errors
kubectl logs deployment/keycloak -n fineract-dev | grep -i error
```

**Log Aggregation:**
Logs are collected by Loki/Promtail and available in Grafana (see `/apps/logging/`).

## Troubleshooting

### Common Issues

#### 1. Pod Stuck in Init:0/1 (deploy-webank-theme)

**Symptom**: Pod stuck in init container, theme deployment failed.

**Diagnosis:**
```bash
# Check init container logs
kubectl logs deployment/keycloak -n fineract-dev -c deploy-webank-theme

# Check PVC exists
kubectl get pvc keycloak-themes -n fineract-dev

# Check ConfigMaps exist
kubectl get configmap keycloak-webank-theme -n fineract-dev
kubectl get configmap keycloak-webank-theme-css -n fineract-dev
```

**Solution:**
```bash
# If PVC doesn't exist, create it
kubectl apply -f apps/keycloak/base/themes-pvc.yaml

# If ConfigMaps don't exist, create them
kubectl apply -f apps/keycloak/base/theme-configmap.yaml
kubectl apply -f apps/keycloak/base/theme-css-configmap.yaml

# Restart pod
kubectl delete pod -l app=keycloak -n fineract-dev
```

#### 2. Database Connection Failed

**Symptom**: Pod crash with "Unable to connect to database" error.

**Diagnosis:**
```bash
# Check database secret
kubectl get secret keycloak-db-credentials -n fineract-dev -o yaml

# Test database connectivity
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -n fineract-dev -- \
  psql -h DB_HOST -U DB_USER -d keycloak -c "SELECT 1;"

# Check logs for connection errors
kubectl logs deployment/keycloak -n fineract-dev | grep -i database
```

**Solution:**
```bash
# Verify RDS security group allows EKS node IPs
# Verify database credentials in secret are correct
# Verify database name exists (CREATE DATABASE keycloak;)

# Update secret if needed
kubectl delete secret keycloak-db-credentials -n fineract-dev
kubectl create secret generic keycloak-db-credentials \
  --from-literal=host=correct-rds-endpoint.rds.amazonaws.com \
  --from-literal=port=5432 \
  --from-literal=database=keycloak \
  --from-literal=username=keycloak \
  --from-literal=password=correct-password \
  -n fineract-dev
```

#### 3. Admin Console 403 Forbidden

**Symptom**: Cannot access admin console, 403 Forbidden error.

**Cause**: Admin credentials incorrect or admin user not created.

**Diagnosis:**
```bash
# Check admin secret
kubectl get secret keycloak-admin-credentials -n fineract-dev -o yaml

# Check Keycloak logs for admin user creation
kubectl logs deployment/keycloak -n fineract-dev | grep -i "Admin credentials"

# Test login via API
curl -X POST "https://auth.fineract.example.com/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" \
  -d "client_id=admin-cli"
```

**Solution:**
```bash
# Update admin credentials secret
kubectl delete secret keycloak-admin-credentials -n fineract-dev
kubectl create secret generic keycloak-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=NewStrongPassword123! \
  -n fineract-dev

# Delete pod to recreate admin user
kubectl delete pod -l app=keycloak -n fineract-dev
```

#### 4. Realm "fineract" Not Found

**Symptom**: Login fails with "Realm not found" error.

**Cause**: Realm configuration job not run or failed.

**Diagnosis:**
```bash
# Check realm config job status
kubectl get jobs -n fineract-dev | grep apply-keycloak-config

# View job logs
kubectl logs job/apply-keycloak-config -n fineract-dev

# List realms via API
curl -X GET "https://auth.fineract.example.com/auth/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

**Solution:**
```bash
# Run realm configuration job
kubectl delete job apply-keycloak-config -n fineract-dev
kubectl apply -f operations/keycloak-config/base/jobs/apply-keycloak-config.yaml

# Or manually create realm via admin console
# Navigate to https://auth.fineract.example.com/auth/admin/
# Click "Add realm" → Name: "fineract"
```

#### 5. Slow Login (>10 seconds)

**Symptom**: Login page loads slowly or takes >10 seconds to authenticate.

**Cause**: Insufficient resources, database latency, or theme caching issues.

**Diagnosis:**
```bash
# Check pod resource usage
kubectl top pod -n fineract-dev -l app=keycloak

# Check database latency
kubectl exec -it deployment/keycloak -n fineract-dev -- \
  time psql -h $KC_DB_URL_HOST -U $KC_DB_USERNAME -d $KC_DB_URL_DATABASE -c "SELECT 1;"

# Check logs for slow queries
kubectl logs deployment/keycloak -n fineract-dev | grep -i "slow query"
```

**Solution:**
```bash
# Increase resources
# Edit deployment resources:
resources:
  requests:
    memory: "768Mi"
    cpu: "400m"
  limits:
    memory: "1.5Gi"
    cpu: "1000m"

# Increase JVM heap
env:
  - name: JAVA_OPTS
    value: "-Xms512m -Xmx1024m"

# Apply changes
kubectl apply -k apps/keycloak/overlays/dev/
```

#### 6. OAuth2 Token Validation Failed

**Symptom**: Fineract returns 403 Forbidden with "Invalid token" error.

**Cause**: JWT issuer mismatch or JWK Set unreachable.

**Diagnosis:**
```bash
# Check Keycloak issuer URL
kubectl exec -it deployment/keycloak -n fineract-dev -- \
  curl http://localhost:8080/auth/realms/fineract/.well-known/openid-configuration | jq '.issuer'

# Check JWK Set endpoint
kubectl exec -it deployment/keycloak -n fineract-dev -- \
  curl http://localhost:8080/auth/realms/fineract/protocol/openid-connect/certs

# Test from Fineract pod
kubectl exec -it fineract-write-xxx -n fineract-dev -- \
  curl http://keycloak-service:8080/auth/realms/fineract/protocol/openid-connect/certs
```

**Solution:**
```bash
# Verify hostname configuration matches issuer
# Issuer in OIDC config must match --hostname startup arg

# Check Keycloak deployment args
kubectl get deployment keycloak -n fineract-dev -o yaml | grep hostname

# Update if needed via overlay kustomization
```

### Useful Commands

```bash
# View all Keycloak resources
kubectl get all -n fineract-dev -l app=keycloak

# Check pod events
kubectl get events -n fineract-dev --sort-by='.lastTimestamp' | grep keycloak

# Describe pod for detailed status
kubectl describe pod -l app=keycloak -n fineract-dev

# Execute shell in pod
kubectl exec -it deployment/keycloak -n fineract-dev -- /bin/bash

# Test admin login via API
curl -X POST "https://auth.fineract.example.com/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" \
  -d "client_id=admin-cli"

# View PVC usage
kubectl get pvc -n fineract-dev
kubectl exec -it deployment/keycloak -n fineract-dev -- df -h /opt/keycloak/data
```

## Security

### Security Hardening

**Pod Security Context:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

**Container Security Context:**
```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  runAsNonRoot: true
```

### Network Policies

Keycloak is subject to Kubernetes NetworkPolicies (see `/apps/network-policies/` and `/operations/keycloak-config/security-policies/`):

**Ingress:**
- Allow from OAuth2-Proxy
- Allow from Ingress NGINX
- Allow from Fineract pods (JWK Set requests)
- Allow from Prometheus (metrics)

**Egress:**
- Allow to PostgreSQL RDS (port 5432)
- Allow to DNS (port 53)

**Production**: Admin console access can be restricted via NetworkPolicy (see `/operations/keycloak-config/security-policies/network-policy-production.yaml`).

### TLS/HTTPS

- Ingress uses TLS certificates from Cert-Manager (Let's Encrypt)
- Keycloak runs in HTTP-only mode behind Ingress (TLS termination at Ingress)
- Database connections use TLS (`KC_DB_URL_PROPERTIES=?sslmode=require`)

### Secret Management

All sensitive data is stored in Sealed Secrets:

**Secrets:**
- `keycloak-db-credentials`: Database credentials
- `keycloak-admin-credentials`: Admin username and password
- `keycloak-client-secrets`: OAuth2 client secrets (managed in realm config)

**Sealed Secrets Controller**: Decrypts sealed secrets at runtime (see `/apps/sealed-secrets-controller/`)

## Related Documentation

### Core Documentation
- [Architecture Overview](/docs/architecture/README.md)
- [Authentication and Routing](/docs/operations/AUTHENTICATION_AND_ROUTING.md)
- [Secrets Management](/docs/SECRETS_MANAGEMENT.md)

### Component Documentation
- [Fineract (Resource Server)](/apps/fineract/README.md)
- [OAuth2-Proxy](/apps/oauth2-proxy/base/README.md)
- [Ingress NGINX](/apps/ingress-nginx/base/README.md)
- [Network Policies](/apps/network-policies/README.md)

### Operations Documentation
- [Keycloak Configuration](/operations/keycloak-config/README.md) - **Comprehensive realm configuration**
- [Keycloak Security](/operations/keycloak-config/docs/SECURITY.md)
- [Keycloak Role Mapping](/operations/keycloak-config/ROLE_MAPPING.md)
- [User Sync Service](/operations/keycloak-config/user-sync-service/README.md)
- [Database Setup](/operations/keycloak-database-setup/README.md)

### External Resources
- [Keycloak Official Documentation](https://www.keycloak.org/documentation)
- [Keycloak Server Configuration](https://www.keycloak.org/server/configuration)
- [Keycloak Hostname Configuration](https://www.keycloak.org/server/hostname)
- [Keycloak Reverse Proxy Setup](https://www.keycloak.org/server/reverseproxy)

---

**Last Updated**: 2025-01-19
**Maintainer**: DevOps Team
**Keycloak Version**: 24.0.5
