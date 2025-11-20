# Scripts - Utility Scripts & Automation

This directory contains utility scripts for deployment, testing, validation, and maintenance of the Fineract GitOps platform.

---

## Overview

The scripts directory provides automation for:
- **Secrets Management** - Creating, checking, and cleaning up secrets
- **Configuration Management** - Template generation and placeholder replacement
- **Testing & Validation** - Component testing and deployment validation
- **Development Tools** - Local development utilities

---

## Quick Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `create-all-sealed-secrets.sh` | Create all sealed secrets for an environment | `./create-all-sealed-secrets.sh dev` |
| `check-plaintext-secrets.sh` | Check for plaintext secrets in Git | `./check-plaintext-secrets.sh` |
| `remove-plaintext-secrets.sh` | Remove plaintext secrets from repo | `./remove-plaintext-secrets.sh` |
| `replace-placeholders.sh` | Replace placeholders with actual values | `./replace-placeholders.sh` |
| `validate-deployment.sh` | Validate full deployment | `./validate-deployment.sh dev` |
| `validate-data.py` | Validate YAML configuration data | `./validate-data.py` |
| `test-argocd.sh` | Test ArgoCD functionality | `./test-argocd.sh` |
| `test-backups.sh` | Test backup procedures | `./test-backups.sh dev` |
| `test-kafka.sh` | Test Kafka messaging | `./test-kafka.sh dev` |
| `test-logging.sh` | Test logging stack | `./test-logging.sh dev` |
| `test-minio.sh` | Test MinIO/S3 storage | `./test-minio.sh dev` |
| `test-monitoring.sh` | Test monitoring stack | `./test-monitoring.sh dev` |
| `dev-proxy.sh` | Start local proxy for development | `./dev-proxy.sh` |
| `COMPLETE_FRONTEND_SETUP.sh` | Complete frontend app setup | `./COMPLETE_FRONTEND_SETUP.sh` |
| `generate-yaml-templates.sh` | Generate YAML templates | `./generate-yaml-templates.sh` |

---

## Secrets Management Scripts

### create-all-sealed-secrets.sh

**Purpose**: Automate creation of all sealed secrets for an environment

**Usage**:
```bash
./scripts/create-all-sealed-secrets.sh <environment>

# Examples:
./scripts/create-all-sealed-secrets.sh dev
./scripts/create-all-sealed-secrets.sh uat
./scripts/create-all-sealed-secrets.sh production
```

**What it does**:
1. Generates strong random passwords for all services
2. Creates Kubernetes secrets with proper formatting
3. Seals secrets using kubeseal
4. Saves sealed secrets to `secrets/<environment>/`
5. Provides summary of created secrets

**Secrets created**:
- PostgreSQL credentials
- Redis password
- MinIO access keys
- Keycloak admin credentials
- Grafana admin credentials
- Message gateway credentials
- Fineract database credentials

**Prerequisites**:
- `kubeseal` CLI installed
- `kubectl` configured
- Sealed Secrets controller deployed
- Write access to `secrets/` directory

**Example output**:
```
Creating sealed secrets for environment: dev
✓ Created: postgresql-credentials
✓ Created: redis-password
✓ Created: minio-credentials
✓ Created: keycloak-admin-credentials
✓ Created: grafana-admin-credentials

Summary: 5 sealed secrets created in secrets/dev/
Next step: kubectl apply -f secrets/dev/
```

---

### check-plaintext-secrets.sh

**Purpose**: Scan repository for accidentally committed plaintext secrets

**Usage**:
```bash
./scripts/check-plaintext-secrets.sh
```

**What it does**:
1. Searches for `kind: Secret` in YAML files
2. Checks for base64-encoded data (plaintext secrets)
3. Ignores sealed secrets and templates
4. Reports files containing plaintext secrets
5. Exits with error code if secrets found

**When to use**:
- Before committing changes
- In CI/CD pipelines (pre-commit check)
- During security audits
- Regular repository scans

