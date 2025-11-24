# Fineract GitOps Multi-Tenant Implementation Guide

**Version:** 1.0
**Last Updated:** 2025-11-24
**Prerequisites:** See MULTI_TENANT_ARCHITECTURE.md

## Overview

This guide provides step-by-step instructions to transform the current single-tenant Fineract GitOps setup into a multi-tenant SaaS platform.

### Implementation Phases

| Phase | Component | Duration | Complexity | Risk |
|-------|-----------|----------|------------|------|
| **Phase 0** | Pre-implementation Setup | 1 day | Low | Low |
| **Phase 1** | Keycloak Multi-Tenant Setup | 2-3 days | Medium | Medium |
| **Phase 2** | Database Multi-Tenant Configuration | 2-3 days | Medium | High |
| **Phase 3** | Application Layer Changes | 3-5 days | High | High |
| **Phase 4** | Ingress and Routing | 2-3 days | Medium | Medium |
| **Phase 5** | Testing and Validation | 3-5 days | Medium | Medium |
| **Phase 6** | Migration of Default Tenant | 1-2 days | Low | Medium |

**Total Duration:** 14-22 days

---

## Phase 0: Pre-Implementation Setup

### 0.1 Environment Preparation

**Create Development Branch**:
```bash
cd /Users/guymoyo/dev/fineract-gitops

# Create feature branch
git checkout -b feature/multi-tenant-architecture
git push -u origin feature/multi-tenant-architecture
```

**Backup Current Configuration**:
```bash
# Backup current single-tenant configs
mkdir -p backups/single-tenant-$(date +%Y%m%d)

# Backup key configuration files
cp -r operations/keycloak-config/base/config backups/single-tenant-$(date +%Y%m%d)/keycloak-config
cp -r operations/fineract-config/base/config backups/single-tenant-$(date +%Y%m%d)/fineract-config
cp -r apps/fineract/base/deployment-*.yaml backups/single-tenant-$(date +%Y%m%d)/
cp -r apps/ingress/base/*.yaml backups/single-tenant-$(date +%Y%m%d)/

echo "✅ Backup completed in backups/single-tenant-$(date +%Y%m%d)/"
```

### 0.2 Prerequisites Checklist

- [ ] Kubernetes cluster access (KUBECONFIG configured)
- [ ] ArgoCD access with admin permissions
- [ ] AWS CLI configured (for RDS/S3 operations)
- [ ] Keycloak admin credentials
- [ ] PostgreSQL admin credentials
- [ ] DNS control (for wildcard subdomain setup)
- [ ] Certificate management access (cert-manager/ACM)
- [ ] Git repository write access

### 0.3 Documentation Review

Read the following documents before proceeding:
- [ ] `MULTI_TENANT_ARCHITECTURE.md` - Architecture overview
- [ ] Current `operations/fineract-database-init/` - Database setup
- [ ] Current `apps/fineract/base/deployment-*.yaml` - Application config
- [ ] Current `operations/keycloak-config/` - Keycloak setup

---

## Phase 1: Keycloak Multi-Tenant Setup

### 1.1 Enable Keycloak Organizations Feature

**Verify Keycloak Version**:
```bash
# Check current Keycloak version
kubectl get deployment keycloak -n fineract-dev -o jsonpath='{.spec.template.spec.containers[0].image}'

# Expected: quay.io/keycloak/keycloak:24.0 or higher
# Organizations feature requires Keycloak 24+
```

**Update Keycloak Deployment** (if needed):
```yaml
# apps/keycloak/base/deployment.yaml
spec:
  template:
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:25.0.1  # Update to latest version
          env:
            # Enable organizations feature
            - name: KC_FEATURES
              value: "organizations"

            # Enable organization OAuth2 validation
            - name: KC_SPI_ORGANIZATION_OAUTH2_REQUIRE_VALIDATION
              value: "true"
```

Apply changes:
```bash
# Update Keycloak deployment
kubectl apply -k apps/keycloak/overlays/dev/

# Wait for rollout
kubectl rollout status deployment/keycloak -n fineract-dev

# Verify organizations feature is enabled
kubectl logs -n fineract-dev deployment/keycloak | grep "organizations"
```

### 1.2 Create Multi-Tenant Realm Configuration

**Create new realm configuration**:
```bash
# Create new multi-tenant realm config
cp operations/keycloak-config/base/config/realm-fineract.yaml \
   operations/keycloak-config/base/config/realm-fineract-multi-tenant.yaml
```

**Edit realm configuration**:
```yaml
# operations/keycloak-config/base/config/realm-fineract-multi-tenant.yaml

realm: fineract
displayName: Fineract Banking Platform (Multi-Tenant)
enabled: true

# Enable organizations
attributes:
  organizationsEnabled: "true"
  organizationsOAuth2RequireValidation: "true"

# OAuth2 Proxy Client with wildcard redirects
clients:
  - clientId: "${OAUTH2_PROXY_CLIENT_ID}"
    name: Fineract OAuth2 Proxy Multi-Tenant
    enabled: true
    clientAuthenticatorType: client-secret
    secret: "${OAUTH2_PROXY_CLIENT_SECRET}"

    # Wildcard redirect URIs for all tenants
    redirectUris:
      - "https://*.app.${BASE_DOMAIN}/oauth2/callback"
      - "https://tenant1.app.${BASE_DOMAIN}/oauth2/callback"  # Explicit for tenant1
      - "https://tenant2.app.${BASE_DOMAIN}/oauth2/callback"  # Explicit for tenant2

    webOrigins:
      - "https://*.app.${BASE_DOMAIN}"

    standardFlowEnabled: true
    directAccessGrantsEnabled: false
    publicClient: false
    protocol: openid-connect

    # Multi-tenant protocol mappers
    protocolMappers:
      # 1. Organization ID to tenant claim
      - name: organization-to-tenant-mapper
        protocol: openid-connect
        protocolMapper: oidc-organization-membership-mapper
        consentRequired: false
        config:
          claim.name: "tenant"
          jsonType.label: "String"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          organization.attribute: "id"  # Maps org ID to tenant

      # 2. Organization name
      - name: organization-name-mapper
        protocol: openid-connect
        protocolMapper: oidc-organization-membership-mapper
        consentRequired: false
        config:
          claim.name: "org_name"
          jsonType.label: "String"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          organization.attribute: "name"

      # 3. Fineract user ID (from user attributes)
      - name: fineract-user-id-mapper
        protocol: openid-connect
        protocolMapper: oidc-usermodel-attribute-mapper
        consentRequired: false
        config:
          user.attribute: "fineract_user_id"
          claim.name: "fineract_user_id"
          jsonType.label: "String"
          id.token.claim: "true"
          access.token.claim: "true"

      # 4. Office ID mapper
      - name: office-id-mapper
        protocol: openid-connect
        protocolMapper: oidc-usermodel-attribute-mapper
        consentRequired: false
        config:
          user.attribute: "office_id"
          claim.name: "office_id"
          jsonType.label: "String"
          id.token.claim: "true"
          access.token.claim: "true"

      # 5. Employee ID mapper
      - name: employee-id-mapper
        protocol: openid-connect
        protocolMapper: oidc-usermodel-attribute-mapper
        consentRequired: false
        config:
          user.attribute: "employee_id"
          claim.name: "employee_id"
          jsonType.label: "String"
          id.token.claim: "true"
          access.token.claim: "true"

      # 6. Roles mapper
      - name: roles-mapper
        protocol: openid-connect
        protocolMapper: oidc-usermodel-realm-role-mapper
        consentRequired: false
        config:
          claim.name: "roles"
          jsonType.label: "String"
          id.token.claim: "true"
          access.token.claim: "true"
          multivalued: "true"

# Realm roles (shared across tenants)
roles:
  realm:
    - name: SUPER_USER
      description: "Super user with full access"
    - name: ADMIN
      description: "Administrator"
    - name: LOAN_OFFICER
      description: "Loan officer"
    - name: TELLER
      description: "Bank teller"
    - name: ACCOUNTANT
      description: "Accountant"
    - name: AUDITOR
      description: "Auditor (read-only)"

# Security settings
bruteForceProtected: true
failureFactor: 3
passwordPolicy: "length(12) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1)"
```

