# Loading All Dev Data into Fineract

Complete guide to load all data from `data/dev/` into Fineract.

## Table of Contents

1. [Quick Start (Kubernetes/ArgoCD)](#quick-start-kubernetesargocd)
2. [Local Loading (Direct)](#local-loading-direct)
3. [Loading Order (Dependencies)](#loading-order-dependencies)
4. [Prerequisites](#prerequisites)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start (Kubernetes/ArgoCD)

**Recommended method for production/staging environments**

### Prerequisites

- Kubernetes cluster access
- ArgoCD installed and configured
- Fineract deployed and running
- Keycloak configured with client credentials

### Step 1: Push Your Code

```bash
cd /Users/guymoyo/dev/fineract-gitops

# Make sure all changes are committed
git status

# Push to deploy branch
git push origin deploy-key
```

### Step 2: Sync ArgoCD Application

```bash
# Option A: Using argocd CLI
argocd app sync fineract-data

# Option B: Using ArgoCD UI
# 1. Go to ArgoCD UI
# 2. Find "fineract-data" application
# 3. Click "Sync" button
# 4. Click "Synchronize"

# Option C: Using kubectl
kubectl apply -k operations/fineract-data/kubernetes/overlays/dev/
```

### Step 3: Monitor Job Execution

The jobs run in dependency order (sync-waves):

```bash
# Watch all jobs
kubectl get jobs -n fineract-dev -w

# Watch specific job
kubectl logs -f job/fineract-data-system-foundation -n fineract-dev

# Check job status
kubectl get jobs -n fineract-dev | grep fineract-data
```

### Expected Job Sequence

Jobs run in this order (controlled by sync-wave annotations):

1. **Wave 5: System Foundation** (`job-01-system-foundation`)
   - Offices, Staff, Roles, Permissions
   - Currencies, Working Days
   - Code Values
   - Account Number Formats

2. **Wave 6: Products** (`job-02-products`)
   - Loan Products
   - Savings Products
   - Charges

3. **Wave 7: Accounting** (`job-03-accounting`)
   - Chart of Accounts (GL Accounts)
   - Tax Groups
   - Fund Sources
   - Payment Types
   - Financial Activity Mappings

4. **Wave 8: Entities** (`job-04-entities`)
   - Clients
   - Collateral Types
   - Guarantor Types
   - Data Tables
   - Floating Rates

5. **Wave 9: Transactions** (`job-05-transactions`)
   - Loan Accounts
   - Savings Accounts
   - Loan Repayments
   - Savings Deposits/Withdrawals

6. **Wave 10: Calendar** (`job-06-calendar`)
   - Holidays
   - Calendar Events

### Verify Success

```bash
# All jobs should be "Complete"
kubectl get jobs -n fineract-dev | grep fineract-data

# Check for any failed jobs
kubectl get jobs -n fineract-dev | grep -i "0/1"

# View logs of completed job
kubectl logs job/fineract-data-system-foundation -n fineract-dev
```

**Expected Output:**
```
================================================================================
LOADING SUMMARY
================================================================================
Total Created: 45
Total Updated: 0
Total Skipped: 0
Total Failed: 0
Success Rate: 100.0%
================================================================================
```

---

## Local Loading (Direct)

**For development, testing, or when you don't have Kubernetes**

### Prerequisites

1. **Running Fineract Instance**
   ```bash
   # Local development
   cd /Users/guymoyo/dev/fineract
   ./gradlew bootRun

   # Or using Docker
   docker-compose up fineract-server
   ```

2. **Python 3 and Dependencies**
   ```bash
   cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data
   pip3 install -r requirements.txt
   ```

3. **Environment Variables**
   ```bash
   # Fineract connection
   export FINERACT_URL="http://localhost:8443/fineract-provider/api/v1"
   export FINERACT_VERIFY_SSL="false"  # For local dev with self-signed certs
   export TENANT="default"

   # Authentication - Option A: OAuth2 (Recommended)
   export FINERACT_CLIENT_ID="fineract-data-loader"
   export FINERACT_CLIENT_SECRET="your-secret-here"
   export FINERACT_TOKEN_URL="http://localhost:8080/auth/realms/fineract/protocol/openid-connect/token"

   # Authentication - Option B: Basic Auth (Legacy)
   export FINERACT_USERNAME="mifos"
   export FINERACT_PASSWORD="password"

   # Optional: Reference resolution mode
   export STRICT_REFERENCE_RESOLUTION="true"  # Fail on missing references
   ```

### Loading Script

I'll create a master loading script for you. Here's how to use it:

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Load all data in correct order
./scripts/load-all-data.sh

# Or load specific waves
./scripts/load-all-data.sh --wave 1  # System foundation only
./scripts/load-all-data.sh --wave 2  # Products only
```

### Manual Loading (Step-by-Step)

If you prefer to load manually in the correct order:

#### Wave 1: System Foundation

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# 1. Offices (must be first - other entities depend on it)
python3 scripts/loaders/offices.py \
  --yaml-dir data/dev/offices \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 2. Staff (depends on offices)
python3 scripts/loaders/staff.py \
  --yaml-dir data/dev/staff \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 3. Roles & Permissions
python3 scripts/loaders/roles.py \
  --yaml-dir data/dev/roles \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 4. Currencies
python3 scripts/loaders/currencies.py \
  --yaml-dir data/dev/system-config/currencies \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 5. Working Days
python3 scripts/loaders/working_days.py \
  --yaml-dir data/dev/system-config/working-days \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 6. Code Values
python3 scripts/loaders/code_values.py \
  --yaml-dir data/dev/codes-and-values \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 7. Account Number Formats
python3 scripts/loaders/account_number_formats.py \
  --yaml-dir data/dev/system-config/account-number-formats \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT
```

#### Wave 2: Products

```bash
# 1. Charges (products depend on charges)
python3 scripts/loaders/charges.py \
  --yaml-dir data/dev/charges \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 2. Loan Products
python3 scripts/loaders/loan_products.py \
  --yaml-dir data/dev/products/loan-products \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 3. Savings Products
python3 scripts/loaders/savings_products.py \
  --yaml-dir data/dev/products/savings-products \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT
```

#### Wave 3: Accounting

```bash
# 1. Chart of Accounts (GL Accounts)
python3 scripts/loaders/chart_of_accounts.py \
  --yaml-dir data/dev/accounting/chart-of-accounts \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 2. Tax Groups
python3 scripts/loaders/tax_groups.py \
  --yaml-dir data/dev/accounting/tax-groups \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 3. Fund Sources
python3 scripts/loaders/fund_sources.py \
  --yaml-dir data/dev/accounting/fund-sources \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 4. Payment Types
python3 scripts/loaders/payment_types.py \
  --yaml-dir data/dev/accounting/payment-types \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT
```

#### Wave 4: Entities

```bash
# 1. Clients
python3 scripts/loaders/clients.py \
  --yaml-dir data/dev/clients \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 2. Collateral Types
python3 scripts/loaders/collateral_types.py \
  --yaml-dir data/dev/collateral-types \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 3. Guarantor Types
python3 scripts/loaders/guarantor_types.py \
  --yaml-dir data/dev/guarantor-types \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 4. Data Tables
python3 scripts/loaders/data_tables.py \
  --yaml-dir data/dev/data-tables \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 5. Floating Rates
python3 scripts/loaders/floating_rates.py \
  --yaml-dir data/dev/floating-rates \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT
```

#### Wave 5: Transactions

```bash
# 1. Loan Accounts
python3 scripts/loaders/loan_accounts.py \
  --yaml-dir data/dev/accounts/loan-accounts \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 2. Savings Accounts
python3 scripts/loaders/savings_accounts.py \
  --yaml-dir data/dev/accounts/savings-accounts \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 3. Loan Repayments
python3 scripts/loaders/loan_repayments.py \
  --yaml-dir data/dev/transactions/loan-repayments \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 4. Savings Deposits
python3 scripts/loaders/savings_deposits.py \
  --yaml-dir data/dev/transactions/savings-deposits \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# 5. Savings Withdrawals
python3 scripts/loaders/savings_withdrawals.py \
  --yaml-dir data/dev/transactions/savings-withdrawals \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT
```

#### Wave 6: Calendar

```bash
# 1. Holidays
python3 scripts/loaders/holidays.py \
  --yaml-dir data/dev/calendar/holidays \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT
```

---

## Loading Order (Dependencies)

**Critical:** Loaders must run in this order due to dependencies:

```
┌─────────────────────────────────────────────────────────┐
│ Wave 1: System Foundation                               │
├─────────────────────────────────────────────────────────┤
│ 1. Offices         ← No dependencies                    │
│ 2. Staff           ← Depends on: Offices                │
│ 3. Roles           ← No dependencies                    │
│ 4. Currencies      ← No dependencies                    │
│ 5. Working Days    ← No dependencies                    │
│ 6. Code Values     ← No dependencies                    │
│ 7. Account Formats ← No dependencies                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Wave 2: Products                                        │
├─────────────────────────────────────────────────────────┤
│ 1. Charges         ← Depends on: Code Values            │
│ 2. Loan Products   ← Depends on: Currencies, Charges    │
│ 3. Savings Products← Depends on: Currencies, Charges    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Wave 3: Accounting                                      │
├─────────────────────────────────────────────────────────┤
│ 1. GL Accounts     ← Can have parent references         │
│ 2. Tax Groups      ← Depends on: GL Accounts            │
│ 3. Fund Sources    ← Depends on: GL Accounts            │
│ 4. Payment Types   ← Depends on: GL Accounts            │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Wave 4: Entities                                        │
├─────────────────────────────────────────────────────────┤
│ 1. Clients         ← Depends on: Offices, Staff         │
│ 2. Collateral Types← No dependencies                    │
│ 3. Guarantor Types ← No dependencies                    │
│ 4. Data Tables     ← No dependencies                    │
│ 5. Floating Rates  ← No dependencies                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Wave 5: Transactions                                    │
├─────────────────────────────────────────────────────────┤
│ 1. Loan Accounts   ← Depends on: Clients, Loan Products │
│ 2. Savings Accounts← Depends on: Clients, Savings Prod. │
│ 3. Loan Repayments ← Depends on: Loan Accounts          │
│ 4. Deposits        ← Depends on: Savings Accounts       │
│ 5. Withdrawals     ← Depends on: Savings Accounts       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Wave 6: Calendar                                        │
├─────────────────────────────────────────────────────────┤
│ 1. Holidays        ← No dependencies                    │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### For Kubernetes/ArgoCD Loading

- [x] Kubernetes cluster (minikube, kind, EKS, GKE, AKS, etc.)
- [x] ArgoCD installed in cluster
- [x] `kubectl` configured with cluster access
- [x] `argocd` CLI installed (optional)
- [x] Fineract deployed and healthy
- [x] Keycloak configured with OAuth2 client
- [x] ServiceAccount `fineract-data-loader` created
- [x] Secret `keycloak-client-secrets` created

### For Local Loading

- [x] Python 3.11+
- [x] Fineract running (local or remote)
- [x] Network access to Fineract API
- [x] Valid credentials (OAuth2 or Basic Auth)
- [x] Dependencies installed: `pip install -r requirements.txt`

### Data Validation (Always)

Before loading, validate your YAML files:

```bash
cd /Users/guymoyo/dev/fineract-gitops/operations/fineract-data

# Validate all YAML files
./scripts/validate-all.sh

# Or validate specific directory
./scripts/validate_yaml_data.py data/dev/offices
```

---

## Verification

### Check Data in Fineract UI

1. **Login to Fineract**
   - URL: http://localhost:8443 (or your Fineract URL)
   - Username: mifos
   - Password: password

2. **Verify Each Category:**

   **Offices:**
   - Go to: Admin → Organization → Offices
   - Should see: Head Office + Branch offices

   **Staff:**
   - Go to: Admin → Organization → Employees
   - Should see: All staff members

   **Roles:**
   - Go to: Admin → Users → Manage Roles
   - Should see: Custom roles defined in YAML

   **Products:**
   - Go to: Admin → Products → Loan Products
   - Go to: Admin → Products → Savings Products
   - Should see: All products from YAML

   **Chart of Accounts:**
   - Go to: Admin → Accounting → Chart of Accounts
   - Should see: All GL accounts in hierarchy

   **Clients:**
   - Go to: Clients
   - Should see: All clients from YAML

### Check Via API

```bash
# Count entities
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/offices | jq '. | length'
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/staff | jq '. | length'
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/loanproducts | jq '. | length'
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/savingsproducts | jq '. | length'
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/glaccounts | jq '. | length'
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/clients | jq '.totalFilteredRecords'
```

### Expected Counts

Based on your `data/dev/` structure:

```
Offices:          ~6
Staff:            ~15
Roles:            ~7
Loan Products:    ~10
Savings Products: ~5
GL Accounts:      ~50+
Charges:          ~12
Clients:          ~13
Code Values:      ~100+
```

---

## Troubleshooting

### Job Failures in Kubernetes

```bash
# Check job status
kubectl get jobs -n fineract-dev

# View job logs
kubectl logs job/fineract-data-system-foundation -n fineract-dev

# Describe job for events
kubectl describe job/fineract-data-system-foundation -n fineract-dev

# Check pod status
kubectl get pods -n fineract-dev | grep fineract-data

# View pod logs
kubectl logs <pod-name> -n fineract-dev
```

**Common Issues:**

1. **ImagePullBackOff**
   - Solution: Check image name and registry access
   ```bash
   kubectl describe pod <pod-name> -n fineract-dev
   ```

2. **CrashLoopBackOff**
   - Solution: Check pod logs for Python errors
   ```bash
   kubectl logs <pod-name> -n fineract-dev
   ```

3. **Secret Not Found**
   - Solution: Ensure Keycloak secret exists
   ```bash
   kubectl get secret keycloak-client-secrets -n fineract-dev
   ```

### Local Loading Failures

1. **Connection Refused**
   ```bash
   # Check Fineract is running
   curl http://localhost:8443/fineract-provider/api/v1/offices

   # Check environment variables
   echo $FINERACT_URL
   ```

2. **Authentication Failed**
   ```bash
   # Test OAuth2 token
   curl -X POST $FINERACT_TOKEN_URL \
     -d "grant_type=client_credentials" \
     -d "client_id=$FINERACT_CLIENT_ID" \
     -d "client_secret=$FINERACT_CLIENT_SECRET"

   # Or test Basic Auth
   curl -u $FINERACT_USERNAME:$FINERACT_PASSWORD \
     http://localhost:8443/fineract-provider/api/v1/offices
   ```

3. **Missing Reference Error**
   ```
   ValueError: Office 'Branch A' not found
   ```
   - Solution: Load offices first, or check YAML for typos
   - Check reference resolution mode:
   ```bash
   export STRICT_REFERENCE_RESOLUTION=false  # To skip missing refs
   ```

4. **Invalid YAML**
   ```bash
   # Validate before loading
   ./scripts/validate-all.sh

   # Check specific file
   ./scripts/validate_yaml_data.py data/dev/offices -v
   ```

### Idempotency Issues

If you see duplicates after re-running:

```bash
# This shouldn't happen - idempotency should prevent it
# Check loader output - should show "Skipped" not "Created"

# If duplicates exist, they have different IDs
# You may need to manually delete duplicates in Fineract UI
```

---

## Advanced Usage

### Load Subset of Data

```bash
# Load only offices and staff
python3 scripts/loaders/offices.py --yaml-dir data/dev/offices ...
python3 scripts/loaders/staff.py --yaml-dir data/dev/staff ...

# Skip the rest
```

### Dry Run Mode

```bash
# Preview what would be loaded (no actual API calls)
python3 scripts/loaders/offices.py \
  --yaml-dir data/dev/offices \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT \
  --dry-run
```

### Selective Re-loading

Thanks to idempotency, you can re-run safely:

```bash
# Update a loan product YAML file
vim data/dev/products/loan-products/standard-loan.yaml

# Re-run loader - will UPDATE, not duplicate
python3 scripts/loaders/loan_products.py \
  --yaml-dir data/dev/products/loan-products \
  --fineract-url $FINERACT_URL \
  --tenant $TENANT

# Output should show: "↻ Updated: Standard Loan"
```

---

## Related Documentation

- [TESTING_GUIDE.md](TESTING_GUIDE.md) - How to test loaders
- [VALIDATION_GUIDE.md](VALIDATION_GUIDE.md) - YAML validation
- [LOCAL_TESTING.md](LOCAL_TESTING.md) - Local development testing
- [SCHEMA_MANAGEMENT.md](SCHEMA_MANAGEMENT.md) - API schema sync
- [REFACTOR_PLAN.md](../REFACTOR_PLAN.md) - Complete refactor plan

---

## Quick Reference

```bash
# KUBERNETES/ARGOCD METHOD
git push origin deploy-key
argocd app sync fineract-data
kubectl logs -f job/fineract-data-system-foundation -n fineract-dev

# LOCAL METHOD
./scripts/load-all-data.sh

# VALIDATION
./scripts/validate-all.sh

# VERIFICATION
curl -u mifos:password http://localhost:8443/fineract-provider/api/v1/offices
```
