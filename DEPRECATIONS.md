# Deprecated Features - fineract-gitops

This document tracks deprecated features, components, and methods in the fineract-gitops repository. For each deprecation, we provide the reason, alternative approach, and tentative removal timeline.

---

## Active Deprecations (Pending Removal)

### Deployment Scripts

#### `deploy-with-loadbalancer-dns.sh`

**Status**: ⚠️ **DEPRECATED**
**Deprecated**: 2025-11-20
**Removal planned**: 2026-05-20 (6 months)

**Reason**:
- Requires manual kubeconfig setup
- Monolithic design makes debugging difficult
- No automatic configuration of LoadBalancer DNS
- Superseded by two-phase deployment approach

**Alternative**:
```bash
# Two-phase deployment (recommended for fresh infrastructure)
make deploy-infrastructure-dev
make deploy-k8s-with-loadbalancer-dns-dev

# OR interactive GitOps deployment
make deploy-gitops
```

**Migration guide**: See [DEPLOYMENT.md](DEPLOYMENT.md#two-phase-deployment)

---

### Secrets Management

#### Fineract Admin Credentials Secret

**Status**: ⚠️ **DEPRECATED**
**Deprecated**: 2025-11-20
**Removal planned**: TBD

**Reason**:
- Security best practice to avoid static admin credentials
- Keycloak-based authentication preferred

**Alternative**: Use Keycloak admin user with appropriate roles

---

#### `rds-connection` Secret (Legacy Name)

**Status**: ⚠️ **COMPATIBILITY MODE**
**Deprecated**: 2025-11-20
**Removal planned**: 2026-05-20

**Reason**:
- Unnecessary secret wrapper
- RDS credentials managed via IRSA
- Direct environment variables more transparent

**Alternative**: Use RDS endpoint environment variables directly via IRSA

**Note**: Currently kept for backward compatibility during migration period

---

### Kubernetes Resources

#### Keycloak Export Secrets Job

**Status**: ⚠️ **DEPRECATED**
**Deprecated**: 2025-01-15

**Reason**:
- Replaced by pre-generated sealed secrets approach
- More secure and GitOps-friendly

**Alternative**: Use sealed secrets for Keycloak configuration

**File**: `operations/keycloak-config/base/jobs/export-secrets-job.yaml`

---

### OAuth2 / Security

#### OAuth2 Implicit Flow

**Status**: ❌ **SECURITY DEPRECATED**
**Deprecated**: Industry-wide (OAuth 2.1 specification)

**Reason**:
- Security vulnerability (token exposure in URL)
- Deprecated by OAuth 2.1 specification

**Alternative**: Use Authorization Code Flow with PKCE

**Reference**: See `operations/keycloak-config/docs/SECURITY.md`

---

## Completed Removals

### External Secrets Operator (ESO)

**Status**: ✅ **REMOVED**
**Deprecated**: 2025-01-15
**Removed**: 2025-01-19

**Reason**:
- Complex setup and maintenance
- AWS-dependent (vendor lock-in)
- Cost implications (AWS Secrets Manager charges)
- Sealed Secrets provides simpler, cost-effective alternative

**Alternative**: Sealed Secrets (Bitnami)

**Migration completed**: See [docs/migrations/ESO_DOCUMENTATION_CLEANUP_SUMMARY.md](docs/migrations/ESO_DOCUMENTATION_CLEANUP_SUMMARY.md)

**Removed components**:
- External Secrets Operator charts and configurations
- AWS Secrets Manager Terraform resources
- ESO-related scripts and documentation
- Migration completed across all environments

---

### Fineract Web Apps (Frontend)

**Status**: ✅ **REMOVED**
**Deprecated**: 2024 (date unknown)
**Removed**: 2025

**Reason**:
- No longer maintained
- Replaced by modern frontend solutions

**Alternative**: Use current Fineract web application

---

### Apache Gateway

**Status**: ✅ **REMOVED**
**Deprecated**: 2024
**Removed**: 2025

**Reason**:
- Replaced by OAuth2 Proxy + Nginx Ingress
- Better integration with Keycloak authentication
- More flexible routing capabilities

**Alternative**: OAuth2 Proxy with Nginx Ingress Controller

---

### Message Gateway Service

**Status**: ✅ **REMOVED**
**Deprecated**: 2024
**Removed**: 2025

**Reason**:
- No published Docker image available
- Component not actively maintained

**Alternative**: Direct messaging integration at application level

---

### Keycloak Clients (Obsolete)

**Status**: ✅ **REMOVED**
**Removed**: 2025

**Removed clients**:
- `mobile-app` - No longer needed
- `payment-gateway` - Service deprecated
- `message-gateway` - Service deprecated

**Current active clients**:
- `fineract-server` - Core authentication
- `fineract-admin` - Admin portal
- `oauth2-proxy` - Gateway authentication

---

## Deprecation Process

When a feature is deprecated in this project:

1. **Announcement**: Add entry to this document with deprecation date
2. **Warning**: Add runtime warnings to affected scripts/code
3. **Documentation**: Update all relevant documentation
4. **Grace period**: Minimum 6 months before removal (unless security-critical)
5. **Removal**: Archive to `scripts/legacy/` or remove entirely
6. **Changelog**: Document in Git commit and CHANGELOG.md

---

## Questions?

If you're using a deprecated feature and need help migrating:

1. Check the alternative approach listed above
2. Refer to the migration guide (if provided)
3. Consult [DEPLOYMENT.md](DEPLOYMENT.md) for current best practices
4. Open a GitHub issue if you need clarification

---

**Last updated**: 2025-11-20
