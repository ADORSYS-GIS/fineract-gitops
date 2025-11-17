# Fineract Data Loader Separation Plan

## Overview
This document outlines the plan to separate the fineract-data loader into a standalone repository, providing cleaner separation of concerns between loader code and configuration data.

## Executive Summary

The fineract-data loader system will be split into two repositories:
1. **fineract-data-loader** (NEW): Python loader scripts, Docker image build
2. **fineract-gitops** (EXISTING): YAML data, Kubernetes manifests, GitOps configuration

## Benefits

### 1. Cleaner Separation of Concerns
- **Loader repo**: Application code, business logic for data loading
- **GitOps repo**: Configuration data, infrastructure manifests, deployment specs

### 2. Independent Versioning and Releases
- Loader can evolve with semantic versioning (v1.0.0, v2.0.0, etc.)
- Data changes don't trigger loader rebuilds
- Loader improvements don't require data repo changes

### 3. Reusability Across Environments
- Same loader image used across dev, UAT, prod
- Multiple projects can use the same loader
- Easier to share loader with other teams/organizations

### 4. Easier CI/CD Management
- Loader builds only when code changes
- Data syncs only when configuration changes
- Clearer separation in GitHub Actions workflows
- Reduced build times and resource usage

---

## Current Architecture

### File Structure

```
fineract-gitops/
└── operations/fineract-data/
    ├── data/                           # YAML configuration files
    │   └── dev/
    │       ├── codes-and-values/
    │       ├── offices/
    │       ├── products/
    │       └── ...
    │
    ├── scripts/                        # Loader Python scripts
    │   ├── loaders/
    │   │   ├── base_loader.py          # Base class
    │   │   ├── load_system_foundation.py
    │   │   ├── load_products.py
    │   │   └── ... (67 Python files total)
    │   ├── Dockerfile
    │   ├── requirements.txt
    │   └── generate-configmap-kustomization.py
    │
    └── kubernetes/
        └── base/
            └── jobs/
                ├── job-01-system-foundation.yaml
                ├── job-02-products.yaml
                └── ...

.github/
└── workflows/
    └── build-loader-image.yml          # Builds loader Docker image
```

### Current Workflow

#### Data Changes (90% of updates):
```
1. Edit YAML → 2. Regenerate kustomization → 3. Git commit/push
   ↓
4. ArgoCD detects change → 5. ConfigMap hash changes
   ↓
6. Job re-runs → 7. Fineract API updated
```

#### Loader Code Changes (10% of updates):
```
1. Edit Python script → 2. Git commit/push
   ↓
3. GitHub Actions builds image → 4. Push to ghcr.io
   ↓
5. Update job manifest image tag → 6. Git commit/push
   ↓
7. ArgoCD syncs → 8. Jobs use new loader
```

---

## Target Architecture

### New Repository: fineract-data-loader

