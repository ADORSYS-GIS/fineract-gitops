# Fineract Data Operations

This directory contains **all Fineract configuration data** managed as YAML files with GitOps automation.

## ✅ Status: PRODUCTION READY

**Last Updated:** 2025-01-17

Complete Fineract data loader system with optimized GitOps automation:
- ✅ **6 consolidated Kubernetes jobs** (85% reduction from 40 jobs)
- ✅ **Custom Docker image** (`ghcr.io/adorsys-gis/fineract-loader:v1.0.0`)
- ✅ **Wave-based job orchestration** (waves 5, 10, 21, 30, 35, 40)
- ✅ **Automated ConfigMap generation** from YAML data files
- ✅ **Complete RBAC** configuration
- ✅ **GitOps-ready** YAML-based configuration
- ✅ **Idempotent operations** (safe to re-run)
- ✅ **Reference resolution** for all dependencies
- ✅ **Keycloak integration** for user provisioning

## 📁 Structure

```
fineract-data/
├── README.md                          # This file
├── data/                              # Configuration data in YAML
│   └── dev/                           # Development environment
│       ├── codes-and-values/          # Dropdown code values (9 entities)
│       ├── offices/                   # Branch offices
│       ├── staff/                     # Staff members
│       ├── roles/                     # User roles
│       ├── system-config/             # System configurations
│       │   ├── currency-config/
│       │   ├── working-days/
│       │   ├── account-number-formats/
│       │   ├── maker-checker/
│       │   └── scheduler-jobs/
│       ├── products/                  # Loan/savings products (11 entities)
│       │   ├── loan-products/
│       │   └── savings-products/
│       ├── charges/                   # Fees
│       ├── collateral-types/
│       ├── guarantor-types/
│       ├── floating-rates/
│       ├── delinquency/buckets/
│       ├── notification-templates/
│       ├── data-tables/
│       ├── tellers/
│       ├── reports/
│       ├── accounting/                # Accounting configuration (9 entities)
│       │   ├── chart-of-accounts/
│       │   ├── fund-sources/
│       │   ├── payment-types/
│       │   ├── tax-groups/
│       │   ├── loan-provisioning/
│       │   ├── financial-activity-mappings/
│       │   ├── loan-product-accounting/
│       │   ├── savings-product-accounting/
│       │   └── payment-type-accounting/
│       ├── clients/                   # Demo clients (5 entities)
│       ├── accounts/
│       │   ├── savings-accounts/
│       │   └── loan-accounts/
│       ├── loans/
│       │   ├── loan-collateral/
│       │   └── loan-guarantors/
│       ├── transactions/              # Demo transactions (4 entities)
│       │   ├── savings-deposits/
│       │   ├── savings-withdrawals/
│       │   ├── loan-repayments/
│       │   └── inter-branch-transfers/
│       └── calendar/                  # Holidays (1 entity)
│           └── holidays/
│
├── kubernetes/                        # Kubernetes deployment (6 jobs)
│   ├── base/                         # Base Kustomize resources
│   │   ├── kustomization.yaml        # Base deployment config
│   │   ├── rbac.yaml                 # ServiceAccount + RBAC
│   │   └── jobs/                     # Consolidated job manifests (6 jobs)
│   │       ├── job-01-system-foundation.yaml  # Wave 5
│   │       ├── job-02-products.yaml           # Wave 10
│   │       ├── job-03-accounting.yaml         # Wave 21
│   │       ├── job-04-entities.yaml           # Wave 30
│   │       ├── job-05-transactions.yaml       # Wave 35
│   │       └── job-06-calendar.yaml           # Wave 40
│   │
│   └── overlays/                     # Environment-specific overlays
│       └── dev/                      # Development (all jobs + demo data)
│           └── kustomization.yaml    # Dev overlay config
│
├── scripts/                          # Python data loaders
│   ├── Dockerfile                    # Custom loader image definition
│   ├── requirements.txt              # Python dependencies
│   ├── loaders/                      # Consolidated loaders
│   │   ├── base_loader.py            # Base class with OAuth2, reference resolution
│   │   ├── load_system_foundation.py # Loads wave 5 entities (9 entities)
│   │   ├── load_products.py          # Loads wave 10 entities (11 entities)
│   │   ├── load_accounting.py        # Loads wave 21 entities (9 entities)
│   │   ├── load_entities.py          # Loads wave 30 entities (5 entities)
│   │   ├── load_transactions.py      # Loads wave 35 entities (4 entities)
│   │   └── load_calendar.py          # Loads wave 40 entities (1 entity)
│   ├── validate_yaml_data.py         # YAML validation script
│   └── generate-configmap-kustomization.py  # ConfigMap generator
│
├── kustomization.yaml                # Root kustomization (auto-generated)
└── .github/
    └── workflows/
        └── build-loader-image.yml    # Auto-builds Docker image on push
```

