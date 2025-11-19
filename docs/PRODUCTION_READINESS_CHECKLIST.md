# Production Readiness Checklist

**Document Version**: 1.0
**Last Updated**: 2025-01-19
**Status**: Active
**Audience**: DevOps Engineers, Platform Team, Release Managers

---

## Overview

This document defines the requirements and checklist for deploying the Fineract GitOps platform to production. All items in this checklist must be completed and verified before production deployment.

### Purpose

- Ensure production deployments meet security, reliability, and performance standards
- Provide clear acceptance criteria for production readiness
- Document required configurations specific to production environment
- Establish deployment and verification procedures

### Production Definition

**Production environment** is defined as:
- User-facing system serving real customers
- Contains actual financial data (not test data)
- Subject to SLAs and uptime requirements
- Requires change control and approval processes
- Must comply with regulatory and audit requirements

---

## Table of Contents

1. [Mandatory Fixes Before Production](#mandatory-fixes-before-production)
2. [Production Configuration Requirements](#production-configuration-requirements)
3. [Security Hardening](#security-hardening)
4. [High Availability Requirements](#high-availability-requirements)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Backup & Disaster Recovery](#backup--disaster-recovery)
7. [Performance Requirements](#performance-requirements)
8. [Compliance Requirements](#compliance-requirements)
9. [Pre-Deployment Validation](#pre-deployment-validation)
10. [Production Deployment Procedure](#production-deployment-procedure)
11. [Post-Deployment Verification](#post-deployment-verification)
12. [Production vs Dev/UAT Comparison](#production-vs-devuat-comparison)
13. [Sign-Off Requirements](#sign-off-requirements)

---

## Mandatory Fixes Before Production

These items from the [Audit Findings](./AUDIT_FINDINGS_2025-01-19.md) **MUST** be resolved before production deployment.

### Critical Issues (P0 - Blocking)

#### 1. Pin All Container Image Versions

**Status**: ❌ Required
**Reference**: Audit Finding #1, #2
**Effort**: 2 hours

**What to do**:
```bash
# Update the following files with specific version tags:

# apps/fineract-redis/base/statefulset.yaml
image: redis:7.2.4-alpine  # Currently: redis (no tag)
image: oliver006/redis_exporter:v1.55.0-alpine  # Currently: no tag

# apps/oauth2-proxy/base/deployment.yaml
image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1  # Currently: no tag
image: curlimages/curl:8.5.0  # Currently: no tag

# apps/fineract/base/deployment-*.yaml (all 3 files)
image: apache/fineract:1.8.4  # Currently: develop tag

# apps/user-sync-service/base/deployment.yaml
image: ghcr.io/adorsys-gis/keycloak-user-sync:v1.2.3  # Currently: latest
```

**Verification**:
```bash
# Check no :latest or missing tags in production overlays
grep -r "image:" environments/production/ | grep -E "(latest|image:[^:]+$)"
# Should return no results
```

---

#### 2. Update Let's Encrypt Email Address

**Status**: ❌ Required
**Reference**: Audit Finding #4
**Effort**: 15 minutes

**What to do**:
```yaml
# Create: environments/production/patches/cert-manager-email.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: devops@your-organization.com  # UPDATE THIS

---
# Add to: environments/production/kustomization.yaml
patches:
  - path: patches/cert-manager-email.yaml
    target:
      kind: ClusterIssuer
      name: letsencrypt-prod
```

**Verification**:
```bash
# Verify email is not placeholder
kubectl get clusterissuer letsencrypt-prod -o yaml | grep email
# Should show actual email, not example.com
```

---

#### 3. Configure Cloud-Specific Storage Classes

**Status**: ❌ Required
**Reference**: Audit Finding #3
**Effort**: 2 hours

**What to do**:
```yaml
# Create: environments/production/patches/storage-class.yaml
# For AWS:
- op: add
  path: /spec/storageClassName
  value: gp3

# For Azure:
- op: add
  path: /spec/storageClassName
  value: managed-premium

# For GCP:
- op: add
  path: /spec/storageClassName
  value: standard-rwo
```

**Apply to**:
- All StatefulSets (Redis, Keycloak)
- All PersistentVolumeClaims

**Verification**:
```bash
# Check all PVCs have storage class
kubectl get pvc -n fineract-production -o custom-columns=NAME:.metadata.name,STORAGECLASS:.spec.storageClassName
# Should show gp3/managed-premium/standard-rwo, not <none>
```

---

#### 4. Verify IRSA Role ARNs (AWS Only)

**Status**: ⚠️ Verify
**Reference**: Audit Finding #5
**Effort**: 30 minutes

**What to do**:
```bash
# 1. Get role ARN from Terraform
cd terraform/aws/environments/production
terraform output fineract_irsa_role_arn

# 2. Verify it's patched in production overlay
cat ../../environments/production/kustomization.yaml | grep -A5 "ServiceAccount"

# 3. Should see:
# patches:
#   - target:
#       kind: ServiceAccount
#       name: fineract
#     patch: |-
#       - op: replace
#         path: /metadata/annotations/eks.amazonaws.com~1role-arn
#         value: arn:aws:iam::123456789012:role/fineract-production-irsa-role
```

**Verification**:
```bash
# Deploy and check service account
kubectl get sa fineract -n fineract-production -o yaml | grep role-arn
# Should show actual ARN, not PLACEHOLDER
```

---

### High Priority Issues (P1 - Should Fix)

#### 5. Add GitHub Actions Workflow Timeouts

**Status**: ❌ Required
**Reference**: Audit Finding #9
**Effort**: 1 hour

**What to do**:
```yaml
# Add to all workflow jobs in .github/workflows/*.yaml
jobs:
  validate:
    name: Validate Manifests
    runs-on: ubuntu-latest
    timeout-minutes: 10  # Add this line
```

**Recommended timeouts**:
- validate-manifests: 10 minutes
- validate-secrets: 5 minutes
- scan-images: 15 minutes
- build-loader-image: 20 minutes
- terraform: 30 minutes
- test-sealed-secrets-backup: 20 minutes

---

#### 6. Fill Emergency Contact Information

**Status**: ❌ Required
**Reference**: Audit Finding #10
**Effort**: 30 minutes

**What to update**:
```markdown
# Update in all DR documentation:
- docs/DISASTER_RECOVERY.md
- docs/MULTI_REGION_DR_STRATEGY.md
- docs/SEALED_SECRETS_DR_RUNBOOK.md
- operations/disaster-recovery/README.md

## Emergency Contacts

| Role | Name | Contact | Availability |
|------|------|---------|--------------|
| Primary On-Call | [FILL IN] | [PHONE/SLACK] | 24/7 |
| Backup On-Call | [FILL IN] | [PHONE/SLACK] | 24/7 |
| DevOps Lead | [FILL IN] | [PHONE/SLACK] | Business hours |
| Security Team | [FILL IN] | [EMAIL/SLACK] | 24/7 |
```

---

#### 7. Improve Shell Script Error Handling

**Status**: 🟡 Recommended
**Reference**: Audit Finding #8
**Effort**: 2 hours

**What to do**:
```bash
# Add to all scripts in scripts/
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Add error trap
trap 'echo "ERROR: Script failed at line $LINENO"; exit 1' ERR
```

Priority scripts:
- scripts/backup-sealed-secrets-keys.sh
- scripts/restore-sealed-secrets-keys.sh
- scripts/seal-terraform-secrets.sh
- scripts/setup-eks-kubeconfig.sh

---

#### 8. Review Internal HTTP vs HTTPS Decision

**Status**: 🟡 Decision Required
**Reference**: Audit Finding #7
**Effort**: 8-16 hours (if implementing HTTPS)

**Options**:

**Option A: Accept HTTP for Internal Traffic** (Recommended)
- Document decision in security policy
- Justify: Cluster network is isolated and trusted
- External ingress already uses HTTPS
- Effort: 1 hour (documentation)

**Option B: Implement Service Mesh for mTLS**
- Deploy Istio or Linkerd
- Automatic encryption of all pod-to-pod traffic
- Effort: 16 hours

**Option C: Manual Internal TLS**
- Generate internal certificates with cert-manager
- Update all service references to HTTPS
- Effort: 8 hours

**Decision**: Consult security team before production.

---

## Production Configuration Requirements

### Environment-Specific Settings

#### Fineract Configuration

```yaml
# environments/production/fineract-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fineract-config
  namespace: fineract-production
data:
  # Database
  FINERACT_DEFAULT_TENANTDB_HOSTNAME: "fineract-prod.xxxxx.us-east-1.rds.amazonaws.com"
  FINERACT_DEFAULT_TENANTDB_PORT: "5432"
  FINERACT_DEFAULT_TENANTDB_NAME: "fineract_tenants"

  # Logging
  FINERACT_LOGGING_LEVEL_ROOT: "WARN"  # Reduce log volume in prod
  FINERACT_LOGGING_LEVEL_ORG_APACHE_FINERACT: "INFO"

  # Performance
  FINERACT_HIKARI_MAXIMUM_POOL_SIZE: "20"  # Higher for production
  FINERACT_HIKARI_MINIMUM_IDLE: "5"

  # Security
  FINERACT_SECURITY_OAUTH_ENABLED: "true"
  FINERACT_SECURITY_BASICAUTH_ENABLED: "false"  # OAuth2 only in prod

  # Tenant management
  FINERACT_TENANT_MASTER_PASSWORD: ""  # From sealed secret
  FINERACT_MODE_READ_ENABLED: "true"
  FINERACT_MODE_WRITE_ENABLED: "false"
  FINERACT_MODE_BATCH_ENABLED: "false"
```

---

#### Keycloak Configuration

```yaml
# environments/production/keycloak-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-env
  namespace: fineract-production
data:
  # Database
  KC_DB: "postgres"
  KC_DB_URL_HOST: "keycloak-prod.xxxxx.us-east-1.rds.amazonaws.com"
  KC_DB_URL_DATABASE: "keycloak"

  # Hostname (CRITICAL for production)
  KC_HOSTNAME: "https://auth.fineract.com"
  KC_HOSTNAME_STRICT: "true"
  KC_HOSTNAME_STRICT_BACKCHANNEL: "false"

  # Production mode
  KC_HTTP_ENABLED: "true"  # Behind ingress with TLS termination
  KC_PROXY: "edge"
  KC_PROXY_HEADERS: "xforwarded"

  # Health
  KC_HEALTH_ENABLED: "true"
  KC_METRICS_ENABLED: "true"

  # Caching (for multi-replica)
  KC_CACHE: "ispn"
  KC_CACHE_STACK: "kubernetes"

  # Logging
  KC_LOG_LEVEL: "INFO"
  KC_LOG_CONSOLE_OUTPUT: "json"  # Structured logs for prod
```

---

#### OAuth2-Proxy Configuration

```yaml
# environments/production/oauth2-proxy-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-config
  namespace: fineract-production
data:
  OAUTH2_PROXY_PROVIDER: "oidc"
  OAUTH2_PROXY_OIDC_ISSUER_URL: "https://auth.fineract.com/realms/fineract"
  OAUTH2_PROXY_CLIENT_ID: "fineract-oauth2-proxy"
  OAUTH2_PROXY_REDIRECT_URL: "https://app.fineract.com/oauth2/callback"

  # Cookie settings (production)
  OAUTH2_PROXY_COOKIE_SECURE: "true"  # HTTPS only
  OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
  OAUTH2_PROXY_COOKIE_SAMESITE: "lax"
  OAUTH2_PROXY_COOKIE_DOMAINS: ".fineract.com"  # Domain-level cookie
  OAUTH2_PROXY_COOKIE_EXPIRE: "24h"
  OAUTH2_PROXY_COOKIE_REFRESH: "1h"

  # Session storage (for multi-replica HA)
  # Option: Use Redis for shared sessions
  # OAUTH2_PROXY_SESSION_STORE_TYPE: "redis"
  # OAUTH2_PROXY_REDIS_CONNECTION_URL: "redis://fineract-redis:6379"

  # Logging
  OAUTH2_PROXY_LOGGING_LOCAL_TIME: "false"  # UTC timestamps
  OAUTH2_PROXY_STANDARD_LOGGING: "true"
  OAUTH2_PROXY_AUTH_LOGGING: "true"
  OAUTH2_PROXY_REQUEST_LOGGING: "true"
```

---

### Resource Allocation

**Production resource limits** (per pod):

```yaml
# Fineract Write Instance
resources:
  requests:
    cpu: 1000m      # 1 CPU
    memory: 2Gi
  limits:
    cpu: 2000m      # 2 CPU
    memory: 4Gi

# Fineract Read Instance
resources:
  requests:
    cpu: 500m       # 0.5 CPU
    memory: 1Gi
  limits:
    cpu: 1000m      # 1 CPU
    memory: 2Gi

# Fineract Batch Instance
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi

# Keycloak
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi

# Redis
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 2Gi

# PostgreSQL RDS
# Recommended: db.t3.large or db.m5.large (2 vCPU, 8GB RAM)
```

---

## Security Hardening

### Required Security Configurations

#### 1. TLS/HTTPS Configuration

```yaml
# All external ingresses MUST use HTTPS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod  # NOT staging
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"  # Redirect HTTP to HTTPS
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"  # Modern TLS only
spec:
  tls:
    - hosts:
        - app.fineract.com
        - api.fineract.com
        - auth.fineract.com
      secretName: fineract-tls
```

---

#### 2. Network Policies

**Required**: Implement network policies to restrict pod-to-pod communication.

```yaml
# Example: Fineract can only talk to PostgreSQL and Redis
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fineract-write-netpol
  namespace: fineract-production
spec:
  podSelector:
    matchLabels:
      app: fineract-write
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: oauth2-proxy
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow DNS
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Allow PostgreSQL (RDS)
    - to:
        - namespaceSelector: {}  # External (RDS)
      ports:
        - protocol: TCP
          port: 5432
    # Allow Redis
    - to:
        - podSelector:
            matchLabels:
              app: fineract-redis
      ports:
        - protocol: TCP
          port: 6379
    # Allow Keycloak
    - to:
        - podSelector:
            matchLabels:
              app: keycloak
      ports:
        - protocol: TCP
          port: 8080
```

---

#### 3. Pod Security Standards

**Required**: Enforce restricted pod security standards.

```yaml
# Label namespace for pod security enforcement
apiVersion: v1
kind: Namespace
metadata:
  name: fineract-production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

All pods must have:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
```

---

#### 4. Secrets Management

**Required checklist**:
- ✅ All secrets sealed with Sealed Secrets (no plaintext in Git)
- ✅ Sealed secrets keys backed up to AWS Secrets Manager
- ✅ Backup validated monthly (GitHub Actions workflow)
- ✅ Secret rotation procedure documented
- ✅ Emergency contacts filled in DR documentation

**Verification**:
```bash
# No plaintext secrets in Git
git grep -i "password\|secret\|api.key" -- '*.yaml' '*.yml' | grep -v "SealedSecret"
# Should return no results

# All secrets are SealedSecrets
kubectl get secrets -n fineract-production -o json | \
  jq -r '.items[] | select(.type != "kubernetes.io/service-account-token") | .metadata.name'
# All should have corresponding SealedSecret in Git
```

---

#### 5. RBAC and Service Accounts

**Required**: Least privilege access for all service accounts.

```yaml
# Fineract service account (AWS IRSA)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fineract
  namespace: fineract-production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/fineract-production-irsa-role
automountServiceAccountToken: true

---
# Minimal RBAC role (if needed)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: fineract-role
  namespace: fineract-production
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
```

---

## High Availability Requirements

### Replica Counts

**Minimum replica counts for production**:

| Component | Min Replicas | Max Replicas (HPA) | Notes |
|-----------|--------------|---------------------|-------|
| **Fineract Write** | 2 | 10 | Active-active with sticky sessions |
| **Fineract Read** | 3 | 20 | HPA based on CPU |
| **Fineract Batch** | 2 | 5 | HPA based on CPU |
| **Keycloak** | 3 | 5 | Requires clustering config |
| **OAuth2-Proxy** | 3 | 10 | Stateless, easy to scale |
| **Frontend Apps** | 2 | 10 | Web-app, Reporting, Accounting |
| **Redis** | 1 or 3 | - | Cache: 1 replica OK, or 3 with Sentinel |
| **Prometheus** | 2 | - | HA mode with shared storage |
| **Grafana** | 2 | - | Shared PostgreSQL backend |
| **Loki** | 3 | - | Distributed mode |
| **AlertManager** | 3 | - | Clustering for deduplication |

---

### Pod Disruption Budgets

**Required for all critical services**:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fineract-write-pdb
  namespace: fineract-production
spec:
  minAvailable: 1  # At least 1 pod must be available
  selector:
    matchLabels:
      app: fineract-write

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: keycloak-pdb
  namespace: fineract-production
spec:
  minAvailable: 2  # At least 2 of 3 pods available
  selector:
    matchLabels:
      app: keycloak
```

---

### Horizontal Pod Autoscalers

**Required HPAs**:

```yaml
# Fineract Write HPA (CREATE THIS - currently missing)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fineract-write-hpa
  namespace: fineract-production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fineract-write
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80

# Fineract Read HPA (already exists, verify settings)
# Fineract Batch HPA (already exists, verify settings)
```

---

### Database High Availability

**AWS RDS Configuration**:
```hcl
# terraform/aws/environments/production/main.tf
module "rds" {
  multi_az               = true  # REQUIRED for production
  backup_retention_period = 30   # 30 days
  deletion_protection    = true  # Prevent accidental deletion

  # Performance Insights
  performance_insights_enabled = true
  performance_insights_retention_period = 7

  # Enhanced monitoring
  monitoring_interval = 60
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}
```

**Azure Database**:
- Zone-redundant HA enabled
- Geo-redundant backup
- 30-day retention

**GCP Cloud SQL**:
- Regional HA configuration
- Automated backups with 30-day retention
- Point-in-time recovery enabled

---

## Monitoring & Alerting

### Required Prometheus Alerts

**Critical Alerts** (PagerDuty escalation):

```yaml
# High CPU usage
- alert: HighCPUUsage
  expr: |
    (sum(rate(container_cpu_usage_seconds_total{namespace=~"fineract-production"}[5m])) by (pod) /
    sum(container_spec_cpu_quota{namespace=~"fineract-production"}/container_spec_cpu_period{namespace=~"fineract-production"}) by (pod)) > 0.9
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Pod {{ $labels.pod }} has high CPU usage"
    description: "CPU usage is {{ $value | humanizePercentage }}"

# High memory usage
- alert: HighMemoryUsage
  expr: |
    (container_memory_working_set_bytes{namespace=~"fineract-production"} /
    container_spec_memory_limit_bytes{namespace=~"fineract-production"}) > 0.9
  for: 5m
  labels:
    severity: critical

# Pod not ready
- alert: PodNotReady
  expr: |
    kube_pod_status_ready{namespace=~"fineract-production", condition="false"} == 1
  for: 5m
  labels:
    severity: critical

# Deployment replica mismatch
- alert: DeploymentReplicasMismatch
  expr: |
    kube_deployment_status_replicas{namespace=~"fineract-production"} !=
    kube_deployment_status_replicas_available{namespace=~"fineract-production"}
  for: 10m
  labels:
    severity: warning

# Fineract API error rate
- alert: HighErrorRate
  expr: |
    rate(http_requests_total{namespace=~"fineract-production", status=~"5.."}[5m]) > 0.05
  for: 5m
  labels:
    severity: critical

# Keycloak authentication failures
- alert: HighAuthFailureRate
  expr: |
    rate(keycloak_failed_login_attempts{namespace=~"fineract-production"}[5m]) > 10
  for: 5m
  labels:
    severity: warning

# Database connection pool exhaustion
- alert: DatabaseConnectionPoolExhausted
  expr: |
    hikaricp_connections_active{namespace=~"fineract-production"} /
    hikaricp_connections_max{namespace=~"fineract-production"} > 0.9
  for: 5m
  labels:
    severity: critical

# Certificate expiring soon
- alert: CertificateExpiringSoon
  expr: |
    (certmanager_certificate_expiration_timestamp_seconds - time()) < (7 * 24 * 3600)
  labels:
    severity: warning
  annotations:
    summary: "Certificate {{ $labels.name }} expires in less than 7 days"
```

---

### Required Grafana Dashboards

**Must have**:
1. **Fineract Overview Dashboard**
   - API request rate and latency
   - Error rate by endpoint
   - Active users
   - Database connection pool status

2. **Infrastructure Dashboard**
   - Node CPU/memory/disk usage
   - Pod status and restarts
   - Network traffic
   - PersistentVolume usage

3. **Keycloak Dashboard**
   - Login success/failure rate
   - Active sessions
   - Token issuance rate
   - Realm statistics

4. **Database Dashboard** (if using RDS)
   - Connection count
   - Query latency
   - Replication lag (if Multi-AZ)
   - Disk I/O

---

### Log Retention

**Production logging configuration**:

```yaml
# Loki retention (30 days minimum for production)
limits_config:
  retention_period: 720h  # 30 days

# Log shipping to long-term storage (optional)
# Consider: S3, CloudWatch Logs, Splunk, Datadog
```

**Audit log requirements**:
- Authentication events: 90 days
- Authorization events: 90 days
- Financial transactions: 7 years (regulatory requirement)
- System events: 30 days

---

## Backup & Disaster Recovery

### Required Backups

#### 1. Database Backups

**Automated daily backups**:
```hcl
# AWS RDS
backup_retention_period = 30  # 30 days automated backups
backup_window          = "03:00-04:00"  # UTC
preferred_maintenance_window = "mon:04:00-mon:05:00"

# Manual snapshots before major changes
# Tag with: environment, purpose, date
```

**Verification**:
```bash
# List recent backups
aws rds describe-db-snapshots \
  --db-instance-identifier fineract-production \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Should show daily snapshots for last 30 days
```

---

#### 2. Sealed Secrets Key Backup

**Automated monthly validation** (GitHub Actions):
- Workflow: `.github/workflows/test-sealed-secrets-backup.yaml`
- Verifies backup exists in AWS Secrets Manager
- Tests restore procedure in isolated namespace
- Creates GitHub issue on failure

**Manual backup procedure**:
```bash
# Backup sealed secrets keys
./scripts/backup-sealed-secrets-keys.sh production

# Verify backup
aws secretsmanager describe-secret \
  --secret-id /fineract/production/sealed-secrets/master-key
```

**Backup location**: `AWS Secrets Manager: /fineract/production/sealed-secrets/master-key`

---

#### 3. Configuration Backup

**GitOps = Version Control**:
- All configuration in Git
- Tag production releases
- Maintain release notes

```bash
# Tag production deployment
git tag -a prod-2025-01-19 -m "Production release 2025-01-19"
git push origin prod-2025-01-19
```

---

#### 4. Keycloak Configuration Export

**Manual export before major changes**:

```bash
# Export Keycloak realm configuration
kubectl exec -it deployment/keycloak -n fineract-production -- \
  /opt/keycloak/bin/kc.sh export \
  --dir /tmp/keycloak-export \
  --realm fineract \
  --users realm_file

# Copy export to local
kubectl cp fineract-production/keycloak-pod-name:/tmp/keycloak-export ./keycloak-backup-2025-01-19
```

**Store in secure location** (encrypted S3 bucket or vault).

---

### Disaster Recovery Procedures

**RTO (Recovery Time Objective)**: 1 hour
**RPO (Recovery Point Objective)**: 1 hour

**Required documentation**:
- ✅ [Sealed Secrets DR Runbook](./SEALED_SECRETS_DR_RUNBOOK.md)
- ✅ [Disaster Recovery Guide](./DISASTER_RECOVERY.md)
- ✅ [Multi-Region DR Strategy](./MULTI_REGION_DR_STRATEGY.md)

**Required testing**:
- Quarterly DR drill (restore from backup to non-production environment)
- Document results and update procedures
- Track in `operations/sealed-secrets-key-audit.yaml`

**Verification**:
```bash
# Test restore procedure (in non-production)
./scripts/restore-sealed-secrets-keys.sh production
./scripts/validate-sealed-secrets-compatibility.sh
```

---

## Performance Requirements

### Load Testing Results

**Required before production**:

1. **API Load Test**
   - Tool: JMeter, K6, or Gatling
   - Target: 1000 concurrent users
   - Duration: 1 hour sustained load
   - Success criteria: <5% error rate, p95 latency <500ms

2. **Database Performance Test**
   - Tool: pgbench or similar
   - Verify connection pool sizing
   - Monitor query performance

3. **Stress Test**
   - Gradually increase load until failure
   - Identify breaking point
   - Verify graceful degradation

**Document results**:
```markdown
# Load Test Results - 2025-01-19

## Environment
- Cluster: production
- Fineract: 2 write, 5 read instances
- Database: db.t3.large Multi-AZ RDS

## Results
- Peak throughput: 5000 req/sec
- P50 latency: 120ms
- P95 latency: 450ms
- P99 latency: 800ms
- Error rate: 0.2%
- CPU utilization: 65%
- Memory utilization: 70%

## Bottlenecks
- None identified at current load
- Database connection pool at 60% capacity
- Recommendation: Can handle 2x current production load
```

---

### Capacity Planning

**Production sizing** (adjust based on load testing):

```yaml
# Fineract Write: 2-10 instances
# Expected load: 100-500 concurrent users
# Expected TPS: 50-200 transactions/sec

# Database: db.t3.large or db.m5.large
# Connections: 100 max (20 per Fineract instance)
# Storage: 100GB with auto-scaling to 500GB

# Redis: 2Gi memory
# Expected cache hit rate: >80%
```

---

## Compliance Requirements

### Audit Trail

**Required logging**:

1. **Authentication Events**
   ```yaml
   # Keycloak event logging enabled
   KC_LOG_LEVEL: "INFO"
   # Events stored in database + logs
   ```

2. **API Access Logs**
   ```yaml
   # Nginx ingress access logs
   nginx.ingress.kubernetes.io/enable-access-log: "true"
   # Log format: JSON with user identity, timestamp, endpoint, status
   ```

3. **Database Audit Log**
   ```sql
   -- Enable PostgreSQL audit logging (pgAudit)
   -- Track: DDL, WRITE operations on financial tables
   ```

4. **Infrastructure Changes**
   ```bash
   # All changes via GitOps (Git audit trail)
   # Tag: environment, change type, approver
   ```

---

### Data Residency

**Ensure**:
- Database in correct region (e.g., EU customers → eu-west-1)
- Backups in same region
- Log storage complies with data residency

---

### Security Compliance

**Checklist**:
- ✅ TLS 1.2+ only (no TLS 1.0/1.1)
- ✅ Strong cipher suites configured
- ✅ Secrets encrypted at rest (Sealed Secrets, AWS Secrets Manager)
- ✅ Database encrypted at rest (RDS encryption)
- ✅ Database encrypted in transit (SSL connections)
- ✅ No plaintext passwords in Git
- ✅ Regular security scanning (Trivy, Grype)
- ✅ CVE monitoring and patching process

---

## Pre-Deployment Validation

### Infrastructure Validation

```bash
# 1. Verify Terraform state
cd terraform/aws/environments/production
terraform plan -var-file=production.tfvars
# Should show: No changes. Infrastructure is up-to-date.

# 2. Verify RDS is Multi-AZ
aws rds describe-db-instances \
  --db-instance-identifier fineract-production \
  --query 'DBInstances[0].MultiAZ'
# Should return: true

# 3. Verify backup retention
aws rds describe-db-instances \
  --db-instance-identifier fineract-production \
  --query 'DBInstances[0].BackupRetentionPeriod'
# Should return: 30

# 4. Verify sealed secrets backup exists
aws secretsmanager describe-secret \
  --secret-id /fineract/production/sealed-secrets/master-key
# Should succeed

# 5. Verify certificate issuer email
kubectl get clusterissuer letsencrypt-prod -o yaml | grep email
# Should NOT show example.com
```

---

### Application Validation

```bash
# 1. Validate all Kubernetes manifests
kustomize build environments/production | kubeval --strict --kubernetes-version 1.31.0

# 2. Check for :latest tags
grep -r "image:" environments/production/ | grep -E "latest|image:[^:]+$"
# Should return: nothing

# 3. Verify resource limits exist
kustomize build environments/production | \
  yq eval 'select(.kind == "Deployment") | .spec.template.spec.containers[].resources.limits'
# All should have limits defined

# 4. Verify security contexts
kustomize build environments/production | \
  yq eval 'select(.kind == "Deployment") | .spec.template.spec.securityContext.runAsNonRoot'
# All should be: true

# 5. Verify PodDisruptionBudgets exist
kubectl get pdb -n fineract-production
# Should show PDBs for: fineract-write, fineract-read, keycloak, oauth2-proxy
```

---

### Security Validation

```bash
# 1. Scan for secrets in Git
git secrets --scan
# OR
gitleaks detect --source . --verbose

# 2. Check for plaintext secrets
kubectl get secrets -n fineract-production -o json | \
  jq -r '.items[] | select(.metadata.annotations["sealedsecrets.bitnami.com/managed"] != "true") | .metadata.name'
# Should only show: service account tokens

# 3. Verify IRSA annotations
kubectl get sa fineract -n fineract-production -o yaml | grep role-arn
# Should show actual ARN, not PLACEHOLDER

# 4. Check TLS configuration
kubectl get ingress -n fineract-production -o yaml | grep -A5 tls
# All ingresses should have TLS configured
```

---

## Production Deployment Procedure

### Pre-Deployment Steps

**1 Week Before Deployment**:
- [ ] Complete all mandatory fixes (critical + high priority)
- [ ] Load testing completed and results documented
- [ ] DR drill completed successfully
- [ ] Security scan passed (no critical vulnerabilities)
- [ ] Change request approved (if required by organization)

**1 Day Before Deployment**:
- [ ] Backup current production state (database snapshot, Git tag)
- [ ] Notify users of maintenance window
- [ ] Team on standby (primary + backup on-call)
- [ ] Rollback plan reviewed and tested

---

### Deployment Steps

**Maintenance Window Recommended**: 2-4 hours (off-peak hours)

```bash
# Step 1: Pre-deployment backup
# Database snapshot
aws rds create-db-snapshot \
  --db-instance-identifier fineract-production \
  --db-snapshot-identifier fineract-prod-pre-deploy-$(date +%Y%m%d)

# Git tag
git tag -a prod-pre-deploy-$(date +%Y%m%d) -m "Pre-deployment snapshot"
git push origin prod-pre-deploy-$(date +%Y%m%d)

# Step 2: Deploy infrastructure changes (if any)
cd terraform/aws/environments/production
terraform apply -var-file=production.tfvars
# Review plan carefully before applying

# Step 3: Deploy sealed secrets
kubectl apply -k secrets/production/

# Wait for secrets to be created
kubectl wait --for=condition=Ready \
  sealedsecret --all \
  -n fineract-production \
  --timeout=120s

# Step 4: Deploy applications via ArgoCD
argocd app sync fineract-production --prune
# OR
kubectl apply -k environments/production/

# Step 5: Watch deployment progress
kubectl rollout status deployment/fineract-write -n fineract-production
kubectl rollout status deployment/fineract-read -n fineract-production
kubectl rollout status deployment/fineract-batch -n fineract-production
kubectl rollout status statefulset/keycloak -n fineract-production

# Step 6: Verify all pods running
kubectl get pods -n fineract-production
# All should be Running with READY 1/1
```

---

### Post-Deployment Verification

**Run within 15 minutes of deployment**:

```bash
# 1. Health checks
curl https://api.fineract.com/fineract-provider/actuator/health
# Should return: {"status":"UP"}

curl https://auth.fineract.com/realms/fineract/.well-known/openid-configuration
# Should return: OIDC configuration JSON

# 2. Test authentication flow
# Login via web app: https://app.fineract.com
# Create test loan
# Verify API responses

# 3. Check logs for errors
kubectl logs -n fineract-production -l app=fineract-write --tail=100 | grep -i error
# Should see: no critical errors

# 4. Verify database connectivity
kubectl exec -it deployment/fineract-write -n fineract-production -- \
  psql -h $FINERACT_DEFAULT_TENANTDB_HOSTNAME -U fineract -d fineract_tenants -c "SELECT version();"
# Should return: PostgreSQL version

# 5. Check Prometheus metrics
# Open Grafana: https://grafana.fineract.com
# Verify all dashboards showing data

# 6. Verify no alerts firing
# Open AlertManager: https://alertmanager.fineract.com
# Should see: no critical alerts
```

---

### Rollback Procedure

**If issues detected within 1 hour of deployment**:

```bash
# Option 1: Rollback Kubernetes deployment
kubectl rollout undo deployment/fineract-write -n fineract-production
kubectl rollout undo deployment/fineract-read -n fineract-production
kubectl rollout undo deployment/fineract-batch -n fineract-production
kubectl rollout undo statefulset/keycloak -n fineract-production

# Option 2: Rollback via GitOps (if using ArgoCD)
git revert HEAD
git push origin main
argocd app sync fineract-production

# Option 3: Restore from previous Git tag
git checkout prod-pre-deploy-$(date +%Y%m%d)
kubectl apply -k environments/production/

# Option 4: Database rollback (LAST RESORT)
# Restore from snapshot (causes data loss)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier fineract-production-restored \
  --db-snapshot-identifier fineract-prod-pre-deploy-$(date +%Y%m%d)
# Note: This creates a NEW instance, must update DNS/connection strings
```

---

## Production vs Dev/UAT Comparison

| Configuration | Development | UAT | Production |
|---------------|-------------|-----|------------|
| **Container Images** | `:latest` acceptable | Pinned versions | **Pinned versions (REQUIRED)** |
| **Replica Count** | 1 | 2 | **3+ (REQUIRED)** |
| **Resource Limits** | Low (256Mi-1Gi) | Medium (1-2Gi) | **High (2-4Gi)** |
| **Database** | Single-AZ | Single-AZ | **Multi-AZ (REQUIRED)** |
| **Backup Retention** | 7 days | 14 days | **30 days (REQUIRED)** |
| **TLS Certificates** | Self-signed OK | Let's Encrypt Staging | **Let's Encrypt Prod (REQUIRED)** |
| **Logging Level** | DEBUG | INFO | **WARN/INFO** |
| **Log Retention** | 7 days | 14 days | **30 days minimum** |
| **Monitoring Alerts** | Optional | Recommended | **Required (PagerDuty)** |
| **High Availability** | Single pod OK | PDB optional | **PDB required** |
| **Pod Security** | Permissive | Baseline | **Restricted (REQUIRED)** |
| **Network Policies** | Optional | Recommended | **Required** |
| **Disaster Recovery** | No DR plan | DR documented | **DR tested quarterly (REQUIRED)** |
| **Change Control** | No approval needed | Manager approval | **CAB approval (REQUIRED)** |
| **Load Testing** | Not required | Recommended | **Required before deploy** |
| **Security Scanning** | Weekly | Daily | **Continuous + manual review** |

---

## Sign-Off Requirements

### Pre-Production Sign-Off Checklist

**Infrastructure Team**:
- [ ] All critical and high-priority issues resolved
- [ ] Terraform state verified and backed up
- [ ] Multi-AZ RDS provisioned and tested
- [ ] Sealed secrets keys backed up and tested
- [ ] Network policies configured and tested
- [ ] Load balancer and DNS configured
- **Signed**: _________________ Date: _______

**Security Team**:
- [ ] No plaintext secrets in Git
- [ ] TLS configuration reviewed (TLS 1.2+ only)
- [ ] Pod security standards enforced (restricted)
- [ ] RBAC least privilege verified
- [ ] Vulnerability scan passed (no critical CVEs)
- [ ] Penetration test completed (if required)
- **Signed**: _________________ Date: _______

**Application Team**:
- [ ] Load testing completed with acceptable results
- [ ] Keycloak authentication tested
- [ ] All API endpoints functional
- [ ] Database migrations tested
- [ ] Rollback procedure tested
- **Signed**: _________________ Date: _______

**Operations Team**:
- [ ] Monitoring and alerting configured
- [ ] Log aggregation working
- [ ] Backup validation passed
- [ ] DR procedure documented and tested
- [ ] On-call rotation staffed
- [ ] Runbooks updated
- **Signed**: _________________ Date: _______

**Compliance/Audit** (if applicable):
- [ ] Audit logging enabled
- [ ] Data residency requirements met
- [ ] Retention policies configured
- [ ] Access controls documented
- **Signed**: _________________ Date: _______

---

### Production Go-Live Approval

**Final approval required from**:
- [ ] Engineering Manager
- [ ] DevOps Lead
- [ ] Security Lead
- [ ] Change Advisory Board (CAB) if required

**Production deployment authorized by**:

**Name**: _______________________
**Title**: _______________________
**Date**: _______________________
**Signature**: _______________________

---

## Appendix: Quick Reference

### Critical Production URLs

```markdown
# External (customer-facing)
- Web App: https://app.fineract.com
- API: https://api.fineract.com
- Authentication: https://auth.fineract.com

# Internal (operations)
- Grafana: https://grafana.fineract.com
- Prometheus: https://prometheus.fineract.com
- AlertManager: https://alertmanager.fineract.com
- ArgoCD: https://argocd.fineract.com
```

---

### Emergency Contacts

See: [docs/SEALED_SECRETS_DR_RUNBOOK.md](./SEALED_SECRETS_DR_RUNBOOK.md#emergency-contacts)

---

### Quick Commands

```bash
# Check production health
kubectl get pods -n fineract-production

# View logs
kubectl logs -n fineract-production -l app=fineract-write --tail=100

# Restart service
kubectl rollout restart deployment/fineract-write -n fineract-production

# Check database connection
kubectl exec -it deployment/fineract-write -n fineract-production -- \
  psql -h $DB_HOST -U fineract -c "SELECT 1;"

# View metrics
kubectl top pods -n fineract-production

# Check sealed secrets
kubectl get sealedsecrets -n fineract-production
kubectl get secrets -n fineract-production
```

---

**Document Version**: 1.0
**Last Updated**: 2025-01-19
**Next Review**: Before production deployment
**Maintained By**: DevOps Team