```
fineract-data-loader/
├── .github/
│   └── workflows/
│       ├── build-and-publish.yml       # Build Docker image
│       ├── test.yml                    # Unit tests
│       └── integration-test.yml        # Integration tests
│
├── loaders/
│   ├── __init__.py
│   ├── base_loader.py                  # Core base class
│   │
│   ├── consolidated/                   # Wave-based loaders
│   │   ├── __init__.py
│   │   ├── load_system_foundation.py
│   │   ├── load_products.py
│   │   ├── load_accounting.py
│   │   ├── load_entities.py
│   │   ├── load_transactions.py
│   │   └── load_calendar.py
│   │
│   └── entities/                       # Individual entity loaders
│       ├── __init__.py
│       ├── chart_of_accounts.py
│       ├── tax_groups.py
│       ├── offices.py
│       └── ... (60+ entity loaders)
│
├── utils/
│   ├── __init__.py
│   ├── validate_yaml_data.py
│   ├── detect_drift.py
│   └── validate_data_load.py
│
├── tests/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
│       └── sample_data/                # Sample YAML for testing
│
├── examples/
│   └── yaml/                           # Example YAML files
│
├── scripts/
│   ├── test_loaders_locally.sh
│   └── test_all_loaders.sh
│
├── docs/
│   ├── DEVELOPMENT.md
│   ├── TESTING.md
│   ├── LOADER_API.md
│   └── TROUBLESHOOTING.md
│
├── Dockerfile
├── requirements.txt
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

### Updated Repository: fineract-gitops

```
operations/fineract-data/
├── data/
│   ├── dev/                            # YAML configuration data
│   ├── uat/                            # UAT environment data
│   └── prod/                           # Production data
│
├── kubernetes/
│   ├── base/
│   │   ├── rbac.yaml                   # ServiceAccount, Role, RoleBinding
│   │   └── jobs/
│   │       ├── job-01-system-foundation.yaml
│   │       ├── job-02-products.yaml
│   │       ├── job-03-accounting.yaml
│   │       ├── job-04-entities.yaml
│   │       ├── job-05-transactions.yaml
│   │       └── job-06-calendar.yaml
│   └── overlays/
│       ├── dev/
│       ├── uat/
│       └── prod/
│
├── scripts/
│   ├── generate-configmap-kustomization.py  # STAYS - coupled to data
│   └── update-job-configmaps.py             # STAYS - updates jobs
│
├── schemas/                            # JSON schemas for YAML validation
│
├── docs/
│   ├── DATA_MANAGEMENT.md
│   ├── LOADER_INTEGRATION.md
│   └── VERSIONING.md
│
├── kustomization.yaml                  # Generated by script
├── README.md
└── CHANGELOG.md
```

---

## What Moves vs What Stays

### Moving to fineract-data-loader Repository

#### 1. All Loader Python Scripts (67 files, ~468KB)
- `base_loader.py` - Core base class with OAuth2, reference resolution
- 6 consolidated loaders (waves 5, 10, 21, 30, 35, 40)
- 60+ individual entity loaders
- `validate_yaml_data.py` - YAML validation utility
- Testing scripts (`test_loaders_locally.sh`, `test_all_loaders.sh`)
- Other utilities (`detect_drift.py`, `validate_data_load.py`)

#### 2. Docker Build Configuration
- `Dockerfile` - Python 3.11 slim with loader scripts
- `requirements.txt` - PyYAML, requests dependencies
- `.dockerignore` - Build optimization

#### 3. GitHub Actions Workflow
- `.github/workflows/build-and-publish.yml` (renamed from build-loader-image.yml)
- Builds multi-platform images (linux/amd64, linux/arm64)
- Publishes to `ghcr.io/adorsys-gis/fineract-loader`
- Triggered by changes to loader code

#### 4. Documentation
- Loader development guide
- API reference for creating custom loaders
- Testing procedures
- Troubleshooting guide

### Staying in fineract-gitops Repository

#### 1. YAML Data Files
- All configuration data in `data/dev/`, `data/uat/`, `data/prod/`
- Organized by entity type and wave
- Environment-specific configurations

#### 2. Kubernetes Manifests
- 6 job YAML files
- RBAC configuration (ServiceAccount, Role, RoleBinding)
- Kustomize overlays for environments

#### 3. ConfigMap Generation Script
**CRITICAL DECISION: `generate-configmap-kustomization.py` STAYS**

**Reasoning:**
- Tightly coupled to data structure and organization
- Knows wave mappings (which entities belong to which ConfigMaps)
- Uses relative paths to scan data files
- Part of data update workflow, not loader logic
- Generates `kustomization.yaml` from actual data files

**Workflow:**
```bash
# User edits data
vim data/dev/products/loan-products/sme-loan.yaml

# Script regenerates ConfigMap definitions
python3 scripts/generate-configmap-kustomization.py --output kustomization.yaml

# Both data and kustomization are committed together
git add data/dev/products/loan-products/sme-loan.yaml
git add kustomization.yaml
git commit -m "ops: add SME loan product"
```

#### 4. Job Update Script
- `update-job-configmaps.py` - Updates job manifests with ConfigMap references
- Part of GitOps maintenance, not loader logic

---

## Integration Points

### How Repositories Integrate

#### 1. Docker Image Reference
Job manifests reference the loader Docker image:

```yaml
# kubernetes/base/jobs/job-02-products.yaml
spec:
  template:
    spec:
      containers:
      - name: loader
        image: ghcr.io/adorsys-gis/fineract-loader:v2.0.0
        command: ["python3", "/app/loaders/load_products.py"]
        args: ["--yaml-dir", "/data"]
```

#### 2. Version Management Strategy

**Development Environment:**
- Use `latest` or branch tags (e.g., `main-a1b2c3d`)
- Automatic updates for rapid iteration

**UAT/Production:**
- Pin to specific semantic versions (e.g., `v2.0.0`)
- Explicit upgrades with testing

**Compatibility Matrix:**
| Loader Version | Compatible Data Schema | Notes |
|----------------|------------------------|-------|
| v1.0.0 | 2024-01 | Initial consolidated loaders |
| v2.0.0 | 2024-01 | Separated into standalone repo |
| v2.1.0 | 2024-02 | Added support for new entity types |

### Workflows After Separation

#### Workflow 1: Loader Code Changes

```
fineract-data-loader repo:
1. Developer edits Python script (e.g., fix bug in interest rate calculation)
2. Commit and push to fineract-data-loader repo
3. GitHub Actions workflow triggers
4. Docker image built with new tag (e.g., v2.1.0)
5. Image pushed to ghcr.io/adorsys-gis/fineract-loader:v2.1.0

