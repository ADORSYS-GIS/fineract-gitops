# Secrets Management Strategy

**UPDATE (2025-01-10)**: This document has been updated to reflect the migration to **Sealed Secrets** as the primary secrets management approach for better portability and true GitOps compliance.

**DEPRECATION NOTICE**: External Secrets Operator has been removed in favor of Sealed Secrets for better cloud portability, simpler architecture, and pure GitOps principles.

This document outlines the secrets management strategy for the Fineract GitOps repository using [Sealed Secrets](https://sealed-secrets.netlify.app/) with Bitnami Sealed Secrets Controller.

## Table of Contents

- [Overview](#overview)
- [Why Sealed Secrets?](#why-sealed-secrets)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Workflow](#workflow)
- [Environment Strategy](#environment-strategy)
- [Security Best Practices](#security-best-practices)
- [Backup and Recovery](#backup-and-recovery)
- [Troubleshooting](#troubleshooting)
- [Migration from Plaintext Secrets](#migration-from-plaintext-secrets)
- [FAQ](#faq)

## Overview

**Problem:** GitOps requires storing all configuration in Git, but secrets contain sensitive data that cannot be stored in plaintext.

**Solution:** Sealed Secrets encrypts secrets with the cluster's public key, allowing them to be safely stored in Git. Only the Sealed Secrets controller running in the cluster can decrypt them using its private key.

**Benefits:**
- ✅ True GitOps - Everything in Git (encrypted)
- ✅ No cloud dependencies - Works on any Kubernetes
- ✅ Self-contained - No external secret stores needed
- ✅ Fast - No external API calls
- ✅ Portable - Works on AWS, GCP, Azure, on-prem
- ✅ Free - No cloud service costs
- ✅ Simple architecture - Just controller + kubeseal CLI
- ✅ Secrets never stored in plaintext

## Why Sealed Secrets?

We evaluated several options and chose Sealed Secrets:

| Solution | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Sealed Secrets** | Simple, no infrastructure, GitOps-native, portable | Encrypted secrets in Git, cluster coupling, manual rotation | ✅ **CHOSEN** (Jan 2025) |
| ~~External Secrets Operator~~ | Cloud-native, dynamic secrets, AWS integration | AWS dependency, complex, costly | ❌ **DEPRECATED** (Jan 2025) |
| SOPS | Multiple backends, mature | Requires KMS, harder rotation | ❌ Needs additional tooling |
| Git-crypt | Simple | Not Kubernetes-native | ❌ Poor K8s integration |
| Plaintext in Git | Simple | **INSECURE** | ❌ Security risk |

**Decision (2025-01-10):** Sealed Secrets provides the best balance of simplicity, portability, and GitOps purity. The migration from External Secrets Operator was completed to gain:
- Cloud portability (no AWS lock-in)
- Simpler architecture (no external dependencies)
- Lower costs (no AWS Secrets Manager fees ~$24/year)
- True GitOps (everything in Git, even if encrypted)
- Faster secret resolution (no API calls)

## Architecture

```
PHASE 1: SECRET CREATION (Local Machine)
════════════════════════════════════════════════

┌──────────────┐
│  Terraform   │  1. Provisions AWS resources (RDS, S3)
│    (AWS)     │     Outputs: passwords, endpoints, bucket names
└──────┬───────┘
       │
       ▼
┌─────────────────────────────────────┐
│  Scripts (seal-terraform-secrets.sh) │  2. Extracts Terraform outputs
│  - Fetches RDS passwords            │     Generates strong passwords
│  - Fetches S3 bucket names          │     for non-Terraform secrets
│  - Generates application passwords  │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────┐
│  kubectl create │  3. Creates secret YAML (in memory)
│  --dry-run      │     Never saved to disk!
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  kubeseal       │  4. Encrypts with cluster's public key
│  (CLI tool)     │     Uses RSA-2048 encryption
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  SealedSecret (encrypted YAML)      │  5. Safe to commit to Git
│  secrets/dev/fineract-db-*-sealed.yaml │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────┐
│  Git Repository │  6. git add → commit → push
│  (GitHub)       │     Encrypted secrets in version control
└────────┬────────┘
         │
         │
PHASE 2: DEPLOYMENT (Kubernetes Cluster)
════════════════════════════════════════════════
         │
         ▼
┌─────────────────┐
│  ArgoCD         │  7. Syncs from Git repository
│  (GitOps)       │     Detects new/changed SealedSecrets
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Kubernetes API Server                      │
│  ├─ Namespace: fineract-dev                 │
│  └─ Resource: SealedSecret/*                │
└────────┬────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Sealed Secrets Controller                  │
│  (runs in kube-system namespace)            │
│                                             │
│  1. Watches for SealedSecret resources      │
│  2. Retrieves cluster's private key         │
│  3. Decrypts SealedSecret                   │
│  4. Creates regular Kubernetes Secret       │
└────────┬────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Kubernetes Secret                          │
│  Name: fineract-db-credentials              │
│  Namespace: fineract-dev                    │
│  Type: Opaque                               │
│                                             │
│  Data:                                      │
│    host: fineract-db.xxx.rds.amazonaws.com │
│    port: 5432                               │
│    username: fineract                       │
│    password: <decrypted>                    │
│    jdbc-url: jdbc:postgresql://...         │
└────────┬────────────────────────────────────┘
         │
         │
PHASE 3: CONSUMPTION (Application Pods)
════════════════════════════════════════════════
         │
         ▼
┌─────────────────────────────────────────────┐
│  Fineract Deployment                        │
│                                             │
│  env:                                       │
│  - name: FINERACT_HIKARI_JDBC_URL           │
│    valueFrom:                               │
│      secretKeyRef:                          │
│        name: fineract-db-credentials  ◄─────┼─ References secret
│        key: jdbc-url                        │   by name & key
│                                             │
│  - name: FINERACT_HIKARI_PASSWORD           │
│    valueFrom:                               │
│      secretKeyRef:                          │
│        name: fineract-db-credentials  ◄─────┼─ Same secret,
│        key: password                        │   different key
└────────┬────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Application Pod (Running Container)        │
│                                             │
│  Environment Variables:                     │
│    FINERACT_HIKARI_JDBC_URL=jdbc:post...   │
│    FINERACT_HIKARI_PASSWORD=<actual-pwd>   │
│                                             │
│  Application uses these credentials         │
│  to connect to RDS PostgreSQL              │
└─────────────────────────────────────────────┘
```

**Key Points:**
- ✅ Secrets encrypted with cluster's public key (only that cluster can decrypt)
- ✅ Encrypted secrets safe to commit to Git
- ✅ No external dependencies (AWS, etc.)
- ✅ Works on any Kubernetes cluster

## Getting Started

### Prerequisites

1. **Sealed Secrets Controller** installed in cluster
2. **kubeseal CLI** installed locally
3. **kubectl** access to cluster

### Installation

#### 1. Install Sealed Secrets Controller

```bash
# Via ArgoCD (recommended)
kubectl apply -f argocd/applications/system/sealed-secrets-controller.yaml

# Verify deployment
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

#### 2. Install kubeseal CLI

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.3/kubeseal-0.26.3-linux-amd64.tar.gz
tar -xvzf kubeseal-0.26.3-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Verify
kubeseal --version
```

#### 3. Fetch Public Key (Optional)

```bash
# Download public key for offline encryption
kubeseal --fetch-cert \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  > pub-sealed-secrets.pem

# Use offline:
kubeseal --cert pub-sealed-secrets.pem < secret.yaml > sealed-secret.yaml
```

## Workflow

### Sealing Terraform-Managed Secrets (for AWS Managed Provider)

When using a managed cloud provider (like AWS with RDS, ElastiCache, S3), Terraform provisions these services and their credentials. The `scripts/seal-terraform-secrets.sh` script automates the process of extracting these credentials from Terraform outputs and creating Sealed Secrets for them.

**Usage:**

```bash
./scripts/seal-terraform-secrets.sh <environment> # e.g., dev, uat, production
```

**This script will:**
- Navigate to the `terraform/aws` directory, run `terraform output` to fetch credentials (RDS, S3, ElastiCache, SES).
- Create `rds-connection-sealed.yaml`, `aws-rds-credentials-sealed.yaml`, `fineract-db-credentials-sealed.yaml`, `s3-connection-sealed.yaml`, and optionally `smtp-credentials-sealed.yaml` in `secrets/<environment>/`.
- Create `fineract-redis-credentials-sealed.yaml` if ElastiCache is provisioned.
- Generate a `service-account.yaml` manifest with the correct IRSA annotation for Fineract.

**Prerequisites:**
- Terraform `apply` must have been successfully completed for the target environment.
- `kubectl` and `kubeseal` CLIs must be installed and configured.
- Sealed Secrets controller must be deployed in the cluster.

**Next Steps after running the script:**
1. Review the generated sealed secrets in `secrets/<environment>/`.
2. Commit these sealed secrets to Git.
3. ArgoCD will then sync these secrets to your Kubernetes cluster.

### Creating a New Secret

#### Option 1: Automated Generation (Recommended for initial setup)

Use the provided script to generate all common sealed secrets for a given environment. This is ideal for initial setup or when you need to regenerate all standard secrets.

```bash
./scripts/create-all-sealed-secrets.sh <environment> # e.g., dev, uat, production
```

This script will:
- Generate strong random passwords for Redis and Keycloak admin.
- Create `redis-credentials-sealed.yaml` and `keycloak-admin-credentials-sealed.yaml` in `secrets/<environment>/`.
- Output important credentials to the console (save these securely!).

**Note:** Database (PostgreSQL) and S3 credentials for managed cloud providers are typically provisioned and managed by Terraform, not this script. Refer to the `terraform/aws/README.md` for details on how those secrets are handled.

#### Option 2: Manual Creation (For custom or individual secrets)

For secrets not covered by the automation script, or for more granular control, follow these manual steps:

**Step 1: Copy Template**

```bash
cp secrets/base/postgresql-credentials.template.yaml /tmp/my-secret.yaml
```

**Step 2: Generate Strong Password**

```bash
pwgen -s 32 1 # Generate 32-character random password
# Or use openssl
openssl rand -base64 32
```

**Step 3: Edit Secret**

```bash
nano /tmp/my-secret.yaml
```

Replace `REPLACE_WITH_STRONG_PASSWORD` with generated password.

**Step 4: Encrypt Secret**

```bash
kubeseal --controller-namespace kube-system \
         --controller-name sealed-secrets-controller \
         --format yaml \
         --context dev-cluster \
         < /tmp/my-secret.yaml \
         > secrets/dev/my-secret-sealedsecret.yaml
```

**Step 5: Delete Unencrypted File**

```bash
rm /tmp/my-secret.yaml
```

**Step 6: Commit to Git**

```bash
git add secrets/dev/my-secret-sealedsecret.yaml
git commit -m "feat: add my-secret for dev environment"
git push
```

**Step 7: ArgoCD Syncs**

ArgoCD automatically:
1. Detects new SealedSecret
2. Applies to cluster
3. Controller decrypts to regular Secret
4. Applications use the Secret

### Rotating a Secret

**When to Rotate:**
- Every 90 days (recommended)
- After security incident
- When employee leaves
- After accidental exposure

**How to Rotate:**

```bash
# 1. Create new secret with new password
pwgen -s 32 1  # Generate new password

# 2. Edit and encrypt
nano /tmp/my-secret-new.yaml
kubeseal ... < /tmp/my-secret-new.yaml > secrets/dev/my-secret-sealedsecret.yaml

# 3. Commit (overwrites old encrypted secret)
git add secrets/dev/my-secret-sealedsecret.yaml
git commit -m "chore: rotate my-secret password"
git push

# 4. ArgoCD syncs automatically
# Wait ~1 minute for sync

# 5. Restart application (if needed)
kubectl rollout restart deployment/myapp -n fineract

# 6. Verify application still works
kubectl get pods -n fineract
kubectl logs -n fineract deployment/myapp

# 7. Clean up
rm /tmp/my-secret-new.yaml
```

## Environment Strategy

### Three Environments

| Environment | Purpose | Secret Strength | Encryption Key |
|-------------|---------|-----------------|----------------|
| **Dev** | Development & testing | Moderate (16+ chars) | Dev cluster key |
| **UAT** | User acceptance testing | Strong (24+ chars) | UAT cluster key |
| **Production** | Live system | Very strong (32+ chars) | Prod cluster key |

### Different Passwords Per Environment

**Why?**
- Prevents dev passwords from leaking to production
- Limits blast radius if one environment is compromised
- Allows different rotation schedules

**Example:**

```
Dev:        postgres-password: "dev-postgres-2024"
UAT:        postgres-password: "X9mK2pL5vW8tR3hY6jC4fD1gS7aZ9bN3"
Production: postgres-password: "Q7wE9rT2yU5iO8pA3sD6fG1hJ4kL9zX2cV5bN8mM1"
```

### Directory Structure

```
secrets/
├── base/                # Templates (no real passwords)
│   ├── postgresql-credentials.template.yaml
│   ├── redis-credentials.template.yaml
│   └── ...
├── dev/                 # Dev encrypted secrets
│   ├── postgresql-credentials-sealedsecret.yaml
│   ├── redis-credentials-sealedsecret.yaml
│   └── ...
├── uat/                 # UAT encrypted secrets
│   └── ...
└── production/          # Production encrypted secrets
    └── ...
```

### Environment Kustomization

**`environments/dev/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../apps/postgresql/base
  - ../../secrets/dev/postgresql-credentials-sealedsecret.yaml
  - ../../secrets/dev/redis-credentials-sealedsecret.yaml
  # ... other dev secrets
```

**`environments/production/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../apps/postgresql/base
  - ../../secrets/production/postgresql-credentials-sealedsecret.yaml
  - ../../secrets/production/redis-credentials-sealedsecret.yaml
  # ... other production secrets
```

## Security Best Practices

### Password Requirements

| Environment | Min Length | Complexity | Example Generator |
|-------------|------------|------------|-------------------|
| Dev | 16 chars | Alphanumeric | `pwgen -s 16 1` |
| UAT | 24 chars | Alphanumeric + symbols | `pwgen -sy 24 1` |
| Production | 32 chars | Alphanumeric + symbols | `pwgen -sy 32 1` |

### DO ✅

- ✅ Use `pwgen -s 32 1` for strong passwords
- ✅ Different passwords for each environment
- ✅ Encrypt before committing to Git
- ✅ Delete unencrypted files immediately
- ✅ Backup Sealed Secrets controller keys
- ✅ Rotate secrets every 90 days
- ✅ Use `.gitignore` to block plaintext secrets
- ✅ Review Git commits for accidental secrets

### DON'T ❌

- ❌ Commit plaintext secrets to Git
- ❌ Use same password across environments
- ❌ Use weak passwords (< 16 chars, dictionary words)
- ❌ Share passwords via email/Slack
- ❌ Store controller keys in Git
- ❌ Reuse passwords from other systems
- ❌ Keep unencrypted files on disk

### Git Security

**`.gitignore` Configuration:**

```gitignore
# In secrets/.gitignore
*.yaml                    # Block all YAML
!*-sealedsecret.yaml     # Allow encrypted
!base/*.template.yaml    # Allow templates
```

**Pre-commit Hook (Optional):**

```bash
# .git/hooks/pre-commit
#!/bin/bash
if git diff --cached --name-only | grep -E "secret.*\.yaml" | grep -v "sealedsecret.yaml"; then
  echo "ERROR: Attempting to commit plaintext secret!"
  exit 1
fi
```

## Backup and Recovery

### Automated Key Persistence

To ensure the resilience and recoverability of our Sealed Secrets, the controller's encryption keys are automatically backed up to AWS Secrets Manager. This prevents catastrophic data loss if a cluster is destroyed or needs to be rebuilt.

#### 1. Automated Backup Process

The `scripts/backup-sealed-secrets-keys.sh` script automates the extraction and secure storage of the Sealed Secrets controller's private and public keys.

*   **Key Extraction:** The script connects to the Kubernetes cluster, identifies the active Sealed Secrets controller keys in the `kube-system` namespace, and extracts them.
*   **Secure Storage:** The extracted keys are then base64 encoded and stored as a versioned secret in AWS Secrets Manager. The secret name follows the pattern `/fineract/<environment>/sealed-secrets/master-key` (e.g., `/fineract/dev/sealed-secrets/master-key`).
*   **Automated Trigger:** This backup process is integrated into our automated deployment pipeline. Specifically, the `scripts/deploy-with-loadbalancer-dns.sh` script automatically executes `scripts/backup-sealed-secrets-keys.sh` after the Sealed Secrets controller has been successfully deployed. This ensures that keys are backed up as part of every full environment deployment.

#### 2. Disaster Recovery / Key Restoration

In the event of a cluster loss, migration, or if the Sealed Secrets controller keys are otherwise compromised or lost, they can be restored using the `scripts/restore-sealed-secrets-keys.sh` script.

*   **Key Retrieval:** The restoration script fetches the appropriate versioned keys from AWS Secrets Manager based on the specified environment.
*   **Cluster Application:** It then applies these retrieved keys to the Kubernetes cluster.
*   **Controller Integration:** Once the keys are applied, the Sealed Secrets controller (which must be running in the cluster) will automatically pick them up, enabling it to decrypt all existing SealedSecrets.

#### 3. Manual Backup (Optional, for ad-hoc needs)

While automated backups are in place, you can manually trigger a backup if needed:

```bash
./scripts/backup-sealed-secrets-keys.sh <environment> [aws-region]
# Example: ./scripts/backup-sealed-secrets-keys.sh dev us-east-2
```

#### 4. Manual Restoration (Optional, for ad-hoc needs)

Similarly, you can manually trigger a restoration:

```bash
./scripts/restore-sealed-secrets-keys.sh <environment> [aws-region]
# Example: ./scripts/restore-sealed-secrets-keys.sh dev us-east-2
```

**CRITICAL:** Backing up the controller's private keys is essential. The automated process ensures this, but understanding the manual options is also important for advanced scenarios.

## Troubleshooting

### SealedSecret Not Decrypting

**Symptoms:**
- SealedSecret exists but no Secret created
- Controller logs show decryption errors

**Debug:**

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check SealedSecret status
kubectl get sealedsecret -n fineract my-secret -o yaml

# Common errors:
# - "no key could decrypt secret" → Encrypted for wrong cluster
# - "unsupported algorithm" → Version mismatch
```

**Solutions:**

1. **Wrong Cluster:** Re-encrypt with correct `--context`
2. **Version Mismatch:** Update kubeseal CLI to match controller
3. **RBAC Issue:** Check controller has permissions

### Can't Find Controller

**Check if controller is running:**

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
kubectl get svc -n kube-system sealed-secrets-controller
```

**If not running:**

```bash
# Reinstall
kubectl apply -k apps/sealed-secrets-controller/base/
```

### Wrong Encryption Key

**Problem:** Encrypted for dev, trying to use in production

**Solution:** Must re-encrypt for each environment:

```bash
# Encrypt for production
kubeseal --context production-cluster ... \
  < secret.yaml \
  > secrets/production/secret-sealedsecret.yaml
```

### Password Still Plaintext

**Check if .gitignore is working:**

```bash
cd secrets/
git status

# Should NOT show *.yaml files (except sealedsecret.yaml)
```

**If plaintext files appear:**

```bash
# Remove from Git (keep local)
git rm --cached secret.yaml

# Or remove completely
git rm secret.yaml
```

## Migration from Plaintext Secrets

If you have existing plaintext secrets in `apps/*/base/secret.yaml`:

### Step 1: Audit Existing Secrets

```bash
# Find all plaintext secrets
find apps/ -name "secret*.yaml"

# List:
# apps/postgresql/base/secret.yaml
# apps/redis/base/secret.yaml
# apps/kafka/base/secret.yaml
# ... etc
```

### Step 2: Create Templates

For each secret:

```bash
# Copy to template directory
cp apps/postgresql/base/secret.yaml \
   secrets/base/postgresql-credentials.template.yaml

# Edit: Replace passwords with REPLACE_WITH_STRONG_PASSWORD
nano secrets/base/postgresql-credentials.template.yaml
```

### Step 3: Create Encrypted Secrets

For each environment:

```bash
# Create secret with real password
cp secrets/base/postgresql-credentials.template.yaml /tmp/pg-dev.yaml
nano /tmp/pg-dev.yaml  # Add real password

# Encrypt
kubeseal --context dev-cluster ... \
  < /tmp/pg-dev.yaml \
  > secrets/dev/postgresql-credentials-sealedsecret.yaml

# Clean up
rm /tmp/pg-dev.yaml
```

### Step 4: Update Kustomizations

Remove secret from app base:

**Before (`apps/postgresql/base/kustomization.yaml`):**

```yaml
resources:
  - deployment.yaml
  - service.yaml
  - secret.yaml  # ← Remove this
```

**After:**

```yaml
resources:
  - deployment.yaml
  - service.yaml
  # secret.yaml removed - now in environments/*/
```

Add to environment overlay:

**`environments/dev/kustomization.yaml`:**

```yaml
resources:
  - ../../apps/postgresql/base
  - ../../secrets/dev/postgresql-credentials-sealedsecret.yaml
```

### Step 5: Test

```bash
# Apply to dev cluster
kubectl apply -k environments/dev/

# Verify secret created
kubectl get secret postgresql-credentials -n fineract -o yaml

# Verify application works
kubectl get pods -n fineract
```

### Step 6: Remove Plaintext Secrets

```bash
# Delete plaintext secret files
git rm apps/postgresql/base/secret.yaml
git rm apps/redis/base/secret.yaml
# ... etc

git commit -m "chore: remove plaintext secrets, migrated to SealedSecrets"
```

## FAQ

### Q: Can I use the same SealedSecret across multiple clusters?

**A:** No. Each cluster has unique encryption keys. You must create separate SealedSecrets for each environment.

### Q: What happens if I lose the controller keys?

**A:** You must re-create all secrets with new passwords and re-encrypt them. This is why backing up keys is critical.

### Q: Can I view the decrypted secret?

**A:** Yes, but only from within the cluster:

```bash
kubectl get secret my-secret -n fineract -o yaml
echo "base64string" | base64 -d
```

### Q: How do I share secrets with team members?

**A:** Don't! Each developer should:
1. Use dev environment (weak passwords OK)
2. Production secrets managed by ops team only
3. Use password manager for production access

### Q: Can I automate secret rotation?

**A:** Yes, with a script:

```bash
#!/bin/bash
# rotate-secret.sh
NEW_PASSWORD=$(pwgen -sy 32 1)
# ... update secret, encrypt, commit, push
```

Schedule with cron or CI/CD.

### Q: What if kubeseal version doesn't match controller?

**A:** Update kubeseal CLI to match controller version:

```bash
# Check controller version
kubectl get deployment -n kube-system sealed-secrets-controller \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Install matching kubeseal version
# Example: v0.26.3
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.3/...
```

### Q: Can I use Sealed Secrets with Helm?

**A:** Yes! Create SealedSecret for Helm values:

```bash
# Encrypt values
kubeseal ... < helm-values-secret.yaml > sealed-values.yaml

# Reference in Helm
helm install myapp ... -f sealed-values.yaml
```

### Q: How do I migrate to a different secrets solution later?

**A:**
1. Deploy new secrets solution (e.g., External Secrets Operator, SOPS, Vault)
2. Configure to create same Secret resources with same names/keys
3. Test applications work with new secrets
4. Remove SealedSecrets gradually
5. Uninstall Sealed Secrets controller

## References

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [GitOps Secrets Management Guide](https://www.redhat.com/en/blog/a-guide-to-secrets-management-with-gitops-and-kubernetes)
- [Argo CD Secret Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/#security-properties)

## Support

For questions or issues:
1. Check this documentation
2. Review `secrets/README.md`
3. Check Sealed Secrets GitHub issues
4. Contact platform team
