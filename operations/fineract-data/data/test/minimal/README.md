# Minimal Test Data

This directory contains minimal test data for quick validation of data loaders.

## Purpose

- **Quick Testing**: Validate loader logic without loading large datasets
- **CI/CD**: Fast automated testing in pipelines
- **Development**: Rapid iteration during loader development

## Structure

Each subdirectory contains 2-3 minimal YAML files for testing:

```
minimal/
├── offices/
│   └── test-office.yaml (1 test office)
├── staff/
│   └── test-staff.yaml (1 test staff member)
├── products/
│   ├── test-loan-product.yaml (1 loan product)
│   └── test-savings-product.yaml (1 savings product)
└── accounting/
    └── test-gl-account.yaml (3 GL accounts)
```

## Usage

```bash
# Test with minimal data
python3 scripts/loaders/offices.py \
  --yaml-dir data/test/minimal/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant test

# Dry-run test
python3 scripts/loaders/offices.py \
  --yaml-dir data/test/minimal/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant test \
  --dry-run
```

## Creating Test Data

When creating test data:
1. Use prefix `test-` in metadata names
2. Keep minimal required fields only
3. Use simple, obvious values
4. Document any special requirements

## Cleanup

Test data can be deleted via Fineract UI or API after testing.
