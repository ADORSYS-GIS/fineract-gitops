# Operations - Operational Tooling & Configuration

This directory contains operational tools, configuration management utilities, and runtime data for the Fineract platform.

---

## Overview

The operations directory provides tools and configurations for:

1. **Fineract Data Management** - YAML-based configuration data
2. **Keycloak Configuration** - SSO/IAM setup and user synchronization
3. **Disaster Recovery** - Backup and restore procedures

These tools help manage the platform at runtime and handle operational tasks that go beyond basic Kubernetes manifests.

---

## Directory Structure

```
operations/
├── README.md                           # This file
├── fineract-data/                      # Configuration data management
│   ├── README.md                       # Data management guide
│   ├── data/                           # YAML configuration files
│   │   ├── base/                       # Base configurations
│   │   │   ├── codes/                  # System codes
│   │   │   ├── roles/                  # User roles
│   │   │   └── notifications/          # Notification templates
│   │   ├── dev/                        # Dev-specific configs
│   │   ├── uat/                        # UAT-specific configs
│   │   └── production/                 # Production-specific configs
│   └── scripts/                        # Data loading scripts
│
├── keycloak-config/                    # Keycloak SSO configuration
│   ├── README.md                       # Keycloak setup guide
│   ├── config/                         # Realm configurations
│   │   ├── realm-fineract.yaml         # Fineract realm definition
│   │   ├── clients.yaml                # OAuth clients
│   │   └── roles.yaml                  # Keycloak roles
│   ├── user-sync-service/              # User synchronization
│   │   ├── README.md                   # Service documentation
│   │   ├── deployment.yaml             # Kubernetes deployment
│   │   └── src/                        # Source code
│   └── ROLE_MAPPING_SOLUTION.md        # Role mapping guide
│
└── disaster-recovery/                  # Backup & restore
    ├── README.md                       # DR procedures
    ├── backup-scripts/                 # Automated backup scripts
    └── restore-procedures/             # Restore runbooks
```

---

## Components

### 1. Fineract Data Management

**Purpose**: Manage Fineract configuration data as YAML instead of Excel sheets

**Location**: `operations/fineract-data/`

**What it provides**:
- YAML-based configuration for codes, roles, notifications
- Version control for configuration data
- Environment-specific configurations
- Data loading scripts

**Why YAML instead of Excel**:
- ✅ Version control with Git
- ✅ Code reviews for config changes
- ✅ Environment-specific overrides
- ✅ Automated validation
- ✅ GitOps-compatible
- ✅ Easier to diff and merge

**Key Features**:
- **System Codes**: Define lookup codes (loan products, account types, etc.)
- **User Roles**: Define permissions and access control
- **Notification Templates**: SMS and email templates
- **Validation Scripts**: Ensure data integrity before deployment

**Usage**:
```bash
# Navigate to fineract-data
cd operations/fineract-data

# Review README for detailed instructions
cat README.md

# Validate configuration data
./scripts/validate-data.py

# Load data to environment
./scripts/load-data.sh dev
```

**Related Documentation**:
- [Convert Excel to YAML Guide](../docs/operations/CONVERT_EXCEL_TO_YAML.md)
- [Fineract Data README](fineract-data/README.md)

---

### 2. Keycloak Configuration

**Purpose**: Configure Keycloak SSO/IAM for Fineract authentication

**Location**: `operations/keycloak-config/`

**What it provides**:
- Keycloak realm configuration
- OAuth2/OIDC client setup
- Role-based access control (RBAC)
- User synchronization service
- Password reset functionality

**Key Features**:
- **Realm Configuration**: Fineract-specific realm with proper settings
- **OAuth Clients**: Pre-configured clients for web apps and APIs
- **Role Mapping**: Map Keycloak roles to Fineract permissions
- **User Sync Service**: Automatic user creation/update between Keycloak and Fineract
- **Password Reset**: Self-service password reset flow

**Components**:

#### Keycloak Realm Configuration
```yaml
# config/realm-fineract.yaml
- Realm: fineract
- Login theme customization
- Password policies
- Session timeouts
- OAuth2/OIDC settings
```

#### User Sync Service
```
user-sync-service/
├── deployment.yaml      # Kubernetes deployment
├── service.yaml         # Kubernetes service
├── configmap.yaml       # Service configuration
└── src/                 # Python service code
```

**Functionality**:
1. Listens for Keycloak user events
2. Creates corresponding users in Fineract
3. Synchronizes password changes
4. Handles password reset requests
5. Updates user attributes

**Usage**:
```bash
# Navigate to keycloak-config
cd operations/keycloak-config

# Review README for setup instructions
cat README.md

# Deploy realm configuration
kubectl apply -f config/realm-fineract.yaml

# Deploy user sync service
kubectl apply -k user-sync-service/
```

**Related Documentation**:
- [Keycloak Config README](keycloak-config/README.md)
- [User Sync Service README](keycloak-config/user-sync-service/README.md)
- [Role Mapping Solution](keycloak-config/ROLE_MAPPING_SOLUTION.md)

---

### 3. Disaster Recovery

**Purpose**: Backup and restore procedures for Fineract platform

**Location**: `operations/disaster-recovery/`

**What it provides**:
- Automated backup scripts
- Restore procedures
- Recovery runbooks
- Testing procedures