## 🏗️ Architecture Overview

### Consolidated Job Architecture

The system uses **6 consolidated Kubernetes jobs** instead of 40+ individual jobs:

| Job | Wave | Entities Loaded | ConfigMap |
|-----|------|-----------------|-----------|
| `job-01-system-foundation` | 5 | 9 entities (code values, offices, staff, roles, system config) | `fineract-data-system-foundation` |
| `job-02-products` | 10 | 11 entities (loan/savings products, charges, types, rates) | `fineract-data-products` |
| `job-03-accounting` | 21 | 9 entities (chart of accounts, mappings, product accounting) | `fineract-data-accounting` |
| `job-04-entities` | 30 | 5 entities (clients, accounts, collateral, guarantors) | `fineract-data-entities` |
| `job-05-transactions` | 35 | 4 entities (deposits, withdrawals, repayments, transfers) | `fineract-data-transactions` |
| `job-06-calendar` | 40 | 1 entity (holidays) | `fineract-data-calendar` |

### Benefits of Consolidation

- **85% reduction** in Kubernetes overhead (40 → 6 jobs)
- **Faster deployment** (reduced API server load)
- **Simplified monitoring** (6 jobs vs 40)
- **Maintains logical grouping** and wave-based dependency ordering
- **Reuses existing entity loaders** via dynamic importing

### Docker Image Approach

**Code (in Docker image)**: Loader scripts baked into `ghcr.io/adorsys-gis/fineract-loader:v1.0.0`
**Data (in ConfigMaps)**: YAML files mounted via ConfigMaps (with hash suffixes)

When data changes, ConfigMap hash changes, triggering job re-runs via ArgoCD.

**Image Build**: Automatic via GitHub Actions when scripts change
- Registry: GitHub Container Registry (`ghcr.io`)
- Tags: `latest`, commit SHA, `v1.0.0`
- Platforms: `linux/amd64`, `linux/arm64`
- Authentication: Built-in `GITHUB_TOKEN` (no external secrets)

## 🚀 How It Works

### GitOps Data Loading Workflow

```
1. Edit YAML → 2. Git Commit → 3. ArgoCD Sync → 4. ConfigMap Updated → 5. Job Runs → 6. Data Loaded
```

**Example:**

```bash
# 1. Add new loan product
vim data/dev/products/loan-products/sme-loan.yaml

# 2. Validate
python3 scripts/validate_yaml_data.py data/dev/products/loan-products

# 3. Commit
git add data/dev/products/loan-products/sme-loan.yaml
git commit -m "ops: add SME Growth Loan product"
git push

# 4. ArgoCD auto-syncs within 3 minutes
# 5. ConfigMap hash changes → Job 02 (products) re-runs
# 6. Product created in Fineract via API
```

### Wave-Based Job Loading

Jobs run in numbered sequence to handle dependencies:

```
Wave 5:  System Foundation  → Code values, offices, staff, roles, system config
Wave 10: Products           → Loan/savings products, charges, types, rates
Wave 21: Accounting         → Chart of accounts, product accounting mappings
Wave 30: Entities           → Clients, accounts, collateral, guarantors (dev/uat only)
Wave 35: Transactions       → Deposits, withdrawals, repayments, transfers (dev/uat only)
Wave 40: Calendar           → Holidays
```