**Update Keycloak config job**:
```yaml
# operations/keycloak-config/base/jobs/apply-keycloak-config.yaml
spec:
  template:
    spec:
      containers:
        - name: keycloak-config-cli
          env:
            - name: KEYCLOAK_AVAILABILITYCHECK_ENABLED
              value: "true"
            - name: KEYCLOAK_AVAILABILITYCHECK_TIMEOUT
              value: "120s"
            - name: IMPORT_FILES
              value: "/config/realm-fineract-multi-tenant.yaml"  # Use new config
```

**Update kustomization**:
```yaml
# operations/keycloak-config/base/kustomization.yaml
configMapGenerator:
  - name: keycloak-config
    files:
      - config/realm-fineract-multi-tenant.yaml  # Add new config file
```

### 1.3 Create Organizations via Keycloak Admin Console

**Method 1: Keycloak Admin Console (Recommended for initial setup)**

```bash
# Port-forward to Keycloak
kubectl port-forward -n fineract-dev svc/keycloak-service 8080:8080

# Open browser: http://localhost:8080/auth/admin
# Login with admin credentials
```

**Create Organization "tenant1"**:
1. Navigate to **Realm Settings** → Select realm `fineract`
2. Click **Organizations** (left menu)
3. Click **Create Organization**
4. Fill in details:
   - **ID**: `tenant1` (must match subdomain)
   - **Name**: `Acme Bank`
   - **Description**: `Test tenant for multi-tenant setup`
   - **Domain**: `tenant1.app.example.com`
   - **Enabled**: ✅
5. Click **Create**

**Create Organization "tenant2"**:
1. Repeat above steps with:
   - **ID**: `tenant2`
   - **Name**: `Global Finance`
   - **Domain**: `tenant2.app.example.com`

**Method 2: Keycloak Admin CLI (for automation)**

```bash
# Get admin access token
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

# Create organization tenant1
curl -X POST "http://localhost:8080/auth/admin/realms/fineract/organizations" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "tenant1",
    "name": "Acme Bank",
    "description": "Test tenant for multi-tenant setup",
    "enabled": true,
    "attributes": {
      "domain": ["tenant1.app.example.com"]
    }
  }'

# Create organization tenant2
curl -X POST "http://localhost:8080/auth/admin/realms/fineract/organizations" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "tenant2",
    "name": "Global Finance",
    "description": "Second test tenant",
    "enabled": true,
    "attributes": {
      "domain": ["tenant2.app.example.com"]
    }
  }'
```

### 1.4 Create Test Users in Organizations

**Create user in tenant1 organization**:
1. In Keycloak Admin Console: **Users** → **Add User**
2. Fill in:
   - **Username**: `admin@tenant1`
   - **Email**: `admin@tenant1.example.com`
   - **First Name**: `Admin`
   - **Last Name**: `Tenant1`
   - **Email Verified**: ✅
   - **Enabled**: ✅
3. Click **Create**
4. Go to **Credentials** tab:
   - Set password: `Test123!@#`
   - **Temporary**: ❌
5. Go to **Role Mappings** tab:
   - Assign role: `SUPER_USER`
6. Go to **Attributes** tab:
   - Add `fineract_user_id` = `1`
   - Add `office_id` = `1`
   - Add `employee_id` = `EMP001`
7. Go to **Organizations** tab:
   - Click **Join Organization**
   - Select `tenant1`
   - Click **Join**

**Repeat for tenant2**:
- Username: `admin@tenant2`
- Email: `admin@tenant2.example.com`
- Password: `Test123!@#`
- Organization: `tenant2`

### 1.5 Test Keycloak Multi-Tenant Setup

**Test JWT token contains tenant claim**:
```bash
# Get token for tenant1 user
TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8080/auth/realms/fineract/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin@tenant1" \
  -d "password=Test123!@#" \
  -d "grant_type=password" \
  -d "client_id=fineract-oauth2-proxy" \
  -d "client_secret=${OAUTH2_PROXY_CLIENT_SECRET}")

# Extract access token
ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.access_token')

# Decode JWT (using jwt.io or jwt-cli)
echo $ACCESS_TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .

# Verify JWT contains:
# {
#   "tenant": "tenant1",
#   "org_name": "Acme Bank",
#   "fineract_user_id": "1",
#   "office_id": "1",
#   "employee_id": "EMP001",
#   "roles": ["SUPER_USER"]
# }
```

**Validation Checklist**:
- [ ] Organizations feature enabled in Keycloak
- [ ] Organization `tenant1` created with ID matching subdomain
- [ ] Organization `tenant2` created
- [ ] Test users created and assigned to organizations
- [ ] JWT tokens contain `tenant` claim with organization ID
- [ ] JWT tokens contain `org_name` with organization name
- [ ] User attributes (fineract_user_id, office_id) mapped correctly

---

## Phase 2: Database Multi-Tenant Configuration

### 2.1 Update RDS Terraform Configuration

**Modify Terraform to support multiple tenant databases**:

```hcl
# terraform/aws/modules/rds/main.tf
# (No changes needed - existing RDS instance supports multiple databases)

# Connection limit validation
locals {
  max_connections = {
    "db.t3.medium"  = 150
    "db.m5.large"   = 200
    "db.m5.xlarge"  = 500
    "db.m5.2xlarge" = 1000
    "db.m5.4xlarge" = 2000
  }

  instance_max_connections = lookup(local.max_connections, var.instance_class, 500)

  # Calculate required connections for tenants
  # Formula: (tenants × pools_per_tenant × connections_per_pool) + overhead
  # Example: (10 tenants × 3 pools × 15 connections) + 50 = 500 connections
  expected_tenants = var.environment == "prod" ? 50 : 10
  required_connections = (var.expected_tenants * 3 * 15) + 50
}

# Add validation to prevent over-subscription
resource "null_resource" "connection_validation" {
  triggers = {
    instance_class = var.instance_class
    tenants = var.expected_tenants
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ ${local.required_connections} -gt ${local.instance_max_connections} ]; then
        echo "ERROR: Required connections (${local.required_connections}) exceeds instance capacity (${local.instance_max_connections})"
        echo "Either reduce tenant count or upgrade to larger instance class"
        exit 1
      fi
    EOT
  }
}
```

