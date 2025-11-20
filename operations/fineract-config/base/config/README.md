# Fineract Configuration Files

This directory contains YAML configuration files for Apache Fineract. Files placed here are automatically loaded by the `fineract-config-cli` job.

---

## Quick Reference

### File Naming Convention

Use descriptive, numbered prefixes to control load order:

```
01-system-config.yml       # System-level settings
02-offices.yml             # Organizational structure
03-roles.yml               # Security roles and permissions
04-accounting.yml          # Chart of accounts
05-products.yml            # Loan and savings products
06-sample-data.yml         # Demo/test data (optional)
```

Files are processed in **alphabetical order**.

### Basic Structure

All files must start with:

```yaml
tenant: default  # Required - specifies Fineract tenant

# Then add your entities...
offices:
  - name: Head Office
    # ...
```

---

## Supported Entities

### System Configuration (Wave 1)
- `currency` - Currency settings
- `workingDays` - Business days configuration
- `globalConfig` - Global configuration parameters
- `codes` - Code values and types
- `accountNumbering` - Account number formats
- `dataTable` - Custom data tables

### Security & Organization (Wave 2)
- `roles` - Security roles and permissions
- `offices` - Office hierarchy
- `staff` - Staff members
- `users` - System users
- `tellers` - Teller/cashier setup

### Accounting (Wave 3)
- `chartOfAccounts` (or `glAccounts`) - GL accounts
- `financialMappings` - Accounting mappings
- `tellerCashManagement` - Teller accounting rules

### Products (Wave 4)
- `charges` - Fees and charges
- `loanProducts` - Loan product definitions
- `savingsProducts` - Savings product definitions
- `shareProducts` - Share product definitions
- `fixedDepositProducts` - Fixed deposit products
- `recurringDepositProducts` - Recurring deposit products

### Entities (Wave 5)
- `clients` - Client/customer records
- `groups` - Client groups
- `centers` - Centers (for group lending)

### Accounts & Transactions (Wave 6)
- `savingsAccounts` - Savings account opening
- `loanAccounts` - Loan account creation
- `deposits` - Deposit transactions
- `withdrawals` - Withdrawal transactions
- `loanDisbursements` - Loan disbursements
- `loanRepayments` - Loan repayment transactions

---

## Examples

### Example 1: Office Hierarchy

```yaml
# 02-offices.yml
tenant: default

offices:
  # Parent office
  - name: Head Office
    externalId: HO001
    openingDate: [2024, 1, 1]

  # Child offices reference parent by name
  - name: Douala Branch
    externalId: DLA001
    parentName: Head Office
    openingDate: [2024, 2, 1]

  - name: Yaoundé Branch
    externalId: YAO001
    parentName: Head Office
    openingDate: [2024, 2, 1]
```

### Example 2: Roles with Permissions

```yaml
# 03-roles.yml
tenant: default

roles:
  - name: Branch Manager
    description: Full branch operations management
    permissions:
      - ALL_FUNCTIONS_READ
      - CREATE_CLIENT
      - CREATE_LOAN
      - APPROVE_LOAN
      - DISBURSE_LOAN
      - REPAYLOAN_LOAN

  - name: Loan Officer
    description: Loan processing and management
    permissions:
      - READ_CLIENT
      - CREATE_LOAN
      - UPDATE_LOAN
      - DISBURSE_LOAN
      - REPAYLOAN_LOAN
```

### Example 3: Chart of Accounts

```yaml
# 04-accounting.yml
tenant: default

chartOfAccounts:
  # Assets
  - name: Cash
    glCode: "1000"
    type: ASSET
    usage: DETAIL
    manualEntriesAllowed: true

  - name: Bank Accounts
    glCode: "1100"
    type: ASSET
    usage: DETAIL

  - name: Loan Portfolio
    glCode: "1300"
    type: ASSET
    usage: DETAIL

  # Liabilities
  - name: Savings Deposits
    glCode: "2000"
    type: LIABILITY
    usage: DETAIL

  # Income
  - name: Interest Income
    glCode: "4000"
    type: INCOME
    usage: DETAIL

  # Expenses
  - name: Operating Expenses
    glCode: "5000"
    type: EXPENSE
    usage: DETAIL
```

### Example 4: Loan Product with Dependencies

```yaml
# 05-products.yml
tenant: default

# Define charges first
charges:
  - name: Processing Fee
    chargeAppliesTo: LOAN
    chargeTimeType: DISBURSEMENT
    chargeCalculationType: FLAT
    amount: 1000
    currency: USD
    active: true

  - name: Late Payment Penalty
    chargeAppliesTo: LOAN
    chargeTimeType: OVERDUE_INSTALLMENT
    chargeCalculationType: PERCENT_OF_AMOUNT
    amount: 5
    currency: USD
    active: true

# Then reference them in products
loanProducts:
  - name: Personal Loan
    shortName: PL
    description: Standard personal loan product

    # Currency
    currencyCode: USD
    digitsAfterDecimal: 2
    inMultiplesOf: 100

    # Principal
    principal: 10000
    minPrincipal: 1000
    maxPrincipal: 100000

    # Terms
    numberOfRepayments: 12
    minNumberOfRepayments: 6
    maxNumberOfRepayments: 36
    repaymentEvery: 1
    repaymentFrequencyType: MONTHS

    # Interest
    interestRatePerPeriod: 12.0
    minInterestRatePerPeriod: 8.0
    maxInterestRatePerPeriod: 20.0
    interestType: DECLINING_BALANCE
    interestCalculationPeriodType: SAME_AS_REPAYMENT_PERIOD

    # Amortization
    amortizationType: EQUAL_INSTALLMENTS

    # Charges - reference using $charge.<name>
    charges:
      - $charge.Processing Fee
      - $charge.Late Payment Penalty

    # Accounting - reference GL accounts using $glAccount.<code>
    accounting:
      fundSource: $glAccount.1100
      loanPortfolio: $glAccount.1300
      interestIncome: $glAccount.4000
      feeIncome: $glAccount.4100
      penaltyIncome: $glAccount.4200
```

