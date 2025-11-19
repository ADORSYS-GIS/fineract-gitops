# Fineract-Data Improvement Plan

**Strategy: Incremental Improvements Inspired by keycloak-config-cli**

**Goal:** Keep current wave-based Kubernetes Jobs architecture but add missing capabilities for better debugging, testing, validation, and idempotency.

**Timeline:** 3-4 weeks part-time
**Risk Level:** Low (incremental changes, existing architecture preserved)
**Status:** Not Started

---

## Current Pain Points (To Be Addressed)

- [ ] **Debugging is difficult** - Hard to identify which entity/file caused failures
- [ ] **Cannot test locally** - Requires live Fineract instance
- [ ] **Data not loading in defined sequence** - Dependency ordering issues
- [ ] **Not idempotent** - Re-running causes inconsistencies
- [ ] **Complex to maintain** - Too many files (100+ YAML files)
- [ ] **Late error detection** - Schema errors caught during API calls, not before

---

## Phase 1: Improve Observability & Debugging

**Timeline:** Week 1
**Status:** ⏳ Not Started

### 1.1 Add Structured Logging (JSON format with context)

**Status:** ⏳ Not Started

**Current State:**
- Plain text logs mixed with Python stack traces
- No request IDs to correlate with Fineract API logs
- Errors don't show which YAML file caused failure

**Target State:**
```python
# Example structured log output
{
  "timestamp": "2024-11-19T20:04:15Z",
  "level": "ERROR",
  "entity_type": "Office",
  "yaml_file": "/data/offices__yaounde-branch.yaml",
  "api_endpoint": "POST /fineract-provider/api/v1/offices",
  "request_id": "req_abc123",
  "error_type": "ValidationError",
  "error_message": "parentId is required",
  "fineract_response": {"errors": [{"developerMessage": "parentId is required"}]},
  "payload": {"name": "Yaounde Branch", "externalId": "BR-YDE-001"}
}
```

**Implementation Tasks:**
- [ ] Add Python `structlog` dependency to requirements.txt
- [ ] Create `LoggerMixin` class in base_loader.py
- [ ] Update all log statements in BaseLoader to use structured logging
- [ ] Add context manager for tracking current entity/file
- [ ] Add request_id generation and propagation to Fineract API headers

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- `operations/fineract-data/scripts/requirements.txt`

---

### 1.2 Enhance Error Reporting

**Status:** ⏳ Not Started

**Current State:**
```
SYSTEM FOUNDATION - FINAL SUMMARY
Total Created: 23
Total Updated: 5
Total Failed: 2
Failed Entity Types:
  ✗ Offices
```

**Target State:**
```
SYSTEM FOUNDATION - DETAILED SUMMARY
┌────────────────┬─────────┬─────────┬─────────┬────────┐
│ Entity Type    │ Created │ Updated │ Skipped │ Failed │
├────────────────┼─────────┼─────────┼─────────┼────────┤
│ CodeValues     │    15   │    0    │    3    │   0    │
│ Offices        │     5   │    2    │    0    │   2    │
│ Staff          │     3   │    1    │    0    │   0    │
└────────────────┴─────────┴─────────┴─────────┴────────┘

FAILED ENTITIES (2):
✗ Office: Yaounde Branch (offices__yaounde-branch.yaml)
  Error: ValidationError - parentId is required
  Parent office 'Cameroon Regional' not found in system

✗ Office: Douala Branch (offices__douala-branch.yaml)
  Error: ValidationError - parentId is required
  Parent office 'Cameroon Regional' not found in system

ERROR CATEGORIES:
  ValidationError: 2 (missing parent references)
  AuthError: 0
  NetworkError: 0
  DependencyError: 0
```

**Implementation Tasks:**
- [ ] Create `SummaryReporter` class with tabular output (use `tabulate` library)
- [ ] Add per-entity status tracking in consolidated loaders
- [ ] Categorize errors by type (ValidationError, AuthError, NetworkError, DependencyError)
- [ ] Show failed entity details with YAML file path
- [ ] Add suggestion engine for common errors (e.g., "Did you create the parent office first?")

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- `operations/fineract-data/scripts/loaders/load_system_foundation.py`
- `operations/fineract-data/scripts/loaders/load_products.py`
- `operations/fineract-data/scripts/loaders/load_accounting.py`
- `operations/fineract-data/scripts/loaders/load_entities.py`
- `operations/fineract-data/scripts/loaders/load_transactions.py`
- `operations/fineract-data/scripts/loaders/load_calendar.py`
- `operations/fineract-data/scripts/requirements.txt` (add `tabulate`)

