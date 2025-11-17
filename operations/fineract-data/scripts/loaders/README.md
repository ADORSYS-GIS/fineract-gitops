# Fineract Data Loaders

Python-based loaders for importing YAML configuration data into Apache Fineract.

## Overview

This directory contains entity-specific loaders that read YAML files and create/update entities in Fineract via the REST API. All loaders inherit from `BaseLoader` which provides:

- OAuth2 authentication
- HTTP request handling (GET, POST, PUT)
- YAML parsing and validation
- Reference data caching
- Error handling and logging
- Summary reporting

## Quick Start

### Prerequisites

```bash
# Install Python dependencies
pip install -r requirements.txt

# Set environment variables
export FINERACT_USER="mifos"
export FINERACT_PASS="password"
```

### Run a Single Loader

```bash
python3 chart_of_accounts.py \
  --yaml-dir ../../data/dev/accounting/chart-of-accounts \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

### Run All Loaders (Recommended)

```bash
# Test locally
cd ../
./test_loaders_locally.sh

# Or specify custom URL
./test_loaders_locally.sh --url http://localhost:8443/fineract-provider/api/v1
```

## Implemented Loaders

### Production-Ready (✅)

| Loader | YAML Kind | API Endpoint | Operation | Dependencies |
|--------|-----------|--------------|-----------|--------------|
| `chart_of_accounts.py` | GLAccount | `/glaccounts` | CREATE | None |
| `tax_groups.py` | TaxGroup | `/taxes/group` | CREATE | GL Accounts |
| `floating_rates.py` | FloatingRate | `/floatingrates` | CREATE | None |
| `savings_product_accounting.py` | SavingsProductAccounting | `/savingsproducts/{id}` | UPDATE | GL Accounts, Products |
| `financial_activity_mappings.py` | FinancialActivityMapping | `/financialactivityaccounts` | CREATE | GL Accounts |

### Stub Templates (⏳)

43 additional loaders are available as stub templates in this directory. They need implementation following the patterns above.

## Loader Details

### 1. Chart of Accounts (`chart_of_accounts.py`)

**Purpose**: Load the General Ledger chart of accounts

**YAML Structure**:
```yaml
apiVersion: fineract.apache.org/v1
kind: GLAccount
metadata:
  name: cash-on-hand
spec:
  name: Cash on Hand
  glCode: '42'
  type: Asset              # Asset, Liability, Equity, Income, Expense
  usage: Detail            # Detail or Header
  manualEntriesAllowed: true
  parentGLCode: '40'       # Optional: for hierarchical accounts
  description: Physical cash
```

**Features**:
- Multi-pass loading for hierarchical relationships
- Automatically resolves parent accounts
- Maps account types to numeric IDs
- Validates GL codes for uniqueness

**Usage**:
```bash
python3 chart_of_accounts.py \
  --yaml-dir ../../data/dev/accounting/chart-of-accounts \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

---

### 2. Tax Groups (`tax_groups.py`)

**Purpose**: Load tax groups with tax components

**YAML Structure**:
```yaml
apiVersion: fineract.apache.org/v1
kind: TaxGroup
metadata:
  name: savings-interest-tax
spec:
  name: Savings Interest Tax
  taxComponents:
    - name: Withholding Tax on Interest
      taxType: Savings Interest
      percentage: 15.0
      startDate: '2024-01-01'
      creditAccountType: Liability
      creditGLCode: '141'
      creditGLName: Tax Payable - WHT
```

**Features**:
- Processes multiple tax components per group
- Resolves GL accounts for credit mappings
- Maps account types to numeric IDs
- Validates percentages and dates

**Usage**:
```bash
python3 tax_groups.py \
  --yaml-dir ../../data/dev/accounting/tax-groups \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

---

### 3. Floating Rates (`floating_rates.py`)

**Purpose**: Load floating interest rates with rate periods

**YAML Structure**:
```yaml
apiVersion: fineract.apache.org/v1
kind: FloatingRate
metadata:
  name: beac-base-rate
spec:
  name: BEAC Base Rate
  description: Central African Bank reference rate
  isBaseLendingRate: true
  isActive: true
  ratePeriods:
    - fromDate: '2024-01-01'
      interestRate: 3.5
```

**Features**:
- Supports multiple rate periods
- Handles base lending rates
- Tracks active/inactive status
- Date formatting and validation

**Usage**:
```bash
python3 floating_rates.py \
  --yaml-dir ../../data/dev/floating-rates \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

---

### 4. Savings Product Accounting (`savings_product_accounting.py`)

**Purpose**: Update existing savings products with GL account mappings

**YAML Structure**:
```yaml
apiVersion: fineract.apache.org/v1
kind: SavingsProductAccounting
metadata:
  name: mgrp
spec:
  productName: MGRP
  accountMappings:
    - mappingType: Savings Reference
      glAccountCode: '42'
      glAccountName: Cash on Hand
    - mappingType: Savings Control
      glAccountCode: '63'
      glAccountName: Mandatory Group Savings
```

**Features**:
- **UPDATES** existing products (not create)
- Maps 11+ account mapping types
- Resolves products by name
- Validates all GL accounts exist
- Requires products to exist first

**Important**: Run this AFTER products are created via other means.

**Usage**:
```bash
python3 savings_product_accounting.py \
  --yaml-dir ../../data/dev/accounting/savings-product-accounting \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

---

### 5. Financial Activity Mappings (`financial_activity_mappings.py`)

**Purpose**: Map financial activities to GL accounts

**YAML Structure**:
```yaml
apiVersion: fineract.apache.org/v1
kind: FinancialActivityMapping
metadata:
  name: fund-source
spec:
  financialActivityName: Fund Source
  glAccountCode: '42'
  glAccountName: Cash on Hand
  description: Default fund source