### Example 5: Staff with User Creation

```yaml
# 06-staff.yml
tenant: default

staff:
  - firstName: Marie
    lastName: Ngono
    office: $office.Douala Branch  # Reference by name
    isLoanOfficer: true
    isActive: true
    joiningDate: [2024, 11, 20]
    mobileNo: "+237677123456"
    emailAddress: marie.ngono@example.com

    # Create user account for staff
    createUser: true
    username: marie.ngono
    password: ${MARIE_PASSWORD}  # From environment variable
    roles:
      - $role.Loan Officer
```

---

## Dependency Resolution

Use `$<entity-type>.<identifier>` to reference other entities:

### Supported Reference Types

```yaml
# Offices
office: $office.Head Office

# Roles
role: $role.Branch Manager

# Staff
staff: $staff.John Doe

# GL Accounts (by code)
glAccount: $glAccount.1000

# Charges
charge: $charge.Processing Fee

# Products
loanProduct: $loanProduct.Personal Loan
savingsProduct: $savingsProduct.Savings Account
```

### Resolution Order

The CLI loads entities in dependency order:

1. System config (no dependencies)
2. Offices, roles (can reference each other)
3. Staff (depends on offices, roles)
4. Accounting setup
5. Products (depend on GL accounts, charges)
6. Clients (depend on offices, staff)
7. Accounts (depend on clients, products)
8. Transactions (depend on accounts)

---

## Variable Substitution

Use `${VAR_NAME}` for environment variables:

```yaml
systemConfig:
  globalConfig:
    - name: amazon-S3_access_key
      value: ${AWS_ACCESS_KEY}  # From environment

users:
  - username: admin
    password: ${ADMIN_PASSWORD}  # From secret
```

Variables are substituted by the `substitute-variables` init container before the CLI runs.

---

## Best Practices

### 1. Use External IDs

Always provide external IDs for entities:

```yaml
offices:
  - name: Head Office
    externalId: HO001  # Unique, stable identifier
```

External IDs enable:
- Idempotent imports (same config applied multiple times)
- Cross-environment consistency
- Easier troubleshooting

### 2. Organize by Type

Separate entities into logical files:

```
02-offices.yml          # Just offices
03-roles.yml            # Just roles
04-accounting.yml       # GL accounts only
05-products.yml         # Products and charges
```

### 3. Use Descriptive Names

```yaml
# Good
- name: Yaoundé Central Branch
  externalId: YAO-CENTRAL-001

# Avoid
- name: Branch 1
  externalId: B1
```

### 4. Comment Complex Configurations

```yaml
loanProducts:
  - name: Microfinance Loan
    # Small loans for low-income entrepreneurs
    # Interest calculated on declining balance
    # Weekly repayments over 6 months
    principal: 500000  # 500,000 XAF
    interestRatePerPeriod: 2.0  # 2% per month = 24% annual
```

### 5. Version Control Everything

```bash
# Commit incrementally
git add 02-offices.yml
git commit -m "feat: add Yaoundé branch office"

# Use descriptive commit messages
git commit -m "fix: correct interest rate for personal loan (12% -> 10%)"
```

### 6. Test in Dev First

```bash
# Add to dev environment first
git checkout develop
# ... make changes
git push

# Verify in dev
kubectl logs -n fineract-dev job/apply-fineract-config

# Then promote to UAT/production
```

### 7. Use Dry-Run for Testing

Enable dry-run mode temporarily:

```yaml
# overlays/dev/patches/job-config.yaml
- name: IMPORT_DRY_RUN
  value: "true"
```

Review output, then set back to `false` to apply.

---

## Common Pitfalls

### ❌ Missing External ID

```yaml
# Will cause issues with idempotency
offices:
  - name: Head Office
    # Missing externalId!
```

### ❌ Invalid Date Format

```yaml
# Wrong
openingDate: "2024-01-01"

# Correct
openingDate: [2024, 1, 1]
```

### ❌ Circular Dependencies

```yaml
# Avoid circular references
offices:
  - name: Office A
    parentName: Office B
  - name: Office B
    parentName: Office A  # Circular!
```

### ❌ Incorrect Reference Syntax

```yaml
# Wrong
staff:
  - office: Head Office  # Missing $office.

# Correct
staff:
  - office: $office.Head Office
```

### ❌ Sensitive Data in Git

```yaml
# Never commit passwords directly
users:
  - username: admin
    password: SecretPass123!  # Bad!

# Use environment variables instead
users:
  - username: admin
    password: ${ADMIN_PASSWORD}  # Good!
```

---

## Resources

- **Main README**: `../README.md` - Complete documentation
- **Fineract Config CLI Docs**: See official documentation in Fineract repository
- **YAML Schema Reference**: Detailed entity field documentation
- **Example Configs**: See `config-examples/` in fineract-config-cli repository

---

## Getting Help

If you encounter issues:

1. **Check job logs**:
   ```bash
   kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli
   ```

2. **Validate YAML syntax**:
   ```bash
   yamllint your-config.yml
   ```

3. **Review main README**: `../README.md`

4. **Contact DevOps team** for assistance

---

**Happy Configuring! 🎉**
