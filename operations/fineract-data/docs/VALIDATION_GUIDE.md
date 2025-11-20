# YAML Validation Guide

This guide explains how to validate your Fineract YAML data files before committing.

## Quick Start

### Validate All Data (Recommended)

Run this before every commit:

```bash
cd operations/fineract-data
./scripts/validate-all.sh
```

This validates all YAML files in all data directories.

### Validate Specific Directory

```bash
./scripts/validate_yaml_data.py data/loan-products
```

### Validate with Verbose Output

```bash
./scripts/validate-all.sh -v
```

Shows details for each file validated.

## What Gets Validated

The validation script checks:

### 1. YAML Syntax
- File can be parsed as valid YAML
- No syntax errors

### 2. Required Structure
- Has `apiVersion` field (must start with `fineract.apache.org/`)
- Has `kind` field (entity type)
- Has `metadata.name` field
- Has `spec` field with entity data

### 3. Required Fields by Entity Type

**GLAccount**:
- `name`, `glCode`, `type`, `usage`

**LoanProduct**:
- `name`, `shortName`, `currency`, `principal`, `numberOfRepayments`, `interestRate`

**SavingsProduct**:
- `name`, `shortName`, `currency`, `nominalAnnualInterestRate`

**Office**:
- `name`

**Staff**:
- `firstname`, `lastname`, `officeId`

**Role**:
- `name`, `description`

**Charge**:
- `name`, `chargeAppliesTo`, `chargeTimeType`, `chargeCalculationType`, `amount`

**TaxGroup**:
- `name`, `taxComponents`

**Client**:
- `firstname`, `lastname`, `officeId`, `activationDate`

And more...

### 4. Valid Enum Values

**Account Types** (GLAccount):
- `ASSET`, `LIABILITY`, `EQUITY`, `INCOME`, `EXPENSE`

**Usage** (GLAccount):
- `DETAIL`, `HEADER`

**Repayment Frequency** (LoanProduct):
- `DAYS`, `WEEKS`, `MONTHS`, `YEARS`

**Interest Type** (LoanProduct):
- `FLAT`, `DECLINING_BALANCE`

**Charge Applies To**:
- `LOAN`, `SAVINGS`, `CLIENT`, `SHARES`

And more...

### 5. Nested Structure Validation

For complex entities like LoanProduct, validates nested structures:
- `principal.default`, `principal.min`, `principal.max`
- `interestRate.default`, `interestRate.min`, `interestRate.max`
- `numberOfRepayments.default`, `numberOfRepayments.min`, `numberOfRepayments.max`

### 6. Reference Integrity

Checks that referenced entities make sense:
- Parent GL accounts
- Office references
- Tax component GL codes

## Example Output

### Successful Validation

```
============================================
Fineract YAML Data Validation
============================================
Validating: loan-products (5 files)
================================================================================
VALIDATION SUMMARY
================================================================================
Total files processed: 5
Valid: 5
Invalid: 0
Skipped: 0
================================================================================

✓ loan-products validated successfully

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

### Validation Errors

```
============================================
Fineract YAML Data Validation
============================================
Validating: loan-products (5 files)

Processing: standard-loan.yaml
  ❌ Missing required field in spec: principal
  ❌ Invalid enum value for repaymentFrequency: 'Monthly' (must be: DAYS, WEEKS, MONTHS, YEARS)

Processing: micro-loan.yaml
  ❌ YAML syntax error: mapping values are not allowed here

================================================================================
VALIDATION SUMMARY
================================================================================
Total files processed: 5
Valid: 3
Invalid: 2
Skipped: 0
================================================================================

Validation failed with 2 errors

✗ loan-products validation failed

============================================
VALIDATION SUMMARY
============================================
Total directories:  12
Valid directories:  11
Failed directories: 1
============================================

❌ Validation failed
Please fix the errors above before committing
```

## Common Errors and Fixes

### Missing Required Fields

**Error:**
```
❌ Missing required field in spec: principal
```

**Fix:**
Add the missing field to your YAML:
```yaml
spec:
  name: "Standard Loan"
  principal:        # ← Add this
    default: 10000
    min: 1000
    max: 50000