**Apply Terraform changes**:
```bash
cd terraform/aws/

# Plan changes
terraform plan -out=tfplan

# Review output (should show no changes to RDS, just validation)
terraform show tfplan

# Apply if satisfied
terraform apply tfplan
```

### 2.2 Create Database Creation Script

**Create helper script for tenant database provisioning**:

```bash
# scripts/tenant-provisioning/create-tenant-database.sh
#!/bin/bash
set -euo pipefail

# Script to create a new tenant database in RDS
# Usage: ./create-tenant-database.sh <tenant_id>

TENANT_ID="${1:-}"

if [ -z "$TENANT_ID" ]; then
  echo "❌ Error: Tenant ID is required"
  echo "Usage: $0 <tenant_id>"
  echo "Example: $0 tenant1"
  exit 1
fi

# Validate tenant ID format (alphanumeric, lowercase, max 20 chars)
if ! [[ "$TENANT_ID" =~ ^[a-z0-9]{1,20}$ ]]; then
  echo "❌ Error: Invalid tenant ID format"
  echo "Tenant ID must be:"
  echo "  - Lowercase alphanumeric only"
  echo "  - 1-20 characters"
  echo "  - No special characters or spaces"
  exit 1
fi

echo "🚀 Creating database for tenant: $TENANT_ID"

# Get database credentials from Kubernetes secret
echo "📝 Getting database credentials..."
DB_HOST=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d)
DB_PORT=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.port}' | base64 -d)
DB_USER=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d)
DB_PASSWORD=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d)

export PGPASSWORD="$DB_PASSWORD"

# Check if database already exists
echo "🔍 Checking if database exists..."
DB_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='fineract_$TENANT_ID';")

if [ "$DB_EXISTS" = "1" ]; then
  echo "⚠️  Database fineract_$TENANT_ID already exists. Skipping creation."
  exit 0
fi

# Create database
echo "🏗️  Creating database fineract_$TENANT_ID..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres <<-EOSQL
  CREATE DATABASE fineract_$TENANT_ID OWNER $DB_USER;
  GRANT ALL PRIVILEGES ON DATABASE fineract_$TENANT_ID TO $DB_USER;
EOSQL

# Register tenant in metadata database
echo "📋 Registering tenant in metadata database..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d fineract_tenants <<-EOSQL
  INSERT INTO tenants (identifier, name, timezone_id, created_date)
  VALUES ('$TENANT_ID', '$TENANT_ID', 'UTC', NOW())
  ON CONFLICT (identifier) DO NOTHING;
EOSQL

# Verify creation
DB_SIZE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc \
  "SELECT pg_size_pretty(pg_database_size('fineract_$TENANT_ID'));")

echo "✅ Database created successfully!"
echo ""
echo "Database Details:"
echo "  Name: fineract_$TENANT_ID"
echo "  Size: $DB_SIZE"
echo "  Host: $DB_HOST"
echo "  Port: $DB_PORT"
echo ""
echo "Next steps:"
echo "  1. Run schema migration: ./run-tenant-schema-migration.sh $TENANT_ID"
echo "  2. Load initial data: ./load-tenant-data.sh $TENANT_ID"
echo "  3. Create Keycloak organization: $TENANT_ID"

unset PGPASSWORD
```

**Make script executable**:
```bash
chmod +x scripts/tenant-provisioning/create-tenant-database.sh
```

### 2.3 Create Schema Migration Script per Tenant

**Create tenant-specific schema migration script**:

```bash
# scripts/tenant-provisioning/run-tenant-schema-migration.sh
#!/bin/bash
set -euo pipefail

# Script to run Liquibase schema migration for a specific tenant
# Usage: ./run-tenant-schema-migration.sh <tenant_id>

TENANT_ID="${1:-}"

if [ -z "$TENANT_ID" ]; then
  echo "❌ Error: Tenant ID is required"
  echo "Usage: $0 <tenant_id>"
  exit 1
fi

echo "🚀 Running schema migration for tenant: $TENANT_ID"

# Get Fineract image from current deployment
FINERACT_IMAGE=$(kubectl get deployment fineract-write -n fineract-dev -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "📦 Using Fineract image: $FINERACT_IMAGE"

# Get database credentials
DB_HOST=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d)
DB_PORT=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.port}' | base64 -d)
DB_USER=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d)
DB_PASSWORD=$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d)

# Create Kubernetes Job for migration
echo "🏗️  Creating Liquibase migration job..."

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: schema-migration-$TENANT_ID
  namespace: fineract-dev
  labels:
    app: fineract-schema-migration
    tenant: $TENANT_ID
spec:
  ttlSecondsAfterFinished: 3600  # Clean up after 1 hour
  template:
    metadata:
      labels:
        app: fineract-schema-migration
        tenant: $TENANT_ID
    spec:
      restartPolicy: OnFailure
      containers:
        - name: liquibase
          image: $FINERACT_IMAGE
          command:
            - sh
            - -c
            - |
              echo "Starting Liquibase migration for tenant: $TENANT_ID"
              echo "Database: fineract_$TENANT_ID"

              # Run Liquibase with tenant database
              java -Dloader.main=org.apache.fineract.ServerApplication \\
                -Dspring.liquibase.enabled=true \\
                -Dspring.datasource.hikari.jdbc-url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/fineract_${TENANT_ID} \\
                -Dspring.datasource.hikari.username=${DB_USER} \\
                -Dspring.datasource.hikari.password=${DB_PASSWORD} \\
                -Dfineract.mode.batch-manager-enabled=false \\
                -Dfineract.mode.batch-worker-enabled=false \\
                -jar /app/fineract-provider.jar --spring.main.web-application-type=none

              echo "✅ Migration completed successfully"
          env:
            - name: DB_HOST
              value: "$DB_HOST"
            - name: DB_PORT
              value: "$DB_PORT"
            - name: DB_USER
              value: "$DB_USER"
            - name: DB_PASSWORD
              value: "$DB_PASSWORD"
            - name: TENANT_ID
              value: "$TENANT_ID"
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
EOF

# Wait for job to complete
echo "⏳ Waiting for migration to complete..."
kubectl wait --for=condition=complete --timeout=600s job/schema-migration-$TENANT_ID -n fineract-dev

# Show logs
echo "📋 Migration logs:"
kubectl logs job/schema-migration-$TENANT_ID -n fineract-dev

# Get final status
JOB_STATUS=$(kubectl get job schema-migration-$TENANT_ID -n fineract-dev -o jsonpath='{.status.conditions[0].type}')

if [ "$JOB_STATUS" = "Complete" ]; then
  echo "✅ Schema migration completed successfully for tenant: $TENANT_ID"

  # Verify schema
  export PGPASSWORD="$DB_PASSWORD"
  TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "fineract_$TENANT_ID" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")

  echo ""
  echo "Database Statistics:"
  echo "  Tables created: $TABLE_COUNT"
  echo "  Expected: ~150 tables"

  if [ "$TABLE_COUNT" -lt 100 ]; then
    echo "⚠️  Warning: Table count seems low. Migration may have failed partially."
    exit 1
  fi

  unset PGPASSWORD
else
  echo "❌ Schema migration failed for tenant: $TENANT_ID"
  exit 1
fi
```