**Backup Scope**:
- PostgreSQL databases (full + incremental)
- Keycloak realm configurations
- Fineract configuration data
- MinIO/S3 objects
- Kubernetes manifests

**Backup Schedule**:
- **Daily**: Full database backups
- **Hourly**: Incremental/WAL archives
- **Weekly**: Full system snapshot
- **Monthly**: Long-term archive

**Usage**:
```bash
# Navigate to disaster-recovery
cd operations/disaster-recovery

# Review README for procedures
cat README.md

# Run manual backup
./backup-scripts/manual-backup.sh dev

# Test restore procedure
./restore-procedures/test-restore.sh
```

**Related Documentation**:
- [Disaster Recovery README](disaster-recovery/README.md)
- [Backup & Restore Guide](../docs/BACKUP_RESTORE.md) [TODO]

---

## Common Operational Tasks

### Task 1: Add New System Code

```bash
# 1. Navigate to fineract-data
cd operations/fineract-data

# 2. Create new code YAML
cat > data/base/codes/new-code.yaml <<EOF
code_name: NEW_CODE
code_description: Description of new code
values:
  - value: "OPTION1"
    description: "Option 1 description"
  - value: "OPTION2"
    description: "Option 2 description"
EOF

# 3. Validate
./scripts/validate-data.py

# 4. Load to environment
./scripts/load-data.sh dev
```

### Task 2: Configure New Keycloak Client

```bash
# 1. Navigate to keycloak-config
cd operations/keycloak-config

# 2. Edit clients configuration
vi config/clients.yaml

# 3. Add new client definition
# ...

# 4. Apply configuration
kubectl apply -f config/clients.yaml
```

### Task 3: Run Manual Backup

```bash
# 1. Navigate to disaster-recovery
cd operations/disaster-recovery

# 2. Execute backup script
./backup-scripts/manual-backup.sh production

# 3. Verify backup completed
kubectl get jobs -n backup
```

### Task 4: Add Notification Template

```bash
# 1. Navigate to fineract-data
cd operations/fineract-data

# 2. Create SMS template
cat > data/base/notifications/new-sms-template.yaml <<EOF
name: NEW_SMS_NOTIFICATION
type: sms
template: "Hello {{name}}, your transaction {{amount}} was successful."
triggers:
  - event: TRANSACTION_COMPLETE
EOF

# 3. Create email template (similar process)

# 4. Validate and load
./scripts/validate-data.py
./scripts/load-data.sh dev
```

---

## Environment-Specific Operations

Each operational component supports environment-specific configurations:

### Development
- Relaxed validation rules
- Test data loading
- Verbose logging
- Frequent backups for testing

### UAT
- Production-like configuration
- Real data (sanitized)
- Standard backup schedule
- Integration testing

### Production
- Strict validation
- Production data
- Automated backups
- Monitoring and alerting

---

## Automation & CI/CD

### Fineract Data
- Validate YAML on PR
- Auto-load to dev on merge
- Manual promotion to UAT/production

### Keycloak Config
- Validate realm config on PR
- Auto-apply to dev
- Manual review for production

### Disaster Recovery
- Daily automated backups
- Weekly automated restore tests
- Monthly DR drill execution

---

## Security Considerations

### Fineract Data
- Sensitive data encrypted in sealed secrets
- Environment-specific data isolation
- Audit logging for data changes

### Keycloak Config
- Client secrets in sealed secrets
- TLS for all communications
- Session timeouts enforced
- MFA recommended for admin

### Disaster Recovery
- Encrypted backups
- Access control on backup storage
- Backup retention policies
- Secure restore procedures

---

## Monitoring & Alerts

### Fineract Data
- Data load success/failure
- Validation errors
- Configuration drift detection

### Keycloak
- User sync failures
- Authentication failures
- Session anomalies
- Client errors

### Disaster Recovery
- Backup job status
- Backup size trends
- Restore test results
- Storage utilization

---

## Troubleshooting

### Common Issues

#### Data Load Failures
**Symptom**: YAML data not loading to Fineract

**Solutions**:
1. Validate YAML syntax
2. Check Fineract API connectivity
3. Review API credentials
4. Check Fineract logs

#### Keycloak Sync Issues
**Symptom**: Users not syncing between Keycloak and Fineract

**Solutions**:
1. Check user-sync-service logs
2. Verify Keycloak event configuration
3. Check Fineract API permissions
4. Review role mappings

#### Backup Failures
**Symptom**: Backups not completing

**Solutions**:
1. Check backup job logs
2. Verify MinIO/S3 connectivity
3. Check storage capacity
4. Review backup credentials

---

## Related Documentation

- **[CI/CD Integration](../docs/operations/CI_CD_INTEGRATION.md)** - Pipeline setup
- **[Convert Excel to YAML](../docs/operations/CONVERT_EXCEL_TO_YAML.md)** - Data migration
- **[Fineract Environment Variables](../docs/FINERACT_ENVIRONMENT_VARIABLES.md)** - Config reference
- **[Secrets Management](../docs/SECRETS_MANAGEMENT.md)** - Secrets handling

---

## Support

For operational issues:

1. **Check component README** in subdirectory
2. **Review logs**: `kubectl logs -n fineract-dev <pod-name>`
3. **Check documentation** in `docs/` directory
4. **Review deployment** via ArgoCD UI

---

**Last Updated:** 2025-10-28
**Components:** Fineract Data, Keycloak Config, Disaster Recovery
**Status:** Active and Operational