```

### Invalid Enum Values

**Error:**
```
❌ Invalid enum value for repaymentFrequency: 'Monthly' (must be: DAYS, WEEKS, MONTHS, YEARS)
```

**Fix:**
Use the correct enum value:
```yaml
spec:
  repaymentFrequency: MONTHS  # ← Not "Monthly"
```

### YAML Syntax Errors

**Error:**
```
❌ YAML syntax error: mapping values are not allowed here
```

**Fix:**
Common causes:
- Missing colon after key
- Incorrect indentation
- Special characters not quoted
- Tab characters (use spaces)

Use a YAML validator or IDE with YAML support.

### Missing Structure

**Error:**
```
❌ Missing 'spec' field
```

**Fix:**
Ensure your YAML has the correct top-level structure:
```yaml
apiVersion: fineract.apache.org/v1
kind: LoanProduct
metadata:
  name: standard-loan
spec:        # ← Must have this
  # ... your configuration
```

## Integration with Git

### Pre-commit Hook (Optional)

You can add validation to run automatically before commits:

1. Install pre-commit:
```bash
pip install pre-commit
```

2. The `.pre-commit-config.yaml` is already configured

3. Install the hook:
```bash
pre-commit install
```

4. Now validation runs automatically before each commit

To bypass (not recommended):
```bash
git commit --no-verify
```

## CI/CD Integration

Validation runs automatically in GitHub Actions on:
- Pull requests
- Pushes to main/develop/deploy-key branches

The workflow file: `.github/workflows/data-quality-tests.yml`

PRs with invalid YAML will be blocked from merging.

## Validation Script Details

### validate_yaml_data.py

Main validation script that checks individual directories.

**Usage:**
```bash
./scripts/validate_yaml_data.py <directory> [OPTIONS]

Options:
  -v, --verbose     Show details for each file
  --kind KIND       Only validate specific entity type
```

**Examples:**
```bash
# Validate loan products
./scripts/validate_yaml_data.py data/loan-products

# Validate with verbose output
./scripts/validate_yaml_data.py data/chart-of-accounts -v

# Validate only GLAccount entities
./scripts/validate_yaml_data.py data/chart-of-accounts --kind GLAccount
```

### validate-all.sh

Convenience wrapper that validates all data directories.

**Usage:**
```bash
./scripts/validate-all.sh [OPTIONS]

Options:
  -v, --verbose     Show details for all files
  -h, --help        Show help message
```

## Best Practices

### 1. Validate Before Committing
Always run `./scripts/validate-all.sh` before committing YAML changes.

### 2. Fix Errors Immediately
Don't commit with validation errors - they will fail in CI/CD anyway.

### 3. Use Verbose Mode for Debugging
When you have errors, use `-v` flag to see more details.

### 4. Validate After Editing
If you edit multiple files, validate after each batch of changes.

### 5. Check CI/CD Results
Even if local validation passes, check the GitHub Actions results.

## Extending Validation

To add validation for new entity types:

1. Edit `scripts/validate_yaml_data.py`

2. Add required fields to `REQUIRED_FIELDS` dict:
```python
REQUIRED_FIELDS = {
    'MyNewEntity': ['field1', 'field2', 'field3'],
    # ...
}
```

3. Add enum validation if needed in `validate_enum_values()`

4. Add nested structure validation if needed in `validate_nested_structures()`

5. Test your changes:
```bash
./scripts/validate_yaml_data.py data/my-new-entities -v
```

## Troubleshooting

### Script Not Executable

```bash
chmod +x scripts/validate-all.sh
chmod +x scripts/validate_yaml_data.py
```

### Python Not Found

Ensure Python 3 is installed:
```bash
python3 --version
```

### YAML Library Missing

```bash
pip install pyyaml
```

### Permission Denied

Run with appropriate permissions or check file ownership.

## Related Documentation

- [REFACTOR_PLAN.md](../REFACTOR_PLAN.md) - Overall refactoring plan
- [SCHEMA_MANAGEMENT.md](SCHEMA_MANAGEMENT.md) - API schema management
- [README.md](../README.md) - Main documentation
- [Test Data Quality](../tests/test_data_quality.py) - Automated tests

## Questions or Issues?

If validation seems incorrect or you need to add new validation rules:

1. Check existing YAML files for examples
2. Review Fineract API documentation
3. Check the OpenAPI schema: `schemas/fineract-openapi.json`
4. Create an issue with validation output and expected behavior
