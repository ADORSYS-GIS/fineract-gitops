# Fineract Data Schemas

JSON schemas for validating Fineract configuration YAML files.

## Available Schemas (30/30 Complete) ✅

All entity types now have comprehensive JSON schema validation with complete field definitions, type validations, enums, and descriptions.

**Phase 2 Complete - Added 3 new schemas for high-value production features:**
- ✨ notification-template.schema.json - SMS/Email notification templates
- ✨ payment-type-accounting.schema.json - Payment method GL account mappings
- ✨ report.schema.json - Financial and COBAC reporting configurations

### Products & Financial (8 schemas)
- `loan-product.schema.json` - Loan product validation
- `loan-product-accounting.schema.json` - Loan product GL mappings ✨ NEW
- `savings-product.schema.json` - Savings product validation
- `savings-product-accounting.schema.json` - Savings product GL mappings ✨ NEW
- `charge.schema.json` - Fee/charge definitions
- `floating-rate.schema.json` - Variable rate products
- `loan-provisioning.schema.json` - Loan loss provisioning
- `delinquency-bucket.schema.json` - Delinquency classifications

### User & Access Management (4 schemas)
- `office.schema.json` - Office/branch structures
- `staff.schema.json` - Staff/employee records
- `role.schema.json` - Role definitions
- `permission.schema.json` - Permission mappings

### System Configuration (7 schemas)
- `code-value.schema.json` - Code value definitions
- `currency-config.schema.json` - Currency settings
- `working-days.schema.json` - Business day calendar
- `holiday.schema.json` - Holiday calendar
- `account-number-format.schema.json` - Account numbering rules
- `teller.schema.json` - Teller/cashier configurations
- `maker-checker.schema.json` - Approval workflow config

### Accounting (5 schemas)
- `chart-of-accounts.schema.json` - GL account structure
- `fund-source.schema.json` - Fund sources
- `payment-type.schema.json` - Payment method types
- `payment-type-accounting.schema.json` - Payment type GL mappings ✨ NEW
- `financial-activity-mapping.schema.json` - Activity to GL mapping

### Advanced Features (6 schemas)
- `collateral-type.schema.json` - Collateral definitions
- `guarantor-type.schema.json` - Guarantor types
- `data-table.schema.json` - Custom data tables
- `tax-group.schema.json` - Tax configurations
- `notification-template.schema.json` - SMS/Email templates ✨ NEW
- `report.schema.json` - Financial and COBAC reports ✨ NEW

## Usage

### Validate YAML Files

```bash
# Validate all YAML files against schemas
python3 scripts/validate-data.py

# Validate specific entity type
python3 scripts/validate-data.py --type loan-products
```

### Schema Structure

All schemas follow this structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Fineract Entity Type",
  "type": "object",
  "required": ["apiVersion", "kind", "metadata", "spec"],
  "properties": {
    "apiVersion": {
      "type": "string",
      "enum": ["fineract.apache.org/v1"]
    },
    "kind": {
      "type": "string",
      "enum": ["EntityType"]
    },
    "metadata": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name": {
          "type": "string",
          "pattern": "^[a-z0-9-]+$"
        }
      }
    },
    "spec": {
      "type": "object",
      "properties": {
        // Entity-specific fields
      }
    }
  }
}
```

## Validation Examples

### Valid YAML

```yaml
apiVersion: fineract.apache.org/v1
kind: LoanProduct
metadata:
  name: personal-loan
  labels:
    product-type: loan
spec:
  name: Personal Loan
  currency: USD
  principal:
    min: 1000
    default: 5000
    max: 50000
```

### Invalid YAML (Caught by Schema)

```yaml
apiVersion: fineract.apache.org/v1
kind: LoanProduct
metadata:
  name: Personal Loan  # ❌ Invalid: Should be kebab-case
spec:
  currency: US  # ❌ Invalid: Must be 3-letter ISO code
```

## Benefits

- **Early Error Detection**: Catch configuration errors before deployment
- **Consistency**: Enforce naming conventions (kebab-case)
- **Documentation**: Schemas serve as API documentation
- **IDE Support**: Schemas enable auto-completion in IDEs
- **CI/CD Integration**: Automated validation in pipelines

## Schema Enhancement Status

✅ **All 30 schemas complete** (2025-11-12)

**Phase 1 Complete - Critical Production Features:**
- ✨ loan-product-accounting.schema.json - NEW (16 mapping types)
- ✨ savings-product-accounting.schema.json - NEW (11 mapping types)

**Phase 2 Complete - High-Value Production Features:**
- ✨ notification-template.schema.json - NEW (SMS/Email templates with event triggers)
- ✨ payment-type-accounting.schema.json - NEW (Payment type to GL account mappings)
- ✨ report.schema.json - NEW (Financial and COBAC reports with SQL and parameters)

**Priority 1 - New Loaders (6):**
- holiday.schema.json - Date ranges, offices array
- payment-type.schema.json - Cash/non-cash flags, positioning
- account-number-format.schema.json - Account type enums, prefix rules
- teller.schema.json - Office mapping, status, dates
- collateral-type.schema.json - Quality/unit types, valuation
- fund-source.schema.json - External ID integration

**Priority 2 - Existing Loaders (10):**
- code-value.schema.json - Values array with nested structure
- currency-config.schema.json - ISO currency codes array
- working-days.schema.json - Recurrence patterns, rescheduling
- office.schema.json - Hierarchical structure, contact info
- floating-rate.schema.json - Rate periods with dates
- tax-group.schema.json - Tax components with GL mappings
- chart-of-accounts.schema.json - GL types, usage, hierarchy
- financial-activity-mapping.schema.json - Activity-to-GL mapping
- role.schema.json - Permission objects array
- staff.schema.json - Keycloak integration fields

**Priority 3 - Other Entities (6):**
- delinquency-bucket.schema.json - Age ranges array
- guarantor-type.schema.json - Type enum (customer/staff/external)
- loan-provisioning.schema.json - Category, percentage, age ranges
- maker-checker.schema.json - Entity and action enums
- data-table.schema.json - Custom columns with types
- permission.schema.json - Code patterns, action enums

**Already Complete (3):**
- loan-product.schema.json
- savings-product.schema.json
- charge.schema.json

## Related Documentation

- [Operations Guide](../../../docs/OPERATIONS_GUIDE.md)
- [Data Loading README](../README.md)
- [Validation Scripts](../scripts/README.md)
