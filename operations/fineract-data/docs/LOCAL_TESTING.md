# Local Testing Guide

Complete guide for testing Fineract data loaders locally before deployment.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Setup Local Environment](#setup-local-environment)
- [Testing Strategies](#testing-strategies)
- [Testing Individual Loaders](#testing-individual-loaders)
- [Testing All Loaders](#testing-all-loaders)
- [Dry-Run Mode](#dry-run-mode)
- [YAML Validation](#yaml-validation)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Quick Start

```bash
# 1. Start local Fineract
docker-compose up -d

# 2. Wait for services to be ready (2-3 minutes)
docker-compose logs -f fineract-server

# 3. Test all loaders
./scripts/test_all_loaders.sh

# 4. Stop services
docker-compose down
```

---

## Prerequisites

### Required Software

- **Docker** (20.10+) and Docker Compose (v2.0+)
- **Python** (3.9+)
- **Git**

### Python Dependencies

```bash
pip install pyyaml requests
```

### Optional Tools

- `kubectl` - For testing Kubernetes manifests
- `kustomize` - For validating kustomize builds
- `jq` - For JSON processing in tests

---

## Setup Local Environment

### 1. Start Local Fineract with Docker Compose

The `docker-compose.yml` file provides a complete local environment:

```bash
# Start all services (Fineract + MySQL + Keycloak)
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f fineract-server
```

**Services Provided:**
- **Fineract** - `http://localhost:8443` (HTTPS) or `http://localhost:8080` (HTTP)
- **MySQL** - `localhost:3306`
- **Keycloak** - `http://localhost:8090` (optional, for OAuth2)

**Default Credentials:**
- Fineract: `mifos` / `password`
- MySQL root: `root` / `mysql`
- Keycloak admin: `admin` / `admin`

### 2. Wait for Fineract to be Ready

Fineract takes 2-3 minutes to start. Check readiness:

```bash
# Check health endpoint
curl -k https://localhost:8443/fineract-provider/actuator/health

# Or watch logs until you see "Started Apache Fineract"
docker-compose logs -f fineract-server | grep "Started"
```

### 3. Set Environment Variables (Optional)

```bash
# Basic Auth (default)
export FINERACT_USERNAME=mifos
export FINERACT_PASSWORD=password

# OAuth2 (if using Keycloak)
export FINERACT_CLIENT_ID=fineract-client
export FINERACT_CLIENT_SECRET=your-secret
export FINERACT_TOKEN_URL=http://localhost:8090/realms/fineract/protocol/openid-connect/token
```

---

## Testing Strategies

### 1. Unit Testing (Fastest)
Test individual loader logic with actual data:
```bash
python3 scripts/loaders/offices.py \
  --yaml-dir data/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default
```

### 2. Integration Testing (Comprehensive)
Test full data loading with real datasets:
```bash
./scripts/test_all_loaders.sh
```

### 3. Dry-Run Testing (No Changes)
Preview changes without applying:
```bash
python3 scripts/loaders/offices.py \
  --yaml-dir data/dev/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default \
  --dry-run
```

### 4. YAML Validation (No API Calls)
Validate YAML syntax and schema:
```bash
python3 scripts/validate_yaml_data.py data/dev/
```

---

## Testing Individual Loaders

### Basic Usage

```bash
python3 scripts/loaders/{loader_name}.py \
  --yaml-dir data/dev/{entity-type} \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default
```

### Examples

**Test Code Values:**
```bash
python3 scripts/loaders/code_values.py \
  --yaml-dir data/dev/codes-and-values \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default
```

**Test Offices:**
```bash
python3 scripts/loaders/offices.py \
  --yaml-dir data/dev/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default
```

**Test with Real Data:**
```bash
python3 scripts/loaders/offices.py \
  --yaml-dir data/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default
```

### Loader Dependencies

Loaders must run in dependency order. Follow sync waves:

**Wave 1-3 (Foundation):**
1. code_values
2. offices
3. staff
4. roles
5. currency_config
6. working_days

**Wave 4-9 (System Config):**
7. holidays
8. data_tables
9. payment_types
10. notification_templates
11. reports
12. maker_checker
13. sms_gateway
14. scheduler_jobs
15. account_number_formats
16. tellers

**Wave 10-14 (Accounting):**
17. chart_of_accounts
18. tax_groups
19. delinquency_buckets
20. loan_provisioning
21. floating_rates
22. fund_sources
23. collateral_types
24. guarantor_types

**Wave 15 (Charges):**
25. charges

**Wave 20-21 (Products):**
26. loan_products
27. savings_products
28. loan_product_accounting
29. savings_product_accounting
30. financial_activity_mappings
31. payment_type_accounting

---

## Testing All Loaders

### Comprehensive Test Script

The `test_all_loaders.sh` script tests all 39 loaders in dependency order:

```bash
# Test all loaders
./scripts/test_all_loaders.sh

# Test with verbose output
./scripts/test_all_loaders.sh --verbose

# Test specific loader
./scripts/test_all_loaders.sh --loader code_values

# Test against custom Fineract instance
./scripts/test_all_loaders.sh --url http://localhost:8443/fineract-provider/api/v1
```

### Script Features

✅ **Dependency-Ordered** - Tests loaders in sync wave order
✅ **Color-Coded Output** - Green (passed), Red (failed), Yellow (skipped)
✅ **Summary Report** - Shows passed/failed/skipped counts
✅ **Dry-Run Support** - Preview changes without applying
✅ **Verbose Mode** - Detailed output for debugging
✅ **Connection Test** - Validates Fineract accessibility

### Example Output

```
╔════════════════════════════════════════════════════════════════╗
║         Fineract Data Loaders - Comprehensive Test Suite      ║
╚════════════════════════════════════════════════════════════════╝

Testing Fineract connection...
✓ Fineract is accessible at http://localhost:8443/fineract-provider/api/v1

═══ WAVE 1-3: Foundation ═══

Testing: code_values (Code Values)
  ✓ PASSED

Testing: offices (Offices)
  ✓ PASSED

...

╔════════════════════════════════════════════════════════════════╗
║                         Test Summary                           ║
╚════════════════════════════════════════════════════════════════╝

  Total:   39
  Passed:  35
  Failed:  0
  Skipped: 4

All tests passed!
```

---

## Dry-Run Mode

Dry-run mode previews changes without making actual API calls.

### Enable Dry-Run

**Individual Loader:**
```bash
python3 scripts/loaders/offices.py \
  --yaml-dir data/dev/offices \
  --fineract-url http://localhost:8443/fineract-provider/api/v1 \
  --tenant default \
  --dry-run
```

**All Loaders:**
```bash
./scripts/test_all_loaders.sh --dry-run
```

### Dry-Run Output

```
[DRY-RUN] Would POST to /offices
[DRY-RUN] Payload: {"name": "Test Office", "openingDate": "2024-01-01", ...}
```

### Benefits

- ✅ Preview changes before applying
- ✅ Validate YAML transformation logic
- ✅ Test without modifying Fineract
- ✅ Safe for production environments

---

## YAML Validation

### Validate YAML Syntax

```bash
# Validate all YAML files
python3 scripts/validate_yaml_data.py data/dev/

# Validate specific directory
python3 scripts/validate_yaml_data.py data/dev/accounting/chart-of-accounts/

# Verbose output
python3 scripts/validate_yaml_data.py data/dev/ --verbose
```

### What is Validated

✅ **YAML Syntax** - Valid YAML format
✅ **Fineract Structure** - Required fields (apiVersion, kind, metadata, spec)
✅ **Entity-Specific Rules** - Field types, enums, patterns
✅ **JSON Schema** - Schema compliance for each entity type

### Example Output

```
Validating: data/dev/offices/yaounde-branch.yaml
✓ Valid YAML syntax
✓ Has required Fineract structure
✓ Schema validation passed

Summary:
Total files: 50
Valid: 50
Invalid: 0
```

---

## Troubleshooting

### Fineract Not Starting

**Problem:** Docker container starts but Fineract not accessible

**Solution:**
```bash
# Check logs
docker-compose logs fineract-server

# Common issue: MySQL not ready
# Wait 2-3 minutes for MySQL initialization

# Restart if needed
docker-compose restart fineract-server
```

### Connection Refused

**Problem:** `Connection refused` error when testing

**Solutions:**
1. **Check Fineract is running:**
   ```bash
   curl -k https://localhost:8443/fineract-provider/actuator/health
   ```

2. **Use HTTP instead of HTTPS:**
   ```bash
   --fineract-url http://localhost:8080/fineract-provider/api/v1
   ```

3. **Check Docker container status:**
   ```bash
   docker-compose ps
   ```

### Authentication Errors

**Problem:** `401 Unauthorized` errors

**Solutions:**
1. **Verify credentials:**
   ```bash
   curl -u mifos:password -k https://localhost:8443/fineract-provider/api/v1/offices
   ```

2. **Set environment variables:**
   ```bash
   export FINERACT_USERNAME=mifos
   export FINERACT_PASSWORD=password
   ```

3. **Check Basic Auth is enabled** in Fineract

### Loader Fails with Dependencies

**Problem:** Loader fails because dependency entities don't exist

**Solution:** Run loaders in dependency order (use `test_all_loaders.sh`)

Example dependency chain:
```
code_values → offices → staff → loan_accounts
             ↓
        loan_products
```

### YAML Validation Errors

**Problem:** YAML validation fails

**Common Issues:**
1. **Indentation errors** - Use 2 spaces, not tabs
2. **Missing required fields** - Check schema documentation
3. **Invalid field types** - Strings vs numbers
4. **Invalid enum values** - Check allowed values

**Debug:**
```bash
# Use verbose mode
python3 scripts/validate_yaml_data.py data/dev/offices/ --verbose

# Check specific file
python3 -c "import yaml; print(yaml.safe_load(open('file.yaml')))"
```

---

## Best Practices

### 1. Always Test in Order

Follow sync wave order to avoid dependency errors:
```bash
# Use the comprehensive test script
./scripts/test_all_loaders.sh
```

### 2. Use Dry-Run First

Preview changes before applying:
```bash
python3 scripts/loaders/offices.py --yaml-dir data/dev/offices --dry-run
```

### 3. Validate YAML Before Loading

Catch errors early:
```bash
python3 scripts/validate_yaml_data.py data/dev/
```

### 4. Test with Small Datasets First

Start with smaller entity types for fast iteration:
```bash
# Offices are small and have few dependencies
python3 scripts/loaders/offices.py --yaml-dir data/offices
```

### 5. Use Verbose Mode for Debugging

Get detailed output when troubleshooting:
```bash
./scripts/test_all_loaders.sh --verbose
```

### 6. Clean Up Test Data

After testing, clean up test entities:
- Via Fineract UI (Admin → Manage)
- Or delete Docker volumes and restart

### 7. Version Control

Commit working configurations:
```bash
git add data/dev/
git commit -m "test: validated office configurations"
```

### 8. Document Custom Test Scenarios

Create custom test scripts for specific workflows:
```bash
#!/bin/bash
# custom-test.sh - Test loan workflow

# 1. Load prerequisites
python3 scripts/loaders/code_values.py --yaml-dir data/dev/codes-and-values
python3 scripts/loaders/offices.py --yaml-dir data/dev/offices
python3 scripts/loaders/chart_of_accounts.py --yaml-dir data/dev/accounting/chart-of-accounts

# 2. Load loan products
python3 scripts/loaders/loan_products.py --yaml-dir data/dev/products/loan-products

# 3. Validate
curl -k https://localhost:8443/fineract-provider/api/v1/loanproducts
```

---

## Testing Checklist

Before deploying to production:

- [ ] YAML validation passes for all files
- [ ] All loaders pass with dev data
- [ ] Dry-run mode shows expected changes
- [ ] Dependencies load in correct order
- [ ] No authentication/authorization errors
- [ ] Reference resolution works (GL accounts, offices, etc.)
- [ ] Idempotent (can re-run safely)
- [ ] Test data cleanup completed
- [ ] Documentation updated

---

## Next Steps

After successful local testing:

1. **Deploy to Dev Environment:**
   ```bash
   kubectl apply -k kubernetes/ -n fineract-dev
   ```

2. **Monitor Job Execution:**
   ```bash
   kubectl get jobs -n fineract-dev -w
   ```

3. **Review Logs:**
   ```bash
   kubectl logs -n fineract-dev job/fineract-data-offices
   ```

4. **Promote to UAT/Production** after validation

---

## Additional Resources

- **Main README**: `../README.md` - Complete project documentation
- **Deployment Guide**: `kubernetes/docs/DEPLOYMENT_GUIDE.md` - Production deployment
- **Quick Reference**: `kubernetes/docs/QUICK_REFERENCE.md` - Command reference
- **Loader Documentation**: `scripts/loaders/README.md` - Loader development guide
- **Schema Documentation**: `schemas/README.md` - Schema validation guide

---

**Happy Testing!** 🚀