**Make script executable**:
```bash
chmod +x scripts/tenant-provisioning/run-tenant-schema-migration.sh
```

### 2.4 Create Tenant Databases (tenant1, tenant2)

**Create databases for test tenants**:
```bash
# Create tenant1 database
./scripts/tenant-provisioning/create-tenant-database.sh tenant1

# Create tenant2 database
./scripts/tenant-provisioning/create-tenant-database.sh tenant2

# Run schema migrations
./scripts/tenant-provisioning/run-tenant-schema-migration.sh tenant1
./scripts/tenant-provisioning/run-tenant-schema-migration.sh tenant2
```

**Verify databases created**:
```bash
# List all databases
kubectl run -it --rm psql-client --image=postgres:15-alpine --restart=Never -- psql \
  -h $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d) \
  -U $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d) \
  -d postgres \
  -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datname LIKE 'fineract_%' ORDER BY datname;"

# Expected output:
#        datname        |  size
# ---------------------+---------
#  fineract_default    | 45 MB
#  fineract_tenant1    | 42 MB
#  fineract_tenant2    | 42 MB
#  fineract_tenants    | 8192 kB
```

### 2.5 Update Database Init Job (for future tenants)

**Modify database creation job to be tenant-agnostic**:

```yaml
# operations/fineract-database-init/base/create-databases-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: create-fineract-databases
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-weight: "-1"
    argocd.argoproj.io/sync-wave: "-1"
spec:
  template:
    metadata:
      labels:
        app: fineract-database-init
    spec:
      restartPolicy: OnFailure
      containers:
        - name: create-databases
          image: postgres:15-alpine
          command:
            - sh
            - -c
            - |
              echo "Creating Fineract databases if they don't exist"

              export PGPASSWORD="${PGPASSWORD}"

              # Create tenant metadata database (only once)
              psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres <<-EOSQL
                SELECT 'CREATE DATABASE fineract_tenants OWNER ${PGUSER}'
                WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'fineract_tenants')\gexec

                GRANT ALL PRIVILEGES ON DATABASE fineract_tenants TO ${PGUSER};
              EOSQL

              echo "✅ Tenant metadata database ready"

              # Note: Individual tenant databases are created via scripts/tenant-provisioning/
              # This job only ensures the metadata database exists

              # For backwards compatibility with "default" tenant
              psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres <<-EOSQL
                SELECT 'CREATE DATABASE fineract_default OWNER ${PGUSER}'
                WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'fineract_default')\gexec

                GRANT ALL PRIVILEGES ON DATABASE fineract_default TO ${PGUSER};
              EOSQL

              echo "✅ Default tenant database ready (backwards compatibility)"

              echo "Database creation completed successfully"
          env:
            - name: PGHOST
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: host
            - name: PGPORT
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: port
            - name: PGUSER
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: username
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: password
```

**Validation Checklist**:
- [ ] RDS instance supports multiple databases
- [ ] Database creation script created and tested
- [ ] Schema migration script created and tested
- [ ] tenant1 database created with full schema
- [ ] tenant2 database created with full schema
- [ ] Tenant metadata database (fineract_tenants) contains tenant records
- [ ] Database init job updated for multi-tenant support

---

## Phase 3: Application Layer Changes

### 3.1 Update Fineract Deployment for Multi-Tenant

**Create new multi-tenant deployment configuration**:

```bash
# Create multi-tenant deployment configs
cp apps/fineract/base/deployment-write.yaml apps/fineract/base/deployment-write-multi-tenant.yaml
cp apps/fineract/base/deployment-read.yaml apps/fineract/base/deployment-read-multi-tenant.yaml
cp apps/fineract/base/deployment-batch.yaml apps/fineract/base/deployment-batch-multi-tenant.yaml
```

**Edit write deployment** (showing key changes):

```yaml
# apps/fineract/base/deployment-write-multi-tenant.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract-write
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: fineract
          env:
            # ============================================
            # REMOVE OLD SINGLE-TENANT CONFIG
            # ============================================
            # DELETE THESE LINES:
            # - name: FINERACT_DEFAULT_TENANTDB_HOSTNAME
            # - name: FINERACT_DEFAULT_TENANTDB_NAME
            # - name: FINERACT_DEFAULT_TENANTDB_IDENTIFIER

            # ============================================
            # ADD MULTI-TENANT DATABASE CONFIGURATION
            # ============================================

            # Tenant Master Database (Metadata)
            - name: FINERACT_TENANT_MASTER_HOST
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: host
            - name: FINERACT_TENANT_MASTER_PORT
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: port
            - name: FINERACT_TENANT_MASTER_DATABASE
              value: "fineract_tenants"
            - name: FINERACT_TENANT_MASTER_USERNAME
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: username
            - name: FINERACT_TENANT_MASTER_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: password

            # Tenant Database Configuration (Dynamic)
            - name: FINERACT_TENANT_HOST
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: host
            - name: FINERACT_TENANT_PORT
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: port
            - name: FINERACT_TENANT_USERNAME
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: username
            - name: FINERACT_TENANT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: password

            # Database naming pattern: fineract_{tenant_id}
            - name: FINERACT_TENANT_DB_NAME_PREFIX
              value: "fineract_"
            - name: FINERACT_TENANT_DB_NAME_SUFFIX
              value: ""

            # ============================================
            # TENANT IDENTIFIER CONFIGURATION
            # ============================================

            # Enable tenant resolution from JWT token
            - name: FINERACT_TENANT_IDENTIFIER_SOURCE
              value: "jwt"  # Primary: JWT claim

            # JWT claim name for tenant identifier
            - name: FINERACT_TENANT_IDENTIFIER_JWT_CLAIM
              value: "tenant"

            # Fallback to header if JWT claim not found
            - name: FINERACT_TENANT_IDENTIFIER_HEADER
              value: "X-Tenant-Id"

            # Disable hardcoded default tenant
            - name: FINERACT_DEFAULT_TENANTDB_IDENTIFIER
              value: ""  # Empty = disabled

            # Strict tenant validation (reject if tenant not found)
            - name: FINERACT_TENANT_VALIDATION_STRICT
              value: "true"

            # ============================================
            # HIKARICP CONNECTION POOL (PER TENANT)
            # ============================================

            - name: FINERACT_HIKARI_MINIMUM_IDLE
              value: "5"
            - name: FINERACT_HIKARI_MAXIMUM_POOL_SIZE
              value: "15"
            - name: FINERACT_HIKARI_IDLE_TIMEOUT
              value: "600000"  # 10 minutes
            - name: FINERACT_HIKARI_CONNECTION_TIMEOUT
              value: "30000"   # 30 seconds
            - name: FINERACT_HIKARI_MAX_LIFETIME
              value: "1800000" # 30 minutes

            # ============================================
            # REDIS CACHE (TENANT-AWARE)
            # ============================================

            - name: SPRING_CACHE_REDIS_KEY_PREFIX
              value: "fineract:"  # Will become: fineract:{tenant}:cache_key
            - name: SPRING_CACHE_REDIS_USE_KEY_PREFIX
              value: "true"

            # ============================================
            # S3 DOCUMENT STORAGE (TENANT-AWARE)
            # ============================================

            # Use tenant prefix for S3 paths
            - name: FINERACT_CONTENT_S3_OBJECT_KEY_PREFIX_TYPE
              value: "tenant"  # Will become: {tenant}/documents/...

            # ============================================
            # LOGGING (TENANT CONTEXT)
            # ============================================

            - name: FINERACT_LOGGING_PATTERN
              value: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - tenant=%X{tenant} - %msg%n"

            # ============================================
            # MONITORING (TENANT METRICS)
            # ============================================

            - name: MANAGEMENT_METRICS_TAGS_TENANT
              value: "${fineract.tenant.identifier}"
```