**ArgoCD Sync Waves** ensure proper order via annotations:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # Wave 10
    argocd.argoproj.io/hook: PostSync
```

### Data Flow Architecture

1. **YAML files** in `data/dev/` directories (e.g., `loan-products/`)
2. **ConfigMap generation** via `generate-configmap-kustomization.py`
3. **Kustomize build** creates ConfigMaps with hash suffixes
4. **ArgoCD syncs** ConfigMaps to Kubernetes
5. **Job mounts** ConfigMap as volume at `/data`
6. **Loader script** reads YAML files, calls Fineract API
7. **Data persists** in Fineract PostgreSQL database

### How Jobs Use Loaders and YAML Data

Each consolidated job dynamically imports multiple entity loaders:

**Example: `load_system_foundation.py`**
```python
# Wave 5 job loads 9 entities sequentially
import loaders.code_values as code_values_loader
import loaders.offices as offices_loader
import loaders.staff as staff_loader
import loaders.roles as roles_loader
import loaders.currency_config as currency_config_loader
import loaders.working_days as working_days_loader
import loaders.account_number_formats as account_formats_loader
import loaders.maker_checker as maker_checker_loader
import loaders.scheduler_jobs as scheduler_jobs_loader

# Run loaders in dependency order
code_values_loader.load(yaml_dir="/data/codes-and-values")
offices_loader.load(yaml_dir="/data/offices")
staff_loader.load(yaml_dir="/data/staff")
# ... etc
```

| Job Loader | Entity Loaders Called | YAML Directories |
|------------|----------------------|------------------|
| `load_system_foundation.py` | 9 loaders | `codes-and-values/`, `offices/`, `staff/`, etc. |
| `load_products.py` | 11 loaders | `products/loan-products/`, `charges/`, etc. |
| `load_accounting.py` | 9 loaders | `accounting/chart-of-accounts/`, etc. |
| `load_entities.py` | 5 loaders | `clients/`, `accounts/`, `loans/` |
| `load_transactions.py` | 4 loaders | `transactions/savings-deposits/`, etc. |
| `load_calendar.py` | 1 loader | `calendar/holidays/` |

## 📝 YAML File Format

### Example: Loan Product

```yaml
apiVersion: fineract.apache.org/v1
kind: LoanProduct
metadata:
  name: personal-loan               # Unique ID (kebab-case)
  labels:
    product-type: loan
    category: personal

spec:
  name: Personal Loan               # Display name
  currency: USD                     # ISO 4217

  principal:
    min: 1000
    default: 5000
    max: 50000

  interestRate:
    min: 12.0
    default: 15.0
    max: 18.0
    type: DECLINING_BALANCE

  numberOfRepayments:
    min: 6
    default: 12
    max: 36

  repaymentEvery: 1
  repaymentFrequency: MONTHS
```

### Example: Office

```yaml
apiVersion: fineract.apache.org/v1
kind: Office
metadata:
  name: branch-office-001

spec:
  name: Downtown Branch
  externalId: BR-001
  parentOffice: head-office
  openingDate: "2024-01-01"

  address:
    street: 123 Main Street
    city: New York
    postalCode: "10001"
    country: USA

  contact:
    phone: "+1-212-555-0100"
    email: downtown@example.com

  status: ACTIVE
```

## 🔧 Creating New Configuration

### 1. Create YAML File

```bash
# Use existing file as template
cp data/dev/products/loan-products/personal-loan.yaml \
   data/dev/products/loan-products/sme-loan.yaml

# Edit values
vim data/dev/products/loan-products/sme-loan.yaml
```

### 2. Regenerate ConfigMaps

```bash
cd operations/fineract-data

# Regenerate kustomization.yaml with new ConfigMaps
python3 scripts/generate-configmap-kustomization.py --output kustomization.yaml

