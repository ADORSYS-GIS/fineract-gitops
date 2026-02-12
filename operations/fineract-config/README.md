# Fineract Config CLI - Kubernetes Integration

**Declarative configuration management for Apache Fineract using GitOps**

This directory contains the Kubernetes job definition for managing Fineract configuration declaratively using YAML files. Inspired by the [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli) pattern, this provides a GitOps workflow for Fineract configuration.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage](#usage)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

---

## Overview

### What is Fineract Config CLI?

Fineract Config CLI is a Spring Boot-based tool that enables **Configuration as Code** for Apache Fineract. It allows you to:

- ✅ Manage Fineract configuration in version-controlled YAML files
- ✅ Apply configurations idempotently (safe to run multiple times)
- ✅ Track configuration changes through Git history
- ✅ Automate configuration deployment via ArgoCD
- ✅ Support 40+ Fineract entity types (offices, roles, products, etc.)

### Key Features

- **Idempotent Operations**: Same config applied multiple times = same result
- **Smart Dependency Resolution**: Auto-resolve entity references (`$office.name`)
- **State Management**: Track managed resources, detect changes via checksums
- **OAuth2 Authentication**: Secure service account authentication via Keycloak
- **Dry-Run Mode**: Preview changes before applying
- **Managed Resource Modes**: Control create/update/delete behavior per entity type

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│  Git Repository (fineract-gitops)                           │
│  ├── operations/fineract-config/base/config/                │
│  │   ├── offices.yml          ← Your config files          │
│  │   ├── roles.yml                                          │
│  │   └── products.yml                                       │
│  └── operations/fineract-config/overlays/dev/               │
└──────────────┬──────────────────────────────────────────────┘
               │
               │ ArgoCD monitors for changes
               ▼
┌─────────────────────────────────────────────────────────────┐
│  ArgoCD (fineract-dev-fineract-config)                      │
│  - Detects ConfigMap hash change                            │
│  - Triggers sync                                            │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Job: apply-fineract-config                      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Init Container 1: wait-for-fineract                    │ │
│  │ - Polls Fineract actuator health endpoint             │ │
│  │ - Max 10 minutes wait time                            │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Init Container 2: substitute-variables                 │ │
│  │ - Processes YAML templates with envsubst              │ │
│  │ - Injects OAuth2 credentials                          │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Main Container: fineract-config-cli                    │ │
│  │ - Authenticates with OAuth2 (Keycloak)               │ │
│  │ - Validates YAML configuration                        │ │
│  │ - Calculates checksum, checks for changes            │ │
│  │ - Applies configuration to Fineract API              │ │
│  │ - Saves state for idempotency                        │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│  Apache Fineract                                            │
│  - Configuration updated via REST API                       │
└─────────────────────────────────────────────────────────────┘
```

### Sync Wave Strategy

The job runs in **ArgoCD PostSync Wave 10**, ensuring:

1. **Wave -5**: Sealed Secrets controller deployed
2. **Wave -1**: Database initialization completed
3. **Wave 0**: Keycloak deployed and healthy
4. **Wave 1**: OAuth2 Proxy deployed
5. **Wave 2**: Redis deployed
6. **Wave 3**: Fineract (write, read, batch) deployed **← Must be healthy first**
7. **Wave 4**: Community App deployed
8. **Wave 10**: **fineract-config-cli runs** ← This job

This ensures Fineract is fully operational before configuration is applied.

---

## Quick Start

### Prerequisites

1. **Keycloak** running with Fineract realm configured
2. **OAuth2 client** (`fineract-data-loader`) with Super User role
3. **Sealed secrets** deployed with `keycloak-client-secrets`
4. **Fineract** deployed and healthy

### Step 1: Add Configuration Files

Create YAML files in `base/config/`:

```bash
cd operations/fineract-config/base/config/

# Example: Create offices configuration
cat > offices.yml <<'EOF'
tenant: default

offices:
  - name: Head Office
    externalId: HO001
    openingDate: [2024, 1, 1]

  - name: Yaoundé Branch
    externalId: YAO001
    parentName: Head Office
    openingDate: [2024, 11, 20]
EOF
```

### Step 2: Update Kustomization

Edit `base/kustomization.yaml` to include your files:

```yaml
configMapGenerator:
  - name: fineract-config-data
    files:
      - config/offices.yml
      - config/roles.yml
      # Add more files as needed
```

### Step 3: Commit and Push

```bash
git add operations/fineract-config/
git commit -m "feat: add Fineract configuration for offices"
git push origin dev/fineract-deployment
```

### Step 4: ArgoCD Auto-Syncs

ArgoCD detects the change and automatically:
1. Generates new ConfigMap with hash suffix
2. Triggers job re-run (due to ConfigMap reference change)
3. Job applies configuration to Fineract

### Step 5: Verify

```bash
# Check job status
kubectl get jobs -n fineract-dev | grep apply-fineract-config

# View job logs
kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli

# Check Fineract offices via API
curl -k https://fineract-write-service:8443/fineract-provider/api/v1/offices
```

---

## Configuration

### Environment Variables

The job is configured via environment variables, which can be overridden in overlays:

#### Fineract Connection
```yaml
FINERACT_BASE_URL: "https://fineract-write-service:8443/fineract-provider"
FINERACT_TENANT: "default"
FINERACT_SSL_VERIFY: "false"  # Internal service, self-signed cert
```

#### Authentication
```yaml
FINERACT_AUTH_TYPE: "oauth2"
FINERACT_AUTH_OAUTH2_TOKEN_URL: "http://keycloak-service:8080/realms/fineract/protocol/openid-connect/token"
FINERACT_AUTH_OAUTH2_CLIENT_ID: "fineract-data-loader"  # From secret
FINERACT_AUTH_OAUTH2_CLIENT_SECRET: "..."  # From secret
```

#### Import Settings
```yaml
IMPORT_FILES_LOCATIONS: "/config-processed/*.yml"
IMPORT_VALIDATE: "true"  # Validate before applying
IMPORT_PARALLEL: "false"  # Sequential processing
IMPORT_DRY_RUN: "false"  # Actually apply changes
IMPORT_FORCE: "false"  # Respect checksums (idempotent)
```

#### State Management
```yaml
IMPORT_REMOTE_STATE_ENABLED: "true"  # Track state in Fineract
IMPORT_REMOTE_STATE_CHECKSUM_BEHAVIOR: "continue"  # Skip if unchanged
```

#### Managed Resource Modes

Control create/update/delete behavior per entity type:

```yaml
# no-delete: Create and update, but never delete
IMPORT_MANAGED_OFFICE: "no-delete"
IMPORT_MANAGED_ROLE: "no-delete"
IMPORT_MANAGED_CLIENT: "no-delete"

# full: Create, update, AND delete resources not in YAML
IMPORT_MANAGED_LOANPRODUCT: "full"
IMPORT_MANAGED_SAVINGSPRODUCT: "full"
```

**Modes**:
- **`no-delete`**: Safe mode - preserves resources not in YAML
- **`full`**: Strict declarative - deletes unmanaged resources

### Environment-Specific Settings

#### Development (`overlays/dev`)
- All managed modes: `no-delete` (preserve everything)
- Logging: `DEBUG`
- Image: `latest` tag (auto-update)

#### UAT (`overlays/uat`)
- Mixed modes: `full` for config, `no-delete` for data
- Logging: `INFO`
- Image: `latest` tag

#### Production (`overlays/production`)
- Managed modes: `full` for all config entities
- Manual approval required in ArgoCD
- Image: Specific version tag (e.g., `1.0.0`)
- SSL verification: enabled

---

## Usage

### Adding New Configuration

1. **Create YAML file** in `base/config/`:
   ```yaml
   # base/config/loan-products.yml
   tenant: default

   loanProducts:
     - name: Personal Loan
       shortName: PL
       currencyCode: USD
       principal: 10000
       numberOfRepayments: 12
       interestRatePerPeriod: 12.0
       # ... more fields
   ```

2. **Update kustomization** to include the file

3. **Commit and push** - ArgoCD handles the rest

### Updating Existing Configuration

1. **Edit YAML file** in Git
2. **Commit and push**
3. Job automatically re-runs and applies changes

### Dry-Run Mode

Preview changes before applying (useful for testing):

```yaml
# In overlays/dev/patches/job-config.yaml
- name: IMPORT_DRY_RUN
  value: "true"  # Enable dry-run
```

View output in job logs to see planned changes.

### Forcing Re-import

If you need to reapply configuration even if unchanged:

```yaml
- name: IMPORT_FORCE
  value: "true"  # Ignore checksum
```

---

## Examples

### Example 1: Simple Office Hierarchy

```yaml
tenant: default

offices:
  - name: Head Office
    externalId: HO001
    openingDate: [2024, 1, 1]

  - name: Douala Branch
    externalId: DLA001
    parentName: Head Office  # References parent
    openingDate: [2024, 2, 1]

  - name: Yaoundé Branch
    externalId: YAO001
    parentName: Head Office
    openingDate: [2024, 2, 1]
```

### Example 2: Roles and Permissions

```yaml
tenant: default

roles:
  - name: Branch Manager
    description: Manage branch operations
    permissions:
      - READ_OFFICE
      - CREATE_CLIENT
      - APPROVE_LOAN
      - VIEW_REPORTS

  - name: Loan Officer
    description: Process loan applications
    permissions:
      - READ_CLIENT
      - CREATE_LOAN
      - DISBURSE_LOAN
```

### Example 3: Dependency Resolution

Use `$<entity-type>.<identifier>` to reference other entities:

```yaml
tenant: default

staff:
  - firstName: Marie
    lastName: Ngono
    office: $office.Head Office  # Resolves to office ID
    role: $role.Branch Manager    # Resolves to role ID
    username: marie.ngono
    createUser: true

loanProducts:
  - name: SME Loan
    charges:
      - $charge.Processing Fee    # Resolves to charge ID
    accounting:
      fundSource: $glAccount.1000  # Resolves to GL account
```

### Example 4: Environment Variables

```yaml
tenant: default

systemConfig:
  globalConfig:
    - name: amazon-S3_access_key
      value: ${FINERACT_DATA_LOADER_CLIENT_ID}  # From secret
      enabled: true
```

Variables are substituted by the `substitute-variables` init container.

---

## Troubleshooting

### Job Fails with "Fineract not ready"

**Cause**: Fineract not fully started before job runs.

**Solution**:
```bash
# Check Fineract health
kubectl get pods -n fineract-dev | grep fineract

# Check actuator endpoint
kubectl exec -it -n fineract-dev fineract-write-0 -- \
  curl -k https://localhost:8443/fineract-provider/actuator/health

# Increase wait time in job (if needed)
# Edit base/jobs/apply-fineract-config.yaml:
MAX_RETRIES=240  # 20 minutes instead of 10
```

### Job Fails with "401 Unauthorized"

**Cause**: OAuth2 authentication failing.

**Solution**:
```bash
# Verify secret exists
kubectl get secret keycloak-client-secrets -n fineract-dev

# Check secret values
kubectl get secret keycloak-client-secrets -n fineract-dev -o jsonpath='{.data.fineract-data-loader-client-id}' | base64 -d

# Test OAuth2 token manually
curl -X POST http://keycloak-service:8080/realms/fineract/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=fineract-data-loader \
  -d client_secret=<secret>
```

### Job Succeeds but No Changes Applied

**Cause**: Checksum unchanged (idempotent behavior).

**Expected behavior** - this means configuration is already up-to-date.

To force re-import:
```yaml
# In overlay patch
- name: IMPORT_FORCE
  value: "true"
```

### Configuration Validation Errors

**Cause**: Invalid YAML syntax or schema.

**Solution**:
```bash
# Check job logs for detailed error
kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli

# Validate YAML locally (if you have the CLI)
java -jar fineract-config-cli.jar validate --file=config.yml
```

### Dependency Resolution Failures

**Cause**: Referenced entity not found.

**Example error**:
```
Cannot resolve: $office.Branch Office
```

**Solution**:
- Ensure referenced entity exists in Fineract
- Check spelling and case (case-sensitive)
- Use correct resolution syntax: `$office.Head Office` (space in name is OK)

---

## Advanced Topics

### Custom Docker Image

To use a custom or specific version:

```yaml
# In overlay patch
containers:
  - name: fineract-config-cli
    image: ghcr.io/adorsys-gis/fineract-config-cli:1.0.0
    imagePullPolicy: IfNotPresent
```

### Parallel Processing

For large configurations, enable parallel imports:

```yaml
- name: IMPORT_PARALLEL
  value: "true"
- name: IMPORT_PARALLEL_THREAD_POOL_SIZE
  value: "8"
```

### Multiple Configuration Files

Organize by entity type:

```
base/config/
├── 01-system-config.yml     # System settings
├── 02-offices.yml           # Organizational structure
├── 03-roles.yml             # Security roles
├── 04-accounting.yml        # Chart of accounts
├── 05-products.yml          # Loan and savings products
└── 06-sample-data.yml       # Demo/test data
```

Files are processed in alphabetical order.

### Backup Before Import

Enable automatic backup:

```yaml
- name: IMPORT_BACKUP
  value: "true"
- name: IMPORT_BACKUP_PATH
  value: "/data/backup"
```

Mount a volume to persist backups.

### Custom Managed Modes

Fine-tune per entity:

```yaml
# Strict for configuration
- name: IMPORT_MANAGED_OFFICE
  value: "full"
- name: IMPORT_MANAGED_ROLE
  value: "full"
- name: IMPORT_MANAGED_LOANPRODUCT
  value: "full"

# Lenient for operational data
- name: IMPORT_MANAGED_CLIENT
  value: "no-delete"
- name: IMPORT_MANAGED_LOANACCOUNT
  value: "no-delete"
- name: IMPORT_MANAGED_TRANSACTION
  value: "no-delete"
```

---

## References

- [Fineract Config CLI Documentation](https://github.com/apache/fineract/tree/develop/docs/data-collection/fineract-config-cli)
- [Keycloak Config CLI (Inspiration)](https://github.com/adorsys/keycloak-config-cli)
- [GitOps with ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
- [Fineract API Documentation](https://demo.fineract.dev/fineract-provider/api-docs/apiLive.htm)

---

## Support

For issues or questions:

1. Check job logs: `kubectl logs -n fineract-dev job/apply-fineract-config`
2. Review ArgoCD application status
3. Consult fineract-config-cli documentation
4. Raise issue in fineract-gitops repository

---

**Version**: 1.0.0
**Last Updated**: 2025-11-20
**Maintained By**: DevOps Team
