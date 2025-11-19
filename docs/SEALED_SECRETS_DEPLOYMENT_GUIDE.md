# Sealed Secrets Deployment Guide

This guide explains how to deploy Fineract using Sealed Secrets for secret management.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Step-by-Step Deployment](#step-by-step-deployment)
4. [Troubleshooting](#troubleshooting)
5. [Secret Inventory](#secret-inventory)

## Related Documentation

For operational procedures and emergency recovery:
- **[Sealed Secrets DR Runbook](./SEALED_SECRETS_DR_RUNBOOK.md)** - Emergency recovery quick reference
- **[Secrets Management Strategy](./SECRETS_MANAGEMENT.md)** - Complete secrets strategy and best practices
- **[Disaster Recovery Guide](./DISASTER_RECOVERY.md)** - Comprehensive DR procedures
- **[Multi-Region DR Strategy](./MULTI_REGION_DR_STRATEGY.md)** - Cross-region failover strategy
- **[ADR-003: Sealed Secrets](./architecture/ADR-003-sealed-secrets.md)** - Architecture decision record

---

## Prerequisites

### Required Tools

1. **kubectl** - Kubernetes CLI (v1.28+)
2. **kubeseal** - Sealed Secrets CLI
   ```bash
   # macOS
   brew install kubeseal

   # Linux
   wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz
   tar -xvzf kubeseal-0.27.0-linux-amd64.tar.gz
   sudo install -m 755 kubeseal /usr/local/bin/kubeseal
   ```

3. **Terraform** - Infrastructure provisioning (v1.5+)
4. **openssl** - Password generation

### Infrastructure Requirements

- Kubernetes cluster (EKS, K3s, or any Kubernetes 1.28+)
- AWS account with RDS, S3 provisioned by Terraform
- ArgoCD installed (optional, but recommended)

---

## Quick Start

For impatient users who want to get started quickly:

```bash
# 1. Install Sealed Secrets controller
kubectl apply -k apps/sealed-secrets-controller/base/

# 2. Wait for controller to be ready
kubectl wait --for=condition=available --timeout=300s deployment/sealed-secrets-controller -n kube-system

# 3. Provision AWS infrastructure
cd terraform/aws
terraform apply -var-file=environments/dev.tfvars
cd ../..

# 4. Generate ALL sealed secrets
./scripts/seal-terraform-secrets.sh dev
./scripts/create-complete-sealed-secrets.sh dev

# 5. Add sealed secrets to kustomization (see below)

# 6. Deploy via kubectl or ArgoCD
kubectl apply -k environments/dev/
```

---

## Step-by-Step Deployment

### Step 1: Deploy Sealed Secrets Controller

The Sealed Secrets controller must be deployed FIRST, before any sealed secrets are created.

**Option A: Via kubectl**

```bash
kubectl apply -k apps/sealed-secrets-controller/base/
```

**Option B: Via ArgoCD**

```bash
kubectl apply -f argocd/applications/system/sealed-secrets-controller.yaml
```

**Verify deployment:**

```bash
# Check controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets-controller

# Should show:
# NAME                                         READY   STATUS    RESTARTS   AGE
# sealed-secrets-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

**CRITICAL: Backup controller keys immediately!**

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-keys-backup-$(date +%Y%m%d).yaml
```

Store this backup in a secure location (NOT in Git!):
- Password manager (1Password, LastPass)
- Encrypted USB drive
- Secure file share

---

### Step 2: Provision AWS Infrastructure

Use Terraform to create RDS, S3, and other AWS resources:

```bash
cd terraform/aws

# Initialize Terraform
terraform init

# Review plan
terraform plan -var-file=environments/dev.tfvars

# Apply (creates RDS, S3, generates passwords)
terraform apply -var-file=environments/dev.tfvars
```

**Terraform creates:**
- RDS PostgreSQL instance (Fineract + Keycloak databases)
- S3 buckets (documents, backups)
- IAM roles for IRSA
- Generates secure passwords for databases

---

### Step 3: Generate Terraform-Managed Sealed Secrets

Extract Terraform outputs and create sealed secrets:

```bash
./scripts/seal-terraform-secrets.sh dev
```

**This creates:**
1. `secrets/dev/rds-connection-sealed.yaml`
2. `secrets/dev/fineract-db-credentials-sealed.yaml`
3. `secrets/dev/keycloak-db-credentials-sealed.yaml`
4. `secrets/dev/oauth2-proxy-secrets-sealed.yaml`
5. `secrets/dev/s3-connection-sealed.yaml`
6. `secrets/dev/service-account.yaml` (IRSA manifest)

**Output example:**

```
✓ Created: secrets/dev/fineract-db-credentials-sealed.yaml
✓ Created: secrets/dev/keycloak-db-credentials-sealed.yaml
✓ Created: secrets/dev/oauth2-proxy-secrets-sealed.yaml
✓ Created: secrets/dev/s3-connection-sealed.yaml
```

---

### Step 4: Generate Application Sealed Secrets

Create secrets for Redis, Keycloak admin, data loaders, and Grafana:

```bash
./scripts/create-complete-sealed-secrets.sh dev
```

**This creates:**
1. `secrets/dev/fineract-redis-secret-sealed.yaml` (in-cluster Redis)
2. `secrets/dev/keycloak-admin-credentials-sealed.yaml` (Keycloak admin user)
3. `secrets/dev/fineract-admin-credentials-sealed.yaml` (OAuth2 client for jobs)
4. `secrets/dev/grafana-admin-credentials-sealed.yaml` (Grafana admin)
5. `secrets/dev/keycloak-client-secrets-sealed.yaml` (placeholder)

**SAVE THE CREDENTIALS DISPLAYED!**

The script outputs important credentials like:

```
Keycloak Admin:
  Username: admin
  Password: <generated-password>

Fineract Admin OAuth2 Client:
  Client ID: fineract-admin-cli
  Client Secret: <generated-secret>
```

**Save these in your password manager!**

---

### Step 5: Add Sealed Secrets to Kustomization

Edit `environments/dev/kustomization.yaml` and add sealed secret resources:

```yaml
resources:
  # Namespace (created first)
  - namespace.yaml

  # Sealed Secrets (created second, before pods need them)
  - ../../secrets/dev/fineract-db-credentials-sealed.yaml
  - ../../secrets/dev/keycloak-db-credentials-sealed.yaml
  - ../../secrets/dev/keycloak-admin-credentials-sealed.yaml
  - ../../secrets/dev/oauth2-proxy-secrets-sealed.yaml
  - ../../secrets/dev/s3-connection-sealed.yaml
  - ../../secrets/dev/fineract-redis-secret-sealed.yaml
  - ../../secrets/dev/fineract-admin-credentials-sealed.yaml
  - ../../secrets/dev/keycloak-client-secrets-sealed.yaml

  # Database initialization
  - ../../operations/fineract-database-init/base

  # Fineract application
  - ../../apps/fineract/base
```

**Note:** See `secrets/base/sealed-secrets-kustomization-example.yaml` for complete examples.

---

### Step 6: Commit Sealed Secrets to Git

Sealed secrets are **safe to commit** - they are encrypted:

```bash
# Review what you're committing
git status
git diff secrets/dev/

# Add sealed secrets
git add secrets/dev/*.yaml

# Commit
git commit -m "Add sealed secrets for dev environment"

# Push
git push
```

---

### Step 7: Deploy Applications

**Option A: Via kubectl**

```bash
kubectl apply -k environments/dev/
```

**Option B: Via ArgoCD**

```bash
# Sync the Fineract application
argocd app sync fineract-dev-fineract

# Or apply the app-of-apps
kubectl apply -f argocd/applications/dev/app-of-apps.yaml
```

---

### Step 8: Verify Secrets Were Created

Check that Kubernetes secrets were created from sealed secrets:

```bash
# Check all secrets in namespace
kubectl get secrets -n fineract-dev

# Should include:
# - fineract-db-credentials
# - keycloak-db-credentials
# - keycloak-admin-credentials
# - oauth2-proxy-secrets
# - s3-connection
# - fineract-redis-secret
# - fineract-admin-credentials
# - keycloak-client-secrets (may be empty initially)

# Verify a specific secret
kubectl get secret fineract-db-credentials -n fineract-dev -o yaml

# Check if secret has correct keys
kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data}' | jq 'keys'
# Should show: ["database", "host", "jdbc-url", "password", "port", "username"]
```

---

### Step 9: Configure Keycloak OAuth2 Client

After Keycloak is deployed, configure the OAuth2 client for data loaders:

1. **Access Keycloak admin console:**
   ```bash
   # Get Keycloak admin password
   kubectl get secret keycloak-admin-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d

   # Port-forward to Keycloak
   kubectl port-forward -n fineract-dev svc/keycloak 8080:8080

   # Open browser: http://localhost:8080
   # Username: admin
   # Password: <from above>
   ```

2. **Create OAuth2 client:**
   - Go to: Clients → Create
   - Client ID: `fineract-admin-cli` (must match script output)
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Service Accounts Enabled: `ON`
   - Click Save

3. **Set client secret:**
   - Go to: Credentials tab
   - Secret: <use the secret from `create-complete-sealed-secrets.sh` output>
   - Click Regenerate Secret → Enter the secret from script

4. **Test OAuth2 client:**
   ```bash
   CLIENT_ID="fineract-admin-cli"
   CLIENT_SECRET="<from-script-output>"
   TOKEN_URL="http://keycloak.fineract-dev.svc.cluster.local:8080/realms/fineract/protocol/openid-connect/token"

   curl -X POST "${TOKEN_URL}" \
     -d "grant_type=client_credentials" \
     -d "client_id=${CLIENT_ID}" \
     -d "client_secret=${CLIENT_SECRET}"

   # Should return an access_token
   ```

---

## Troubleshooting

### SealedSecret Not Decrypting

**Symptoms:**
- SealedSecret resource exists
- But no Kubernetes Secret created

**Debug:**

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets-controller

# Common errors:
# - "no key could decrypt secret" → Encrypted for wrong cluster
# - "unsupported algorithm" → Version mismatch

# Check SealedSecret status
kubectl get sealedsecret fineract-db-credentials -n fineract-dev -o yaml
```

**Solutions:**

1. **Wrong cluster:** Re-encrypt with correct kubeseal connection
2. **Version mismatch:** Update kubeseal CLI to match controller version
3. **RBAC issue:** Check controller has permissions

### Secret Has Wrong Keys

**Problem:** Secret exists but missing expected keys

```bash
# Check what keys exist
kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data}' | jq 'keys'

# Expected for fineract-db-credentials:
# ["database", "host", "jdbc-url", "password", "port", "username"]
```

**Solution:** Re-run `seal-terraform-secrets.sh` to regenerate with correct keys

### Pod Can't Find Secret

**Symptoms:**
- Pod stuck in `CreateContainerConfigError`
- Events show: `Secret "xyz" not found`

**Debug:**

```bash
# Check pod events
kubectl describe pod <pod-name> -n fineract-dev

# Check if secret exists
kubectl get secret <secret-name> -n fineract-dev

# Check if SealedSecret exists
kubectl get sealedsecret <secret-name> -n fineract-dev
```

**Solution:**

1. Ensure SealedSecret is created first
2. Check controller is running
3. Check secret is in correct namespace

### Grafana Secret in Wrong Namespace

**Problem:** Grafana in `monitoring` namespace, but secret created in `fineract-dev`

**Solution:**

The script creates Grafana secret in `monitoring` namespace automatically. Ensure your Grafana kustomization includes:

```yaml
resources:
  - ../../secrets/dev/grafana-admin-credentials-sealed.yaml
```

---

## Secret Inventory

### Complete List of Secrets

| Secret Name | Namespace | Keys | Source | Created By |
|-------------|-----------|------|--------|------------|
| `fineract-db-credentials` | `fineract-*` | `host`, `port`, `username`, `password`, `database`, `jdbc-url` | Terraform | `seal-terraform-secrets.sh` |
| `keycloak-db-credentials` | `fineract-*` | `host`, `port`, `username`, `password`, `database`, `jdbc-url` | Terraform | `seal-terraform-secrets.sh` |
| `oauth2-proxy-secrets` | `fineract-*` | `client-id`, `client-secret`, `cookie-secret`, `redis-password` | Terraform/Generated | `seal-terraform-secrets.sh` |
| `s3-connection` | `fineract-*` | `documents-bucket`, `region` | Terraform | `seal-terraform-secrets.sh` |
| `fineract-redis-secret` | `fineract-*` | `redis-password` | Generated | `create-complete-sealed-secrets.sh` |
| `keycloak-admin-credentials` | `fineract-*` | `username`, `password` | Generated | `create-complete-sealed-secrets.sh` |
| `fineract-admin-credentials` | `fineract-*` | `client-id`, `client-secret`, `token-url` | Generated | `create-complete-sealed-secrets.sh` |
| `keycloak-client-secrets` | `fineract-*` | Various client secrets | Keycloak export job | `create-complete-sealed-secrets.sh` (placeholder) |
| `grafana-admin-credentials` | `monitoring` | `username`, `password` | Generated | `create-complete-sealed-secrets.sh` |

### Secrets by Component

**Fineract (read/write/batch):**
- `fineract-db-credentials` (RDS PostgreSQL)
- `s3-connection` (S3 document storage)
- `fineract-redis-secret` (in-cluster Redis)

**Keycloak:**
- `keycloak-db-credentials` (RDS PostgreSQL)
- `keycloak-admin-credentials` (admin console)

**OAuth2 Proxy:**
- `oauth2-proxy-secrets` (authentication)

**Data Loader Jobs (40+):**
- `fineract-admin-credentials` (OAuth2 client)

**Grafana:**
- `grafana-admin-credentials` (admin console)

---

## Multi-Environment Deployment

To deploy UAT or Production:

```bash
# 1. Provision infrastructure
cd terraform/aws
terraform apply -var-file=environments/uat.tfvars
cd ../..

# 2. Generate secrets for UAT
./scripts/seal-terraform-secrets.sh uat
./scripts/create-complete-sealed-secrets.sh uat

# 3. Update environments/uat/kustomization.yaml (add sealed secrets)

# 4. Commit secrets
git add secrets/uat/
git commit -m "Add sealed secrets for UAT environment"
git push

# 5. Deploy
kubectl apply -k environments/uat/
```

**Important:** Each environment needs its own sealed secrets encrypted for that cluster!

---

## Security Checklist

Before going to production:

- [ ] Backed up Sealed Secrets controller keys
- [ ] Stored backup in secure location (NOT Git)
- [ ] Used strong passwords for production (32+ chars)
- [ ] Different passwords for each environment
- [ ] Committed only encrypted sealed secrets to Git
- [ ] Deleted all plaintext secret files
- [ ] Tested secret rotation procedure
- [ ] Documented disaster recovery process
- [ ] Configured secret rotation schedule (90 days)
- [ ] Set up monitoring for secret expiration

---

## Next Steps

After successful deployment:

1. **Test all components:**
   - Fineract API responds
   - Keycloak login works
   - OAuth2 Proxy redirects correctly
   - Data loader jobs complete successfully
   - Grafana dashboards load

2. **Set up monitoring:**
   - Monitor SealedSecret decryption failures
   - Alert on secret rotation due dates
   - Track secret access patterns

3. **Document credentials:**
   - Store all passwords in team password manager
   - Document who has access to what
   - Create runbook for secret rotation

4. **Plan for rotation:**
   - Schedule first rotation in 90 days
   - Test rotation procedure in dev first
   - Document rotation steps

---

## References

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [Secrets Management Guide](./SECRETS_MANAGEMENT.md)
- [Terraform AWS Module](../terraform/aws/README.md)