**Example output**:
```
Checking for plaintext secrets in Git...

⚠ WARNING: Plaintext secrets found in:
  - secrets/dev/database-secret.yaml (NOT SEALED)
  - apps/keycloak/base/admin-secret.yaml (NOT SEALED)

ERROR: 2 plaintext secrets detected!
Please seal them with kubeseal or remove from repository.
```

**CI/CD Integration**:
```yaml
# .github/workflows/security-check.yml
- name: Check for Plaintext Secrets
  run: ./scripts/check-plaintext-secrets.sh
```

---

### remove-plaintext-secrets.sh

**Purpose**: Remove plaintext secrets from repository (cleanup utility)

**Usage**:
```bash
# Dry run (show what would be removed)
./scripts/remove-plaintext-secrets.sh --dry-run

# Actually remove plaintext secrets
./scripts/remove-plaintext-secrets.sh
```

**What it does**:
1. Finds all plaintext secrets in repository
2. Creates backup before deletion
3. Removes plaintext secret files
4. Unstages secrets from Git
5. Reports removed files

**Safety features**:
- Creates backup directory
- Requires confirmation
- Dry-run mode available
- Only removes unsealed secrets

**Example output**:
```
Removing plaintext secrets from repository...

Backup created: .backup/secrets-20251028-143022/

Removing plaintext secrets:
  ✓ Removed: secrets/dev/database-secret.yaml
  ✓ Removed: apps/keycloak/base/admin-secret.yaml

Summary: 2 plaintext secrets removed
Backup location: .backup/secrets-20251028-143022/
```

---

### replace-placeholders.sh

**Purpose**: Replace placeholder values with environment-specific configurations

**Usage**:
```bash
./scripts/replace-placeholders.sh
```

**What it does**:
1. Scans for placeholder patterns (e.g., `YOUR_DOMAIN`, `YOUR_EMAIL`)
2. Prompts for replacement values
3. Replaces placeholders across all files
4. Creates backup before replacement
5. Reports files modified

**Common placeholders**:
- `YOUR_DOMAIN` → Actual domain name
- `YOUR_EMAIL` → Admin email address
- `YOUR_CLUSTER_NAME` → Kubernetes cluster name
- `YOUR_REGION` → Cloud region
- `YOUR_PROJECT_ID` → Cloud project ID

**Example**:
```bash
$ ./scripts/replace-placeholders.sh

Found placeholders:
  - YOUR_DOMAIN (5 files)
  - YOUR_EMAIL (3 files)
  - YOUR_CLUSTER_NAME (2 files)

Enter replacement for YOUR_DOMAIN: fineract.example.com
Enter replacement for YOUR_EMAIL: admin@example.com
Enter replacement for YOUR_CLUSTER_NAME: fineract-prod

Replacing placeholders...
✓ Updated: argocd/config/argocd-cm.yaml
✓ Updated: apps/apache-gateway/base/configmap.yaml
✓ Updated: terraform/aws/variables.tf

Summary: 10 files updated
```

---

## Testing & Validation Scripts

### validate-deployment.sh

**Purpose**: Comprehensive deployment validation across all components

**Usage**:
```bash
./scripts/validate-deployment.sh <environment>

# Examples:
./scripts/validate-deployment.sh dev
./scripts/validate-deployment.sh uat
./scripts/validate-deployment.sh production
```

**What it validates**:
1. **Kubernetes Cluster**: Connectivity, version, storage classes
2. **Namespaces**: All required namespaces exist
3. **Sealed Secrets**: Controller running, secrets decrypted
4. **Databases**: PostgreSQL/Redis running and accessible
5. **Storage**: MinIO/S3 accessible
6. **Applications**: Fineract instances healthy
7. **Gateway**: Apache Gateway responding
8. **Monitoring**: Prometheus/Grafana accessible
9. **Logging**: Loki/Promtail running
10. **ArgoCD**: Applications synced