fineract-gitops repo:
6. Update job manifests to reference new image tag
7. Commit and push changes
8. ArgoCD detects change and syncs
9. Jobs now use new loader code
```

**Timeline:** 5-10 minutes (image build + sync)

#### Workflow 2: Data Changes (No Loader Changes)

```
fineract-gitops repo:
1. Developer edits YAML data file
2. Run: python3 scripts/generate-configmap-kustomization.py
3. Commit data + updated kustomization.yaml
4. Push to fineract-gitops repo
5. ArgoCD detects change (ConfigMap hash changes)
6. Jobs automatically re-run with new data
7. Fineract API updated
```

**Timeline:** 3-5 minutes (no image build needed)

#### Workflow 3: Both Code and Data Changes

```
fineract-data-loader repo:
1. Update loader code
2. Build and publish new image (e.g., v2.2.0)

fineract-gitops repo:
3. Update data files
4. Update job manifests to use v2.2.0
5. Regenerate kustomization
6. Commit and push
7. ArgoCD syncs both code and data changes
```

**Timeline:** 5-10 minutes

---

## Detailed File Inventory

### Files Moving to fineract-data-loader

#### Loader Scripts (67 Python files)

**Base Infrastructure:**
- `loaders/base_loader.py` (1,060 lines) - OAuth2, HTTP, reference resolution

**Consolidated Loaders (6 files):**
1. `loaders/consolidated/load_system_foundation.py` - Wave 5 (9 entities)
2. `loaders/consolidated/load_products.py` - Wave 10 (11 entities)
3. `loaders/consolidated/load_accounting.py` - Wave 21 (9 entities)
4. `loaders/consolidated/load_entities.py` - Wave 30 (5 entities)
5. `loaders/consolidated/load_transactions.py` - Wave 35 (4 entities)
6. `loaders/consolidated/load_calendar.py` - Wave 40 (1 entity)

**Individual Entity Loaders (60+ files):**
- System Foundation: `code_values.py`, `offices.py`, `staff.py`, `roles.py`, etc.
- Products: `loan_products.py`, `savings_products.py`, `charges.py`, etc.
- Accounting: `chart_of_accounts.py`, `tax_groups.py`, `gl_closures.py`, etc.
- Entities: `clients.py`, `savings_accounts.py`, `loan_accounts.py`, etc.
- Transactions: `savings_deposits.py`, `loan_repayments.py`, etc.
- Calendar: `holidays.py`

**Utilities:**
- `utils/validate_yaml_data.py` (557 lines) - YAML validation
- `utils/detect_drift.py` - Detect differences between YAML and Fineract
- `utils/validate_data_load.py` - Post-load validation
- `utils/implement_all_loaders.py` - Code generation helper

**Testing Scripts:**
- `scripts/test_loaders_locally.sh` (208 lines) - Local testing
- `scripts/test_all_loaders.sh` - Comprehensive test suite
- `scripts/generate_loaders_and_jobs.py` (439 lines) - Code generation

**Build Configuration:**
- `Dockerfile` - Multi-stage Python 3.11 slim build
- `requirements.txt` - PyYAML==6.0.1, requests==2.31.0

**CI/CD:**
- `.github/workflows/build-and-publish.yml` - Docker image build and publish

### Files Staying in fineract-gitops

#### Data Files (All YAML)
- `data/dev/codes-and-values/` - Code values, value lists
- `data/dev/offices/` - Office hierarchy
- `data/dev/staff/` - Staff members
- `data/dev/products/` - Loan/savings products
- `data/dev/accounting/` - Chart of accounts, tax groups
- `data/dev/entities/` - Clients, accounts
- `data/dev/transactions/` - Deposits, withdrawals, repayments
- `data/dev/calendar/` - Holidays
- Future: `data/uat/`, `data/prod/`

#### Kubernetes Manifests
- `kubernetes/base/rbac.yaml` - ServiceAccount, Role, RoleBinding
- `kubernetes/base/jobs/job-01-system-foundation.yaml` - Wave 5 job
- `kubernetes/base/jobs/job-02-products.yaml` - Wave 10 job
- `kubernetes/base/jobs/job-03-accounting.yaml` - Wave 21 job
- `kubernetes/base/jobs/job-04-entities.yaml` - Wave 30 job
- `kubernetes/base/jobs/job-05-transactions.yaml` - Wave 35 job
- `kubernetes/base/jobs/job-06-calendar.yaml` - Wave 40 job
- `kubernetes/overlays/dev/`, `kubernetes/overlays/uat/`, `kubernetes/overlays/prod/`

#### Scripts
- `scripts/generate-configmap-kustomization.py` (270 lines) - ConfigMap generation
- `scripts/update-job-configmaps.py` (173 lines) - Job manifest updates

#### Root Files
- `kustomization.yaml` - Generated by script, references ConfigMaps and jobs
- `README.md` - Data management documentation
- `CHANGELOG.md` - Data change history

---

## Migration Plan

### Phase 1: Create New Loader Repository (Week 1)

#### Step 1.1: Repository Setup
- [ ] Create `fineract-data-loader` repository on GitHub
- [ ] Initialize with README, LICENSE, .gitignore
- [ ] Set up branch protection for `main`
- [ ] Configure GitHub Container Registry access

#### Step 1.2: Copy Loader Code
- [ ] Create directory structure (loaders/, utils/, tests/, scripts/, docs/)
- [ ] Copy all 67 Python files from fineract-gitops
- [ ] Organize into consolidated/ and entities/ subdirectories
- [ ] Add `__init__.py` files for proper Python package structure

#### Step 1.3: Update Build Configuration
- [ ] Copy Dockerfile to root of new repo
- [ ] Update Dockerfile build context (now root instead of nested path)
- [ ] Copy requirements.txt
- [ ] Test local Docker build: `docker build -t fineract-loader:test .`

#### Step 1.4: Migrate CI/CD
- [ ] Copy `.github/workflows/build-loader-image.yml`
- [ ] Rename to `build-and-publish.yml`
- [ ] Update trigger paths (now watch root, not `operations/fineract-data/scripts/**`)
- [ ] Update build context path in workflow
- [ ] Test workflow with a test commit

#### Step 1.5: Documentation
- [ ] Write comprehensive README.md
  - Project overview
  - Architecture explanation
  - Development setup
  - Usage examples
- [ ] Create DEVELOPMENT.md
  - Local development environment setup
  - Creating new entity loaders
  - Testing procedures
- [ ] Create LOADER_API.md
  - BaseLoader API reference
  - Extending loaders
  - Configuration options
- [ ] Create CHANGELOG.md with v2.0.0 as initial separated version

#### Step 1.6: Testing
- [ ] Copy sample YAML data to `examples/yaml/`
- [ ] Set up unit tests for BaseLoader
- [ ] Set up integration tests
- [ ] Create test fixtures
- [ ] Document testing procedures

#### Step 1.7: First Release
- [ ] Build image from new repo
- [ ] Tag as `v2.0.0` (major version bump to mark separation)
- [ ] Push to `ghcr.io/adorsys-gis/fineract-loader:v2.0.0`
- [ ] Verify image is accessible
- [ ] Test image locally with sample data

### Phase 2: Update GitOps Repository (Week 2)

#### Step 2.1: Update Job Manifests
- [ ] Update all 6 job YAML files to reference new image
  - Change: `ghcr.io/adorsys-gis/fineract-loader:v1.0.0`
  - To: `ghcr.io/adorsys-gis/fineract-loader:v2.0.0`
- [ ] Update initContainer image references (validation)
- [ ] Verify no other references to old scripts

#### Step 2.2: Keep Essential Scripts
- [ ] Verify `generate-configmap-kustomization.py` works with new structure
- [ ] Verify `update-job-configmaps.py` works
- [ ] Test ConfigMap generation: `python3 scripts/generate-configmap-kustomization.py`
- [ ] Verify kustomization.yaml is correctly generated

#### Step 2.3: Documentation Updates
- [ ] Update main README.md
  - Reference loader repo
  - Explain separation
  - Link to loader documentation
- [ ] Create `docs/LOADER_INTEGRATION.md`
  - How to use loader images
  - Version compatibility matrix
  - Update procedures
- [ ] Create `docs/DATA_MANAGEMENT.md`
  - Data file structure
  - Adding new entities
  - Wave dependencies
- [ ] Create `docs/VERSIONING.md`
  - Semantic versioning strategy
  - When to update loader version
  - Compatibility guidelines
- [ ] Update CHANGELOG.md with separation milestone

#### Step 2.4: Create Test Commit
- [ ] Make a small data change (e.g., add a test office)
- [ ] Run ConfigMap generation script
- [ ] Commit and push to dev/test branch
- [ ] Verify ArgoCD detects change
- [ ] Verify job runs successfully with v2.0.0 image

### Phase 3: Validation & Testing (Week 2-3)

#### Step 3.1: Development Environment Testing
- [ ] Deploy to dev environment
- [ ] Test all 6 wave jobs complete successfully
- [ ] Verify data loads correctly into Fineract
- [ ] Check job logs for errors
- [ ] Monitor ArgoCD sync status

#### Step 3.2: Loader Functionality Testing
- [ ] Test Wave 5 (system-foundation) - codes, offices, staff, roles
- [ ] Test Wave 10 (products) - loan/savings products, charges
- [ ] Test Wave 21 (accounting) - chart of accounts, mappings
- [ ] Test Wave 30 (entities) - clients, accounts
- [ ] Test Wave 35 (transactions) - deposits, withdrawals
- [ ] Test Wave 40 (calendar) - holidays

#### Step 3.3: GitOps Workflow Testing
- [ ] Test data-only change workflow
  1. Edit YAML file
  2. Regenerate ConfigMaps
  3. Commit and push
  4. Verify ArgoCD sync
  5. Verify job re-runs automatically
- [ ] Test loader-only change workflow
  1. Make small change to loader code
  2. Build new image (v2.0.1)
  3. Update job manifests
  4. Commit and push
  5. Verify ArgoCD sync
  6. Verify jobs use new image
- [ ] Test combined change workflow

#### Step 3.4: Performance Testing
- [ ] Measure job execution times
- [ ] Compare with previous single-repo times
- [ ] Monitor resource usage
- [ ] Check image pull times

#### Step 3.5: Error Handling Testing
- [ ] Test with invalid YAML (validation should catch)
- [ ] Test with missing references
- [ ] Test with Fineract API errors
- [ ] Verify error messages are clear
- [ ] Test retry mechanisms

### Phase 4: Cleanup & Go-Live (Week 3)

#### Step 4.1: Remove Old Files from fineract-gitops
- [ ] Create backup branch before deletion
- [ ] Remove `operations/fineract-data/scripts/loaders/` (60+ files)
- [ ] Remove `operations/fineract-data/scripts/Dockerfile`
- [ ] Remove `operations/fineract-data/scripts/requirements.txt`
- [ ] Remove old testing scripts (except those kept for data validation)
- [ ] Remove `.github/workflows/build-loader-image.yml`
- [ ] Keep only:
  - `scripts/generate-configmap-kustomization.py`
  - `scripts/update-job-configmaps.py`

#### Step 4.2: Final Documentation
- [ ] Update both repos' README files
- [ ] Cross-reference between repos
- [ ] Document version compatibility
- [ ] Create migration guide (this document!)
- [ ] Update team wiki/confluence

#### Step 4.3: Team Communication
- [ ] Announce separation to development team
- [ ] Conduct training session on new workflow
- [ ] Share documentation links
- [ ] Explain when to update each repo
- [ ] Set up Slack/Teams notifications for new releases

#### Step 4.4: Production Rollout
- [ ] Deploy to UAT environment
- [ ] Run full test suite in UAT
- [ ] Monitor for 24-48 hours
- [ ] If stable, deploy to production
- [ ] Monitor production for 1 week

#### Step 4.5: Post-Migration
- [ ] Archive old branches in fineract-gitops
- [ ] Tag both repos with migration date
- [ ] Document lessons learned
- [ ] Update runbooks and operational procedures
- [ ] Set up automated version checking (renovate/dependabot)

---

## Risk Assessment & Mitigation

### Risk 1: Breaking Changes in Loader Code
**Impact:** High - Could break data loading for all environments

**Probability:** Medium

**Mitigation:**
- Use strict semantic versioning
  - MAJOR: Breaking changes (v2.0.0 → v3.0.0)
  - MINOR: New features, backwards compatible (v2.0.0 → v2.1.0)
  - PATCH: Bug fixes (v2.0.0 → v2.0.1)
- Pin versions in UAT/prod
- Thorough testing in dev before promotion
- Maintain backwards compatibility when possible
- Document breaking changes in CHANGELOG
- Provide migration guides for breaking changes

### Risk 2: Version Drift Between Repos
**Impact:** Medium - Data and loader could become incompatible

**Probability:** Medium

**Mitigation:**
- Document version compatibility in data repo README
- Create compatibility matrix
- Use renovate bot to track image versions
- Set up automated alerts for outdated versions
- Regular sync meetings between teams
- Version check in loader startup

### Risk 3: Circular Dependencies
**Impact:** Low - Could complicate development workflow

**Probability:** Low (already mitigated by design)

**Mitigation:**
- `generate-configmap-kustomization.py` stays in data repo
- Loader has no knowledge of data structure
- Clean separation: loader = HOW, data = WHAT
- No cross-repo code dependencies

### Risk 4: Testing Complexity
**Impact:** Medium - Harder to test loader changes against real data

**Probability:** Medium

**Mitigation:**
- Include sample data in loader repo for unit tests
- Set up integration tests with test Fineract instance
- Docker Compose environment for local testing
- CI/CD pipeline runs tests on every PR
- Document testing procedures clearly
- Provide test data generation scripts

### Risk 5: Image Build Failures
**Impact:** Medium - Could block data updates if loader needs changes

**Probability:** Low

**Mitigation:**
- GitHub Actions provides build reliability
- Multi-platform builds (amd64, arm64)
- Cache layers for faster builds
- Automated testing before image push
- Keep previous working image available
- Monitor build pipeline health

### Risk 6: Documentation Divergence
**Impact:** Low - Confusing for developers

**Probability:** Medium

**Mitigation:**
- Clear ownership: Loader = HOW, Data = WHAT
- Cross-reference between repos
- Single source of truth for each concept
- Regular documentation reviews
- Maintain CHANGELOG in both repos
- Use GitHub wiki for shared concepts

### Risk 7: Access Control Issues
**Impact:** Low - Different teams may need different access

**Probability:** Low

**Mitigation:**
- Configure GitHub teams appropriately
- Loader repo: Platform/DevOps team (code changes)
- Data repo: Product/Config team (data changes)
- Both teams have read access to both repos
- Clear CODEOWNERS files
- Document who to contact for each type of change

### Risk 8: Rollback Complexity
**Impact:** High - Rolling back changes could be complicated

**Probability:** Low

**Mitigation:**
- Keep old fineract-gitops structure in backup branch
- Document rollback procedure
- ArgoCD makes rollback straightforward (change image tag)
- Test rollback procedure before go-live
- 2-week parallel run period
- Clear rollback decision criteria

---

## Version Compatibility Matrix

| Loader Version | Release Date | Data Schema | Kubernetes Version | Breaking Changes | Notes |
|----------------|--------------|-------------|-------------------|------------------|-------|
| v1.0.0 | 2024-Q1 | 2024-01 | 1.28+ | N/A | Initial consolidated loaders in single repo |
| v2.0.0 | 2024-Q2 | 2024-01 | 1.28+ | Repo separation | Separated into standalone fineract-data-loader repo. No API changes. |
| v2.1.0 | TBD | 2024-02 | 1.28+ | None | Added support for new Fineract entity types |
| v3.0.0 | TBD | 2024-03 | 1.29+ | API changes | Breaking: Changed OAuth2 flow, requires updated Keycloak config |

### How to Use This Matrix

**When updating loader in dev:**
- Use `latest` tag for continuous updates
- Or use branch tags (e.g., `main-abc123`) for specific commits

**When promoting to UAT:**
- Check matrix for compatibility
- Pin to specific minor version (e.g., `v2.1.0`)
- Test thoroughly before prod

**When promoting to prod:**
- Only use versions tested in UAT
- Pin to specific patch version (e.g., `v2.1.3`)
- Document version in runbook

---

## Operational Procedures

### Procedure 1: Updating Loader Code

**When:** Fixing bugs, adding features, improving performance

**Who:** Platform/DevOps team

**Steps:**
1. Clone `fineract-data-loader` repo
2. Create feature branch: `git checkout -b feature/improve-retry-logic`
3. Make code changes
4. Run local tests: `./scripts/test_loaders_locally.sh`
5. Commit and push branch
6. Create PR with description of changes
7. Wait for CI/CD tests to pass
8. Get code review approval
9. Merge to `main`
10. GitHub Actions builds and tags image (e.g., `v2.1.0`)
11. Clone `fineract-gitops` repo
12. Update job manifests to reference new image
13. Commit: `chore: update loader to v2.1.0`
14. Push to `fineract-gitops`
15. Monitor ArgoCD sync
16. Verify jobs run successfully

**Timeline:** 30-60 minutes

### Procedure 2: Updating Data Configuration

**When:** Adding offices, products, modifying configuration

**Who:** Product/Config team

**Steps:**
1. Clone `fineract-gitops` repo
2. Navigate to `operations/fineract-data/`
3. Edit YAML files in `data/dev/`
4. Run: `python3 scripts/generate-configmap-kustomization.py`
5. Review changes to `kustomization.yaml`
6. Commit: `ops: add new SME loan product`
7. Push to `fineract-gitops`
8. ArgoCD detects ConfigMap hash change
9. Jobs automatically re-run
10. Monitor job completion
11. Verify data in Fineract UI/API

**Timeline:** 5-10 minutes

### Procedure 3: Emergency Rollback

**When:** Critical issue in production

**Who:** On-call engineer

**Steps:**
1. Identify issue (loader bug or data error?)
2. If loader issue:
   - Update job manifests to previous working image tag
   - Commit: `revert: rollback loader to v2.0.5`
   - Push immediately
   - ArgoCD syncs in ~3 minutes
3. If data issue:
   - Revert data file changes: `git revert <commit>`
   - Regenerate ConfigMaps
   - Push immediately
   - ArgoCD syncs and jobs re-run
4. Monitor recovery
5. Post-incident review
6. Fix root cause

**Timeline:** 5-15 minutes

### Procedure 4: Adding New Entity Type

**When:** Fineract adds new API endpoint to load

**Who:** Platform team (loader) + Config team (data)

**Steps:**

**Part A: Loader repo**
1. Create new entity loader in `loaders/entities/`
2. Extend `BaseLoader`
3. Implement `yaml_to_fineract_api()` method
4. Add to appropriate consolidated loader
5. Add unit tests
6. Create sample YAML in `examples/`
7. Update documentation
8. Build and release new loader version

**Part B: Data repo**
9. Create new data directory
10. Add entity YAML files
11. Update `generate-configmap-kustomization.py` wave mappings
12. Regenerate kustomization
13. Test in dev environment
14. Document entity structure

**Timeline:** 2-4 hours

---

## Success Criteria

### Technical Success Metrics

- [ ] All 6 jobs run successfully in dev with v2.0.0 image
- [ ] ConfigMap generation script works unchanged
- [ ] ArgoCD syncs complete without errors
- [ ] Data loads correctly into Fineract
- [ ] Image build time < 5 minutes
- [ ] Job execution time unchanged (within 10%)
- [ ] No increase in API errors
- [ ] Automated tests pass in loader repo

### Operational Success Metrics

- [ ] Team understands new workflow
- [ ] Documentation complete and accurate
- [ ] No production incidents in first 2 weeks
- [ ] Rollback tested and documented
- [ ] Version compatibility tracked
- [ ] CI/CD pipelines reliable (>95% success rate)

### Business Success Metrics

- [ ] Development velocity maintained or improved
- [ ] Reduced coupling enables independent scaling
- [ ] Loader reusable across multiple projects
- [ ] Clear ownership and responsibility
- [ ] Faster iteration on loader improvements
- [ ] Data changes don't require loader expertise

---

## Timeline Summary

| Phase | Duration | Key Activities | Milestone |
|-------|----------|----------------|-----------|
| Phase 1: Create New Repo | Week 1 | Repo setup, code migration, CI/CD, docs | First v2.0.0 image published |
| Phase 2: Update GitOps | Week 2 | Job updates, script validation, docs | Dev environment using v2.0.0 |
| Phase 3: Validation | Week 2-3 | Testing, performance, workflows | All tests passing |
| Phase 4: Cleanup & Go-Live | Week 3 | Remove old files, train team, production | Production running separated repos |
| **Total** | **3 weeks** | | |

---

## Reference Links

### Loader Repository (After Creation)
- GitHub: `https://github.com/guymoyo/fineract-data-loader`
- Container Registry: `ghcr.io/adorsys-gis/fineract-loader`
- Documentation: `https://github.com/guymoyo/fineract-data-loader/blob/main/README.md`

### GitOps Repository (Current)
- GitHub: `https://github.com/ADORSYS-GIS/fineract-gitops`
- Data Directory: `operations/fineract-data/`
- Jobs: `operations/fineract-data/kubernetes/base/jobs/`

### Related Documentation
- Fineract API: `https://fineract.apache.org/docs/`
- Kustomize: `https://kustomize.io/`
- ArgoCD: `https://argo-cd.readthedocs.io/`

---

## Appendix A: Code Examples

### Example: Updating Loader Image in Job Manifest

**Before:**
```yaml
# kubernetes/base/jobs/job-02-products.yaml
spec:
  template:
    spec:
      initContainers:
      - name: validate-yaml
        image: ghcr.io/adorsys-gis/fineract-loader:v1.0.0
        command: ["python3", "/app/validate_yaml_data.py", "/data"]

      containers:
      - name: loader
        image: ghcr.io/adorsys-gis/fineract-loader:v1.0.0
        command: ["python3", "/app/loaders/load_products.py"]
```

**After:**
```yaml
# kubernetes/base/jobs/job-02-products.yaml
spec:
  template:
    spec:
      initContainers:
      - name: validate-yaml
        image: ghcr.io/adorsys-gis/fineract-loader:v2.0.0
        command: ["python3", "/app/validate_yaml_data.py", "/data"]

      containers:
      - name: loader
        image: ghcr.io/adorsys-gis/fineract-loader:v2.0.0
        command: ["python3", "/app/loaders/load_products.py"]
```

### Example: Building Loader Image Locally

```bash
# Clone loader repo
git clone https://github.com/guymoyo/fineract-data-loader.git
cd fineract-data-loader

# Build image
docker build -t fineract-loader:local .

# Test with sample data
docker run --rm \
  -v $(pwd)/examples/yaml:/data:ro \
  -e FINERACT_BASE_URL=https://fineract.example.com \
  -e FINERACT_TENANT=default \
  -e FINERACT_USERNAME=admin \
  -e FINERACT_PASSWORD=password \
  fineract-loader:local \
  python3 /app/loaders/load_system_foundation.py --yaml-dir /data
```

### Example: Regenerating ConfigMaps After Data Change

```bash
# Navigate to data directory
cd operations/fineract-data

# Edit data file
vim data/dev/products/loan-products/sme-loan.yaml

# Regenerate kustomization with ConfigMaps
python3 scripts/generate-configmap-kustomization.py --output kustomization.yaml

# Review changes
git diff kustomization.yaml

# Commit both data and kustomization
git add data/dev/products/loan-products/sme-loan.yaml
git add kustomization.yaml
git commit -m "ops: add SME loan product for small business lending"
git push
```

---

## Appendix B: Troubleshooting

### Issue: Job fails with "ImagePullBackOff"

**Symptom:** Job pod shows ImagePullBackOff status

**Possible Causes:**
1. Image tag doesn't exist in registry
2. Network issues pulling from ghcr.io
3. Image was deleted

**Resolution:**
```bash
# Check if image exists
docker pull ghcr.io/adorsys-gis/fineract-loader:v2.0.0

# If not, check available tags
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://ghcr.io/v2/guymoyo/fineract-loader/tags/list

# Update job manifest to use existing tag
# Or rebuild image if accidentally deleted
```

### Issue: ConfigMap too large

**Symptom:** ArgoCD sync fails with "ConfigMap exceeds size limit"

**Possible Causes:**
1. Too many YAML files in one wave
2. YAML files have large embedded data

**Resolution:**
```bash
# Check ConfigMap sizes
kustomize build operations/fineract-data/ | \
  grep -A 100 "kind: ConfigMap" | \
  awk '/^---/{s=0}/kind: ConfigMap/{s=1}s{print}' | \
  wc -c

# If too large, split into multiple ConfigMaps
# Update generate-configmap-kustomization.py to create sub-waves
```

### Issue: Loader fails with OAuth2 error

**Symptom:** Job logs show "Failed to get OAuth2 token"

**Possible Causes:**
1. Keycloak credentials incorrect
2. Client not configured in Keycloak
3. Network issues

**Resolution:**
```bash
# Check secret values
kubectl get secret fineract-api-credentials -o yaml

# Test OAuth2 flow manually
curl -X POST https://keycloak.example.com/realms/fineract/protocol/openid-connect/token \
  -d client_id=fineract-loader \
  -d client_secret=<secret> \
  -d grant_type=client_credentials

# Verify client exists in Keycloak admin UI
```

---

## Appendix C: FAQ

**Q: Why separate now instead of keeping everything in one repo?**

A: Several reasons:
1. Cleaner separation of concerns (code vs configuration)
2. Independent versioning (loader improvements don't require data repo changes)
3. Reusability (same loader can be used across multiple Fineract deployments)
4. Simpler CI/CD (loader builds vs data syncs are separate)
5. Better team ownership (platform team owns loader, config team owns data)

**Q: Will this slow down development?**

A: No, it should actually speed things up:
- Data changes (90% of work) don't require loader rebuilds
- Loader changes are isolated and easier to test
- Clear ownership reduces confusion
- Parallel development possible (data and loader teams)

**Q: What if I need to change both loader and data?**

A: Two-step process:
1. First, update loader and release new version
2. Then, update data repo to use new loader version
This ensures data changes always work with available loader

**Q: How do I know which loader version to use?**

A: Check the version compatibility matrix in this document. For production, always pin to a specific version (e.g., v2.0.5). For development, you can use `latest`.

**Q: What happens if loader and data get out of sync?**

A: The loader is designed to be backwards compatible. Older loaders will ignore new YAML fields. Newer loaders provide defaults for missing fields. Breaking changes are rare and documented in CHANGELOG.

**Q: Can I still test locally?**

A: Yes! Both repos provide local testing:
- Loader repo: `./scripts/test_loaders_locally.sh` with sample data
- Data repo: Reference loader image and mount local data

**Q: What if GitHub Actions fails to build image?**

A: You can manually build and push:
```bash
docker build -t ghcr.io/adorsys-gis/fineract-loader:v2.0.1 .
docker push ghcr.io/adorsys-gis/fineract-loader:v2.0.1
```

**Q: How do I add a new entity type?**

A: See "Procedure 4: Adding New Entity Type" in Operational Procedures section. Requires changes to both repos: loader code in loader repo, data files in data repo.

---

## Conclusion

This separation strategy provides a clean, maintainable architecture that:
- ✅ Separates code from configuration
- ✅ Enables independent versioning
- ✅ Maintains GitOps workflow
- ✅ Simplifies CI/CD
- ✅ Improves team ownership
- ✅ Enables reusability

The migration is low-risk and can be completed in 3 weeks with proper testing and validation.

**Next Steps:**
1. Review and approve this plan
2. Schedule migration for Week 1
3. Assign team members to each phase
4. Begin Phase 1: Create new loader repository

---

**Document Version:** 1.0
**Last Updated:** 2025-11-17
**Author:** Claude Code (via guymoyo)
**Status:** Planning - Awaiting approval to execute
