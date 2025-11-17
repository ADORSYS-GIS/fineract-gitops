# Image Version Management

**Status**: ✅ Implemented (Phase 4.1)
**Last Updated**: 2025-11-10

## Overview

This repository uses a centralized image version management system to ensure consistent, reproducible deployments across all environments.

**Single Source of Truth**: [`config/image-versions.yaml`](../config/image-versions.yaml)

## Benefits

- ✅ **Single source of truth** - All versions in one file
- ✅ **Easy updates** - Change version once, propagate everywhere
- ✅ **Audit trail** - Git history tracks all version changes
- ✅ **Vulnerability management** - Easy to identify and upgrade affected images
- ✅ **Reproducible builds** - Exact versions documented
- ✅ **Automated updates** - Scripts handle bulk replacements

## Architecture

```
config/image-versions.yaml (source of truth)
    ↓
scripts/update-image-versions.sh (propagation)
    ↓
├── apps/*/base/kustomization.yaml (kustomize image transformers)
├── apps/*/base/deployment.yaml (deployment manifests)
├── operations/*/*.yaml (jobs, cronjobs, init containers)
└── environments/*/kustomization.yaml (environment overrides)
```

## Quick Start

### View Current Versions

```bash
# View all versions
cat config/image-versions.yaml

# View specific category
yq '.CORE_APPLICATIONS' config/image-versions.yaml
yq '.UTILITY_IMAGES' config/image-versions.yaml

# View specific image
yq '.CORE_APPLICATIONS.FINERACT_VERSION' config/image-versions.yaml
```

### Update an Image Version

#### Example 1: Update Fineract

```bash
# 1. Edit the config file
vi config/image-versions.yaml
# Change FINERACT_VERSION from "1.12.0" to "1.13.0"

# 2. Preview changes
./scripts/update-image-versions.sh --dry-run

# 3. Apply changes
./scripts/update-image-versions.sh

# 4. Validate
kubectl kustomize environments/dev | grep "image: apache/fineract"

# 5. Commit
git add -A
git commit -m "chore: upgrade Fineract to 1.13.0"
```

#### Example 2: Update Multiple Utility Images

```bash
# 1. Edit config file
vi config/image-versions.yaml
# Update kubectl, busybox, curl versions

# 2. Preview changes for all utilities
./scripts/update-image-versions.sh --dry-run --image UTILITIES

# 3. Apply changes
./scripts/update-image-versions.sh --image UTILITIES

# 4. Test
kubectl kustomize environments/dev > /dev/null && echo "✓ Build successful"

# 5. Commit
git add -A
git commit -m "chore: update utility image versions"
```

## Image Categories

### Core Applications

Primary application images that run the Fineract platform:

| Component | Current Version | Image Repository | Update Frequency |
|-----------|----------------|------------------|------------------|
| **Fineract** | 1.12.0 | apache/fineract | Quarterly (stable releases) |
| **Keycloak** | 26.4.0 | quay.io/keycloak/keycloak | Monthly (security patches) |
| **OAuth2 Proxy** | v7.5.1 | quay.io/oauth2-proxy/oauth2-proxy | As needed |
| **Redis** | 7.2-alpine | redis | Quarterly (LTS only) |
| **Redis Exporter** | v1.55.0-alpine | oliver006/redis_exporter | With Redis updates |

### Utility Images

Supporting tools and infrastructure components:

| Component | Current Version | Image Repository | Usage |
|-----------|----------------|------------------|-------|
| **envsubst** | 1.4.2 | bhgedigital/envsubst | Config substitution |
| **kubectl** | 1.28.4 | bitnami/kubectl | K8s operations |
| **aws-cli** | 2.15.0 | amazon/aws-cli | AWS operations |
| **busybox** | 1.36.1 | busybox | Init containers |
| **curl** | 8.5.0 | curlimages/curl | Health checks |
| **keycloak-config-cli** | 5.9.0 | adorsys/keycloak-config-cli | Keycloak config |

### Custom Images

Custom-built images specific to this deployment:

| Component | Current Version | Build Script | Source |
|-----------|----------------|--------------|--------|
| **fineract-keycloak-sync** | v1.0.0 | `scripts/build-user-sync-service.sh` | `operations/keycloak-config/user-sync-service/` |
| **web-app** | Multi-branch (dev/ci/main) | External CI/CD | GitHub Container Registry |

#### Web-App Image Management