**Apply the same changes to read and batch deployments**.

### 3.2 Update Kustomization for Multi-Tenant Deployments

**Update kustomization to use new deployments**:

```yaml
# apps/fineract/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # Multi-tenant deployments
  - deployment-write-multi-tenant.yaml
  - deployment-read-multi-tenant.yaml
  - deployment-batch-multi-tenant.yaml

  # Services (no changes)
  - service-write.yaml
  - service-read.yaml

  # ConfigMaps
  - fineract-oauth2-config.yaml

  # HPA, PDB, etc.
  - hpa.yaml
  - pdb.yaml
```

### 3.3 Verify Fineract Configuration Changes

**Important Note**: The above environment variables assume Fineract natively supports multi-tenancy. However, the current Fineract codebase uses hardcoded configuration.

**Check if Fineract supports dynamic tenant resolution**:

```bash
# Search for tenant resolution code
cd /path/to/fineract/source  # If you have access to source

# Look for tenant identifier handling
grep -r "FINERACT_DEFAULT_TENANTDB_IDENTIFIER" .
grep -r "TenantAwareDataSource" .
grep -r "TenantIdentifierResolver" .
```

**If Fineract does NOT support dynamic tenants natively**, you have two options:

**Option A: Modify Fineract Source Code** (Recommended for production):
- Fork Apache Fineract repository
- Implement `TenantIdentifierResolver` to read from JWT
- Build custom Docker image
- Deploy custom image

**Option B: Use Multiple Fineract Deployments** (Quick workaround):
- Deploy separate Fineract instances per tenant
- Each deployment configured for one tenant
- More resource intensive but works with existing Fineract

**For this guide, we'll document Option B (multiple deployments) as it works immediately**:

```yaml
# apps/fineract/overlays/tenant1/deployment-write.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract-write-tenant1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fineract
      tier: write
      tenant: tenant1
  template:
    metadata:
      labels:
        app: fineract
        tier: write
        tenant: tenant1
    spec:
      containers:
        - name: fineract
          env:
            # Hardcode for tenant1
            - name: FINERACT_DEFAULT_TENANTDB_HOSTNAME
              valueFrom:
                secretKeyRef:
                  name: fineract-db-credentials
                  key: host
            - name: FINERACT_DEFAULT_TENANTDB_NAME
              value: "fineract_tenant1"  # Specific to tenant1
            - name: FINERACT_DEFAULT_TENANTDB_IDENTIFIER
              value: "tenant1"            # Specific to tenant1
```

**Repeat for tenant2, tenant3, etc.**

### 3.4 Deploy Multi-Tenant Fineract

**Deploy via ArgoCD**:
```bash
# Sync Fineract application
argocd app sync fineract --prune

# Watch rollout
kubectl rollout status deployment/fineract-write -n fineract-dev
kubectl rollout status deployment/fineract-read -n fineract-dev

# Verify pods are running
kubectl get pods -n fineract-dev -l app=fineract

# Check logs for tenant resolution
kubectl logs -n fineract-dev -l app=fineract,tier=write --tail=100 | grep -i tenant
```

**Validation Checklist**:
- [ ] New deployment configurations created
- [ ] Old hardcoded tenant config removed
- [ ] Multi-tenant environment variables added
- [ ] Fineract pods deployed successfully
- [ ] Pods can connect to tenant databases
- [ ] No errors in pod logs

---

## Phase 4: Ingress and Routing

### 4.1 Configure Wildcard DNS

**AWS Route53 Example**:

```bash
# Get Load Balancer DNS name
LB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Load Balancer DNS: $LB_DNS"

# Create wildcard DNS record
aws route53 change-resource-record-sets --hosted-zone-id Z1234567890ABC --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "*.app.example.com",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "'$LB_DNS'"}]
    }
  }]
}'

# Verify DNS resolution
dig tenant1.app.example.com
dig tenant2.app.example.com

# Both should resolve to the Load Balancer IP
```

**GCP Cloud DNS Example**:
```bash
# Get Load Balancer IP
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Create wildcard A record
gcloud dns record-sets create "*.app.example.com." \
  --zone=fineract-dns-zone \
  --type=A \
  --ttl=300 \
  --rrdatas="$LB_IP"
```

### 4.2 Configure Wildcard TLS Certificate

**Using cert-manager with Let's Encrypt**:

```yaml
# apps/ingress/base/wildcard-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-app-tls
  namespace: fineract-dev
spec:
  secretName: wildcard-app-tls-cert
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.app.example.com"
    - "app.example.com"  # Include apex domain
  usages:
    - digital signature
    - key encipherment
```

**Apply certificate**:
```bash
kubectl apply -f apps/ingress/base/wildcard-certificate.yaml

# Wait for certificate to be ready
kubectl wait --for=condition=Ready certificate/wildcard-app-tls -n fineract-dev --timeout=300s

# Verify certificate
kubectl describe certificate wildcard-app-tls -n fineract-dev
kubectl get secret wildcard-app-tls-cert -n fineract-dev
```

### 4.3 Update Ingress for Multi-Tenant Routing

**Create multi-tenant ingress**:

```yaml
# apps/ingress/base/fineract-multi-tenant-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-multi-tenant
  namespace: fineract-dev
  annotations:
    # TLS
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # Force HTTPS
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

    # OAuth2 authentication
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2/start?rd=$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token,X-Auth-Request-Roles"

    # Extract tenant from subdomain and validate with JWT
    nginx.ingress.kubernetes.io/configuration-snippet: |
      # Extract tenant ID from subdomain
      # e.g., tenant1.app.example.com -> tenant1
      set $tenant_id "";
      if ($host ~* "^([^.]+)\.app\.example\.com$") {
        set $tenant_id $1;
      }

      # Get access token from auth request
      auth_request_set $access_token $upstream_http_x_auth_request_access_token;

      # Decode JWT and extract tenant claim (requires lua-resty-jwt module)
      # For production, validate tenant_id matches JWT claim
      # For now, we'll pass both and let Fineract validate

      # Forward to backend with tenant context
      proxy_set_header Authorization "Bearer $access_token";
      proxy_set_header X-Tenant-Id $tenant_id;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Fineract-Platform-TenantId $tenant_id;

    # CORS configuration
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://*.app.example.com"
    nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS, PATCH"
    nginx.ingress.kubernetes.io/cors-allow-headers: "Authorization, Content-Type, X-Requested-With, X-Fineract-Platform-TenantId, X-Tenant-Id"

    # Rate limiting (per tenant)
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-connections: "50"

    # Timeouts
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"

    # Body size
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - "*.app.example.com"
        - "app.example.com"
      secretName: wildcard-app-tls-cert
  rules:
    # Wildcard rule for all tenants
    - host: "*.app.example.com"
      http:
        paths:
          # Fineract API
          - path: /fineract-provider
            pathType: Prefix
            backend:
              service:
                name: fineract-read-service
                port:
                  number: 8443

    # Specific rule for OAuth2 Proxy callback
    - host: "*.app.example.com"
      http:
        paths:
          - path: /oauth2
            pathType: Prefix
            backend:
              service:
                name: oauth2-proxy
                port:
                  number: 4180
```

**Create write ingress** (for POST/PUT/DELETE):

```yaml
# apps/ingress/base/fineract-multi-tenant-write-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-multi-tenant-write
  namespace: fineract-dev
  annotations:
    # Same annotations as read ingress
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.fineract-dev.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2/start?rd=$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"

    nginx.ingress.kubernetes.io/configuration-snippet: |
      set $tenant_id "";
      if ($host ~* "^([^.]+)\.app\.example\.com$") {
        set $tenant_id $1;
      }
      auth_request_set $access_token $upstream_http_x_auth_request_access_token;
      proxy_set_header Authorization "Bearer $access_token";
      proxy_set_header X-Tenant-Id $tenant_id;
      proxy_set_header X-Fineract-Platform-TenantId $tenant_id;
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - "*.app.example.com"
      secretName: wildcard-app-tls-cert
  rules:
    - host: "*.app.example.com"
      http:
        paths:
          # Write operations only
          - path: /fineract-provider
            pathType: Prefix
            backend:
              service:
                name: fineract-write-service  # Route to write service
                port:
                  number: 8443
```

**Update kustomization**:

```yaml
# apps/ingress/base/kustomization.yaml
resources:
  - wildcard-certificate.yaml
  - fineract-multi-tenant-ingress.yaml
  - fineract-multi-tenant-write-ingress.yaml
  - keycloak-ingress.yaml  # Existing, no changes
```

### 4.4 Update OAuth2 Proxy for Multi-Tenant

**Update OAuth2 Proxy configuration**:

```yaml
# apps/oauth2-proxy/base/oauth2-proxy-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-config
data:
  oidc-issuer-url: "https://auth.example.com/auth/realms/fineract"
  redis-connection-url: "redis://fineract-redis:6379"

  # Cookie configuration for wildcard domain
  cookie-name: "_oauth2_proxy"
  cookie-domain: ".app.example.com"  # Shared across all subdomains
  cookie-secure: "true"
  cookie-httponly: "true"
  cookie-samesite: "lax"

  # Upstream
  upstreams: "http://fineract-read-service:8443"

  # OIDC scopes
  scope: "openid profile email tenant org_name"

  # Redirect URL (wildcard)
  redirect-url: "https://app.example.com/oauth2/callback"
```

**Update deployment**:

```yaml
# apps/oauth2-proxy/base/deployment.yaml
spec:
  template:
    spec:
      containers:
        - name: oauth2-proxy
          args:
            - --provider=oidc
            - --oidc-issuer-url=$(OIDC_ISSUER_URL)
            - --client-id=$(CLIENT_ID)
            - --client-secret=$(CLIENT_SECRET)
            - --cookie-secret=$(COOKIE_SECRET)
            - --cookie-name=$(COOKIE_NAME)
            - --cookie-domain=$(COOKIE_DOMAIN)  # .app.example.com
            - --cookie-secure=$(COOKIE_SECURE)
            - --email-domain=*
            - --upstream=$(UPSTREAMS)
            - --http-address=0.0.0.0:4180
            - --redis-connection-url=$(REDIS_CONNECTION_URL)
            - --session-store-type=redis
            - --pass-access-token=true
            - --pass-authorization-header=true
            - --set-authorization-header=true
            - --scope=openid profile email tenant org_name
            - --skip-provider-button=true
            # Enable wildcard redirect validation
            - --whitelist-domain=.app.example.com
            - --redirect-url=https://app.example.com/oauth2/callback
```

### 4.5 Deploy Ingress Changes

```bash
# Apply ingress changes
kubectl apply -k apps/ingress/overlays/dev/

# Apply OAuth2 Proxy changes
kubectl apply -k apps/oauth2-proxy/overlays/dev/

# Verify ingress created
kubectl get ingress -n fineract-dev

# Verify wildcard certificate
kubectl get certificate -n fineract-dev

# Check ingress logs for errors
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100
```

**Validation Checklist**:
- [ ] Wildcard DNS configured (*.app.example.com)
- [ ] Wildcard TLS certificate issued and ready
- [ ] Multi-tenant ingress created with subdomain extraction
- [ ] OAuth2 Proxy configured for wildcard domain
- [ ] Ingress controller logs show no errors
- [ ] DNS resolves correctly for tenant subdomains

---

## Phase 5: Testing and Validation

### 5.1 Test Tenant1 End-to-End Flow

**Test DNS and TLS**:
```bash
# Test DNS resolution
dig tenant1.app.example.com

# Test TLS certificate
curl -v https://tenant1.app.example.com/fineract-provider/actuator/health 2>&1 | grep "subject:"
# Should show: subject: CN=*.app.example.com
```

**Test OAuth2 authentication flow**:
```bash
# Open browser
open https://tenant1.app.example.com/fineract-provider/api/v1/offices

# Expected flow:
# 1. Redirect to Keycloak login
# 2. URL: https://auth.example.com/auth/realms/fineract/protocol/openid-connect/auth?...
# 3. Login with: admin@tenant1 / Test123!@#
# 4. Redirect back to tenant1.app.example.com
# 5. See list of offices (from tenant1 database)
```

**Test API with JWT token**:
```bash
# Get token for tenant1 user
TOKEN_RESPONSE=$(curl -s -X POST "https://auth.example.com/auth/realms/fineract/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin@tenant1" \
  -d "password=Test123!@#" \
  -d "grant_type=password" \
  -d "client_id=fineract-oauth2-proxy" \
  -d "client_secret=${OAUTH2_PROXY_CLIENT_SECRET}")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.access_token')

# Call Fineract API
curl -v -X GET "https://tenant1.app.example.com/fineract-provider/api/v1/offices" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Fineract-Platform-TenantId: tenant1" \
  -H "Content-Type: application/json"

# Expected: JSON response with tenant1 offices
```

