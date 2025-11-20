# Database Setup

This directory contains Kubernetes Jobs for database setup tasks.

## Keycloak Database Creation

### Overview

The `create-keycloak-db-job.yaml` creates the Keycloak database and user in RDS PostgreSQL. This job is designed to be run once during initial setup.

### Why a Kubernetes Job?

The Keycloak database creation uses a Kubernetes Job instead of Terraform's `local-exec` provisioner for several reasons:

1. **Network Access**: The Job runs inside the Kubernetes cluster with proper VPC access to RDS
2. **No Local Dependencies**: Doesn't require `psql` installed on the machine running Terraform
3. **Idempotent**: Can be safely re-run; skips creation if database/user already exists
4. **Observable**: Logs are stored in Kubernetes for debugging
5. **Credentials**: Uses existing Fineract credentials from Kubernetes secrets (managed via Sealed Secrets)

### Prerequisites

Before running this job:

1. **RDS Instance**: PostgreSQL RDS instance must be running
2. **Secrets Created**: Sealed Secrets must have been created and unsealed:
   - `fineract-db-credentials` - Contains Fineract user credentials (has CREATEDB privileges)
   - `keycloak-db-credentials` - Contains the password for the Keycloak user

3. **Network Access**: Kubernetes cluster must have network access to RDS (security groups configured)

### Usage

#### Manual Execution

```bash
# Apply the job
kubectl apply -f operations/keycloak-database-setup/create-keycloak-db-job.yaml

# Watch job progress
kubectl get jobs -n fineract-dev -w

# Check logs
kubectl logs -l app=keycloak-db-setup -n fineract-dev

# Verify completion
kubectl get job create-keycloak-db -n fineract-dev
```

#### Automated Execution

This job can be integrated into your deployment pipeline:

```bash
# In post-terraform-setup.sh or similar
kubectl apply -f operations/keycloak-database-setup/create-keycloak-db-job.yaml
kubectl wait --for=condition=complete --timeout=120s job/create-keycloak-db -n fineract-dev
```

### What It Does

The job performs the following operations:

1. Connects to RDS PostgreSQL using Fineract credentials
2. Creates `keycloak` database (if it doesn't exist)
3. Creates `keycloak` user with password from secrets (if it doesn't exist)
4. Grants ALL privileges on the keycloak database to keycloak user
5. Grants schema-level privileges:
   - `GRANT ALL ON SCHEMA public`
   - `GRANT ALL ON ALL TABLES IN SCHEMA public`
   - `GRANT ALL ON ALL SEQUENCES IN SCHEMA public`
   - `ALTER DEFAULT PRIVILEGES` for future objects

### Troubleshooting

**Job Fails with "password authentication failed"**:
- Check that Sealed Secrets have been unsealed to regular Secrets
- Verify Sealed Secrets were created from correct Terraform outputs

**Job Fails with "connection refused"**:
- Check RDS security groups allow traffic from Kubernetes pods
- Verify RDS endpoint is correct in secrets

**Database already exists**:
- This is normal! The job is idempotent and will skip creation
- Check logs to see "already exists" message (suppressed by grep)

**Check secret values**:
```bash
# Verify fineract-db-credentials
kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.host}' | base64 -d

# Verify keycloak-db-credentials exists
kubectl get secret keycloak-db-credentials -n fineract-dev
```

### Cleanup

The job automatically deletes itself 5 minutes after completion (success or failure) due to `ttlSecondsAfterFinished: 300`.

To manually delete:
```bash
kubectl delete job create-keycloak-db -n fineract-dev
```

### Integration with Terraform

The Terraform RDS module generates a random password for the Keycloak user. The `seal-terraform-secrets.sh` script retrieves this from Terraform outputs and creates a Sealed Secret.

**Terraform flow**:
1. `terraform apply` → Creates RDS instance
2. `terraform apply` → Generates random password for Keycloak
3. `seal-terraform-secrets.sh` → Retrieves Terraform outputs
4. `kubeseal` → Encrypts secrets with cluster public key
5. **Sealed Secrets Controller** → Unseals to regular Kubernetes secrets
6. **This Job** → Creates database using credentials from secrets

### Security

- Job runs as non-root user (uid 999)
- No privilege escalation allowed
- All capabilities dropped
- Passwords never logged or echoed
- Auto-cleanup after 5 minutes

### Related Documentation

- [Keycloak Configuration](../keycloak-config/README.md) - Realm and client configuration
- [Sealed Secrets Management](../../docs/SECRETS_MANAGEMENT.md) - Secret encryption and management
- [RDS Module](../../terraform/aws/modules/rds/main.tf) - Database infrastructure
