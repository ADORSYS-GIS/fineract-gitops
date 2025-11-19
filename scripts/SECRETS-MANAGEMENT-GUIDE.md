# Secrets Management Guide

## Overview

This guide explains how to create and manage sealed secrets for the Fineract platform. The repository uses **Bitnami Sealed Secrets** to store encrypted secrets in Git safely.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Secret Management Flow                   │
└─────────────────────────────────────────────────────────────┘

1. Infrastructure Secrets (Terraform-managed)
   ┌──────────────────┐
   │ Terraform Apply  │──> Creates AWS Resources (RDS, S3, etc.)
   └────────┬─────────┘
            │
            v
   ┌─────────────────────────────────┐
   │ seal-terraform-secrets.sh       │──> Extracts from Terraform state
   │ - RDS credentials               │    (NOT from outputs - secure!)
   │ - S3 bucket names               │
   │ - Keycloak DB credentials       │
   │ - OAuth2 Proxy secrets          │
   │ - SMTP credentials (if SES)     │
   │ - Service Account (IRSA)        │
   └────────┬────────────────────────┘
            │
            v
   ┌────────────────────────┐
   │ secrets/ENV/*.yaml     │──> Commit to Git
   └────────────────────────┘

2. Application Secrets (App-managed)
   ┌──────────────────────────────────┐
   │ create-complete-sealed-secrets.sh│──> Generates strong passwords
   │ - Fineract Redis password        │
   │ - Keycloak admin credentials     │
   │ - Fineract admin OAuth2 client   │
   │ - Grafana admin credentials      │
   │ - Keycloak client secrets        │
   └────────┬─────────────────────────┘
            │
            v
   ┌────────────────────────┐
   │ secrets/ENV/*.yaml     │──> Commit to Git
   └────────────────────────┘

3. Deployment
   ┌────────────────────────┐
   │ Git Push               │
   └────────┬───────────────┘
            │
            v
   ┌────────────────────────────────────┐
   │ ArgoCD                              │──> Syncs to cluster
   │ - Deploys SealedSecret resources    │
   │ - Sealed Secrets Controller         │
   │   decrypts to Secret                │
   │ - Applications consume Secrets      │
   └─────────────────────────────────────┘
```

## Available Scripts

### Core Scripts (Use These!)

| Script | Purpose | Usage |
|--------|---------|-------|
| **seal-terraform-secrets.sh** | Creates sealed secrets from Terraform infrastructure | `./scripts/seal-terraform-secrets.sh dev` |
| **create-complete-sealed-secrets.sh** | Creates sealed secrets for application services | `./scripts/create-complete-sealed-secrets.sh dev` |
| **validate-secrets.sh** | Validates no plain text secrets in repository | `./scripts/validate-secrets.sh` |
| **seal-argocd-github-credentials.sh** | Creates ArgoCD GitHub credentials (one-time) | `./scripts/seal-argocd-github-credentials.sh` |

### Script Details

#### 1. seal-terraform-secrets.sh

**When to use:** After running `terraform apply` to create infrastructure.

**What it does:**
- Extracts database credentials from Terraform state (secure method)
- Extracts S3 bucket names, AWS region
- Extracts Keycloak DB credentials
- Generates OAuth2 Proxy secrets (or uses Terraform outputs)
- Creates Service Account manifest with IRSA role
- Seals all secrets using kubeseal

**Prerequisites:**
- Terraform apply completed successfully
- kubectl configured to access cluster
- kubeseal installed (`brew install kubeseal`)
- Sealed Secrets controller running in cluster

**Example:**
```bash
# After terraform apply
cd terraform/aws
terraform apply

# Create sealed secrets
cd ../..
./scripts/seal-terraform-secrets.sh dev

# Review generated secrets
ls -la secrets/dev/

# Commit to Git
git add secrets/dev/
git commit -m "Add sealed secrets for dev environment"
git push
```

**Creates:**
- `rds-connection` - RDS database connection (deprecated)
- `fineract-db-credentials` - Fineract database credentials (comprehensive)
- `keycloak-db-credentials` - Keycloak RDS database credentials
- `oauth2-proxy-secrets` - OAuth2 Proxy cookie secret only (client credentials moved to keycloak-client-secrets)
- `keycloak-client-secrets` - ALL OAuth2 client credentials (consolidated single source of truth)
- `s3-connection` - S3 bucket configuration
- `smtp-credentials` - SES email credentials (if SES enabled)
- `fineract-redis-credentials` - ElastiCache Redis (if provisioned)
- `service-account.yaml` - IRSA service account manifest

---

#### 2. create-complete-sealed-secrets.sh

**When to use:** To create application-level secrets that are NOT managed by Terraform.

**What it does:**
- Generates strong random passwords for application services
- Creates Keycloak admin credentials
- Creates Fineract admin OAuth2 client for data loaders
- Creates Grafana admin credentials
- Creates Redis password for in-cluster Redis
- Seals all secrets using kubeseal

**Prerequisites:**
- kubectl configured to access cluster
- kubeseal installed
- openssl installed

**Example:**
```bash
# Create application sealed secrets
./scripts/create-complete-sealed-secrets.sh dev

# IMPORTANT: Save the printed credentials securely!
# The script prints:
# - Keycloak admin password
# - Redis password
# - Fineract admin OAuth2 client secret
# - Grafana admin password

# Commit to Git
git add secrets/dev/
git commit -m "Add application sealed secrets for dev"
git push
```

**Creates:**
- `fineract-redis-secret` - In-cluster Redis password
- `keycloak-admin-credentials` - Keycloak admin user
- `keycloak-default-users` - Default user passwords for Keycloak realm
- `grafana-admin-credentials` - Grafana admin user

**Note:** OAuth2 client credentials (including fineract-data-loader) are now managed by `seal-terraform-secrets.sh` in the consolidated `keycloak-client-secrets` secret

**Security Notes:**
- Dev environment uses simple passwords (`admin/admin`) for convenience
- UAT/Production use strong random passwords (32 characters)
- ALL generated passwords are printed to console - save them securely!

---

#### 3. validate-secrets.sh

**When to use:** Before committing any changes to ensure no plain text secrets leak.

**What it does:**
- Scans repository for unencrypted Secret manifests
- Detects common secret patterns (passwords, API keys, tokens)
- Checks for cloud provider credentials
- Detects database connection strings with embedded credentials
- Validates all secrets are using SealedSecrets

**Example:**
```bash
# Validate before commit
./scripts/validate-secrets.sh

# Output:
# ✅ Validation PASSED - No plain text secrets detected
```

**Recommended:**
Add to pre-commit hook:
```bash
#!/bin/bash
./scripts/validate-secrets.sh
```

---

#### 4. seal-argocd-github-credentials.sh

**When to use:** One-time setup for ArgoCD to access private GitHub repositories.

**What it does:**
- Creates GitHub credentials for ArgoCD
- Seals the credentials using kubeseal

**Prerequisites:**
- GitHub Personal Access Token with repo access

**Example:**
```bash
# One-time setup
export GITHUB_TOKEN="ghp_your_token_here"
./scripts/seal-argocd-github-credentials.sh

# Commit
git add secrets/argocd/
git commit -m "Add ArgoCD GitHub credentials"
git push
```

## Complete Workflow

### First-Time Setup (New Environment)

```bash
# Step 1: Create Terraform infrastructure
cd terraform/aws
terraform init -backend-config=backend-dev.tfbackend
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars

# Step 2: Create infrastructure sealed secrets
cd ../..
./scripts/seal-terraform-secrets.sh dev

# Step 3: Create application sealed secrets
./scripts/create-complete-sealed-secrets.sh dev

# Step 4: Validate no plain text secrets
./scripts/validate-secrets.sh

# Step 5: Review generated secrets
ls -la secrets/dev/
cat secrets/dev/namespace.yaml
cat secrets/dev/service-account.yaml

# Step 6: Commit to Git
git add secrets/dev/
git commit -m "Add sealed secrets for dev environment"
git push

# Step 7: Deploy to cluster via ArgoCD
kubectl apply -f argocd/bootstrap/dev/app-of-apps.yaml

# Step 8: Monitor deployment
kubectl get pods -n fineract-dev
argocd app get fineract-dev
```

### Updating Secrets

#### Update Infrastructure Secrets (after Terraform changes)

```bash
# After terraform apply
./scripts/seal-terraform-secrets.sh dev

# Commit updated secrets
git add secrets/dev/
git commit -m "Update sealed secrets after infrastructure changes"
git push

# ArgoCD will automatically sync
```

#### Update Application Secrets (password rotation)

```bash
# Regenerate application secrets
./scripts/create-complete-sealed-secrets.sh dev

# IMPORTANT: Update applications with new credentials!
# Example: Update Keycloak admin password in Keycloak UI

# Commit
git add secrets/dev/
git commit -m "Rotate application passwords for dev"
git push
```

#### Manual Secret Update

```bash
# Create secret manifest
kubectl create secret generic my-secret \
  --namespace=fineract-dev \
  --from-literal=key1=value1 \
  --from-literal=key2=value2 \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace=kube-system \
           --controller-name=sealed-secrets-controller \
           -o yaml > secrets/dev/my-secret-sealed.yaml

# Commit
git add secrets/dev/my-secret-sealed.yaml
git commit -m "Add my-secret sealed secret"
git push
```

## Security Best Practices

### DO ✅

1. **Always use sealed secrets** - Never commit plain `kind: Secret` to Git
2. **Extract from Terraform state** - Use `terraform show -json`, not `terraform output`
3. **Validate before commit** - Run `validate-secrets.sh`
4. **Use strong passwords** - Let scripts generate random passwords
5. **Document password storage** - Save generated passwords in password manager
6. **Rotate regularly** - Re-run secret creation scripts quarterly
7. **Use IRSA for AWS** - No static AWS credentials in secrets

### DON'T ❌

1. **Never commit plain text secrets** - Always seal with kubeseal
2. **Never use terraform output for passwords** - Extracts from state instead
3. **Never hardcode passwords** - Use script-generated random values
4. **Never commit .pem or .key files** - Add to .gitignore
5. **Never commit terraform.tfstate** - Contains sensitive data
6. **Never use weak passwords in prod** - Only OK for dev environment
7. **Never skip validation** - Always run validate-secrets.sh before commit

## Troubleshooting

### Problem: kubeseal fails with "unable to connect to controller"

**Solution:**
```bash
# Check sealed-secrets controller is running
kubectl get pods -n kube-system | grep sealed-secrets

# If not running, install it
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
```

### Problem: seal-terraform-secrets.sh fails with "Could not fetch RDS credentials"

**Cause:** Terraform outputs removed in Phase 5.1 for security.

**Solution:** Script now extracts from state - ensure you have latest version:
```bash
# Update script from git
git pull origin eks

# Verify it uses 'terraform show -json'
grep "terraform show -json" scripts/seal-terraform-secrets.sh
```

### Problem: Sealed secret doesn't decrypt in cluster

**Cause:** Sealed secret created with wrong controller certificate.

**Solution:** Ensure kubeseal uses correct certificate:
```bash
# Fetch current certificate
kubeseal --fetch-cert > /tmp/sealed-secrets-cert.pem

# Create secret with explicit cert
kubectl create secret generic my-secret \
  --namespace=fineract-dev \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --cert=/tmp/sealed-secrets-cert.pem \
           -o yaml > secrets/dev/my-secret-sealed.yaml
```

### Problem: "command not found: kubeseal"

**Solution:**
```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Migration from Old Scripts

### Deprecated Scripts (DO NOT USE!)

The following scripts have been removed:

1. ❌ **seal-terraform-secrets-enhanced.sh** - Broken (uses removed outputs)
2. ❌ **create-all-sealed-secrets.sh** - Superseded by create-complete
3. ❌ **regenerate-all-sealed-secrets-automated.sh** - Uses removed outputs
4. ❌ **export-client-secrets.sh** - Keycloak-specific, not needed

### Migration Guide

**If you were using seal-terraform-secrets-enhanced.sh:**
```bash
# Replace with:
./scripts/seal-terraform-secrets.sh dev
```

**If you were using create-all-sealed-secrets.sh:**
```bash
# Replace with:
./scripts/create-complete-sealed-secrets.sh dev
# Note: This creates MORE secrets (includes Grafana, Fineract Admin)
```

**If you were using regenerate-all-sealed-secrets-automated.sh:**
```bash
# Replace with manual workflow:
./scripts/seal-terraform-secrets.sh dev
./scripts/create-complete-sealed-secrets.sh dev
git add secrets/dev/
git commit -m "Regenerate sealed secrets"
git push
```

## Reference

### Sealed Secrets Resources

- **Sealed Secrets GitHub:** https://github.com/bitnami-labs/sealed-secrets
- **Documentation:** https://sealed-secrets.netlify.app/
- **Latest Release:** https://github.com/bitnami-labs/sealed-secrets/releases

### Environment Structure

```
secrets/
├── dev/
│   ├── namespace.yaml
│   ├── service-account.yaml
│   ├── fineract-db-credentials-sealed.yaml
│   ├── keycloak-db-credentials-sealed.yaml
│   ├── keycloak-admin-credentials-sealed.yaml
│   ├── fineract-admin-credentials-sealed.yaml
│   ├── oauth2-proxy-secrets-sealed.yaml
│   ├── fineract-redis-secret-sealed.yaml
│   ├── grafana-admin-credentials-sealed.yaml
│   ├── s3-connection-sealed.yaml
│   └── smtp-credentials-sealed.yaml (if SES enabled)
├── uat/
│   └── (same structure)
└── production/
    └── (same structure)
```

### Secret Types

| Secret Name | Type | Source | Contains |
|-------------|------|--------|----------|
| fineract-db-credentials | Infrastructure | Terraform | RDS host, port, username, password, JDBC URL |
| keycloak-db-credentials | Infrastructure | Terraform | Keycloak RDS database credentials |
| s3-connection | Infrastructure | Terraform | S3 bucket names, AWS region |
| service-account | Infrastructure | Terraform | IRSA role ARN annotation |
| oauth2-proxy-secrets | Infrastructure | Terraform | OAuth2 Proxy cookie secret only |
| keycloak-client-secrets | Infrastructure | Terraform | ALL OAuth2 client credentials (oauth2-proxy, admin-cli, fineract-api, fineract-data-loader) |
| smtp-credentials | Infrastructure | Terraform (optional) | SES SMTP credentials |
| fineract-redis-secret | Application | Generated | In-cluster Redis password |
| keycloak-admin-credentials | Application | Generated | Keycloak admin username/password |
| keycloak-default-users | Application | Generated | Default user passwords for Keycloak realm |
| grafana-admin-credentials | Application | Generated | Grafana admin username/password |

## Support

For issues or questions:
1. Check this guide first
2. Review script comments in `scripts/`
3. Check Sealed Secrets documentation
4. Review CODE_REVIEW.md for security requirements
5. Contact DevOps team

---

**Last Updated:** 2025-01-14 (Phase 5.8)
**Maintained By:** DevOps Team
**Status:** Production Ready ✅