### 5.2 Test Tenant Isolation

**Attempt cross-tenant access (should fail)**:
```bash
# Get token for tenant1 user
TOKEN_TENANT1=$(curl -s -X POST "https://auth.example.com/auth/realms/fineract/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin@tenant1" \
  -d "password=Test123!@#" \
  -d "grant_type=password" \
  -d "client_id=fineract-oauth2-proxy" \
  -d "client_secret=${OAUTH2_PROXY_CLIENT_SECRET}" | jq -r '.access_token')

# Try to access tenant2 with tenant1 token (should fail)
curl -v -X GET "https://tenant2.app.example.com/fineract-provider/api/v1/offices" \
  -H "Authorization: Bearer $TOKEN_TENANT1" \
  -H "X-Fineract-Platform-TenantId: tenant2"

# Expected: 403 Forbidden or 401 Unauthorized
```

**Verify database isolation**:
```bash
# Create client in tenant1
curl -X POST "https://tenant1.app.example.com/fineract-provider/api/v1/clients" \
  -H "Authorization: Bearer $TOKEN_TENANT1" \
  -H "Content-Type: application/json" \
  -d '{
    "officeId": 1,
    "firstname": "John",
    "lastname": "Doe",
    "active": true,
    "activationDate": "2025-01-24",
    "dateFormat": "yyyy-MM-dd",
    "locale": "en"
  }'

# Verify client exists in tenant1 database
kubectl run -it --rm psql-client --image=postgres:15-alpine --restart=Never -- psql \
  -h $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d) \
  -U $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d) \
  -d fineract_tenant1 \
  -c "SELECT id, display_name FROM m_client WHERE firstname='John' AND lastname='Doe';"

# Verify client does NOT exist in tenant2 database
kubectl run -it --rm psql-client --image=postgres:15-alpine --restart=Never -- psql \
  -h $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d) \
  -U $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d) \
  -d fineract_tenant2 \
  -c "SELECT id, display_name FROM m_client WHERE firstname='John' AND lastname='Doe';"

# Expected: 0 rows in tenant2
```

### 5.3 Test S3 Tenant Isolation

**Upload document to tenant1**:
```bash
# Create test PDF
echo "Test document for tenant1" > test-doc-tenant1.txt

# Upload via Fineract API
curl -v -X POST "https://tenant1.app.example.com/fineract-provider/api/v1/clients/1/documents" \
  -H "Authorization: Bearer $TOKEN_TENANT1" \
  -F "name=test-document" \
  -F "description=Test upload" \
  -F "file=@test-doc-tenant1.txt"

# Verify S3 path
aws s3 ls s3://fineract-documents-dev/tenant1/documents/ --recursive

# Expected: s3://fineract-documents-dev/tenant1/documents/clients/1/test-doc-tenant1.txt
```

**Verify tenant2 cannot access tenant1 documents**:
```bash
# Try to access tenant1 document from tenant2 (should fail)
# This requires application-level enforcement

# Check S3 bucket structure
aws s3 ls s3://fineract-documents-dev/ --recursive | grep -E "(tenant1|tenant2)"

# Expected:
# tenant1/documents/...
# tenant2/documents/...
# (Separate prefixes)
```

### 5.4 Test Redis Cache Isolation

**Verify Redis key prefixes**:
```bash
# Connect to Redis
kubectl exec -it -n fineract-dev sts/fineract-redis -- redis-cli

# List all keys
KEYS *

# Expected output:
# 1) "fineract:tenant1:cache:..."
# 2) "tenant1:session:..."
# 3) "fineract:tenant2:cache:..."
# 4) "tenant2:session:..."

# Verify no overlap
KEYS fineract:tenant1:*
KEYS fineract:tenant2:*

# Exit
exit
```

### 5.5 Performance Testing

**Load test tenant1**:
```bash
# Install k6 (load testing tool)
brew install k6  # macOS
# or: apt-get install k6  # Ubuntu

# Create load test script
cat > load-test-tenant1.js <<'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 10 },  // Ramp up to 10 users
    { duration: '5m', target: 10 },  // Stay at 10 users
    { duration: '2m', target: 0 },   // Ramp down
  ],
};

const BASE_URL = 'https://tenant1.app.example.com';
const TOKEN = __ENV.ACCESS_TOKEN;

export default function () {
  // List offices
  let res = http.get(`${BASE_URL}/fineract-provider/api/v1/offices`, {
    headers: {
      'Authorization': `Bearer ${TOKEN}`,
      'X-Fineract-Platform-TenantId': 'tenant1',
    },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
EOF

# Run load test
ACCESS_TOKEN=$TOKEN_TENANT1 k6 run load-test-tenant1.js

# Review metrics:
# - http_req_duration (p95 should be < 500ms)
# - http_req_failed (should be < 1%)
```

**Monitor database connections during load test**:
```bash
# Monitor PostgreSQL connections
watch -n 2 "kubectl run -it --rm psql-client --image=postgres:15-alpine --restart=Never -- psql \
  -h $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d) \
  -U $(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d) \
  -d postgres \
  -tAc \"SELECT datname, numbackends FROM pg_stat_database WHERE datname LIKE 'fineract_%' ORDER BY datname;\""

# Expected:
#  datname          | numbackends
# ------------------+-------------
#  fineract_tenant1 | 8-15        (within pool limits)
#  fineract_tenant2 | 0-2         (idle)
```

### 5.6 Monitoring and Logging

**Check Prometheus metrics**:
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:9090

# Open browser: http://localhost:9090

# Query tenant-specific metrics:
# fineract_http_requests_total{tenant="tenant1"}
# fineract_database_connections_active{tenant="tenant1"}
# fineract_cache_hits_total{tenant="tenant1"}
```

**Check logs for tenant context**:
```bash
# Fineract logs with tenant context
kubectl logs -n fineract-dev -l app=fineract --tail=100 | grep tenant=

# Expected format:
# 2025-11-24 10:30:45 - tenant=tenant1 - INFO - Client created successfully
# 2025-11-24 10:31:12 - tenant=tenant2 - INFO - Loan approved
```

**Validation Checklist**:
- [ ] Tenant1 authentication flow works end-to-end
- [ ] Tenant2 authentication flow works end-to-end
- [ ] Cross-tenant access denied (403/401)
- [ ] Database isolation verified
- [ ] S3 document isolation verified
- [ ] Redis cache isolation verified
- [ ] Load test shows acceptable performance (p95 < 500ms)
- [ ] Database connections within limits
- [ ] Metrics show per-tenant data
- [ ] Logs include tenant context

---

## Phase 6: Migration of Default Tenant

### 6.1 Migrate Existing "default" Tenant to "tenant1"

**Backup default tenant data**:
```bash
# Dump default tenant database
kubectl run -it --rm pg-dump --image=postgres:15-alpine --restart=Never -- sh -c "
  export PGPASSWORD=\$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d)
  pg_dump -h \$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d) \
    -U \$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d) \
    -d fineract_default \
    --format=custom \
    --file=/tmp/default-backup-\$(date +%Y%m%d).dump
  cat /tmp/default-backup-\$(date +%Y%m%d).dump
