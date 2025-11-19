# Fineract Application

Apache Fineract is an open-source, cloud-native core banking platform designed for financial service providers. This directory contains the Kubernetes manifests for deploying Fineract in a multi-instance architecture optimized for performance, scalability, and high availability.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [Multi-Instance Design](#multi-instance-design)
  - [Component Overview](#component-overview)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Database Configuration](#database-configuration)
  - [OAuth2 Authentication](#oauth2-authentication)
  - [S3 Document Storage](#s3-document-storage)
  - [Redis Caching](#redis-caching)
- [Deployment](#deployment)
  - [Prerequisites](#prerequisites)
  - [ArgoCD Deployment](#argocd-deployment)
  - [Manual Deployment](#manual-deployment)
- [Scaling](#scaling)
  - [Horizontal Pod Autoscaling](#horizontal-pod-autoscaling)
  - [Batch Worker Scaling](#batch-worker-scaling)
- [Monitoring and Health Checks](#monitoring-and-health-checks)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Related Documentation](#related-documentation)

## Overview

This Fineract deployment implements a **multi-instance architecture** that separates read, write, and batch workloads for optimal performance and resource utilization. The application is deployed in a Kubernetes cluster with full GitOps automation using ArgoCD.

**Key Features:**
- Multi-instance architecture (read/write/batch separation)
- OAuth2/OIDC authentication via Keycloak
- AWS S3 document storage with IRSA (IAM Roles for Service Accounts)
- Redis caching for improved performance
- PostgreSQL database (AWS RDS)
- Horizontal Pod Autoscaling (HPA) for read instances
- Database schema migrations managed by dedicated job
- Pod Disruption Budgets (PDB) for high availability
- Security hardening with read-only root filesystem

## Architecture

### Multi-Instance Design

The deployment follows Apache Fineract's recommended architecture (ADR-002) with three specialized instance types:

```
┌─────────────────────────────────────────────────────────┐
│                      Ingress + OAuth2                    │
└─────────────────┬───────────────────────┬────────────────┘
                  │                       │
         ┌────────▼────────┐     ┌───────▼────────┐
         │  Fineract-Read  │     │ Fineract-Write │
         │  (1-5 replicas) │     │  (1 replica)   │
         │  HPA enabled    │     │  Session affin.│
         └────────┬────────┘     └───────┬────────┘
                  │                       │
         ┌────────┴───────────────────────┘
         │
┌────────▼─────────┐    ┌──────────────────┐    ┌──────────────┐
│ Fineract-Batch   │───▶│  PostgreSQL RDS  │◀───│ Redis Cache  │
│ (0-N replicas)   │    │  (Managed)       │    │ (StatefulSet)│
└──────────────────┘    └──────────────────┘    └──────────────┘
         │                       │
         └───────────────────────▼
              ┌──────────────────────────┐
              │  AWS S3 Document Storage │
              │  (IRSA authentication)   │
              └──────────────────────────┘
```

#### 1. **Fineract-Read** (Read-Optimized Instances)
- **Purpose**: Handle all read-only API requests (GET operations)
- **Replicas**: 1-5 (auto-scales based on CPU utilization)
- **Mode Flags**:
  - `FINERACT_MODE_READ_ENABLED=true`
  - `FINERACT_MODE_WRITE_ENABLED=false`
  - `FINERACT_MODE_BATCH_ENABLED=false`
- **Resources**:
  - Requests: 500m CPU, 1Gi memory
  - Limits: 2000m CPU, 2Gi memory
- **Scaling**: HPA enabled (80% CPU threshold)
- **Health**: Startup probe with 40-minute window for DB migration

#### 2. **Fineract-Write** (Write-Optimized Instances)
- **Purpose**: Handle all write API requests (POST, PUT, DELETE, PATCH)
- **Replicas**: 1 (single instance with session affinity)
- **Mode Flags**:
  - `FINERACT_MODE_READ_ENABLED=true` (can also serve reads)
  - `FINERACT_MODE_WRITE_ENABLED=true`
  - `FINERACT_MODE_BATCH_ENABLED=false`
- **Resources**:
  - Requests: 400m CPU, 1.5Gi memory
  - Limits: 1500m CPU, 3Gi memory
- **Session Affinity**: ClientIP (3-hour timeout for in-flight transactions)
- **JVM Config**: `-Xmx2048m -Xms512m`

#### 3. **Fineract-Batch** (Batch Worker Instances)
- **Purpose**: Execute scheduled batch jobs (COB, interest posting, etc.)
- **Replicas**: 0 (scaled on-demand)
- **Mode Flags**:
  - `FINERACT_MODE_READ_ENABLED=false`
  - `FINERACT_MODE_WRITE_ENABLED=false`
  - `FINERACT_MODE_BATCH_ENABLED=true`
- **Resources**:
  - Requests: 500m CPU, 1Gi memory
  - Limits: 2000m CPU, 2Gi memory
- **Scaling**: Manual or scheduled (CronJob, KEDA)

See [Scaling](#scaling) section for batch worker scaling strategies.

### Component Overview

The Fineract application directory contains the following Kubernetes resources:

**Base Resources** (`/apps/fineract/base/`):
- `deployment-read.yaml` - Read-optimized Fineract deployment
- `deployment-write.yaml` - Write-optimized Fineract deployment
- `deployment-batch.yaml` - Batch worker deployment (default: 0 replicas)
- `service.yaml` - ClusterIP services for all three instance types
- `service-account.yaml` - ServiceAccount with IRSA annotations for AWS S3
- `configmap.yaml` - Application configuration (currently empty)
- `fineract-oauth2-config.yaml` - OAuth2/OIDC configuration
- `hpa-read.yaml` - HorizontalPodAutoscaler for read instances
- `hpa-batch.yaml` - HorizontalPodAutoscaler for batch workers
- `pdb-read.yaml` - PodDisruptionBudget for read instances
- `pdb-write.yaml` - PodDisruptionBudget for write instance
- `pdb-batch.yaml` - PodDisruptionBudget for batch workers
- `rbac-configmap.yaml` - RBAC for accessing ConfigMaps
- `scale-up-cronjob.yaml` - Automated scaling up (optional)
- `scale-down-cronjob.yaml` - Automated scaling down (optional)
- `rds-shutdown-cronjob.yaml` - RDS management (cost optimization)

**Environment Overlays**:
- Managed through Kustomize overlays in `/environments/{dev,uat,prod}/`
- Each environment can override image tags, resource limits, replica counts, etc.

## Configuration

### Environment Variables

Fineract is configured entirely through environment variables. Key configuration categories:

#### Database Configuration

| Variable | Description | Source | Example |
|----------|-------------|--------|---------|
| `FINERACT_HIKARI_DRIVER_SOURCE_CLASS_NAME` | JDBC driver class | ConfigMap | `org.postgresql.Driver` |
| `FINERACT_HIKARI_JDBC_URL` | Database JDBC URL | Secret | `jdbc:postgresql://db.example.com:5432/fineract_tenants` |
| `FINERACT_HIKARI_USERNAME` | Database username | Secret | `fineract` |
| `FINERACT_HIKARI_PASSWORD` | Database password | Secret | `<secret>` |
| `FINERACT_DEFAULT_TENANTDB_HOSTNAME` | Tenant DB host | Secret | `db.example.com` |
| `FINERACT_DEFAULT_TENANTDB_PORT` | Tenant DB port | ConfigMap | `5432` |
| `FINERACT_DEFAULT_TENANTDB_NAME` | Tenant DB name | ConfigMap | `fineract_default` |
| `FINERACT_DEFAULT_TENANTDB_IDENTIFIER` | Tenant identifier | ConfigMap | `default` |
| `FINERACT_DEFAULT_TENANTDB_UID` | Tenant DB username | Secret | `fineract` |
| `FINERACT_DEFAULT_TENANTDB_PWD` | Tenant DB password | Secret | `<secret>` |

**Secret Name**: `fineract-db-credentials`

#### Instance Mode Configuration

| Variable | Read Instance | Write Instance | Batch Instance |
|----------|---------------|----------------|----------------|
| `FINERACT_MODE_READ_ENABLED` | `true` | `true` | `false` |
| `FINERACT_MODE_WRITE_ENABLED` | `false` | `true` | `false` |
| `FINERACT_MODE_BATCH_ENABLED` | `false` | `false` | `true` |

#### OAuth2/OIDC Configuration

| Variable | Description | Source | Example |
|----------|-------------|--------|---------|
| `FINERACT_SECURITY_BASICAUTH_ENABLED` | Enable basic auth | ConfigMap | `false` |
| `FINERACT_SECURITY_OAUTH_ENABLED` | Enable OAuth2 | ConfigMap | `true` |
| `FINERACT_SERVER_OAUTH_RESOURCE_URL` | OAuth2 issuer URL | ConfigMap | `https://auth.example.com/realms/fineract` |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | JWT issuer (must match token 'iss' claim) | ConfigMap | `https://auth.example.com/realms/fineract` |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI` | JWK Set URI for token validation | ConfigMap | `http://keycloak-service:8080/realms/fineract/protocol/openid-connect/certs` |

**ConfigMap Name**: `fineract-oauth2-config`

See [OAuth2 Authentication](#oauth2-authentication) for detailed setup.

#### S3 Document Storage Configuration

| Variable | Description | Source | Example |
|----------|-------------|--------|---------|
| `FINERACT_CONTENT_S3_ENABLED` | Enable S3 storage | ConfigMap | `true` |
| `FINERACT_CONTENT_S3_BUCKET_NAME` | S3 bucket name | Secret | `fineract-documents-prod` |
| `FINERACT_CONTENT_S3_REGION` | AWS region | Secret | `us-east-1` |

**Secret Name**: `s3-connection`

**Authentication**: AWS credentials are provided via IRSA (IAM Roles for Service Accounts). The ServiceAccount is annotated with `eks.amazonaws.com/role-arn` to assume an IAM role with S3 access.

See [S3 Document Storage](#s3-document-storage) for IRSA setup.

#### Redis Cache Configuration

| Variable | Description | Value |
|----------|-------------|-------|
| `SPRING_CACHE_TYPE` | Cache provider | `redis` |
| `SPRING_REDIS_HOST` | Redis hostname | `fineract-redis` |
| `SPRING_REDIS_PORT` | Redis port | `6379` |
| `SPRING_CACHE_REDIS_TIME_TO_LIVE` | TTL in milliseconds | `3600000` (1 hour) |
| `SPRING_CACHE_REDIS_KEY_PREFIX` | Key prefix | `fineract:cache:` |

**Redis Deployment**: In-cluster StatefulSet (see `/apps/fineract-redis/`)

#### Liquibase Migration Configuration

| Variable | Description | Value | Notes |
|----------|-------------|-------|-------|
| `FINERACT_LIQUIBASE_ENABLED` | Enable in-app migrations | `false` | Migrations handled by dedicated job |

**Migration Strategy**: Database schema migrations are executed by a dedicated Kubernetes Job (`fineract-schema-migration`) that runs before application pods start. This follows Fineract best practices (FINERACT-1882) and prevents:
- Race conditions from multiple pods attempting migrations
- Liquibase lock contention
- Deployment delays from long-running migrations

All application pods include an `initContainer` (`wait-for-schema-migration`) that verifies migrations are complete before starting.

#### Internationalization (i18n) Configuration

| Variable | Description | Value | Notes |
|----------|-------------|-------|-------|
| `FINERACT_I18N_ICU_ENABLED` | Enable ICU message formatting | `false` | Workaround for Yakworks Grails library bug |

**Background**: Apache Fineract uses the Yakworks Grails MessageSource library for i18n. The library has a known bug with ICU (International Components for Unicode) message formatting where parameter substitution fails with "Missing closing '}' in message format" errors. The workaround is to disable ICU and use standard `MessageFormat`, which works correctly with no functionality loss for typical Fineract use cases.

**Future**: Monitor Yakworks library updates and re-enable ICU when the bug is resolved.

#### JVM Configuration (Write Instance Only)

| Variable | Description | Value |
|----------|-------------|-------|
| `JAVA_OPTS` | JVM options | `-Xmx2048m -Xms512m -Djavax.net.ssl.trustAll=true -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true` |

**Note**: SSL trust settings are for internal development/testing. Review security implications for production use.

#### Logging Configuration (Write Instance Only)

| Variable | Description | Value | Purpose |
|----------|-------------|-------|---------|
| `LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY` | Spring Security log level | `DEBUG` | OAuth2 troubleshooting |
| `LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY_OAUTH2` | OAuth2 log level | `DEBUG` | Token validation debugging |

**Note**: Debug logging is enabled on write instance for OAuth2 troubleshooting. Reduce to `INFO` or `WARN` in production after stabilization.

### Database Configuration

Fineract uses PostgreSQL with two database schemas:
1. **Tenant Database** (`fineract_tenants`): Stores multi-tenancy configuration
2. **Default Tenant Database** (`fineract_default`): Default tenant's data

#### AWS RDS PostgreSQL (Recommended)

This deployment is configured for AWS RDS PostgreSQL (managed service):

**Prerequisites:**
1. Create RDS PostgreSQL instance (PostgreSQL 15+)
2. Create databases:
   ```sql
   CREATE DATABASE fineract_tenants;
   CREATE DATABASE fineract_default;
   ```
3. Create sealed secret `fineract-db-credentials` with keys:
   - `host`: RDS endpoint (e.g., `db.cluster-xxx.us-east-1.rds.amazonaws.com`)
   - `username`: Database username
   - `password`: Database password
   - `jdbc-url`: JDBC URL (e.g., `jdbc:postgresql://host:5432/fineract_tenants`)

**Schema Migrations:**
Database schema migrations are handled by a dedicated Kubernetes Job deployed via ArgoCD:
- Job: `fineract-schema-migration` (see `/operations/fineract-database-init/`)
- Runs before application pods (ArgoCD sync-wave: 5)
- Uses Liquibase to apply changesets
- Holds Liquibase lock during migration

**Migration Process:**
1. Schema migration job runs (sync-wave 5)
2. Job applies Liquibase changesets to `fineract_default` database
3. Job releases Liquibase lock on completion
4. Application pods start (sync-wave 10)
5. Application pod `initContainer` verifies migration completion:
   - Checks `DATABASECHANGELOG` table exists
   - Verifies Liquibase lock is released (`DATABASECHANGELOGLOCK.LOCKED = false`)
   - Waits up to 10 minutes (60 retries × 10s) for migration completion
   - Exits with error if migration times out

### OAuth2 Authentication

Fineract is configured for OAuth2/OIDC authentication using Keycloak as the identity provider.

#### Architecture

```
User → OAuth2-Proxy → Keycloak → Fineract
         │                          │
         └─ Session Cookie          └─ JWT Token Validation
```

**Authentication Flow:**
1. User accesses Fineract via OAuth2-Proxy
2. OAuth2-Proxy redirects to Keycloak for authentication
3. Keycloak validates credentials and issues JWT token
4. OAuth2-Proxy sets session cookie and forwards request with JWT
5. Fineract validates JWT using Keycloak's public keys (JWK Set)
6. Fineract grants access based on JWT claims and roles

#### Configuration Requirements

**ConfigMap** (`fineract-oauth2-config`):
```yaml
data:
  # Public-facing OAuth2 issuer URL (must match JWT 'iss' claim)
  oidc-issuer-url: "https://auth.fineract.example.com/realms/fineract"

  # Internal JWK Set URI for JWT validation (avoids DNS/TLS issues)
  jwk-set-uri-internal: "http://keycloak-service:8080/realms/fineract/protocol/openid-connect/certs"
```

**Key Points:**
- **Issuer URL**: Must be the public HTTPS URL that Keycloak uses in JWT tokens (`iss` claim)
- **JWK Set URI**: Uses internal Kubernetes service name to avoid external DNS/TLS issues
- **Internal vs External**: Issuer URL is external (HTTPS), JWK Set URI is internal (HTTP)

#### Keycloak Configuration

**Realm**: `fineract`

**Required Clients:**
1. **Fineract Backend Client** (`fineract-backend`):
   - Client type: OpenID Connect
   - Access type: Confidential
   - Valid redirect URIs: `https://your-domain.com/*`
   - Web origins: `https://your-domain.com`

2. **OAuth2-Proxy Client** (`oauth2-proxy`):
   - Client type: OpenID Connect
   - Access type: Confidential
   - Valid redirect URIs: `https://your-domain.com/oauth2/callback`

**Realm Roles**:
- Create Fineract roles (e.g., `admin`, `teller`, `loan_officer`)
- Map roles to JWT token claims

**User Setup**:
- Create users in Keycloak
- Assign appropriate realm roles
- Fineract uses JWT claims for authorization

See `/apps/keycloak/` and `/operations/keycloak-config/` for Keycloak deployment and configuration.

#### Troubleshooting OAuth2

**Common Issues:**

1. **403 Forbidden - Invalid Token**
   - **Cause**: JWT issuer mismatch
   - **Check**: Verify `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` matches JWT `iss` claim
   - **Debug**: Check write instance logs for "Invalid token" messages

2. **Cannot Fetch JWK Set**
   - **Cause**: JWK Set URI unreachable from Fineract pods
   - **Check**: Test connectivity: `kubectl exec -it fineract-write-xxx -- curl http://keycloak-service:8080/realms/fineract/protocol/openid-connect/certs`
   - **Fix**: Verify Keycloak service exists and network policies allow traffic

3. **Token Signature Verification Failed**
   - **Cause**: JWK Set cache stale or wrong keys
   - **Fix**: Restart Fineract pods to refresh JWK Set cache

**Debug Logging:**
The write instance has OAuth2 debug logging enabled:
```yaml
env:
  - name: LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY
    value: "DEBUG"
  - name: LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY_OAUTH2
    value: "DEBUG"
```

View logs:
```bash
kubectl logs -f deployment/fineract-write -n <namespace>
```

### S3 Document Storage

Fineract stores documents (client documents, loan documents, etc.) in AWS S3.

#### IRSA (IAM Roles for Service Accounts) Configuration

**Authentication Method**: IRSA (no static access keys required)

**Prerequisites:**
1. **Create IAM Policy** with S3 access:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::fineract-documents-prod",
           "arn:aws:s3:::fineract-documents-prod/*"
         ]
       }
     ]
   }
   ```

2. **Create IAM Role** with trust relationship:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:NAMESPACE:fineract-aws"
           }
         }
       }
     ]
   }
   ```

3. **Annotate ServiceAccount** (`service-account.yaml`):
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: fineract-aws
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/fineract-s3-role
   ```

4. **Create Secret** (`s3-connection`):
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: s3-connection
   stringData:
     documents-bucket: "fineract-documents-prod"
     region: "us-east-1"
   ```

**How IRSA Works:**
1. EKS configures pod with OIDC web identity token
2. AWS SDK in Fineract automatically uses token to assume IAM role
3. IAM role provides temporary credentials for S3 access
4. No static access keys needed (more secure)

**Verification:**
```bash
# Check ServiceAccount annotation
kubectl get sa fineract-aws -n <namespace> -o yaml

# Verify pod has AWS environment variables
kubectl exec -it fineract-write-xxx -n <namespace> -- env | grep AWS

# Test S3 access from pod
kubectl exec -it fineract-write-xxx -n <namespace> -- aws s3 ls s3://fineract-documents-prod/
```

### Redis Caching

Fineract uses Redis for application-level caching to improve performance.

#### Configuration

**Cache Settings:**
- **Cache Type**: Redis
- **Host**: `fineract-redis` (Kubernetes service)
- **Port**: 6379
- **TTL**: 3600000ms (1 hour)
- **Key Prefix**: `fineract:cache:`

**Redis Deployment:**
- Deployed as StatefulSet in `/apps/fineract-redis/`
- Single replica (persistence-enabled)
- 1Gi PersistentVolumeClaim
- Resources: 256Mi memory, 100m CPU

#### Cached Data

Fineract caches:
- Code values and lookup tables
- Client/loan/savings data (short TTL)
- Report definitions
- System configuration

#### Cache Invalidation

Cache entries expire after 1 hour (TTL). For immediate invalidation:

**Option 1: Flush Specific Keys**
```bash
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli KEYS "fineract:cache:*"
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli DEL "fineract:cache:key-name"
```

**Option 2: Flush All Cache**
```bash
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli FLUSHALL
```

**Option 3: Restart Fineract Pods**
```bash
kubectl rollout restart deployment/fineract-read -n <namespace>
kubectl rollout restart deployment/fineract-write -n <namespace>
```

#### Monitoring Redis

```bash
# Check Redis status
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli PING

# View cache statistics
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli INFO stats

# Monitor cache keys
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli KEYS "fineract:cache:*" | wc -l

# Monitor memory usage
kubectl exec -it fineract-redis-0 -n <namespace> -- redis-cli INFO memory
```

## Deployment

### Prerequisites

1. **Kubernetes Cluster**: EKS 1.28+ (or equivalent)
2. **ArgoCD**: Installed and configured (see `/argocd/`)
3. **Sealed Secrets**: Controller installed (see `/apps/sealed-secrets-controller/`)
4. **PostgreSQL Database**: RDS instance with databases created
5. **Keycloak**: Deployed and configured (see `/apps/keycloak/`)
6. **Ingress NGINX**: Installed (see `/apps/ingress-nginx/`)
7. **Cert-Manager**: Installed for TLS certificates (see `/apps/cert-manager/`)

### ArgoCD Deployment

Fineract is deployed via ArgoCD Applications defined in `/argocd/applications/{dev,uat,prod}/fineract.yaml`.

#### Dev Environment

**ArgoCD Application**: `argocd/applications/dev/fineract.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fineract-gitops.git
    targetRevision: main
    path: environments/dev/fineract
  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Allow HPA to manage replicas
```

**Deployment Order (Sync Waves):**
1. Wave 0: Namespace and RBAC
2. Wave 1: Sealed secrets controller
3. Wave 2: Sealed secrets (database, S3)
4. Wave 3: ConfigMaps and ServiceAccounts
5. Wave 5: Database schema migration job
6. Wave 10: Fineract deployments (wait for migration)
7. Wave 15: Services and Ingress

**Deploy to Dev:**
```bash
# Apply ArgoCD application
kubectl apply -f argocd/applications/dev/fineract.yaml

# Monitor deployment
argocd app get fineract -n argocd --watch

# Check sync status
argocd app sync fineract -n argocd

# View sync waves
kubectl get all -n fineract-dev -L argocd.argoproj.io/sync-wave
```

#### UAT/Prod Environments

Same process as Dev, using appropriate ArgoCD application files:
- UAT: `argocd/applications/uat/fineract.yaml`
- Prod: `argocd/applications/prod/fineract.yaml`

Each environment can have different:
- Image tags (e.g., `develop` for dev, `v1.9.0` for prod)
- Resource limits
- Replica counts
- Database instances
- S3 buckets

Environment-specific overrides are in `/environments/{dev,uat,prod}/fineract/`.

### Manual Deployment

For testing without ArgoCD:

```bash
# Navigate to environment
cd environments/dev/fineract

# Apply kustomization
kubectl apply -k .

# Verify deployment
kubectl get all -n fineract-dev -l app.kubernetes.io/name=fineract

# Check pod status
kubectl get pods -n fineract-dev

# View logs
kubectl logs -f deployment/fineract-read -n fineract-dev
kubectl logs -f deployment/fineract-write -n fineract-dev
```

**Note**: Manual deployment requires pre-created secrets and dependencies.

## Scaling

### Horizontal Pod Autoscaling

#### Read Instances

Read instances auto-scale based on CPU utilization:

**HPA Configuration** (`hpa-read.yaml`):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fineract-read
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fineract-read
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
```

**Behavior:**
- Scales up when CPU > 80%
- Scales down when CPU < 80%
- Min: 1 replica, Max: 5 replicas

**Monitor HPA:**
```bash
# View HPA status
kubectl get hpa fineract-read -n fineract-dev

# Watch scaling events
kubectl describe hpa fineract-read -n fineract-dev

# View current metrics
kubectl top pods -n fineract-dev -l app=fineract-read
```

**Tuning HPA:**
Environment overlays can adjust HPA settings:
```yaml
# environments/prod/fineract/hpa-read-patch.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fineract-read
spec:
  minReplicas: 2   # More replicas for prod
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Scale earlier
```

#### Write Instances

Write instances do NOT use HPA by design:
- Single replica ensures consistency
- Session affinity for in-flight transactions
- Database connection pooling optimized for single instance
- Scale vertically by adjusting resource limits

**Vertical Scaling:**
```yaml
# Increase CPU/memory limits
resources:
  requests:
    memory: "2Gi"
    cpu: "800m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

### Batch Worker Scaling

Batch workers are scaled manually or on-demand (default: 0 replicas).

#### Scaling Strategies

**1. Manual Scaling (Ad-hoc Jobs)**
```bash
# Scale up for batch processing
kubectl scale deployment fineract-batch --replicas=1 -n fineract-dev

# Monitor batch job progress
kubectl logs -f deployment/fineract-batch -n fineract-dev

# Scale down after completion
kubectl scale deployment fineract-batch --replicas=0 -n fineract-dev
```

**2. Scheduled Scaling (CronJob)**

The base includes example CronJobs for scheduled scaling:

**Scale Up CronJob** (`scale-up-cronjob.yaml`):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: fineract-batch-scale-up
spec:
  schedule: "0 0 * * *"  # Daily at midnight
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: kubectl
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - kubectl scale deployment fineract-batch --replicas=1 -n fineract-dev
```

**Scale Down CronJob** (`scale-down-cronjob.yaml`):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: fineract-batch-scale-down
spec:
  schedule: "0 6 * * *"  # Daily at 6am
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: kubectl
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - kubectl scale deployment fineract-batch --replicas=0 -n fineract-dev
```

**3. Event-Driven Scaling (KEDA - Recommended)**

For production, use KEDA (Kubernetes Event-Driven Autoscaling):

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: fineract-batch-scaler
spec:
  scaleTargetRef:
    name: fineract-batch
  minReplicaCount: 0
  maxReplicaCount: 5
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      metricName: fineract_batch_jobs_pending
      query: sum(fineract_batch_jobs_pending{status="PENDING"})
      threshold: "1"
```

**4. HPA for Batch Workers**

HPA can scale batch workers based on CPU/memory when workload varies:

**HPA Configuration** (`hpa-batch.yaml`):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fineract-batch
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fineract-batch
  minReplicas: 0
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
```

**Note**: HPA with `minReplicas: 0` requires metrics-server and may have scale-from-zero delays.

## Monitoring and Health Checks

### Health Endpoints

Fineract exposes Spring Boot Actuator endpoints:

**Health Check**: `/fineract-provider/actuator/health`
```bash
# Check read instance health
kubectl exec -it fineract-read-xxx -n fineract-dev -- curl https://localhost:8443/fineract-provider/actuator/health

# Response:
# {"status":"UP","components":{"db":{"status":"UP"},"redis":{"status":"UP"}}}
```

**Info Endpoint**: `/fineract-provider/actuator/info`
**Metrics Endpoint**: `/fineract-provider/actuator/metrics`

### Kubernetes Probes

All Fineract deployments include three types of probes:

#### Startup Probe (Read & Write Instances)
```yaml
startupProbe:
  httpGet:
    path: /fineract-provider/actuator/health
    port: 8443
    scheme: HTTPS
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 80  # 80 × 30s = 40 minutes max startup time
```

**Purpose**: Wait for database schema migration to complete (up to 40 minutes)

#### Liveness Probe (All Instances)
```yaml
livenessProbe:
  httpGet:
    path: /fineract-provider/actuator/health
    port: 8443
    scheme: HTTPS
  initialDelaySeconds: 10
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
```

**Purpose**: Restart pod if Fineract becomes unresponsive (after 3 failures = 90 seconds)

#### Readiness Probe (All Instances)
```yaml
readinessProbe:
  httpGet:
    path: /fineract-provider/actuator/health
    port: 8443
    scheme: HTTPS
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Purpose**: Remove pod from service load balancer if not ready (after 3 failures = 30 seconds)

### Pod Disruption Budgets

PDBs ensure high availability during voluntary disruptions (node drains, cluster upgrades):

**Read Instance PDB** (`pdb-read.yaml`):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fineract-read-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: fineract-read
```

**Write Instance PDB** (`pdb-write.yaml`):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fineract-write-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: fineract-write
```

**Batch Worker PDB** (`pdb-batch.yaml`):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fineract-batch-pdb
spec:
  minAvailable: 0
  selector:
    matchLabels:
      app: fineract-batch
```

### Monitoring with Prometheus

Fineract metrics are exposed for Prometheus scraping:

**ServiceMonitor** (if using Prometheus Operator):
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fineract
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: fineract
  endpoints:
  - port: https
    path: /fineract-provider/actuator/prometheus
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
```

**Key Metrics:**
- `fineract_http_requests_total`: HTTP request count
- `fineract_http_request_duration_seconds`: Request latency
- `fineract_database_connections_active`: Active DB connections
- `fineract_cache_gets_total`: Cache hit/miss stats
- `jvm_memory_used_bytes`: JVM memory usage
- `jvm_gc_pause_seconds`: Garbage collection pause time

**Grafana Dashboards:**
- See `/apps/monitoring/` for pre-configured dashboards

### Logging

Logs are collected by Loki/Promtail and available in Grafana:

**View Logs:**
```bash
# Read instance logs
kubectl logs -f deployment/fineract-read -n fineract-dev

# Write instance logs (with OAuth2 debug)
kubectl logs -f deployment/fineract-write -n fineract-dev

# Batch worker logs
kubectl logs -f deployment/fineract-batch -n fineract-dev

# All Fineract logs
kubectl logs -l app.kubernetes.io/name=fineract -n fineract-dev --tail=100
```

**Log Aggregation:**
- See `/apps/logging/` for Loki/Promtail configuration

## Troubleshooting

### Common Issues

#### 1. Pods Stuck in Init:0/1 (wait-for-schema-migration)

**Symptom**: Fineract pods stuck in init container, waiting for schema migration.

**Cause**: Schema migration job not completed or failed.

**Diagnosis:**
```bash
# Check schema migration job status
kubectl get jobs -n fineract-dev | grep schema-migration

# View job logs
kubectl logs job/fineract-schema-migration -n fineract-dev

# Check Liquibase lock
kubectl exec -it fineract-read-xxx -n fineract-dev -c wait-for-schema-migration -- \
  psql -h $DB_HOST -U $DB_USER -d fineract_default -c "SELECT * FROM DATABASECHANGELOGLOCK;"
```

**Solution:**
```bash
# If migration job failed, fix issue and re-run
kubectl delete job fineract-schema-migration -n fineract-dev
argocd app sync fineract -n argocd

# If Liquibase lock is stuck, release it manually
kubectl exec -it fineract-write-xxx -n fineract-dev -- \
  psql -h $DB_HOST -U $DB_USER -d fineract_default -c "UPDATE DATABASECHANGELOGLOCK SET LOCKED=false WHERE ID=1;"
```

#### 2. 403 Forbidden - OAuth2 Authentication Failed

**Symptom**: API requests return 403 Forbidden with "Invalid token" error.

**Cause**: JWT issuer mismatch or JWK Set unreachable.

**Diagnosis:**
```bash
# Check OAuth2 configuration
kubectl get configmap fineract-oauth2-config -n fineract-dev -o yaml

# Check Fineract logs for OAuth2 errors
kubectl logs deployment/fineract-write -n fineract-dev | grep -i oauth

# Test JWK Set connectivity from Fineract pod
kubectl exec -it fineract-write-xxx -n fineract-dev -- \
  curl http://keycloak-service:8080/realms/fineract/protocol/openid-connect/certs

# Get JWT token and inspect claims
kubectl exec -it oauth2-proxy-xxx -n fineract-dev -- cat /oauth2/token.jwt | base64 -d
```

**Solution:**
```bash
# Fix issuer URL mismatch
kubectl edit configmap fineract-oauth2-config -n fineract-dev
# Set oidc-issuer-url to match JWT 'iss' claim exactly

# Restart Fineract to reload config
kubectl rollout restart deployment/fineract-read -n fineract-dev
kubectl rollout restart deployment/fineract-write -n fineract-dev
```

#### 3. Database Connection Failed

**Symptom**: Pods crash with "Cannot connect to database" error.

**Cause**: Incorrect database credentials or network connectivity issue.

**Diagnosis:**
```bash
# Check database secret
kubectl get secret fineract-db-credentials -n fineract-dev -o yaml

# Test database connectivity from pod
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -n fineract-dev -- \
  psql -h DB_HOST -U DB_USER -d fineract_default -c "SELECT 1;"

# Check network policies
kubectl get networkpolicies -n fineract-dev
```

**Solution:**
```bash
# Verify RDS security group allows EKS node IPs
# Verify database credentials in secret are correct
# Verify network policies allow egress to RDS

# Update secret if needed
kubectl delete secret fineract-db-credentials -n fineract-dev
kubectl create secret generic fineract-db-credentials \
  --from-literal=host=correct-rds-endpoint.rds.amazonaws.com \
  --from-literal=username=fineract \
  --from-literal=password=correct-password \
  -n fineract-dev
```

#### 4. S3 Access Denied

**Symptom**: Document upload fails with "Access Denied" error.

**Cause**: IRSA not configured or IAM role lacks S3 permissions.

**Diagnosis:**
```bash
# Check ServiceAccount annotation
kubectl get sa fineract-aws -n fineract-dev -o yaml | grep eks.amazonaws.com/role-arn

# Check pod environment for AWS variables
kubectl exec -it fineract-write-xxx -n fineract-dev -- env | grep AWS

# Test S3 access from pod
kubectl exec -it fineract-write-xxx -n fineract-dev -- \
  aws s3 ls s3://your-bucket-name/
```

**Solution:**
```bash
# Verify IAM role trust policy includes ServiceAccount
# Verify IAM role has S3 permissions
# Annotate ServiceAccount with correct role ARN
kubectl annotate sa fineract-aws -n fineract-dev \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/fineract-s3-role --overwrite

# Restart pods to pick up new ServiceAccount annotation
kubectl rollout restart deployment/fineract-write -n fineract-dev
```

#### 5. High Memory Usage / OOM Killed

**Symptom**: Pods restarted due to OOMKilled (Out of Memory).

**Cause**: JVM heap size too large or memory leak.

**Diagnosis:**
```bash
# Check pod restart reason
kubectl describe pod fineract-write-xxx -n fineract-dev | grep -A 5 "Last State"

# Check memory usage
kubectl top pod -n fineract-dev -l app=fineract-write

# View JVM memory settings
kubectl exec -it fineract-write-xxx -n fineract-dev -- env | grep JAVA_OPTS
```

**Solution:**
```bash
# Reduce JVM heap size (write instance)
# Edit deployment-write.yaml:
env:
  - name: JAVA_OPTS
    value: "-Xmx1536m -Xms512m"  # Reduce from 2048m

# Increase pod memory limits
resources:
  limits:
    memory: "4Gi"  # Increase from 3Gi

# Apply changes via ArgoCD or kubectl
```

#### 6. Batch Worker Not Processing Jobs

**Symptom**: Batch jobs not executing, workers scaled to 0.

**Cause**: Batch workers are intentionally scaled to 0 by default.

**Diagnosis:**
```bash
# Check batch worker replica count
kubectl get deployment fineract-batch -n fineract-dev

# Check if CronJob scaling is configured
kubectl get cronjobs -n fineract-dev | grep fineract-batch
```

**Solution:**
```bash
# Scale up batch workers manually
kubectl scale deployment fineract-batch --replicas=1 -n fineract-dev

# Or enable scheduled scaling (see Scaling section)
kubectl apply -f apps/fineract/base/scale-up-cronjob.yaml
kubectl apply -f apps/fineract/base/scale-down-cronjob.yaml
```

#### 7. Slow API Response Times

**Symptom**: API requests taking >5 seconds, users reporting slow performance.

**Cause**: Database queries slow, cache miss rate high, or insufficient resources.

**Diagnosis:**
```bash
# Check pod resource usage
kubectl top pods -n fineract-dev -l app.kubernetes.io/name=fineract

# Check HPA status (read instances)
kubectl get hpa fineract-read -n fineract-dev

# Check Redis cache hit rate
kubectl exec -it fineract-redis-0 -n fineract-dev -- redis-cli INFO stats | grep keyspace

# Check database connection pool
kubectl exec -it fineract-write-xxx -n fineract-dev -- \
  curl https://localhost:8443/fineract-provider/actuator/metrics/hikari.connections.active
```

**Solution:**
```bash
# Scale up read instances
kubectl scale deployment fineract-read --replicas=3 -n fineract-dev

# Adjust HPA thresholds to scale earlier
# Edit hpa-read.yaml: averageUtilization: 60 (from 80)

# Increase cache TTL
# Edit deployments: SPRING_CACHE_REDIS_TIME_TO_LIVE: "7200000" (2 hours)

# Increase resources
# Edit deployments: increase CPU/memory requests and limits
```

### Debug Mode

To enable additional debugging:

**1. Enable Spring Debug Logging:**
```yaml
env:
  - name: LOGGING_LEVEL_ROOT
    value: "DEBUG"
  - name: LOGGING_LEVEL_ORG_APACHE_FINERACT
    value: "DEBUG"
```

**2. Enable SQL Query Logging:**
```yaml
env:
  - name: LOGGING_LEVEL_ORG_HIBERNATE_SQL
    value: "DEBUG"
  - name: LOGGING_LEVEL_ORG_HIBERNATE_TYPE_DESCRIPTOR_SQL_BASICBINDER
    value: "TRACE"
```

**3. Remote Debugging:**
```yaml
env:
  - name: JAVA_OPTS
    value: "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
ports:
  - containerPort: 5005
    name: jvm-debug
```

```bash
# Port-forward debug port
kubectl port-forward deployment/fineract-write 5005:5005 -n fineract-dev

# Connect IntelliJ/Eclipse debugger to localhost:5005
```

### Useful Commands

```bash
# View all Fineract resources
kubectl get all -n fineract-dev -l app.kubernetes.io/name=fineract

# Check pod events
kubectl get events -n fineract-dev --sort-by='.lastTimestamp' | grep fineract

# Describe pod for detailed status
kubectl describe pod fineract-write-xxx -n fineract-dev

# Execute shell in pod
kubectl exec -it fineract-write-xxx -n fineract-dev -- /bin/sh

# Copy files from pod
kubectl cp fineract-dev/fineract-write-xxx:/tmp/logs.txt ./logs.txt

# View resource usage over time
watch kubectl top pods -n fineract-dev

# Test API endpoint from within cluster
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -n fineract-dev -- \
  curl -k https://fineract-write-service:8443/fineract-provider/actuator/health
```

## Security

### Security Context

All Fineract pods run with security hardening:

**Pod Security Context:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 2000
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
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
```

### Read-Only Root Filesystem

Containers use read-only root filesystem with writable `/tmp`:

```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp
volumes:
- name: tmp
  emptyDir: {}
```

### Network Policies

Fineract pods are subject to Kubernetes NetworkPolicies (see `/apps/network-policies/`):

**Ingress:**
- Allow from OAuth2-Proxy
- Allow from Ingress NGINX
- Allow from Prometheus (metrics)

**Egress:**
- Allow to PostgreSQL RDS (port 5432)
- Allow to Redis (port 6379)
- Allow to Keycloak (port 8080)
- Allow to AWS S3 (HTTPS)
- Allow DNS (port 53)

### Secret Management

All sensitive data is stored in Sealed Secrets:

**Secrets:**
- `fineract-db-credentials`: Database credentials
- `s3-connection`: S3 bucket name and region
- `keycloak-client-secrets`: OAuth2 client secrets

**Sealed Secrets Controller**: Decrypts sealed secrets at runtime (see `/apps/sealed-secrets-controller/`)

### IRSA (IAM Roles for Service Accounts)

S3 access uses IRSA instead of static access keys:
- ServiceAccount annotated with IAM role ARN
- AWS SDK automatically assumes role via OIDC
- No long-lived credentials in cluster
- Auditable in CloudTrail

### TLS/HTTPS

- Ingress uses TLS certificates from Cert-Manager (Let's Encrypt)
- Inter-service communication uses mTLS where applicable
- Fineract exposes HTTPS on port 8443 (self-signed cert)

## Related Documentation

### Core Documentation
- [Architecture Overview](/docs/architecture/README.md)
- [Deployment Guide](/docs/DEPLOYMENT_GUIDE_EKS.md)
- [Operations Guide](/docs/OPERATIONS_GUIDE.md)
- [Secrets Management](/docs/SECRETS_MANAGEMENT.md)

### Component Documentation
- [Keycloak (OAuth2 Provider)](/apps/keycloak/README.md)
- [OAuth2-Proxy](/apps/oauth2-proxy/base/README.md)
- [Redis Cache](/apps/fineract-redis/base/README.md)
- [Ingress NGINX](/apps/ingress-nginx/base/README.md)
- [Network Policies](/apps/network-policies/README.md)

### Operations Documentation
- [Database Initialization](/operations/fineract-database-init/README.md)
- [Fineract Data Loading](/operations/fineract-data/README.md)
- [Keycloak Configuration](/operations/keycloak-config/README.md)
- [Disaster Recovery](/docs/operations/DISASTER_RECOVERY.md)

### ArgoCD Documentation
- [ArgoCD Setup](/argocd/README.md)
- [Sync Waves](/argocd/SYNC-WAVES.md)
- [ApplicationSets](/argocd/applications/README.md)

### Architecture Decisions
- [ADR-002: Multi-Instance Fineract](/docs/architecture/ADR-002-multi-instance-fineract.md)
- [ADR-003: Sealed Secrets](/docs/architecture/ADR-003-sealed-secrets.md)

---

**Last Updated**: 2025-01-19
**Maintainer**: DevOps Team
**Apache Fineract Version**: 1.9.0 (develop branch)
