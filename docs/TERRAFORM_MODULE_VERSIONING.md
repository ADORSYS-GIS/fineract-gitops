# Terraform Module Versioning Guide

Complete guide to versioning, upgrading, and managing Terraform modules in the fineract-gitops repository.

---

## Table of Contents

- [Overview](#overview)
- [Versioning Strategy](#versioning-strategy)
- [Module Versions](#module-versions)
- [Using Modules](#using-modules)
- [Updating Modules](#updating-modules)
- [Version Pinning by Environment](#version-pinning-by-environment)
- [Rollback Procedures](#rollback-procedures)
- [Best Practices](#best-practices)

---

## Overview

All Terraform modules in this repository use **Git tags** for version tracking. This provides:

- 📌 **Version pinning** - Lock environments to specific module versions
- 🔄 **Rollbacks** - Revert to previous versions when needed
- 📝 **Change tracking** - Clear history of module evolution via CHANGELOG.md
- 🔒 **Stability** - Production uses tested versions while dev uses latest

### Why Git Tags?

Git tags provide lightweight versioning without complex infrastructure:
- No separate module registry needed
- Works seamlessly in monorepo setup
- Enables both local development and version pinning
- Standard Git workflow

---

## Versioning Strategy

### Semantic Versioning

All modules follow [Semantic Versioning 2.0.0](https://semver.org/):

```
vMAJOR.MINOR.PATCH

Example: v1.2.3
         │ │ └─── Patch: Bug fixes (backward compatible)
         │ └───── Minor: New features (backward compatible)
         └─────── Major: Breaking changes (requires updates)
```

**Version Rules**:
- **MAJOR** (v2.0.0): Breaking changes requiring configuration updates
- **MINOR** (v1.1.0): New features that are backward compatible
- **PATCH** (v1.0.1): Bug fixes that are backward compatible

### Monorepo Approach

This repository uses **local paths** for module references, which is optimal for monorepo development:

```hcl
# In terraform/aws/main.tf
module "eks" {
  source = "./modules/eks"  # Local path - always uses latest code
  # ...
}
```

**Benefits**:
- ✅ Immediate testing of module changes
- ✅ No need to push tags before testing
- ✅ Simpler development workflow
- ✅ Single commit for infrastructure + module changes

**When to use Git tags**:
- External repositories referencing your modules
- Production version pinning (optional)
- Rollback scenarios
- Change tracking and documentation

---

## Module Versions

### Current Module Versions

| Module | Version | Git Tag | CHANGELOG |
|--------|---------|---------|-----------|
| EKS | v1.0.0 | `modules/terraform/aws/eks/v1.0.0` | [CHANGELOG](../terraform/aws/modules/eks/CHANGELOG.md) |
| IAM | v1.0.0 | `modules/terraform/aws/iam/v1.0.0` | [CHANGELOG](../terraform/aws/modules/iam/CHANGELOG.md) |
| K3s | v1.0.0 | `modules/terraform/aws/k3s/v1.0.0` | [CHANGELOG](../terraform/aws/modules/k3s/CHANGELOG.md) |
| Kubernetes Namespace | v1.0.0 | `modules/terraform/aws/kubernetes-namespace/v1.0.0` | [CHANGELOG](../terraform/aws/modules/kubernetes-namespace/CHANGELOG.md) |
| Kubernetes Secret | v1.0.0 | `modules/terraform/aws/kubernetes-secret/v1.0.0` | [CHANGELOG](../terraform/aws/modules/kubernetes-secret/CHANGELOG.md) |
| RDS | v1.0.0 | `modules/terraform/aws/rds/v1.0.0` | [CHANGELOG](../terraform/aws/modules/rds/CHANGELOG.md) |
| Route53 | v1.0.0 | `modules/terraform/aws/route53/v1.0.0` | [CHANGELOG](../terraform/aws/modules/route53/CHANGELOG.md) |
| S3 | v1.0.0 | `modules/terraform/aws/s3/v1.0.0` | [CHANGELOG](../terraform/aws/modules/s3/CHANGELOG.md) |
| Secrets Manager | v1.0.0 | `modules/terraform/aws/secrets-manager/v1.0.0` | [CHANGELOG](../terraform/aws/modules/secrets-manager/CHANGELOG.md) |
| SES | v1.0.0 | `modules/terraform/aws/ses/v1.0.0` | [CHANGELOG](../terraform/aws/modules/ses/CHANGELOG.md) |
| VPC | v1.0.0 | `modules/terraform/aws/vpc/v1.0.0` | [CHANGELOG](../terraform/aws/modules/vpc/CHANGELOG.md) |

### Tag Naming Convention

```
modules/terraform/aws/{module-name}/v{MAJOR}.{MINOR}.{PATCH}

Examples:
  modules/terraform/aws/eks/v1.0.0
  modules/terraform/aws/rds/v1.2.3
  modules/terraform/aws/vpc/v2.0.0
```

---

## Using Modules

### Option 1: Local Paths (Recommended for Monorepo)

**Use Case**: Development in this repository

```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name    = "my-cluster"
  cluster_version = "1.28"
  # ...
}
```

**Advantages**:
- Immediate testing
- Single commit workflow
- No tag management during development

---

### Option 2: Git Tags (For External Repos or Version Pinning)

**Use Case**: External repositories or strict version control

#### Pin to Specific Version

```hcl
module "eks" {
  source = "git::https://github.com/ADORSYS-GIS/fineract-gitops.git//terraform/aws/modules/eks?ref=modules/terraform/aws/eks/v1.0.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.28"
  # ...
}
```

#### Use Latest in Major Version

```hcl
module "rds" {
  source = "git::https://github.com/ADORSYS-GIS/fineract-gitops.git//terraform/aws/modules/rds?ref=modules/terraform/aws/rds/v1"
  # ...
}
```

This will use the latest v1.x.x version.

#### Use Latest Minor Version

```hcl
module "s3" {
  source = "git::https://github.com/ADORSYS-GIS/fineract-gitops.git//terraform/aws/modules/s3?ref=modules/terraform/aws/s3/v1.2"
  # ...
}
```

This will use the latest v1.2.x version.

---

## Updating Modules

### Development Workflow

1. **Make Changes** in the module directory
   ```bash
   cd terraform/aws/modules/eks
   # Edit files
   ```

2. **Test Locally** with current local path references
   ```bash
   cd ../../
   terraform plan
   ```

3. **Update Module CHANGELOG**
   ```bash
   # Edit terraform/aws/modules/eks/CHANGELOG.md
   # Add entry for new version
   ```

4. **Commit Changes**
   ```bash
   git add terraform/aws/modules/eks
   git commit -m "feat(eks): add cluster autoscaler support"
   ```

5. **Create Version Tag**
   ```bash
   # Determine version (MAJOR.MINOR.PATCH)
   # Example: Adding feature (backward compatible) = MINOR bump
   git tag -a modules/terraform/aws/eks/v1.1.0 -m "Add cluster autoscaler support to EKS module

   - New variable: enable_cluster_autoscaler
   - New IAM policy for autoscaler
   - Documentation updates

   Breaking changes: None
   Migration required: No"
   ```

6. **Push Tag**
   ```bash
   git push origin modules/terraform/aws/eks/v1.1.0
   ```

7. **Update Main README**
   ```bash
   # Update module version table in terraform/aws/README.md
   ```

### Version Bump Decision Tree

```
Is the change backward compatible?
│
├─ YES ──> Does it add new features?
│          │
│          ├─ YES ──> MINOR version bump (v1.1.0)
│          └─ NO ───> PATCH version bump (v1.0.1)
│
└─ NO ───> MAJOR version bump (v2.0.0)
           Requires migration guide!
```

---

## Version Pinning by Environment

### Recommended Strategy

| Environment | Strategy | Example | Rationale |
|-------------|----------|---------|-----------|
| **Development** | Local paths | `./modules/eks` | Rapid iteration, immediate testing |
| **UAT** | Recent tagged version | `v1.1.0` | Test before production |
| **Production** | Stable tagged version | `v1.0.0` | Proven stability, controlled upgrades |

### Example Configuration

```hcl
# environments/dev/main.tf (Development)
module "eks" {
  source = "../../modules/eks"  # Local - latest code
  # ...
}

# environments/uat/main.tf (UAT)
module "eks" {
  source = "git::https://github.com/ADORSYS-GIS/fineract-gitops.git//terraform/aws/modules/eks?ref=modules/terraform/aws/eks/v1.1.0"
  # Testing v1.1.0 before production
  # ...
}

# environments/production/main.tf (Production)
module "eks" {
  source = "git::https://github.com/ADORSYS-GIS/fineract-gitops.git//terraform/aws/modules/eks?ref=modules/terraform/aws/eks/v1.0.0"
  # Stable v1.0.0, proven in UAT
  # ...
}
```

### Upgrade Process

1. **Deploy new version to DEV** (automatic with local paths)
2. **Test thoroughly in DEV**
3. **Update UAT to new version tag**
4. **Test thoroughly in UAT**
5. **After successful UAT validation, update Production**

---

## Rollback Procedures

### Scenario: Module Update Causes Issue in Production

#### Option 1: Revert to Previous Version (Quickest)

```bash
# 1. Update production configuration to use previous version
cd environments/production

# Edit main.tf
# Change: ref=modules/terraform/aws/eks/v1.1.0
# To:     ref=modules/terraform/aws/eks/v1.0.0

# 2. Apply changes
terraform init -upgrade  # Fetch old module version
terraform plan           # Verify changes
terraform apply          # Rollback complete
```

#### Option 2: Create Hotfix Version

```bash
# 1. Create branch from working version tag
git checkout -b hotfix/eks-v1.0.1 modules/terraform/aws/eks/v1.0.0

# 2. Apply fix
cd terraform/aws/modules/eks
# Make minimal fix

# 3. Update CHANGELOG
# Add v1.0.1 entry with hotfix details

# 4. Commit and tag
git commit -m "fix(eks): hotfix for production issue"
git tag -a modules/terraform/aws/eks/v1.0.1 -m "Hotfix: Fix production issue X"
git push origin hotfix/eks-v1.0.1
git push origin modules/terraform/aws/eks/v1.0.1

# 5. Update production to use v1.0.1
```

---

## Best Practices

### DO ✅

1. **Always update CHANGELOG.md** when releasing new versions
2. **Use semantic versioning** correctly (MAJOR.MINOR.PATCH)
3. **Test in DEV → UAT → Production** progression
4. **Document breaking changes** clearly in CHANGELOG
5. **Keep production pinned** to stable versions
6. **Review module changes** before updating production
7. **Use descriptive tag messages** explaining what changed

### DON'T ❌

1. **Don't delete version tags** - they're permanent references
2. **Don't reuse version numbers** - always increment
3. **Don't skip testing** in lower environments
4. **Don't make breaking changes** without MAJOR version bump
5. **Don't forget to push tags** after creating them
6. **Don't update production** without UAT validation

---

## Viewing Module Information

### List All Module Tags

```bash
git tag -l "modules/terraform/aws/*/v*"
```

### View Module CHANGELOG

```bash
cat terraform/aws/modules/eks/CHANGELOG.md
```

### Compare Module Versions

```bash
# See what changed between versions
git diff modules/terraform/aws/eks/v1.0.0..modules/terraform/aws/eks/v1.1.0 -- terraform/aws/modules/eks/
```

### Check Current Module Version in Use

```bash
# For Git-based sources
terraform init
terraform providers
grep -A 2 "module.eks" .terraform/modules/modules.json
```

---

## Troubleshooting

### Issue: "Module not found" with Git source

**Solution**: Ensure tag exists and is pushed
```bash
git tag -l "modules/terraform/aws/eks/*"
git push origin modules/terraform/aws/eks/v1.0.0
```

### Issue: Terraform uses cached old version

**Solution**: Upgrade module cache
```bash
terraform init -upgrade
```

### Issue: Need to test specific version locally

**Solution**: Checkout tag temporarily
```bash
git checkout modules/terraform/aws/eks/v1.0.0
cd terraform/aws
terraform init
terraform plan
git checkout main  # Return to main branch
```

---

## Related Documentation

- [Terraform AWS README](../terraform/aws/README.md) - Main Terraform documentation
- [Module CHANGELOGs](../terraform/aws/modules/) - Individual module change history
- [Semantic Versioning](https://semver.org/) - Official semver specification
- [Terraform Module Sources](https://www.terraform.io/language/modules/sources) - Terraform documentation

---

**Last Updated**: 2025-11-20
**Versioning Started**: 2025-11-20 (Phase 1 of maintenance cleanup)