" > default-backup-$(date +%Y%m%d).dump

echo "✅ Backup saved: default-backup-$(date +%Y%m%d).dump"
```

**Copy default tenant data to tenant1** (if tenant1 is empty):
```bash
# Restore default data to tenant1
kubectl run -it --rm pg-restore --image=postgres:15-alpine --restart=Never -- sh -c "
  export PGPASSWORD=\$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d)
  pg_restore -h \$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d) \
    -U \$(kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d) \
    -d fineract_tenant1 \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    default-backup-$(date +%Y%m%d).dump
"
```

**Map default tenant users to tenant1 organization in Keycloak**:
1. Go to Keycloak Admin Console
2. Navigate to **Users**
3. Find existing users (e.g., `admin`, `mifos`)
4. For each user:
   - Click user → **Organizations** tab
   - Click **Join Organization**
   - Select `tenant1`
   - Add user attributes:
     - `fineract_user_id` = (Fineract user ID)
     - `office_id` = `1`

**Test migration**:
```bash
# Login as migrated user
open https://tenant1.app.example.com/fineract-provider/api/v1/clients

# Verify all clients from default tenant are accessible
```

### 6.2 Deprecate "default" Tenant

**Update documentation**:
```markdown
# DEPRECATION NOTICE

The hardcoded "default" tenant has been deprecated and replaced with multi-tenant architecture.

## Migration Path
- Existing "default" tenant data has been migrated to "tenant1"
- All users should now access: https://tenant1.app.example.com
- Old URL (apps.example.com/fineract-provider) will redirect to tenant selection page
```

**Remove default tenant deployments** (after successful migration):
```bash
# Remove old single-tenant deployments (if separate from multi-tenant)
kubectl delete deployment fineract-write-default -n fineract-dev --ignore-not-found
kubectl delete deployment fineract-read-default -n fineract-dev --ignore-not-found

# Keep default database for rollback purposes (can delete later)
# DO NOT DROP fineract_default database yet
```

**Validation Checklist**:
- [ ] Default tenant data backed up
- [ ] Default tenant users migrated to tenant1 organization
- [ ] All users can access tenant1.app.example.com
- [ ] Data integrity verified (client counts, loan counts match)
- [ ] Old single-tenant deployments removed

---

## Post-Implementation

### Documentation Updates

**Update README.md**:
```markdown
# Fineract GitOps - Multi-Tenant Platform

This repository deploys Apache Fineract as a multi-tenant SaaS platform.

## Architecture
- **Tenant Identification**: Subdomain-based (tenant1.app.example.com)
- **Authentication**: Keycloak Organizations + OAuth2
- **Database**: PostgreSQL RDS with separate database per tenant
- **Isolation**: Database, cache (Redis), storage (S3)

## Accessing the Platform
- Tenant 1: https://tenant1.app.example.com
- Tenant 2: https://tenant2.app.example.com

## Provisioning New Tenants
See: [docs/multi-tenant/TENANT_PROVISIONING_GUIDE.md](docs/multi-tenant/TENANT_PROVISIONING_GUIDE.md)

## Architecture Details
See: [docs/multi-tenant/MULTI_TENANT_ARCHITECTURE.md](docs/multi-tenant/MULTI_TENANT_ARCHITECTURE.md)
```

**Create runbook**:
- [ ] Tenant provisioning procedure documented
- [ ] Troubleshooting guide created
- [ ] Disaster recovery procedures updated
- [ ] Monitoring dashboards configured
- [ ] Cost tracking setup documented

### Training

**Team Training Topics**:
1. Multi-tenant architecture overview
2. Tenant provisioning workflow
3. Troubleshooting tenant-specific issues
4. Monitoring and alerting
5. Security and compliance considerations
6. Backup and disaster recovery

### Security Audit

**Conduct security review**:
- [ ] Tenant isolation verified at all layers
- [ ] JWT validation tested (token tampering, expired tokens)
- [ ] Cross-tenant access attempts blocked
- [ ] Rate limiting per tenant enforced
- [ ] Audit logging captures tenant context
- [ ] S3 bucket policies reviewed
- [ ] Database access controls verified
- [ ] Secrets management reviewed

---

## Troubleshooting

### Common Issues

**Issue 1: JWT token missing tenant claim**
```bash
# Symptom: 401 Unauthorized, logs show "tenant claim not found"

# Solution: Verify organization mapper in Keycloak
kubectl port-forward -n fineract-dev svc/keycloak-service 8080:8080
# Navigate to: Clients → fineract-oauth2-proxy → Client Scopes → Protocol Mappers
# Ensure "organization-to-tenant-mapper" is present and enabled
```

**Issue 2: Database connection pool exhausted**
```bash
# Symptom: 500 errors, logs show "Connection pool exhausted"

# Check current connections
kubectl run -it --rm psql-client --image=postgres:15-alpine --restart=Never -- psql \
  -h $DB_HOST -U $DB_USER -d postgres \
  -c "SELECT datname, numbackends, (SELECT setting::int FROM pg_settings WHERE name='max_connections') as max FROM pg_stat_database WHERE datname LIKE 'fineract_%';"

# Solution: Increase RDS instance class or reduce connections per pool
# Update: apps/fineract/base/deployment-*.yaml
# FINERACT_HIKARI_MAXIMUM_POOL_SIZE: "10"  # Reduce from 15
```

**Issue 3: Wildcard certificate not issued**
```bash
# Symptom: TLS errors, cert-manager logs show challenge failures

# Check certificate status
kubectl describe certificate wildcard-app-tls -n fineract-dev

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Common cause: DNS not configured
# Solution: Verify DNS01 or HTTP01 challenge can complete
```

**Issue 4: Cross-tenant access not blocked**
```bash
# Symptom: User from tenant1 can access tenant2 data

# Verify ingress configuration
kubectl get ingress fineract-multi-tenant -n fineract-dev -o yaml | grep configuration-snippet

# Ensure tenant validation is in place
# Add to configuration-snippet:
# if ($tenant_id != $jwt_tenant_claim) {
#   return 403;
# }
```

### Support

For issues during implementation:
1. Check ArgoCD application health: `argocd app get fineract`
2. Review pod logs: `kubectl logs -n fineract-dev -l app=fineract --tail=100`
3. Verify database connectivity: Run connection test script
4. Check Keycloak realm configuration: Port-forward and review admin console
5. Consult architecture document: `docs/multi-tenant/MULTI_TENANT_ARCHITECTURE.md`

---

## Success Criteria

Implementation is complete when:
- [ ] All 6 phases completed
- [ ] tenant1 and tenant2 fully functional
- [ ] End-to-end tests passing
- [ ] Tenant isolation verified
- [ ] Performance benchmarks met (p95 < 500ms)
- [ ] Database connections within limits
- [ ] Documentation updated
- [ ] Team trained
- [ ] Security audit passed
- [ ] Production deployment plan created

---

**Document Version:** 1.0
**Last Updated:** 2025-11-24
**Estimated Implementation Time:** 14-22 days
**Status:** Ready for Implementation
