# Fineract Data Loader - Quick Reference

## 🚀 One-Line Deploy

```bash
cd operations/fineract-data/kubernetes && ./generate-configmaps.sh && kubectl apply -f configmap-scripts-generated.yaml -f configmap-data-generated.yaml && kubectl apply -k . && ./deploy.sh
```

---

## 📋 Essential Commands

### Setup
```bash
# Create required secrets
kubectl create secret generic fineract-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=<password> \
  -n fineract-dev

kubectl create secret generic keycloak-admin-credentials \
  --from-literal=client-id=admin-cli \
  --from-literal=client-secret=<secret> \
  -n fineract-dev
```

### Deploy
```bash
# Generate ConfigMaps
cd operations/fineract-data/kubernetes
./generate-configmaps.sh

# Apply ConfigMaps
kubectl apply -f configmap-scripts-generated.yaml
kubectl apply -f configmap-data-generated.yaml

# Deploy jobs
kubectl apply -k .

# Monitor
./deploy.sh
```

### Monitor
```bash
# Watch all jobs
kubectl get jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader -w

# Check specific job
kubectl logs job/fineract-data-loan-products -n fineract-dev

# List all jobs with status
kubectl get jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader
```

### Debug
```bash
# View job details
kubectl describe job fineract-data-<loader> -n fineract-dev

# View pod logs
kubectl logs -l job-name=fineract-data-<loader> -n fineract-dev --tail=100

# Re-run failed job
kubectl delete job fineract-data-<loader> -n fineract-dev
kubectl apply -f jobs/job-<loader>.yaml
```

### Cleanup
```bash
# Delete all jobs
kubectl delete jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader

# Delete ConfigMaps
kubectl delete configmap fineract-loader-scripts fineract-data-dev -n fineract-dev

# Delete everything
kubectl delete -k .
```

---

## 📊 Loader List (21 Total)

### Wave 1-6: Foundation & Config
```
1  code-values              System codes
2  offices                  Organization hierarchy
3  staff                    Staff members
3  roles                    User roles
3  currency-config          Currency setup
3  working-days             Working days
4  holidays                 Holiday calendar
5  payment-types            Payment methods
5  account-number-formats   Account numbering
6  tellers                  Teller stations
```

### Wave 10-14: Accounting
```
10 chart-of-accounts        GL accounts
11 tax-groups               Tax configuration
12 floating-rates           Interest rates
13 fund-sources             Fund sources
14 collateral-types         Collateral types
```

### Wave 15-21: Products
```
15 charges                  Fees and charges
20 loan-products            Loan products
20 savings-products         Savings products
21 savings-product-accounting    Product GL mapping
21 financial-activity-mappings   Activity GL mapping
```

---

## 🧪 Test Commands

### Test Locally
```bash
# Single loader
python3 scripts/loaders/loan_products.py \
  --yaml-dir data/dev/products/loan-products \
  --fineract-url https://api.dev.fineract.com \
  --tenant default

# All loaders (dry run)
./test_deployment_locally.sh
```

### Validate YAML
```bash
# Validate specific directory
python3 scripts/validate_yaml_data.py data/dev/products/loan-products

# Validate all
find data/dev -name "*.yaml" -exec python3 scripts/validate_yaml_data.py {} \;
```

---

## 📁 Data Directory Quick Map

```
data/dev/
├── codes-and-values/       → job-code-values
├── offices/                → job-offices
├── staff/                  → job-staff
├── roles/                  → job-roles
├── system-config/          → job-currency-config, job-working-days
├── calendar/               → job-holidays
├── payment-types/          → job-payment-types
├── accounts/               → job-account-number-formats
├── tellers/                → job-tellers
├── accounting/
│   ├── chart-of-accounts/  → job-chart-of-accounts
│   ├── tax-groups/         → job-tax-groups
│   ├── fund-sources/       → job-fund-sources
│   ├── financial-activities/ → job-financial-activity-mappings
│   └── product-mappings/   → job-savings-product-accounting
├── floating-rates/         → job-floating-rates
├── collateral-types/       → job-collateral-types
├── charges/                → job-charges
└── products/
    ├── loan-products/      → job-loan-products
    └── savings-products/   → job-savings-products
```

---

## 🔍 Troubleshooting Quick Fixes

### Job Stuck in Pending
```bash
kubectl describe pod -l job-name=fineract-data-<loader> -n fineract-dev
# Check: ConfigMap exists, secrets exist, resources available
```

### Job Failed
```bash
kubectl logs job/fineract-data-<loader> -n fineract-dev --tail=50
# Common: API unreachable, invalid credentials, missing dependencies
```

### ConfigMap Too Large
```bash
# Check size
kubectl get configmap fineract-data-dev -n fineract-dev -o yaml | wc -c
# If > 1MB, use PersistentVolume instead
```

### Re-run All Jobs
```bash
kubectl delete jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader
kubectl apply -k .
```

---

## 🎯 Common Scenarios

### First Time Setup
```bash
1. Create secrets (see Setup section)
2. Generate ConfigMaps
3. Deploy jobs
4. Monitor until all complete
```

### Update Data
```bash
1. Edit YAML files in data/dev/
2. Regenerate data ConfigMap
3. Delete specific job(s)
4. Reapply job(s)
```

### Add New Loader
```bash
1. Create loader script in scripts/loaders/
2. Create job manifest in kubernetes/jobs/
3. Add to kustomization.yaml
4. Regenerate scripts ConfigMap
5. Deploy
```

---

## 🔑 Environment Variables

### Required for All Loaders
```yaml
FINERACT_URL: "https://api.dev.fineract.com"
TENANT: "default"
FINERACT_USER: (from secret)
FINERACT_PASS: (from secret)
```

### Required for Staff Loader
```yaml
KEYCLOAK_URL: "https://auth.dev.fineract.com"
KEYCLOAK_CLIENT_ID: (from secret)
KEYCLOAK_CLIENT_SECRET: (from secret)
```

---

## 📞 Support

- **Logs**: `kubectl logs job/<job-name> -n fineract-dev`
- **Docs**: See DEPLOYMENT_GUIDE.md
- **Test**: `./test_deployment_locally.sh`
- **Issues**: Check GitHub issues

---

## ✅ Success Checklist

- [ ] Secrets created
- [ ] ConfigMaps generated
- [ ] Jobs deployed
- [ ] All jobs completed
- [ ] Fineract configured
- [ ] Data validated

---

*Quick Reference v2.0 - 21 Loaders*