---

### 1.3 Add Request/Response Logging (Debug Mode)

**Status:** ⏳ Not Started

**Implementation Tasks:**
- [ ] Add `FINERACT_DEBUG` environment variable support
- [ ] Log full HTTP request/response for failed API calls
- [ ] Redact sensitive fields (passwords, secrets) in logs
- [ ] Add `--debug` CLI flag for local testing

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- `operations/fineract-data/kubernetes/base/jobs/job-*.yaml` (add env var)

---

## Phase 2: Schema Validation

**Timeline:** Week 2
**Status:** ⏳ Not Started

### 2.1 Integrate Existing JSON Schemas

**Status:** ⏳ Not Started

**Current State:**
- 33 JSON schemas exist in `/operations/fineract-data/schemas/`
- Schemas not used by loaders
- Validation errors caught during API call (late detection)

**Target State:**
```python
# Validate YAML against schema BEFORE API call
try:
    entity_data = self.load_yaml(yaml_file)
    self.validate_schema(entity_data, schema_name="Office")
except ValidationError as e:
    self.logger.error(f"Schema validation failed for {yaml_file}: {e}")
    return None
```

**Implementation Tasks:**
- [ ] Add `jsonschema` library to requirements.txt
- [ ] Create `SchemaValidator` class in base_loader.py
- [ ] Load schemas from `/schemas/` directory
- [ ] Add `validate_schema()` method to BaseLoader
- [ ] Call validation in `load_single()` before API call
- [ ] Format validation errors with line numbers (if possible with PyYAML)
- [ ] Update all entity loaders to specify schema name

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- `operations/fineract-data/scripts/requirements.txt`
- All 40+ entity loader files (add schema_name parameter)

**Schemas to Review/Update:**
- Verify all 33 schemas are up-to-date with Fineract API
- Add missing schemas for entities without them

---

### 2.2 Add Pre-Commit Hook for YAML Validation

**Status:** ⏳ Not Started

**Implementation Tasks:**
- [ ] Create `.pre-commit-config.yaml` in repository root
- [ ] Add `check-yaml` hook (syntax validation)
- [ ] Add custom hook script: `scripts/validate-fineract-yaml.py`
- [ ] Hook validates changed YAML files against schemas
- [ ] Add documentation in README for setting up pre-commit
- [ ] Add GitHub Actions workflow to enforce validation on PR

**Files to Create:**
- `.pre-commit-config.yaml`
- `operations/fineract-data/scripts/validate-fineract-yaml.py`
- `.github/workflows/validate-yaml.yml`

**Example `.pre-commit-config.yaml`:**
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-yaml
        files: ^operations/fineract-data/data/.*\.yaml$

  - repo: local
    hooks:
      - id: validate-fineract-yaml
        name: Validate Fineract YAML against schemas
        entry: python operations/fineract-data/scripts/validate-fineract-yaml.py
        language: python
        files: ^operations/fineract-data/data/.*\.yaml$
        pass_filenames: true
