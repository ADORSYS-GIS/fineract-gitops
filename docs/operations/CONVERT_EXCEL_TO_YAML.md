# Converting Excel Data to YAML

This guide helps you convert your existing Fineract Excel data to YAML format for GitOps.

## 📊 Your Existing Excel Data

You already have:
```
fineract/docs/data-collection/fineract-demo-data/├── scripts/
│   ├── generate_excel_template.py  ← Generates Excel
│   └── loaders/                    ← Loads from Excel to Fineract
└── fineract_demo_data.xlsx         ← Your data
```

## 🎯 Goal

Convert this Excel data into:
```
fineract-gitops/operations/fineract-data/data/
├── base/              ← Shared code values
├── dev/               ← Dev config + demo data
├── uat/               ← UAT config + test data
└── production/        ← Production config ONLY
```

## 🔄 Conversion Strategy

### Approach 1: Manual Conversion (Recommended for Learning)

**Best for:** Understanding the structure, small datasets

1. **Open Excel file**
2. **For each sheet, create YAML files**
3. **Copy existing YAML as template**
4. **Fill in values from Excel**

**Example:**

Excel "Loan Products" sheet:
| Product Name | Min Principal | Max Principal | Interest Rate |
|--------------|---------------|---------------|---------------|
| Personal Loan | 10000 | 500000 | 15.0 |
| Business Loan | 100000 | 5000000 | 14.0 |

Becomes two YAML files:

`data/dev/products/loan-products/personal-loan.yaml`:
```yaml
apiVersion: fineract.apache.org/v1
kind: LoanProduct
metadata:
  name: personal-loan
spec:
  name: Personal Loan
  currency: KES
  principal:
    min: 10000
    max: 500000
  interestRate:
    default: 15.0
```

`data/dev/products/loan-products/business-loan.yaml`:
```yaml
apiVersion: fineract.apache.org/v1
kind: LoanProduct
metadata:
  name: business-loan
spec:
  name: Business Loan
  currency: KES
  principal:
    min: 100000
    max: 5000000
  interestRate:
    default: 14.0
```

### Approach 2: Automated Conversion Script

**Best for:** Large datasets, repeatable process

Create a Python script to automate conversion:

```python
#!/usr/bin/env python3
# scripts/excel_to_yaml.py

import pandas as pd
import yaml
from pathlib import Path
import re

def to_kebab_case(text):
    """Convert text to kebab-case for filenames"""
    text = text.lower()
    text = re.sub(r'[^a-z0-9]+', '-', text)
    return text.strip('-')

def convert_loan_products(excel_file, output_dir):
    """Convert Loan Products sheet to YAML files"""
    df = pd.read_excel(excel_file, sheet_name='Loan Products')

    output_path = Path(output_dir) / 'products' / 'loan-products'
    output_path.mkdir(parents=True, exist_ok=True)

    for idx, row in df.iterrows():
        product_name = row['Product Name']
        filename = to_kebab_case(product_name) + '.yaml'

        data = {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'LoanProduct',
            'metadata': {
                'name': to_kebab_case(product_name),
                'labels': {
                    'product-type': 'loan',
                    'category': row.get('Category', 'general').lower()
                }
            },
            'spec': {
                'name': product_name,
                'shortName': row.get('Short Name', product_name[:10]),
                'description': row.get('Description', ''),
                'currency': row.get('Currency', 'KES'),
                'digitsAfterDecimal': int(row.get('Digits After Decimal', 2)),
                'inMultiplesOf': int(row.get('In Multiples Of', 100)),

                'principal': {
                    'min': float(row['Min Principal']),
                    'default': float(row['Default Principal']),
                    'max': float(row['Max Principal'])
                },

                'interestRate': {
                    'min': float(row['Min Interest Rate']),
                    'default': float(row['Default Interest Rate']),
                    'max': float(row['Max Interest Rate']),
                    'type': row.get('Interest Type', 'DECLINING_BALANCE')
                },

                'numberOfRepayments': {
                    'min': int(row['Min Repayments']),
                    'default': int(row['Default Repayments']),
                    'max': int(row['Max Repayments'])
                },

                'repaymentEvery': int(row.get('Repayment Every', 1)),
                'repaymentFrequency': row.get('Repayment Frequency', 'MONTHS'),

                'interestCalculationPeriod': row.get('Interest Calculation Period', 'SAME_AS_REPAYMENT_PERIOD'),
                'amortizationType': row.get('Amortization Type', 'EQUAL_INSTALLMENTS'),

                'allowPartialPeriodInterestCalculation': row.get('Allow Partial Period', True),

                'accounting': {
                    'type': row.get('Accounting Type', 'ACCRUAL_PERIODIC'),
                    'fundSource': int(row.get('Fund Source GL', 1)),
                    'loanPortfolio': int(row.get('Loan Portfolio GL', 2)),
                    'interestOnLoans': int(row.get('Interest Income GL', 4))
                }
            }
        }

        # Write YAML file
        with open(output_path / filename, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            print(f"Created: {output_path / filename}")

def convert_offices(excel_file, output_dir):
    """Convert Offices sheet to YAML files"""
    df = pd.read_excel(excel_file, sheet_name='Offices')

    output_path = Path(output_dir) / 'offices'
    output_path.mkdir(parents=True, exist_ok=True)

    for idx, row in df.iterrows():
        office_name = row['Office Name']
        filename = to_kebab_case(office_name) + '.yaml'

        data = {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'Office',
            'metadata': {
                'name': to_kebab_case(office_name),
                'labels': {
                    'office-type': row.get('Office Type', 'branch').lower(),
                    'region': row.get('Region', 'central').lower()
                }
            },
            'spec': {
                'name': office_name,
                'externalId': row.get('External ID', f"OFF-{idx+1:03d}"),
                'parentOffice': to_kebab_case(row['Parent Office']) if pd.notna(row.get('Parent Office')) else None,
                'openingDate': row['Opening Date'].strftime('%Y-%m-%d') if pd.notna(row.get('Opening Date')) else '2024-01-01',

                'address': {
                    'street': row.get('Street', ''),
                    'building': row.get('Building', ''),
                    'city': row.get('City', ''),
                    'postalCode': str(row.get('Postal Code', '')),
                    'country': row.get('Country', 'Kenya')
                },

                'contact': {
                    'phone': row.get('Phone', ''),
                    'email': row.get('Email', ''),
                    'manager': row.get('Manager', '')
                },

                'status': row.get('Status', 'ACTIVE')
            }
        }

        with open(output_path / filename, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            print(f"Created: {output_path / filename}")

def convert_charges(excel_file, output_dir):
    """Convert Charges sheet to YAML files"""
    df = pd.read_excel(excel_file, sheet_name='Charges')

    output_path = Path(output_dir) / 'charges'
    output_path.mkdir(parents=True, exist_ok=True)

    for idx, row in df.iterrows():
        charge_name = row['Charge Name']
        filename = to_kebab_case(charge_name) + '.yaml'

        data = {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'Charge',
            'metadata': {
                'name': to_kebab_case(charge_name),
                'labels': {
                    'charge-type': 'fee' if not row.get('Is Penalty', False) else 'penalty',
                    'applies-to': row.get('Applies To', 'loan').lower()
                }
            },
            'spec': {
                'name': charge_name,
                'currency': row.get('Currency', 'KES'),

                'chargeCalculationType': row.get('Calculation Type', 'FLAT'),
                'amount': float(row['Amount']),

                'chargeAppliesTo': row.get('Applies To', 'LOAN'),
                'chargeTimeType': row.get('Time Type', 'DISBURSEMENT'),

                'chargePaymentMode': row.get('Payment Mode', 'REGULAR'),

                'incomeAccount': int(row.get('Income GL Account', 5)),

                'active': row.get('Active', True),
                'penalty': row.get('Is Penalty', False)
            }
        }

        with open(output_path / filename, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            print(f"Created: {output_path / filename}")

def convert_code_values(excel_file, output_dir):
    """Convert Codes and Values sheet to YAML files"""
    df = pd.read_excel(excel_file, sheet_name='Codes and Values')

    output_path = Path(output_dir) / 'codes-and-values'
    output_path.mkdir(parents=True, exist_ok=True)

    # Group by code name
    for code_name, group in df.groupby('Code Name'):
        filename = to_kebab_case(code_name) + '.yaml'

        values = []
        for idx, row in group.iterrows():
            values.append({
                'name': row['Value Name'],
                'position': int(row.get('Position', idx + 1)),
                'active': row.get('Active', True),
                'description': row.get('Description', '')
            })

        data = {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'CodeValue',
            'metadata': {
                'name': to_kebab_case(code_name),
                'labels': {
                    'code-type': 'dropdown'
                }
            },
            'spec': {
                'codeName': code_name,
                'description': group.iloc[0].get('Code Description', ''),
                'values': values
            }
        }

        with open(output_path / filename, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            print(f"Created: {output_path / filename}")

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Convert Excel to YAML')
    parser.add_argument('--excel', required=True, help='Path to Excel file')
    parser.add_argument('--output', required=True, help='Output directory (e.g., operations/fineract-data/data/dev)')
    parser.add_argument('--entity-type', required=True, choices=[
        'loan-products', 'savings-products', 'offices', 'charges',
        'code-values', 'all'
    ])

    args = parser.parse_args()

    if args.entity_type == 'loan-products' or args.entity_type == 'all':
        convert_loan_products(args.excel, args.output)

    if args.entity_type == 'offices' or args.entity_type == 'all':
        convert_offices(args.excel, args.output)

    if args.entity_type == 'charges' or args.entity_type == 'all':
        convert_charges(args.excel, args.output)

    if args.entity_type == 'code-values' or args.entity_type == 'all':
        convert_code_values(args.excel, args.output)

    print("\n✅ Conversion complete!")

if __name__ == '__main__':
    main()
```

**Usage:**

