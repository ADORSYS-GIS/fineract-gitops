# Fineract API Schema Management

This document describes how we manage and sync the Fineract API schema in this GitOps repository.

## Overview

The Fineract API schema is maintained as an OpenAPI specification extracted from the Apache Fineract source code. This schema is used for:

- Understanding API contracts and data structures
- Future validation of YAML files (Phase 2)
- Detecting breaking changes in Fineract updates
- Documentation and reference for loader development

## Schema Location

**Local Path**: `operations/fineract-data/schemas/fineract-openapi.json`

**Source**: Apache Fineract repository
- Repository: https://github.com/apache/fineract
- Generated during build: `fineract-provider/build/classes/java/main/static/fineract.json`
- Gradle task: `fineract-client:openApiGenerate`

## Automated Schema Sync

### Weekly Automated Sync

A GitHub Actions workflow automatically syncs the schema weekly:

- **Schedule**: Every Monday at 9 AM UTC
- **Workflow**: `.github/workflows/sync-fineract-schemas.yml`
- **Process**:
  1. Checkout latest Apache Fineract source
  2. Build Fineract to generate OpenAPI spec
  3. Copy schema to GitOps repository
  4. Detect changes with git diff
  5. Create PR if changes detected

### Manual Sync Trigger

You can manually trigger a schema sync:

1. Go to **Actions** tab in GitHub
2. Select **Sync Fineract API Schemas** workflow
3. Click **Run workflow**
4. Optionally enable "Force rebuild of Fineract"

## Manual Schema Sync

### Prerequisites

- Apache Fineract source cloned locally
- Java 17 installed
- Gradle wrapper available

### Using the Sync Script

We provide a convenience script for manual schema sync:

```bash
cd operations/fineract-data

# Basic usage (uses existing build if available)
./scripts/sync-fineract-schemas.sh

# Force rebuild of Fineract
./scripts/sync-fineract-schemas.sh --build

# Set custom Fineract directory
FINERACT_DIR=/path/to/fineract ./scripts/sync-fineract-schemas.sh
```

### Manual Process

If you prefer to sync manually:

```bash
# 1. Build Fineract
cd /path/to/fineract
./gradlew :fineract-provider:build -x test -x integrationTest

# 2. Copy schema
cp fineract-provider/build/classes/java/main/static/fineract.json \
   /path/to/fineract-gitops/operations/fineract-data/schemas/fineract-openapi.json

# 3. Check for changes
cd /path/to/fineract-gitops
git diff operations/fineract-data/schemas/fineract-openapi.json
```

## Reviewing Schema Changes

When a schema sync PR is created (automatically or manually), follow this review process:

### 1. Review PR Description

The automated PR includes:
- Fineract commit SHA, date, and latest change message
- Pre-filled review checklist
- Next steps guidance

### 2. Check for Breaking Changes

Look for these types of breaking changes:

**Removed Endpoints**:
```bash
# Search for endpoints used by loaders
grep -r "self.get\|self.post\|self.put\|self.delete" scripts/loaders/
```

**Changed Request Schemas**:
- Review endpoints we use for creating/updating entities
- Check if required fields changed
- Verify enum values are still valid

**Changed Response Schemas**:
- Check fields we rely on in loader responses
- Verify ID fields are still present
- Check for renamed fields

### 3. Test Compatibility Locally

If you suspect compatibility issues:

```bash
# 1. Checkout the PR branch
git fetch origin
git checkout sync/fineract-schemas-XXX

# 2. Run loaders against dev environment
cd operations/fineract-data
export FINERACT_URL=https://fineract-dev.example.com
export KEYCLOAK_URL=https://keycloak-dev.example.com

# Test individual loaders
./scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/chart-of-accounts \
  --fineract-url $FINERACT_URL

# Or run full system-foundation job
kubectl apply -k kubernetes/overlays/dev/
kubectl logs -f job/system-foundation-loader
```

### 4. Identify Required Updates

If breaking changes are found, create follow-up issues for:

**Loader Updates**:
- Update field mappings
- Handle new required fields
- Update enum mappings

**YAML Data Updates**:
- Add new required fields
- Update deprecated field names
- Adjust enum values

**Documentation Updates**:
- Update YAML schema examples
- Document new/changed fields
- Add migration guides

### 5. Merge Decision

**Merge if**:
- No breaking changes detected
- Changes are additive only (new endpoints, optional fields)
- All compatibility issues are addressed

**Hold/Close if**:
- Breaking changes require loader updates first
- Need to coordinate with Fineract upgrade
- Incompatible with current deployment

## Schema Structure

The OpenAPI schema includes:

### Endpoints
All Fineract REST API endpoints with:
- HTTP methods (GET, POST, PUT, DELETE)
- Request parameters
- Request body schemas
- Response schemas
- Authentication requirements

### Data Models
Entity schemas for:
- GLAccount (Chart of Accounts)
- LoanProduct
- SavingsProduct
- Client
- Office
- Staff
- Charge
- TaxGroup
- And many more...

### Enumerations
Valid values for:
- Account types
- Frequency types
- Interest calculation methods
- Amortization types
- Transaction types

## Future Plans

### Phase 2: Local Schema Validation

Once we complete Phase 3, we'll implement Phase 2 to add local validation:

**Goals**:
- Validate YAML files against OpenAPI schema before deployment
- Catch schema violations early in development
- Provide clear error messages for invalid data

**Approach** (TBD):
- Option 1: Use OpenAPI validation library (openapi-core, openapi-spec-validator)
- Option 2: Use Pydantic models generated from OpenAPI schema
- Option 3: Custom validation using schema definitions

**Benefits**:
- Fail fast on invalid data
- Better developer experience
- Reduce deployment failures
- Self-documenting YAML structure

## Troubleshooting

### Schema Sync Fails to Build Fineract

**Problem**: GitHub Action fails during Fineract build

**Solutions**:
1. Check Java version (must be Java 17)
2. Check Gradle version compatibility
3. Review Fineract build logs for errors
4. Check if Fineract build requirements changed

### Schema Changes Not Detected

**Problem**: PR not created despite known changes

**Solutions**:
1. Verify OpenAPI spec was actually copied
2. Check file permissions
3. Review git diff output in workflow logs
4. Ensure schema file path is correct

### Loader Compatibility Issues

**Problem**: Loaders fail after schema update

**Solutions**:
1. Review error messages for specific field/endpoint issues
2. Compare old vs new schema for the affected endpoint
3. Check Fineract release notes for migration guide
4. Test against Fineract API directly to verify behavior

### Merge Conflicts

**Problem**: Schema sync PR has merge conflicts

**Solutions**:
1. This should be rare (schema is auto-generated)
2. Merge main branch into sync branch
3. Re-run sync script to regenerate schema
4. Review conflicts carefully (may indicate manual edits)

## Related Documentation

- [REFACTOR_PLAN.md](../REFACTOR_PLAN.md) - Overall refactoring plan
- [README.md](../README.md) - Fineract data management overview
- [sync-fineract-schemas.sh](../scripts/sync-fineract-schemas.sh) - Manual sync script
- [.github/workflows/sync-fineract-schemas.yml](../../../.github/workflows/sync-fineract-schemas.yml) - Automated sync workflow

## Questions or Issues?

If you encounter issues with schema management:

1. Check this documentation first
2. Review existing GitHub issues
3. Check Fineract release notes and changelog
4. Create a new issue with:
   - Schema sync workflow run link
   - Error messages or logs
   - Expected vs actual behavior