```

---

## Phase 3: Local Testing with Docker Compose

**Timeline:** Week 2-3
**Status:** ⏳ Not Started

### 3.1 Create Docker Compose Stack

**Status:** ⏳ Not Started

**Implementation Tasks:**
- [ ] Create `operations/fineract-data/docker-compose.yml`
- [ ] Add services: PostgreSQL, Keycloak, Fineract, Loader
- [ ] Add health checks for all services
- [ ] Create seed data script for clean slate (`scripts/seed-fineract.sh`)
- [ ] Add reset script (`scripts/reset-local-fineract.sh`)
- [ ] Document usage in README
- [ ] Test startup time (target: <2 minutes)

**Files to Create:**
- `operations/fineract-data/docker-compose.yml`
- `operations/fineract-data/scripts/seed-fineract.sh`
- `operations/fineract-data/scripts/reset-local-fineract.sh`
- `operations/fineract-data/LOCAL_TESTING.md`

**Example docker-compose.yml structure:**
```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: fineract
      POSTGRES_USER: fineract
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U fineract"]
      interval: 5s
      timeout: 5s
      retries: 5

  keycloak:
    image: quay.io/keycloak/keycloak:24.0.5
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
    command: start-dev
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
      interval: 10s
      timeout: 5s
      retries: 30

  fineract:
    image: apache/fineract:latest
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      FINERACT_DEFAULT_TENANTDB_HOSTNAME: postgres
      FINERACT_DEFAULT_TENANTDB_PORT: 5432
      FINERACT_DEFAULT_TENANTDB_NAME: fineract
      FINERACT_DEFAULT_TENANTDB_UID: fineract
      FINERACT_DEFAULT_TENANTDB_PWD: password
    ports:
      - "8443:8443"
    healthcheck:
      test: ["CMD", "curl", "-f", "-k", "https://localhost:8443/fineract-provider/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 30

  fineract-loader:
    build:
      context: .
      dockerfile: Dockerfile
    depends_on:
      fineract:
        condition: service_healthy
      keycloak:
        condition: service_healthy
    environment:
      FINERACT_URL: https://fineract:8443
      FINERACT_VERIFY_SSL: "false"
      KEYCLOAK_URL: http://keycloak:8080
      # ... other env vars
    volumes:
      - ./data/dev:/data:ro
      - ./scripts:/app/scripts:ro
    command: python3 /app/loaders/load_system_foundation.py

volumes:
  postgres_data:
```

---

### 3.2 Enhance Dry-Run Mode

**Status:** ⏳ Not Started

**Current State:**
- `--dry-run` flag exists in BaseLoader but not fully utilized
- Doesn't show what would change
- Doesn't validate references

**Target State:**
```bash
$ python load_system_foundation.py --dry-run

DRY RUN MODE - No changes will be made

CODE VALUES (15 found):
  ✓ ClientType (code-value__client-type.yaml) - Would CREATE
  ✓ Gender (code-value__gender.yaml) - Would SKIP (already exists, no changes)
  ✓ LoanPurpose (code-value__loan-purpose.yaml) - Would UPDATE (description changed)

OFFICES (7 found):
  ✓ Head Office (offices__head-office.yaml) - Would CREATE
  ✓ Cameroon Regional (offices__cameroon-regional.yaml) - Would CREATE
    └─ Parent: Head Office (resolved via externalId: HEAD-001)
  ✗ Yaounde Branch (offices__yaounde-branch.yaml) - Would FAIL
    └─ Parent: 'Gabon Regional' not found (externalId: GAB-001)
  ✓ Douala Branch (offices__douala-branch.yaml) - Would CREATE
    └─ Parent: Cameroon Regional (resolved via externalId: CMR-001)

SUMMARY:
  Would CREATE: 20 entities
  Would UPDATE: 3 entities
  Would SKIP: 10 entities
  Would FAIL: 2 entities (missing dependencies)
```

**Implementation Tasks:**
- [ ] Enhance `--dry-run` mode in BaseLoader
- [ ] Show CREATE/UPDATE/SKIP/FAIL for each entity
- [ ] Show API payloads (formatted JSON)
- [ ] Validate all references without API calls (use local cache)
- [ ] Show dependency resolution tree
- [ ] Add summary with would-be changes
- [ ] Support `--dry-run` in all consolidated loaders

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- All consolidated loader scripts

---

### 3.3 Add Test Suite

**Status:** ⏳ Not Started

**Implementation Tasks:**
- [ ] Create `operations/fineract-data/tests/` directory
- [ ] Add `pytest` and `responses` libraries to requirements.txt
- [ ] Write unit tests for BaseLoader methods
  - [ ] `load_yaml()` - YAML parsing
  - [ ] `entity_exists()` - Existence check logic
  - [ ] `has_changes()` - Change detection logic
  - [ ] `_resolve_office()` - Reference resolution
  - [ ] `_resolve_gl_account()` - GL account resolution
- [ ] Write integration tests against Docker Compose stack
  - [ ] Test full system-foundation load
  - [ ] Test idempotency (run twice, verify no changes)
  - [ ] Test error recovery (fail mid-wave, retry)
  - [ ] Test reference resolution
- [ ] Add GitHub Actions workflow for tests
- [ ] Add coverage reporting

**Files to Create:**
- `operations/fineract-data/tests/__init__.py`
- `operations/fineract-data/tests/test_base_loader.py`
- `operations/fineract-data/tests/test_offices_loader.py`
- `operations/fineract-data/tests/test_integration.py`
- `operations/fineract-data/tests/conftest.py` (pytest fixtures)
- `.github/workflows/test-loaders.yml`

**Example GitHub Actions workflow:**
```yaml
name: Test Fineract Data Loaders

on:
  pull_request:
    paths:
      - 'operations/fineract-data/**'

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: pip install -r operations/fineract-data/scripts/requirements.txt
      - run: pytest operations/fineract-data/tests/test_*.py

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: docker-compose -f operations/fineract-data/docker-compose.yml up -d
      - run: docker-compose -f operations/fineract-data/docker-compose.yml run fineract-loader pytest tests/test_integration.py
      - run: docker-compose -f operations/fineract-data/docker-compose.yml down -v
```

---

## Phase 4: Improve Idempotency

**Timeline:** Week 3-4
**Status:** ⏳ Not Started

### 4.1 Fix Comparison Logic in has_changes()

**Status:** ⏳ Not Started

**Current Issues:**
- String vs number comparison fails (e.g., "100" != 100)
- Null vs empty string treated as different
- Whitespace differences trigger updates
- No field-level change detection (just boolean yes/no)

**Implementation Tasks:**
- [ ] Add type normalization before comparison
  - [ ] Convert numeric strings to numbers
  - [ ] Normalize null/empty/whitespace consistently
  - [ ] Handle boolean string representations ("true" vs True)
- [ ] Add field-level change detection
  - [ ] Return dict of changed fields, not just boolean
  - [ ] Show old vs new values in logs
- [ ] Add configurable comparison tolerance for floats
- [ ] Add special handling for dates/timestamps
- [ ] Write comprehensive tests for comparison logic

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py:has_changes()`

**Example improved output:**
```python
# Before
has_changes() -> True

# After
has_changes() -> {
    'changed': True,
    'fields': {
        'description': {'old': 'Old desc', 'new': 'New desc'},
        'interestRate': {'old': 10.5, 'new': 10.50}  # <- Same value, don't update
    }
}
```

---

### 4.2 Add Checksum-Based Caching (like keycloak-config-cli)

**Status:** ⏳ Not Started

**Current State:**
- Every run fetches entity from API to check changes
- Slow for large datasets (100+ entities)

**Target State:**
- Calculate SHA256 checksum of YAML file content
- Store checksums in ConfigMap or local cache
- Skip API call if checksum unchanged

**Implementation Tasks:**
- [ ] Add checksum calculation to BaseLoader
- [ ] Create cache storage mechanism (Redis, ConfigMap, or local file)
- [ ] Add `--force` flag to bypass cache
- [ ] Update consolidated loaders to use checksum cache
- [ ] Add cache invalidation strategy (TTL or manual)

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- `operations/fineract-data/kubernetes/base/configmaps/` (optional: add cache ConfigMap)

**Example implementation:**
```python
def should_process_entity(self, yaml_file: str) -> bool:
    """Check if entity needs processing based on checksum"""
    current_checksum = self._calculate_checksum(yaml_file)
    cached_checksum = self._get_cached_checksum(yaml_file)

    if current_checksum == cached_checksum and not self.force:
        self.logger.info(f"Skipping {yaml_file} (unchanged)")
        return False

    return True
```

---

## Phase 5: Simplify Configuration

**Timeline:** Week 4
**Status:** ⏳ Not Started

### 5.1 Consolidate YAML Files

**Status:** ⏳ Not Started

**Current State:**
- 100+ individual YAML files (one entity per file)
- Complex to maintain (many files to edit)
- Difficult to see relationships between entities

**Target State:**
- ~30-40 logical grouping files
- Support multiple entities in one YAML file (array format)
- Keep hierarchical structure in YAML (flatten only in ConfigMap)

**Example consolidated format:**
```yaml
# offices.yaml (instead of 7 separate files)
kind: OfficeCollection
offices:
  - kind: Office
    externalId: HEAD-001
    name: Head Office
    openingDate: 2024-01-01

  - kind: Office
    externalId: CMR-001
    name: Cameroon Regional Office
    parentOfficeExternalId: HEAD-001
    openingDate: 2024-01-15

  - kind: Office
    externalId: BR-YDE-001
    name: Yaounde Branch
    parentOfficeExternalId: CMR-001
    openingDate: 2024-02-01
```

**Implementation Tasks:**
- [ ] Design consolidated YAML format (support both single entity and array)
- [ ] Update `discover_yaml_files()` to handle arrays
- [ ] Update ConfigMap generation script to flatten arrays
- [ ] Migrate existing YAML files to consolidated format (per environment)
- [ ] Update documentation

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py:discover_yaml_files()`
- `operations/fineract-data/scripts/generate-configmap-kustomization.py`
- All YAML files in `operations/fineract-data/data/dev/` (gradual migration)

---

### 5.2 Add Explicit Dependency Declaration

**Status:** ⏳ Not Started

**Current State:**
- Dependencies hardcoded in Python loader scripts
- Order is implicit (must read code to understand)

**Target State:**
- Dependencies declared in YAML
- Auto-ordering within waves

**Example:**
```yaml
kind: Office
externalId: BR-YDE-001
name: Yaounde Branch
dependsOn:
  - kind: Office
    externalId: CMR-001  # Parent office must exist first
openingDate: 2024-02-01
```

**Implementation Tasks:**
- [ ] Add `dependsOn` field to YAML schemas
- [ ] Implement dependency graph builder
- [ ] Add topological sort for auto-ordering
- [ ] Detect circular dependencies
- [ ] Update loaders to use dependency graph

**Files to Modify:**
- `operations/fineract-data/scripts/loaders/base_loader.py`
- All JSON schemas (add `dependsOn` field)
- Consolidated loader scripts

---

## Success Metrics

Track these metrics to measure improvement:

- [ ] **Debugging time reduced by 75%**
  - Current: 30 minutes to identify which entity failed
  - Target: <5 minutes with structured logs and detailed error reports

- [ ] **Local testing enabled**
  - Current: Cannot test without live Fineract in Kubernetes
  - Target: `docker-compose up` in <2 minutes

- [ ] **Validation errors caught early**
  - Current: 100% caught during API call
  - Target: 90% caught during YAML load or pre-commit

- [ ] **Idempotency improved**
  - Current: Re-running sometimes causes unnecessary updates
  - Target: 100% idempotent (no updates when no changes)

- [ ] **Maintenance burden reduced**
  - Current: 100+ YAML files
  - Target: 30-40 logical files

- [ ] **Test coverage**
  - Current: 0% test coverage
  - Target: 80% test coverage for core loader logic

---

## Decision Log

### Why Keep Kubernetes Jobs Instead of Single Consolidated Job?

**Decision:** Keep wave-based Kubernetes Jobs architecture

**Reasoning:**
- ArgoCD sync waves provide clean dependency management
- Wave-based approach is already working in production
- Easier to debug (smaller blast radius per job)
- Can retry individual waves without re-running everything
- Aligns with GitOps philosophy (declarative, wave-based deployment)

### Why Not Full Rewrite Like keycloak-config-cli?

**Decision:** Incremental improvements only

**Reasoning:**
- Current architecture fundamentally sound
- Full rewrite carries high risk and cost (3-4 weeks vs 1-2 months)
- Incremental approach allows gradual migration and rollback
- Can adopt best practices from keycloak-config-cli without full rewrite
- Maintains team familiarity with codebase

### Why Docker Compose for Local Testing?

**Decision:** Add Docker Compose stack for local development

**Reasoning:**
- Fast startup (<2 minutes) for quick feedback loops
- No dependency on Kubernetes for local testing
- Easy to reset and seed data
- Standard tool familiar to most developers
- Can be used in CI/CD for integration tests

---

## Next Steps

1. Review and approve this plan
2. Start with Phase 1.1 (Structured Logging) - quick win, high value
3. Implement phases sequentially
4. Mark tasks complete as you go
5. Update this document with lessons learned

---

## Notes and Learnings

(Add notes here as you implement each phase)