```bash
# Convert all entity types
python3 scripts/excel_to_yaml.py \
  --excel fineract/docs/data-collection/fineract-demo-data/fineract_demo_data.xlsx \

# Convert only loan products
python3 scripts/excel_to_yaml.py \
  --excel fineract/docs/data-collection/fineract-demo-data/fineract_demo_data.xlsx \
  --output operations/fineract-data/data/dev \
  --entity-type loan-products
```

## 📋 Conversion Checklist

### Phase 1: Code Values (Shared Base Data)
- [ ] Gender
- [ ] Client Type
- [ ] Client Classification
- [ ] Marital Status
- [ ] Education Level
- [ ] Employment Status
- [ ] Loan Purpose
- [ ] ID Type
- [ ] Relationship Type
- [ ] Business Type

→ Output: `data/base/codes-and-values/*.yaml`

### Phase 2: System Configuration
- [ ] Global Configuration
- [ ] Working Days
- [ ] Currency Config
- [ ] Account Number Preferences
- [ ] Maker Checker Config

→ Output: `data/{env}/system-config/*.yaml`

### Phase 3: Organizational Structure
- [ ] Offices
- [ ] Staff
- [ ] Roles & Permissions
- [ ] Tellers

→ Output: `data/{env}/offices/*.yaml`, etc.

### Phase 4: Products
- [ ] Loan Products
- [ ] Savings Products
- [ ] Floating Rates

→ Output: `data/{env}/products/loan-products/*.yaml`

### Phase 5: Financial Configuration
- [ ] Charges/Fees
- [ ] Chart of Accounts
- [ ] Fund Sources
- [ ] Payment Types
- [ ] Tax Groups
- [ ] Product Accounting Mappings

→ Output: `data/{env}/charges/*.yaml`, `data/{env}/accounting/*`

### Phase 6: Risk Management
- [ ] Loan Provisioning
- [ ] Delinquency Buckets
- [ ] Collateral Types
- [ ] Guarantor Types

→ Output: `data/{env}/risk/*.yaml`, `data/{env}/collateral-types/*.yaml`

### Phase 7: Operations
- [ ] Holidays
- [ ] Scheduler Jobs
- [ ] Notification Templates
- [ ] Data Tables
- [ ] Reports Configuration

→ Output: `data/{env}/holidays/*.yaml`, etc.

### Phase 8: Demo Data (Dev/UAT Only)
- [ ] Clients
- [ ] Loan Accounts
- [ ] Savings Accounts
- [ ] Collateral Assignments
- [ ] Guarantor Assignments
- [ ] Transactions

→ Output: `data/dev/demo-data/**/*.yaml`, `data/uat/test-data/**/*.yaml`

## 🎯 Field Mapping Reference

### Excel → YAML Mapping for Loan Products

| Excel Column | YAML Path | Notes |
|--------------|-----------|-------|
| Product Name | spec.name | Display name |
| Short Name | spec.shortName | Abbreviation |
| Currency | spec.currency | ISO 4217 code |
| Min Principal | spec.principal.min | Minimum loan amount |
| Default Principal | spec.principal.default | Default loan amount |
| Max Principal | spec.principal.max | Maximum loan amount |
| Min Interest Rate | spec.interestRate.min | Minimum % |
| Default Interest Rate | spec.interestRate.default | Default % |
| Max Interest Rate | spec.interestRate.max | Maximum % |
| Interest Type | spec.interestRate.type | FLAT or DECLINING_BALANCE |
| Min Repayments | spec.numberOfRepayments.min | Minimum installments |
| Default Repayments | spec.numberOfRepayments.default | Default installments |
| Max Repayments | spec.numberOfRepayments.max | Maximum installments |
| Repayment Frequency | spec.repaymentFrequency | DAYS, WEEKS, MONTHS, YEARS |

## ✅ Validation After Conversion

```bash
# 1. Validate all YAML files
python3 scripts/validate-data.py

# 2. Check file structure
tree operations/fineract-data/data/dev/

# 3. Verify YAML syntax
find operations/fineract-data/data/ -name "*.yaml" -exec python3 -c "import yaml; yaml.safe_load(open('{}'))" \;

# 4. Check Git diff
git status
git diff
```

## 🚀 Next Steps After Conversion

1. **Commit YAML files:**
   ```bash
   git add operations/fineract-data/data/
   git commit -m "data: convert Excel to YAML format"
   ```

2. **Create data loading jobs** (see IMPLEMENTATION_GUIDE.md)

3. **Write Python loader scripts** to convert YAML → Fineract API

4. **Test in dev environment**

## 💡 Tips

1. **Start with one entity type** (e.g., Loan Products) to validate the process

2. **Keep Excel as backup** until YAML approach is proven

3. **Use version control** - commit after each successful conversion

4. **Validate incrementally** - validate after converting each entity type

5. **Test in dev first** - ensure YAML loads correctly before deploying to production

---

**Conversion is a one-time effort. After this, all changes are made directly in YAML with Git tracking!**