The web-app uses a **multi-branch strategy** with **tag@digest format** for maximum security and flexibility:

**Format**: `ghcr.io/guymoyo/web-app:<branch>@sha256:<digest>`

**Tracked Branches**:
- **dev** → Development environment
- **ci** → Continuous integration testing (future)
- **main** → UAT and production (future)

**Configuration** (`config/image-versions.yaml`):
```yaml
CUSTOM_IMAGES:
  WEB_APP_IMAGE: "ghcr.io/guymoyo/web-app"

  # Dev branch
  WEB_APP_DEV_VERSION: "dev"
  WEB_APP_DEV_DIGEST: "sha256:dc670e26..."

  # CI branch
  WEB_APP_CI_VERSION: "ci"
  WEB_APP_CI_DIGEST: "sha256:..."

  # Main branch
  WEB_APP_MAIN_VERSION: "main"
  WEB_APP_MAIN_DIGEST: "sha256:..."
```

**Benefits of Tag@Digest**:
- ✅ **Security**: Immutable SHA256 digest ensures exact image
- ✅ **Readability**: Tag shows which branch/version is deployed
- ✅ **Traceability**: Easy to correlate with web-app repository commits
- ✅ **Rollback**: Simple to revert by changing digest in config

**Deployment Strategy**:
- **dev environment** → Uses `WEB_APP_DEV` (dev branch image)
- **uat environment** → Uses `WEB_APP_MAIN` (stable main branch)
- **production** → Uses `WEB_APP_MAIN` (tested stable version)

### Monitoring Stack

Observability components (optional, disabled in dev):

| Component | Current Version | Image Repository |
|-----------|----------------|------------------|
| **Grafana** | 10.2.2 | grafana/grafana |
| **Prometheus Operator** | v0.70.0 | quay.io/prometheus-operator/prometheus-operator |
| **Loki** | 2.9.3 | grafana/loki |
| **Promtail** | 2.9.3 | grafana/promtail |

## Update Procedures

### Routine Updates

**Monthly**: Check for security patches to utility images
```bash
# Check for updates
docker pull bitnami/kubectl:latest
docker pull amazon/aws-cli:latest
docker pull busybox:latest

# If updates available, update config and run script
vi config/image-versions.yaml
./scripts/update-image-versions.sh --image UTILITIES
```

**Quarterly**: Review and update core applications
```bash
# Check Fineract releases
open https://github.com/apache/fineract/releases

# Check Keycloak releases
open https://github.com/keycloak/keycloak/releases

# Update versions
vi config/image-versions.yaml
./scripts/update-image-versions.sh
```

**As needed**: Update web-app when new builds are available
```bash
# 1. Get the new image digest from GitHub Container Registry
# Visit: https://github.com/guymoyo/web-app/pkgs/container/web-app
# Or pull the image and inspect it:
docker pull ghcr.io/guymoyo/web-app:dev
docker inspect ghcr.io/guymoyo/web-app:dev | grep -A 1 "RepoDigests"

# 2. Update the digest in config file
vi config/image-versions.yaml
# Update WEB_APP_DEV_DIGEST: "sha256:NEW_DIGEST_HERE"

# 3. Apply changes (updates both initContainer and mainContainer)
./scripts/update-image-versions.sh --image WEB_APP

# 4. Verify consistency
grep "ghcr.io/guymoyo/web-app" apps/web-app/base/deployment.yaml
# Both lines should show the same digest

# 5. Commit changes
git add -A
git commit -m "chore: update web-app image to sha256:\${NEW_DIGEST:0:12}"
git push origin develop  # Triggers auto-deployment in dev
```

### Emergency Security Patch

When a CVE is discovered:

```bash
# 1. Identify affected image
echo "CVE-2024-XXXX affects busybox:1.36.1"

# 2. Find patched version
docker search busybox --limit 5

# 3. Update immediately
yq -i '.UTILITY_IMAGES.BUSYBOX_VERSION = "1.36.2"' config/image-versions.yaml

# 4. Propagate changes
./scripts/update-image-versions.sh --image UTILITIES

# 5. Deploy to all environments
kubectl apply -k environments/dev
kubectl apply -k environments/uat
kubectl apply -k environments/production

# 6. Commit with CVE reference
git add -A
git commit -m "security: patch busybox CVE-2024-XXXX"
git push origin main
```

### Version Selection Criteria