**Example output**:
```
Validating deployment for environment: dev
======================================

✓ Kubernetes cluster: Connected (v1.28.3)
✓ Namespace: fineract-dev (active)
✓ Sealed Secrets: Controller running
✓ PostgreSQL: 1/1 pods ready
✓ Redis: 1/1 pods ready
✓ MinIO: 1/1 pods ready
✓ Fineract Read: 2/2 pods ready
✓ Fineract Write: 2/2 pods ready
✓ Fineract Batch: 1/1 pods ready
✓ Apache Gateway: 2/2 pods ready
✓ Monitoring: Prometheus (1/1), Grafana (1/1)
✓ Logging: Loki (1/1), Promtail (3/3)
✓ ArgoCD: 12/12 applications synced

Summary: All validations passed ✓
Deployment is healthy and ready!
```

**Exit codes**:
- `0` = All validations passed
- `1` = One or more validations failed

---

### test-argocd.sh

**Purpose**: Test ArgoCD installation and application sync

**Usage**:
```bash
./scripts/test-argocd.sh
```

**What it tests**:
- ArgoCD server accessibility
- CLI login functionality
- Application health status
- Sync status of all apps
- Repository connectivity

---

### test-backups.sh

**Purpose**: Test backup procedures and restore capability

**Usage**:
```bash
./scripts/test-backups.sh <environment>

# Example:
./scripts/test-backups.sh dev
```

**What it tests**:
1. Backup CronJob configured
2. MinIO backup bucket accessible
3. Manual backup execution
4. Backup file verification
5. Restore procedure (dry-run)

**Example output**:
```
Testing backup procedures for environment: dev
============================================

✓ Backup CronJob: postgresql-backup exists
✓ MinIO bucket: fineract-backups accessible
✓ Manual backup: Created backup-20251028-143500.sql
✓ Backup verification: File size 125MB, valid SQL
✓ Restore test: Dry-run successful

Summary: All backup tests passed ✓
```

---

### test-kafka.sh

**Purpose**: Test Kafka messaging functionality

**Usage**:
```bash
./scripts/test-kafka.sh <environment>
```

**What it tests**:
- Kafka broker accessibility
- Topic creation
- Message production
- Message consumption
- Zookeeper connectivity

---

### test-logging.sh

**Purpose**: Test logging stack (Loki + Promtail)

**Usage**:
```bash
./scripts/test-logging.sh <environment>
```

**What it tests**:
- Loki API accessibility
- Promtail log collection
- Log query functionality
- Log retention
- Grafana Loki datasource

**Example output**:
```
Testing logging stack for environment: dev
========================================

✓ Loki API: Accessible at http://loki:3100
✓ Promtail: 3 pods collecting logs
✓ Log ingestion: 1,234 log lines in last 5 minutes
✓ Query test: Successfully queried {namespace="fineract-dev"}
✓ Grafana datasource: Loki connected

Summary: Logging stack operational ✓
```

---

### test-minio.sh

**Purpose**: Test MinIO/S3 object storage

**Usage**:
```bash
./scripts/test-minio.sh <environment>
```

**What it tests**:
- MinIO server accessibility
- Bucket creation
- Object upload/download
- Access credentials
- Bucket policies

**Example output**:
```
Testing MinIO for environment: dev
=================================

✓ MinIO server: Accessible at http://minio:9000
✓ Authentication: Credentials valid
✓ Bucket creation: Created test-bucket-xyz
✓ Object upload: Uploaded 1MB test file
✓ Object download: Downloaded and verified
✓ Bucket cleanup: Removed test-bucket-xyz

Summary: MinIO fully functional ✓
```

---

### test-monitoring.sh

**Purpose**: Test monitoring stack (Prometheus + Grafana)

**Usage**:
```bash
./scripts/test-monitoring.sh <environment>
```

**What it tests**:
- Prometheus metrics collection
- ServiceMonitor configuration
- Alert rules
- Grafana dashboard access
- AlertManager connectivity

**Example output**:
```
Testing monitoring stack for environment: dev
===========================================

✓ Prometheus: Accessible at http://prometheus:9090
✓ Metrics collection: 4 ServiceMonitors active
✓ Targets: 12/12 targets up
✓ Alert rules: 20 rules loaded
✓ Grafana: Accessible at http://grafana:3000
✓ Dashboards: 3 dashboards loaded

Summary: Monitoring stack operational ✓
```

---

## Development Tools

### dev-proxy.sh

