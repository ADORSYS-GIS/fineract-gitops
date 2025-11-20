# Base Kustomization for Fineract Environments

This directory contains the **base kustomization** that is shared across all Fineract environments (dev, uat, production).

## Purpose

The base kustomization follows the **DRY (Don't Repeat Yourself)** principle by extracting all common configuration into a single source of truth. This eliminates duplication and makes version updates easier.

## What's Included

### Common Resources
- Database initialization jobs
- Fineract application base configuration

### Common Image Versions
All utility and supporting service images with pinned versions:
- **Keycloak**: 26.4.0
- **OAuth2 Proxy**: v7.13.0
- **Redis**: 7.2-alpine
- **Redis Exporter**: v1.55.0-alpine
- **Alpine**: 3.18
- **Curl**: 8.4.0
- **PostgreSQL Client**: 15-alpine
- **Python**: 3.11-slim
- **kubectl**: v1.28.15
- **Busybox**: 1.36.1
- **Keycloak Config CLI**: 5.9.0

### Common Labels
- `provider: aws-managed`
- `infrastructure: aws`
- `managed-by: argocd`

### Common Annotations
- `provider-type: "aws-managed"`
- `deployment-profile: "aws - managed services"`
- `terraform-required: "true"`

## How Environments Use This Base

Each environment (dev/uat/production) **inherits** from this base using:

```yaml
bases:
  - ../base
```

Then they override only what differs:

### Dev Environment
- **Namespace**: `fineract-dev`
- **Fineract version**: `develop` (latest features)
- **Auto-sync**: Enabled
- **Contact**: dev-team@example.com
- **Additional**: Frontend apps (reporting-app, accounting-app)
- **Additional**: IRSA patch for AWS permissions

### UAT Environment
- **Namespace**: `fineract-uat`
- **Fineract version**: `1.12.1` (stable release)
- **Auto-sync**: Disabled (manual approval)
- **Contact**: qa-team@example.com
- **Additional**: fineract-keycloak-sync service

### Production Environment
- **Namespace**: `fineract-production`
- **Fineract version**: `1.12.1` (stable release)
- **Auto-sync**: Disabled (manual approval)
- **Sync windows**: Business hours only
- **Criticality**: High
- **Contact**: platform-team@example.com, sre-team@example.com
- **Additional**: fineract-keycloak-sync service

## Benefits

### Before Refactoring
- **Total lines**: 615 lines (3 environments × ~205 lines each)
- **Duplication**: 85% of configuration duplicated across environments
- **Maintenance**: Update 3 files for version changes

### After Refactoring
- **Total lines**: 295 lines (1 base @ 150 lines + 3 overlays @ ~48 lines each)
- **Duplication**: Eliminated (base is single source of truth)
- **Maintenance**: Update 1 file (base) for common version changes
- **Reduction**: **52% fewer lines to maintain**

## Updating Image Versions

### Common Utility Images
Update in **this file** (`environments/base/kustomization.yaml`):

```yaml
images:
  - name: quay.io/keycloak/keycloak
    newName: quay.io/keycloak/keycloak
    newTag: "26.4.0"  # Update here
```

This automatically applies to all environments.

### Environment-Specific Images
Update in the environment overlay (e.g., `environments/dev/kustomization.yaml`):

```yaml
images:
  - name: apache/fineract
    newName: apache/fineract
    newTag: "develop"  # Update here for dev only
```

## Validation

To validate that kustomization builds correctly:

```bash
# Test dev
cd environments/dev && kustomize build .

# Test uat
cd environments/uat && kustomize build .

# Test production
cd environments/production && kustomize build .
```

All should build without errors.

## Architecture

```
environments/
├── base/
│   ├── kustomization.yaml       # Common base (this file)
│   └── README.md                # This documentation
├── dev/
│   ├── kustomization.yaml       # Dev overlay (inherits from base)
│   ├── namespace.yaml
│   ├── fineract-oauth2-config-patch.yaml
│   └── fineract-irsa-patch.yaml
├── uat/
│   ├── kustomization.yaml       # UAT overlay (inherits from base)
│   ├── namespace.yaml
│   └── fineract-oauth2-config-patch.yaml
└── production/
    ├── kustomization.yaml       # Production overlay (inherits from base)
    ├── namespace.yaml
    └── fineract-oauth2-config-patch.yaml
```

## Related Documentation

- [Kustomize Documentation](https://kustomize.io/)
- [Version Matrix](../../docs/VERSION_MATRIX.md) - Authoritative version requirements
- [Deployment Guide](../../DEPLOYMENT.md) - How to deploy environments

---

**Last updated**: 2025-11-20
**Refactored**: Phase 2 of maintenance cleanup plan