When choosing image versions:

- ✅ **Use stable releases** - Avoid beta, rc, or nightly builds
- ✅ **Check CVE databases** - Search https://cve.mitre.org/ and https://snyk.io/
- ✅ **Prefer semantic versioning** - Use `major.minor.patch` format
- ✅ **Match Kubernetes version** - For kubectl, match cluster version (1.28.x)
- ✅ **Test in dev first** - Always validate in dev before UAT/production
- ✅ **Document reasons** - Add comments in config file explaining version choice
- ✅ **Avoid latest tag** - Always pin specific versions

### Multi-Environment Updates

#### Development → UAT → Production Promotion

```bash
# 1. Update and test in dev
yq -i '.CORE_APPLICATIONS.FINERACT_VERSION = "1.13.0"' config/image-versions.yaml
./scripts/update-image-versions.sh
kubectl apply -k environments/dev
# Validate application works

# 2. Config file already updated for all environments
# No additional changes needed

# 3. Promote to UAT
kubectl apply -k environments/uat
# Run UAT test suite

# 4. Promote to production
kubectl apply -k environments/production

# 5. Commit once (applies to all environments)
git add -A
git commit -m "chore: upgrade Fineract to 1.13.0 across all environments"
```

## Troubleshooting

### Problem: Image Not Found

```bash
# Error: Failed to pull image "apache/fineract:1.13.0"
# Solution: Verify image exists in registry

docker pull apache/fineract:1.13.0

# If image doesn't exist, revert to previous version
yq -i '.CORE_APPLICATIONS.FINERACT_VERSION = "1.12.0"' config/image-versions.yaml
./scripts/update-image-versions.sh
```

### Problem: Update Script Doesn't Change Files

```bash
# Check if pattern matches
grep -r "apache/fineract:1.12.0" apps/fineract/

# If no matches, images may be using kustomize transformers
grep -A 5 "images:" apps/fineract/base/kustomization.yaml

# Update kustomize manually if needed
yq -i '(.images[] | select(.name == "apache/fineract") | .newTag) = "1.13.0"' \
    apps/fineract/base/kustomization.yaml
```

### Problem: Different Versions in Different Files

```bash
# Audit all versions
echo "=== Fineract Versions ==="
grep -r "apache/fineract:" apps/ environments/ | grep -v "^Binary"

# If inconsistent, force update all
./scripts/update-image-versions.sh
```

## Validation

### Before Committing

```bash
# 1. Validate all kustomize builds
kubectl kustomize environments/dev > /dev/null
kubectl kustomize environments/uat > /dev/null
kubectl kustomize environments/production > /dev/null

# 2. Check for :latest tags (should be zero)
grep -r ":latest" apps/ operations/ | grep -v "imagePullPolicy" | wc -l

# 3. Verify version consistency
./scripts/validate-image-versions.sh  # (Future enhancement)
```

### After Deployment

```bash
# Check running image versions
kubectl get pods -n fineract-dev -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

# Compare with expected versions
yq '.CORE_APPLICATIONS' config/image-versions.yaml
```

## Integration with CI/CD

### Automated Dependency Updates (Future)

```yaml
# .github/workflows/update-dependencies.yml
name: Update Dependencies
on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check for updates
        run: ./scripts/check-image-updates.sh
      - name: Create PR if updates available
        run: ./scripts/create-update-pr.sh
```

### Pre-commit Hook (Future)

```bash
# .git/hooks/pre-commit
#!/bin/bash
# Ensure image versions match config

./scripts/validate-image-versions.sh
if [ $? -ne 0 ]; then
    echo "Error: Image versions don't match config/image-versions.yaml"
    echo "Run: ./scripts/update-image-versions.sh"
    exit 1
fi
```

## Related Documentation

- [Remediation Plan - Phase 4.1](REMEDIATION-PLAN.md#41-implement-image-version-management)
- [Image Pinning Tracking](TODO-IMAGE-PINNING.md)
- [Security Best Practices](../README.md#security)
- [Deployment Guide](E2E_AUTOMATION_GUIDE.md)

## Future Enhancements

- [ ] Automated vulnerability scanning (Snyk, Trivy)
- [ ] Automated update PR creation
- [ ] Image version validation script
- [ ] Dependency graph visualization
- [ ] CVE alerting integration
- [ ] Automated rollback on failure

---

**Questions or Issues?**

Contact: platform-team@example.com