```

**Features**:
- Resolves financial activity names to IDs
- Resolves GL codes to account IDs
- Prevents duplicate mappings
- Simple one-to-one mapping

**Usage**:
```bash
python3 financial_activity_mappings.py \
  --yaml-dir ../../data/dev/accounting/financial-activity-mappings \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

---

## Base Loader (`base_loader.py`)

All loaders inherit from `BaseLoader` which provides:

### Authentication
- OAuth2 client credentials flow
- Automatic token refresh
- Multi-tenancy support via `Fineract-Platform-TenantId` header

### HTTP Methods
```python
self.get(endpoint)           # GET request
self.post(endpoint, payload) # POST request
self.put(endpoint, payload)  # PUT request
```

### Reference Resolution
```python
self._cache_reference_data()                    # Pre-load lookup data
self._resolve_gl_account(code_or_name)          # GL code/name → ID
self._resolve_office(name_or_external_id)       # Office → ID
self._resolve_product(name, type='savings')     # Product → ID
self._resolve_financial_activity(name)          # Activity → ID
self._format_date(date_str, format='yyyy-MM-dd') # Date formatting
```

### Entity Management
```python
self.entity_exists(endpoint, name)  # Check if entity exists by name
self.load_yaml(file_path)           # Load and parse YAML file
```

### Reporting
```python
self.loaded_entities   # Dict of successfully loaded entities
self.failed_entities   # List of failed entity names
self.get_summary()     # Get summary statistics
self.print_summary()   # Print formatted summary
```

## Loading Order

Due to dependencies, loaders should run in this order:

```
1. chart_of_accounts          (no dependencies)
   ↓
2. tax_groups                 (requires GL accounts)
   ↓
3. floating_rates             (no dependencies)
   ↓
4. [CREATE PRODUCTS]          (via separate mechanism)
   ↓
5. savings_product_accounting (requires GL accounts + products)
   ↓
6. financial_activity_mappings (requires GL accounts)
```

## Environment Variables

```bash
# Required
FINERACT_USER     # Fineract username (default: mifos)
FINERACT_PASS     # Fineract password (default: password)

# Optional
FINERACT_URL      # Override Fineract API URL
TENANT            # Override tenant ID
```

## Error Handling

All loaders:
- Log errors with context
- Continue processing after failures
- Provide summary of successes/failures
- Exit with code 1 if any failures occur
- Exit with code 0 if all successful

Example output:
```
================================================================================
SUMMARY
================================================================================
Total entities processed: 35
Successfully loaded: 33
Failed: 2
Skipped (already exist): 5
================================================================================
```

## Debugging

Enable verbose logging:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

Common issues:
1. **Authentication fails** → Check `FINERACT_USER` and `FINERACT_PASS`
2. **GL account not found** → Run `chart_of_accounts` loader first
3. **Product not found** → Create products before running accounting loader
4. **Duplicate entity** → Loader will skip and log (this is normal)

## Testing

### Local Testing Script

```bash
# Test all loaders
./test_loaders_locally.sh

# Test specific loader
./test_loaders_locally.sh --loader chart_of_accounts

# Custom Fineract instance
./test_loaders_locally.sh --url http://localhost:8443/fineract-provider/api/v1
```

### Manual Testing

```bash
# Dry run (read-only, no changes)
# Note: Implement dry-run mode in BaseLoader if needed

# Single entity test
python3 -c "
from chart_of_accounts import ChartOfAccountsLoader
import yaml

yaml_data = yaml.safe_load('''
apiVersion: fineract.apache.org/v1
kind: GLAccount
metadata:
  name: test-account
spec:
  name: Test Account
  glCode: '999'
  type: Asset
  usage: Detail
  manualEntriesAllowed: true
''')

loader = ChartOfAccountsLoader('.', 'https://api.dev.fineract.com', 'default')
payload = loader.yaml_to_fineract_api(yaml_data)
print(payload)
"
```

## Kubernetes Deployment

Each loader can run as a Kubernetes Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: load-chart-of-accounts
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # Load order
spec:
  template:
    spec:
      containers:
      - name: loader
        image: python:3.11-slim
        command:
        - python3
        - /scripts/loaders/chart_of_accounts.py
        - --yaml-dir
        - /data/accounting/chart-of-accounts
        - --fineract-url
        - https://api.dev.fineract.com
        - --tenant
        - default
        env:
        - name: FINERACT_USER
          valueFrom:
            secretKeyRef:
              name: fineract-credentials
              key: username
        - name: FINERACT_PASS
          valueFrom:
            secretKeyRef:
              name: fineract-credentials
              key: password
        volumeMounts:
        - name: scripts
          mountPath: /scripts
        - name: data
          mountPath: /data
      restartPolicy: OnFailure
      volumes:
      - name: scripts
        configMap:
          name: fineract-loader-scripts
      - name: data
        configMap:
          name: fineract-data-dev
```

## Extending with New Loaders

To implement a new loader:

1. **Copy a stub template** from this directory
2. **Implement `yaml_to_fineract_api()`** method
3. **Update `load_all()`** if needed (default is usually fine)
4. **Test locally** with sample YAML
5. **Add to testing script** in `test_loaders_locally.sh`
6. **Create Kubernetes Job** manifest if deploying via GitOps

Example:
```python
class MyEntityLoader(BaseLoader):
    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        spec = yaml_data.get('spec', {})

        # Build Fineract API payload
        payload = {
            'name': spec.get('name'),
            'description': spec.get('description', ''),
            # ... add entity-specific fields
        }

        return payload
```

## Support

For issues or questions:
- Check logs for detailed error messages
- Verify YAML structure matches expected format
- Ensure dependencies are loaded first
- Test against Fineract API documentation

## License

Apache 2.0 - See repository LICENSE file