**Purpose**: Start local proxy for accessing services during development

**Usage**:
```bash
./scripts/dev-proxy.sh

# Or specify services
./scripts/dev-proxy.sh grafana prometheus
```

**What it does**:
1. Creates kubectl port-forwards for common services
2. Provides local URLs for access
3. Runs in background
4. Auto-restarts on connection loss

**Services proxied**:
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100
- MinIO: http://localhost:9001
- ArgoCD: http://localhost:8080
- Keycloak: http://localhost:8081

**Example output**:
```
Starting development proxy...

✓ Grafana: http://localhost:3000
✓ Prometheus: http://localhost:9090
✓ Loki: http://localhost:3100
✓ MinIO: http://localhost:9001

Press Ctrl+C to stop all proxies
```

---

### COMPLETE_FRONTEND_SETUP.sh

**Purpose**: Complete setup for frontend applications

**Usage**:
```bash
./scripts/COMPLETE_FRONTEND_SETUP.sh
```

**What it does**:
1. Checks for required tools (npm, kubectl)
2. Builds frontend applications
3. Creates Docker images
4. Pushes to registry
5. Deploys to Kubernetes

---

### generate-yaml-templates.sh

**Purpose**: Generate YAML templates for common resources

**Usage**:
```bash
./scripts/generate-yaml-templates.sh <resource-type>

# Examples:
./scripts/generate-yaml-templates.sh deployment
./scripts/generate-yaml-templates.sh service
./scripts/generate-yaml-templates.sh secret
```

---

## Best Practices

### Running Scripts

1. **Always review before running**: Especially for destructive operations
2. **Use dry-run when available**: Test before actual execution
3. **Check prerequisites**: Ensure required tools are installed
4. **Run from repository root**: Scripts expect to be run from project root
5. **Check exit codes**: Use `$?` to verify success

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
name: Validate Deployment

on: [pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Check for Plaintext Secrets
        run: ./scripts/check-plaintext-secrets.sh
```

### Security Considerations

- ✅ Never commit credentials to scripts
- ✅ Use environment variables for sensitive data
- ✅ Set restrictive file permissions (chmod 700)
- ✅ Audit script execution logs
- ✅ Validate inputs to prevent injection

---

## Adding New Scripts

When adding a new script:

1. **Add executable permissions**: `chmod +x script-name.sh`
2. **Include usage documentation**: Help text in script header
3. **Add to this README**: Update the Quick Reference table
4. **Follow naming conventions**: Use kebab-case
5. **Add error handling**: Set `set -e` for bash scripts
6. **Provide examples**: Include example usage in comments
7. **Document prerequisites**: List required tools/permissions

**Template**:
```bash
#!/bin/bash
set -e

# Purpose: [Brief description]
# Usage: ./script-name.sh [args]
# Prerequisites: [List required tools]
# Author: [Your name]
# Date: [Creation date]

# Display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help     Show this help message"
    exit 1
}

# Main script logic
main() {
    # Your code here
}

# Execute main function
main "$@"
```

---

## Troubleshooting

### Common Issues

**Script not found**:
```bash
# Ensure you're in repository root
cd /path/to/fineract-gitops

# Run with ./scripts/
./scripts/script-name.sh
```

**Permission denied**:
```bash
# Make script executable
chmod +x scripts/script-name.sh
```

**kubectl not configured**:
```bash
# Set KUBECONFIG
export KUBECONFIG=~/.kube/config

# Verify connection
kubectl cluster-info
```

**kubeseal not found**:
```bash
# Install kubeseal (v0.27.0 - must match controller)
brew install kubeseal  # macOS
# or
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-linux-amd64
```

---

## Related Documentation

- **[Secrets Management](../docs/SECRETS_MANAGEMENT.md)** - Comprehensive secrets guide
- **[CI/CD Integration](../docs/operations/CI_CD_INTEGRATION.md)** - Pipeline setup
- **[Getting Started](../docs/GETTING_STARTED.md)** - Deployment guide

---

**Last Updated:** 2025-10-28
**Total Scripts:** 15
**Categories:** Secrets (4), Testing (7), Development (2), Configuration (2)
