# Testing Guide - Fineract Data Management

Comprehensive guide to test all the refactoring work (Phases 0-4).

## Table of Contents

1. [Quick Test (5 minutes)](#quick-test-5-minutes)
2. [Phase 0: Critical Fixes](#phase-0-critical-fixes)
3. [Phase 1: Full Idempotency](#phase-1-full-idempotency)
4. [Phase 2: Local Validation](#phase-2-local-validation)
5. [Phase 3: Schema Sync](#phase-3-schema-sync)
6. [Phase 4: Error Handling](#phase-4-error-handling)
7. [Integration Testing](#integration-testing)
8. [CI/CD Testing](#cicd-testing)

---

## Quick Test (5 minutes)

Run these commands to verify everything works:

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# 1. Test YAML validation (Phase 2)
./scripts/validate-all.sh

# 2. Test data quality tests (Phase 0)
cd tests
pip install -r requirements-test.txt
pytest -v

# 3. Test schema sync script (Phase 3)
cd ..
./scripts/sync-fineract-schemas.sh
```

**Expected Results:**
- ✅ All YAML files validate successfully
- ✅ All data quality tests pass (20+ tests)
- ✅ Schema syncs without errors

---

## Phase 0: Critical Fixes

### Test 1: Data Quality Tests

**What it tests:** Reference resolution, data integrity, YAML structure

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data/tests

# Install dependencies
pip install -r requirements-test.txt

# Run all tests
pytest -v

# Run specific test categories
pytest -v -k "office"      # Office reference tests
pytest -v -k "staff"       # Staff reference tests
pytest -v -k "gl"          # GL account tests
pytest -v -k "permission"  # Role permission tests
```

**Expected Output:**
```
==================== test session starts ====================
collected 24 items

test_data_quality.py::TestOfficeReferences::test_all_offices_have_required_fields PASSED
test_data_quality.py::TestOfficeReferences::test_office_parent_references_exist PASSED
test_data_quality.py::TestOfficeReferences::test_no_circular_office_hierarchy PASSED
test_data_quality.py::TestStaffReferences::test_all_staff_have_required_fields PASSED
test_data_quality.py::TestStaffReferences::test_staff_office_references_valid PASSED
...
==================== 24 passed in 2.34s ====================
```

**What to check:**
- ✅ All tests pass
- ✅ No missing office references
- ✅ Parent office references resolve correctly
- ✅ Staff office references are valid
- ✅ GL account parent references exist

### Test 2: Strict Reference Resolution

**What it tests:** Loader behavior when references are missing

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Test with strict mode (default - should fail on bad reference)
export STRICT_REFERENCE_RESOLUTION=true
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/chart-of-accounts \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default

# Test with lenient mode (should skip bad references)
export STRICT_REFERENCE_RESOLUTION=false
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/chart-of-accounts \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default
```

**Expected Behavior:**
- Strict mode: Raises `ValueError` if parent GL code doesn't exist
- Lenient mode: Logs warning and continues
- Clear error messages with troubleshooting steps

---

## Phase 1: Full Idempotency

### Test 3: Create-Update-Skip Pattern

**What it tests:** Loaders can create, update, and skip entities correctly

**Prerequisites:** Running Fineract instance (local or dev environment)

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Setup environment
export FINERACT_URL="http://localhost:8443/fineract-provider/api/v1"
export FINERACT_CLIENT_ID="your-client-id"
export FINERACT_CLIENT_SECRET="your-client-secret"
export FINERACT_TOKEN_URL="http://localhost:8443/fineract-provider/oauth/token"

# Test 1: First run (CREATE)
echo "=== Test 1: First run (should CREATE) ==="
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/chart-of-accounts \
  --fineract-url $FINERACT_URL \
  --tenant default
```

**Expected Output (First Run):**
```
================================================================================
LOADING SUMMARY
================================================================================
Total Created: 50
Total Updated: 0
Total Skipped: 0
Total Failed: 0
Success Rate: 100.0%
```

```bash
# Test 2: Second run without changes (SKIP)
echo "=== Test 2: Second run (should SKIP) ==="
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/chart-of-accounts \
  --fineract-url $FINERACT_URL \
  --tenant default
```

**Expected Output (Second Run):**
```
================================================================================
LOADING SUMMARY
================================================================================
Total Created: 0
Total Updated: 0
Total Skipped: 50
Total Failed: 0
Success Rate: 100.0%
```

```bash
# Test 3: Modify a YAML file and run again (UPDATE)
echo "=== Test 3: Modify and run (should UPDATE) ==="

# Modify a GL account (change description)
sed -i.bak 's/description: "Cash"/description: "Cash Account - Updated"/' \
  data/chart-of-accounts/cash-account.yaml

# Run loader
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/chart-of-accounts \
  --fineract-url $FINERACT_URL \
  --tenant default

# Restore original
mv data/chart-of-accounts/cash-account.yaml.bak \
   data/chart-of-accounts/cash-account.yaml
```

**Expected Output (Third Run):**
```
================================================================================
LOADING SUMMARY
================================================================================
Total Created: 0
Total Updated: 1
Total Skipped: 49
Total Failed: 0
Success Rate: 100.0%
```

**What to verify:**
- ✅ First run creates all entities
- ✅ Second run skips all (no changes)
- ✅ Modified entity gets updated (not recreated)
- ✅ No duplicate entities in Fineract

### Test 4: Test All Idempotent Loaders

Test each loader that was updated for idempotency:

```bash
# GL Accounts (Phase 1)
python3 scripts/loaders/chart_of_accounts.py --yaml-dir data/chart-of-accounts ...

# Tax Groups (Phase 1)
python3 scripts/loaders/tax_groups.py --yaml-dir data/tax-groups ...

# Loan Products (already had it)
python3 scripts/loaders/loan_products.py --yaml-dir data/loan-products ...

# Savings Products (already had it)
python3 scripts/loaders/savings_products.py --yaml-dir data/savings-products ...

# Charges (already had it)
python3 scripts/loaders/charges.py --yaml-dir data/charges ...
```

---

## Phase 2: Local Validation

### Test 5: YAML Validation - Success Case

**What it tests:** Validation script correctly validates good YAML files

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Validate all data
./scripts/validate-all.sh

# Validate specific directory
./scripts/validate_yaml_data.py data/offices

# Validate with verbose output
./scripts/validate-all.sh -v
```

**Expected Output:**
```
============================================
Fineract YAML Data Validation
============================================
Validating: offices (4 files)
================================================================================
VALIDATION SUMMARY
================================================================================
Total files processed: 4
Valid: 4
Invalid: 0
Skipped: 0
================================================================================

✓ offices validated successfully

============================================
VALIDATION SUMMARY
============================================
Total directories:  12
Valid directories:  12
Failed directories: 0
============================================

✅ All validations passed
Your YAML files are ready to commit!
```

### Test 6: YAML Validation - Error Detection

**What it tests:** Validation correctly detects errors

```bash
# Create a test file with errors
cat > /tmp/test-invalid.yaml <<EOF
apiVersion: fineract.apache.org/v1
kind: GLAccount
metadata:
  name: test-invalid
spec:
  # Missing required field: glCode
  name: "Test Account"
  type: INVALID_TYPE  # Invalid enum value
  usage: DETAIL
EOF

# Copy to test location
mkdir -p data/test-validation
cp /tmp/test-invalid.yaml data/test-validation/

# Validate (should fail)
./scripts/validate_yaml_data.py data/test-validation

# Cleanup
rm -rf data/test-validation
```

**Expected Output:**
```
Processing: test-invalid.yaml
  ❌ Missing required field in spec: glCode
  ❌ Invalid enum value for type: 'INVALID_TYPE' (must be: ASSET, LIABILITY, EQUITY, INCOME, EXPENSE)

================================================================================
VALIDATION SUMMARY
================================================================================
Total files processed: 1
Valid: 0
Invalid: 1
Skipped: 0
================================================================================

Validation failed with 1 errors
```

**What to check:**
- ✅ Detects missing required fields
- ✅ Detects invalid enum values
- ✅ Clear error messages
- ✅ Exit code 1 on failure

---

## Phase 3: Schema Sync

### Test 7: Manual Schema Sync

**What it tests:** Schema extraction from Fineract source

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Test with existing schema
./scripts/sync-fineract-schemas.sh

# Test with force rebuild
./scripts/sync-fineract-schemas.sh --build
```

**Expected Output:**
```
============================================
Fineract Schema Sync
============================================

✓ Fineract directory: /Users/guymoyo/dev/fineract
✓ OpenAPI spec already exists
✓ OpenAPI spec found: /Users/guymoyo/dev/fineract/fineract-provider/build/classes/java/main/static/fineract.json
   Size: 1.2M
   Modified: 2025-11-20 10:30:45

📋 Copying OpenAPI spec...
✓ Copied to: operations/fineract-data/schemas/fineract-openapi.json

✓ No schema changes detected
  OpenAPI spec is up to date

============================================
Schema sync completed successfully!
============================================
```

**What to check:**
- ✅ Finds Fineract directory
- ✅ Locates OpenAPI spec
- ✅ Copies spec successfully
- ✅ Detects changes (if any)
- ✅ Clear status messages

### Test 8: GitHub Action (Manual Trigger)

**What it tests:** Automated schema sync workflow

**Prerequisites:** Code pushed to GitHub

1. Go to GitHub Actions tab
2. Select "Sync Fineract API Schemas" workflow
3. Click "Run workflow"
4. Select branch: `deploy-key`
5. Click "Run workflow" button

**Expected Behavior:**
- ✅ Workflow runs successfully
- ✅ Builds Fineract
- ✅ Extracts OpenAPI spec
- ✅ Creates PR if changes detected (or reports no changes)

---

## Phase 4: Error Handling

### Test 9: Strict Permission Validation

**What it tests:** Roles loader rejects invalid permission codes

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Create test role with invalid permission
cat > /tmp/test-role.yaml <<EOF
apiVersion: fineract.apache.org/v1
kind: Role
metadata:
  name: test-role
spec:
  name: "Test Role"
  description: "Test role with invalid permission"
  permissions:
    - code: "READ_CLIENT"      # Valid
    - code: "INVALID_CODE"     # Invalid - should fail
EOF

mkdir -p data/test-roles
cp /tmp/test-role.yaml data/test-roles/

# Run loader (should fail with clear error)
python3 scripts/loaders/roles.py \
  --yaml-dir data/test-roles \
  --fineract-url $FINERACT_URL \
  --tenant default

# Cleanup
rm -rf data/test-roles
```

**Expected Output:**
```
Processing: test-role.yaml
  ✗ Invalid permission codes in role 'Test Role': ['INVALID_CODE']
  Available permissions (first 20): ['READ_CLIENT', 'CREATE_CLIENT', ...]
  Total available permissions: 487

ValueError: Invalid permission codes in role 'Test Role': ['INVALID_CODE']
Please check permission codes in YAML file.
Total available permissions: 487
Sample permissions: READ_CLIENT, CREATE_CLIENT, ...
```

**What to check:**
- ✅ Detects invalid permission code
- ✅ Shows sample of valid permissions
- ✅ Shows total count
- ✅ Clear error message with fix suggestions

### Test 10: Enhanced Error Reporting

**What it tests:** Detailed error categorization and suggestions

```bash
# Create multiple files with different error types
mkdir -p data/test-errors

# Missing required field
cat > data/test-errors/error1.yaml <<EOF
apiVersion: fineract.apache.org/v1
kind: GLAccount
metadata:
  name: error1
spec:
  name: "Account 1"
  # Missing: glCode
EOF

# Invalid enum
cat > data/test-errors/error2.yaml <<EOF
apiVersion: fineract.apache.org/v1
kind: GLAccount
metadata:
  name: error2
spec:
  name: "Account 2"
  glCode: "1000"
  type: INVALID_TYPE
  usage: DETAIL
EOF

# Run loader (should fail with grouped errors)
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/test-errors \
  --fineract-url $FINERACT_URL \
  --tenant default

# Cleanup
rm -rf data/test-errors
```

**Expected Output:**
```
================================================================================
LOADING SUMMARY
================================================================================
Total Created: 0
Total Updated: 0
Total Skipped: 0
Total Failed: 2
Success Rate: 0.0%

Failed Entities:
  ✗ error1.yaml
  ✗ error2.yaml

================================================================================
DETAILED ERROR REPORT
================================================================================

📋 Validation Errors (2)

  Entity: error1.yaml
  Error: Missing required fields in GL account YAML
    missing_fields: ['glCode']
    file: data/test-errors/error1.yaml

  Entity: Account 2
  Error: Failed to create GL account via API
    gl_code: 1000
    endpoint: /glaccounts
    parent_gl_code: none

================================================================================
SUGGESTED ACTIONS
================================================================================
• Validation Errors: Review YAML structure and field values
• API Errors: Check Fineract API documentation and field requirements
================================================================================
```

**What to check:**
- ✅ Errors grouped by category
- ✅ Detailed context for each error
- ✅ Actionable suggestions
- ✅ Clear formatting

### Test 11: Pre-flight Validation

**What it tests:** Configuration checks before processing

```bash
# Test with invalid directory
python3 scripts/loaders/account_number_formats.py \
  --yaml-dir /non/existent/path \
  --fineract-url $FINERACT_URL \
  --tenant default

# Test with wrong Fineract URL
python3 scripts/loaders/account_number_formats.py \
  --yaml-dir data/account-number-formats \
  --fineract-url http://wrong-url:8443/api/v1 \
  --tenant default

# Test with invalid tenant
python3 scripts/loaders/account_number_formats.py \
  --yaml-dir data/account-number-formats \
  --fineract-url $FINERACT_URL \
  --tenant invalid_tenant
```

**Expected Errors:**
```
# Invalid directory:
ValueError: YAML directory not found: /non/existent/path
Please ensure the directory exists and is accessible.

# Wrong URL:
ValueError: Cannot connect to Fineract API: http://wrong-url:8443/api/v1
Error: [Errno 8] nodename nor servname provided, or not known
Please check:
  1. Fineract URL is correct
  2. Fineract is running and accessible
  3. Network connectivity
  4. Firewall rules

# Invalid tenant:
ValueError: Invalid tenant: 'invalid_tenant'
Please check tenant configuration in Fineract.
```

---

## Integration Testing

### Test 12: Full Workflow Test

**What it tests:** Complete end-to-end workflow

```bash
#!/bin/bash
# Full workflow test script

cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

echo "Step 1: Validate all YAML files"
./scripts/validate-all.sh || exit 1

echo "Step 2: Run data quality tests"
cd tests && pytest -v || exit 1
cd ..

echo "Step 3: Load system foundation (Wave 1)"
python3 scripts/loaders/offices.py --yaml-dir data/offices ...
python3 scripts/loaders/currencies.py --yaml-dir data/currencies ...
python3 scripts/loaders/working_days.py --yaml-dir data/working-days ...

echo "Step 4: Load accounting (Wave 2)"
python3 scripts/loaders/chart_of_accounts.py --yaml-dir data/chart-of-accounts ...
python3 scripts/loaders/account_number_formats.py --yaml-dir data/account-number-formats ...

echo "Step 5: Load products (Wave 3-4)"
python3 scripts/loaders/loan_products.py --yaml-dir data/loan-products ...
python3 scripts/loaders/savings_products.py --yaml-dir data/savings-products ...

echo "Step 6: Verify idempotency - run again (should skip all)"
python3 scripts/loaders/chart_of_accounts.py --yaml-dir data/chart-of-accounts ...

echo "✅ Full workflow test completed successfully!"
```

### Test 13: GitOps Workflow (with ArgoCD)

**What it tests:** Actual deployment via ArgoCD

**Prerequisites:**
- Code pushed to repository
- ArgoCD configured
- Kubernetes cluster access

```bash
# 1. Make a change to a YAML file
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data
vim data/loan-products/standard-loan.yaml
# Change: principal.default: 10000 → 15000

# 2. Validate locally
./scripts/validate-all.sh

# 3. Commit and push
git add data/loan-products/standard-loan.yaml
git commit -m "test: update standard loan principal"
git push origin deploy-key

# 4. Sync ArgoCD application
argocd app sync fineract-data

# 5. Watch job execution
kubectl logs -f job/system-foundation-loader -n fineract

# 6. Verify update (not create)
# Should see: "↻ Updating: Standard Loan"
# Should NOT see: "✓ Created: Standard Loan"

# 7. Verify in Fineract UI
# Go to: Admin → Products → Loan Products → Standard Loan
# Principal should be 15000
```

---

## CI/CD Testing

### Test 14: GitHub Actions - Data Quality Tests

**What it tests:** Automated tests run on PR

1. Create a branch and make changes:
```bash
git checkout -b test/validation
# Make a YAML change
git add .
git commit -m "test: trigger CI"
git push origin test/validation
```

2. Create Pull Request on GitHub

3. Check Actions tab - should see:
   - ✅ "Fineract Data Quality Tests" workflow runs
   - ✅ All pytest tests pass
   - ✅ Green checkmark on PR

4. Merge PR (or close for test)

### Test 15: GitHub Actions - Schema Sync (Manual)

**What it tests:** Weekly schema sync automation

1. Go to Actions → "Sync Fineract API Schemas"
2. Click "Run workflow"
3. Watch execution
4. If schema changed:
   - ✅ PR created automatically
   - ✅ PR has review checklist
   - ✅ PR includes Fineract version info

---

## Testing Checklist

Use this checklist to verify all phases:

### Phase 0: Critical Fixes
- [ ] Data quality tests pass (pytest)
- [ ] Office parent references work
- [ ] Staff office references work
- [ ] GL parent references work
- [ ] Strict mode fails on bad references
- [ ] Lenient mode skips bad references

### Phase 1: Full Idempotency
- [ ] First run creates entities
- [ ] Second run skips all (no changes)
- [ ] Modified entity gets updated
- [ ] No duplicate entities
- [ ] Works for: GL accounts, tax groups, loan products, savings products, charges

### Phase 2: Local Validation
- [ ] validate-all.sh works
- [ ] Valid YAML passes
- [ ] Invalid YAML detected
- [ ] Clear error messages
- [ ] Exit codes correct

### Phase 3: Schema Sync
- [ ] Manual sync script works
- [ ] Schema extracted from Fineract
- [ ] Change detection works
- [ ] GitHub Action can be triggered
- [ ] PR created on schema change

### Phase 4: Error Handling
- [ ] Invalid permission codes rejected
- [ ] Error categorization works
- [ ] Detailed error context provided
- [ ] Actionable suggestions shown
- [ ] Pre-flight validation catches config issues

### Integration
- [ ] Full workflow runs end-to-end
- [ ] GitOps workflow works with ArgoCD
- [ ] CI/CD tests run on PR
- [ ] Schema sync automation works

---

## Troubleshooting

### Tests Failing?

**Data quality tests fail:**
```bash
# Update test data or fix references
pytest -v --tb=short  # See short traceback
```

**Validation fails:**
```bash
# Check specific file
./scripts/validate_yaml_data.py data/problematic-dir -v
```

**Loader fails:**
```bash
# Check Fineract is running
curl http://localhost:8443/fineract-provider/api/v1/offices

# Check credentials
echo $FINERACT_CLIENT_ID
echo $FINERACT_CLIENT_SECRET
```

**Schema sync fails:**
```bash
# Verify Fineract directory
ls /Users/guymoyo/dev/fineract

# Try force rebuild
./scripts/sync-fineract-schemas.sh --build
```

---

## Next Steps

After all tests pass:

1. **Push to remote:**
   ```bash
   git push origin deploy-key
   ```

2. **Create Pull Request** for review

3. **Deploy to dev environment** via ArgoCD

4. **Monitor job execution** in Kubernetes

5. **Verify in Fineract UI** that data loaded correctly

6. **Document any issues** found during testing

---

## Questions?

If tests fail or you encounter issues:

1. Check this guide's troubleshooting section
2. Review error messages (they're detailed now!)
3. Check logs: `kubectl logs -f job/<job-name>`
4. Review documentation: VALIDATION_GUIDE.md, SCHEMA_MANAGEMENT.md
5. Create an issue with test output and environment details