# Verify ConfigMaps
kustomize build . | grep 'kind: ConfigMap'
```

### 3. Commit and Push

```bash
git add data/dev/products/loan-products/sme-loan.yaml
git add kustomization.yaml
git commit -m "ops: add SME loan product"
git push
```

### 4. Monitor Deployment

```bash
# Watch ArgoCD sync
KUBECONFIG=~/.kube/config-fineract-dev argocd app get fineract-dev-data-loader

# Check job status
KUBECONFIG=~/.kube/config-fineract-dev kubectl get jobs -n fineract-dev

# View logs
KUBECONFIG=~/.kube/config-fineract-dev kubectl logs -n fineract-dev job/fineract-data-products
```

## 🔄 Updating Configuration

### Change Interest Rate

```bash
# 1. Edit file
vim data/dev/products/loan-products/personal-loan.yaml

# Change:
# interestRate:
#   default: 15.0  # Changed from 14.0

# 2. Regenerate ConfigMaps
python3 scripts/generate-configmap-kustomization.py --output kustomization.yaml

# 3. See diff
git diff data/dev/products/loan-products/personal-loan.yaml

# 4. Commit
git add data/dev/products/loan-products/personal-loan.yaml
git add kustomization.yaml
git commit -m "ops: increase personal loan rate from 14% to 15%"
git push

# 5. ArgoCD auto-applies (ConfigMap hash changes → job re-runs)
```

## 📊 Monitoring

### Job Status

```bash
# List all data loader jobs
kubectl get jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader

# Check specific job
kubectl describe job fineract-data-products -n fineract-dev

# View logs
kubectl logs -n fineract-dev job/fineract-data-products --tail=100
```

### Verify Data in Fineract

```bash
# Port-forward to Fineract
kubectl port-forward -n fineract-dev svc/fineract 8080:8080

# Check if data was loaded
curl -u admin:password http://localhost:8080/fineract-provider/api/v1/offices
curl -u admin:password http://localhost:8080/fineract-provider/api/v1/loanproducts
```

## 🔍 Troubleshooting

### Job Failed

```bash
# Check job status
kubectl get job fineract-data-products -n fineract-dev

# View logs
kubectl logs -n fineract-dev job/fineract-data-products

# Check pod events
kubectl describe pod -n fineract-dev <pod-name>
```

### Common Issues

**1. Image Pull Error**
- Ensure GitHub Container Registry is accessible
- Check image exists: `ghcr.io/adorsys-gis/fineract-loader:v1.0.0`
- Verify GITHUB_TOKEN has `packages:read` permission

**2. ConfigMap Not Found**
- Regenerate kustomization.yaml: `python3 scripts/generate-configmap-kustomization.py`
- Verify ConfigMap names match job manifests

**3. Authentication Failed**
- Verify Secret exists: `kubectl get secret fineract-admin-credentials`
- Check credentials are correct

**4. YAML Syntax Error**
- Run validation: `python3 scripts/validate_yaml_data.py data/dev/`
- Check YAML syntax online

## 🏭 Production Considerations

### What Goes in Production

✅ **DO include:**
- System configurations
- Offices and organizational structure
- Products (loan/savings)
- Fees and charges
- Accounting configurations
- Code values
- Holidays, roles, templates

❌ **DO NOT include:**
- Demo/test clients (Wave 30+)
- Demo loan accounts
- Test transactions
- Dummy data

### Security

- Secrets stored in Kubernetes Secrets
- Fineract credentials from Secret
- No credentials in YAML files
- Git history is clean
- Docker image in private registry (GHCR)

### Change Management

1. **Create PR** for all production changes
2. **Review** by product/compliance team
3. **Test in UAT** first
4. **Approve** PR
5. **Merge** to trigger deployment
6. **Monitor** job execution

## 📚 References

- [Fineract API Documentation](https://demo.fineract.dev/fineract-provider/api-docs/apiLive.htm)
- [YAML Specification](https://yaml.org/spec/1.2.2/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

---

**All Fineract configuration is now managed as code with full Git history!** 🎉
