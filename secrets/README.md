# Secrets Management with Sealed Secrets

This directory contains **encrypted** secrets for all environments. These secrets are safe to commit to Git.

## Directory Structure

```
secrets/
├── .gitignore          # Blocks plaintext secrets
├── README.md           # This file
├── base/               # Secret templates (no real values)
├── dev/                # Dev environment sealed secrets
├── uat/                # UAT environment sealed secrets
└── production/         # Production environment sealed secrets
```

## What are Sealed Secrets?

Sealed Secrets are encrypted Kubernetes secrets that can be safely stored in Git. They are encrypted with the cluster's public key and can only be decrypted by the Sealed Secrets controller running in the cluster.

## Creating Sealed Secrets

### Prerequisites

1. **Install kubeseal CLI:**
   ```bash
   # macOS
   brew install kubeseal

   # Linux
   wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz
   tar -xvzf kubeseal-0.27.0-linux-amd64.tar.gz
   sudo install -m 755 kubeseal /usr/local/bin/kubeseal
   ```

2. **Ensure Sealed Secrets controller is deployed:**
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
   ```

### Automated Creation (Recommended)

Use the provided scripts to create all sealed secrets:

#### For Terraform-Managed Secrets (RDS, S3, etc.):
```bash
./scripts/seal-terraform-secrets.sh dev
./scripts/seal-terraform-secrets.sh uat
./scripts/seal-terraform-secrets.sh production
```

This creates:
- `fineract-db-credentials` (RDS database)
- `keycloak-db-credentials` (RDS database)
- `s3-connection` (S3 buckets)
- `aws-rds-credentials` (RDS endpoint)
- `fineract-redis-credentials` (ElastiCache - if enabled)
- `smtp-credentials` (SES - if enabled)

#### For Application Secrets:
```bash
./scripts/create-all-sealed-secrets.sh dev
./scripts/create-all-sealed-secrets.sh uat
./scripts/create-all-sealed-secrets.sh production
```

This creates:
- `redis-credentials` (in-cluster Redis)
- `keycloak-admin-credentials` (Keycloak admin user)

### Manual Creation

1. **Create plaintext secret (in memory, never saved to disk):**
   ```bash
   kubectl create secret generic my-secret \
     --namespace=fineract-dev \
     --from-literal=username=myuser \
     --from-literal=password=mypassword \
     --dry-run=client -o yaml > /tmp/my-secret.yaml
   ```

2. **Encrypt with kubeseal:**
   ```bash
   kubeseal --controller-namespace=kube-system \
            --controller-name=sealed-secrets-controller \
            --format yaml \
            < /tmp/my-secret.yaml \
            > secrets/dev/my-secret-sealed.yaml
   ```

3. **Delete plaintext file immediately:**
   ```bash
   rm /tmp/my-secret.yaml
   ```

4. **Commit encrypted secret:**
   ```bash
   git add secrets/dev/my-secret-sealed.yaml
   git commit -m "Add my-secret for dev environment"
   git push
   ```

## Rotating Secrets

1. **Create new sealed secret** (overwrites old one):
   ```bash
   kubectl create secret generic my-secret \
     --namespace=fineract-dev \
     --from-literal=password=NEW_PASSWORD \
     --dry-run=client -o yaml | \
   kubeseal ... > secrets/dev/my-secret-sealed.yaml
   ```

2. **Commit and push:**
   ```bash
   git add secrets/dev/my-secret-sealed.yaml
   git commit -m "Rotate my-secret password"
   git push
   ```

3. **ArgoCD syncs automatically** (~1-2 minutes)

4. **Restart application** to pick up new secret:
   ```bash
   kubectl rollout restart deployment/myapp -n fineract-dev
   ```

## Secrets Inventory

### DEV Environment (`fineract-dev` namespace)

| Secret Name | Keys | Purpose |
|-------------|------|---------|
| `fineract-db-credentials` | `host`, `port`, `username`, `password`, `jdbc-url` | Fineract RDS database |
| `keycloak-db-credentials` | `host`, `port`, `username`, `password`, `jdbc-url` | Keycloak RDS database |
| `keycloak-admin-credentials` | `username`, `password` | Keycloak admin console |
| `oauth2-proxy-secrets` | `client-id`, `client-secret`, `cookie-secret` | OAuth2 Proxy auth |
| `s3-connection` | `documents-bucket`, `region` | S3 document storage |
| `fineract-redis-secret` | `redis-password` | In-cluster Redis |
| `fineract-admin-credentials` | `client-id`, `client-secret`, `token-url` | Data loader jobs |
| `keycloak-client-secrets` | Various client secrets | Keycloak OAuth clients |
| `grafana-admin-credentials` | `username`, `password` | Grafana admin |

### UAT/Production Environments

Same secrets as DEV, but with:
- Different passwords (stronger in production)
- Different Terraform-sourced values (RDS endpoints, S3 buckets)
- Encrypted for respective clusters

## Security Best Practices

### DO ✅

- ✅ Use `openssl rand -base64 32` for strong passwords
- ✅ Different passwords for each environment
- ✅ Encrypt before committing to Git
- ✅ Delete plaintext files immediately after encryption
- ✅ Backup Sealed Secrets controller keys
- ✅ Rotate secrets every 90 days
- ✅ Review Git commits before pushing

### DON'T ❌

- ❌ Commit plaintext secrets to Git
- ❌ Use same password across environments
- ❌ Use weak passwords (< 16 chars)
- ❌ Share passwords via email/Slack
- ❌ Store controller keys in Git
- ❌ Keep plaintext files on disk

## Disaster Recovery

### Backup Controller Keys

**CRITICAL:** The controller's private keys are required to decrypt secrets.

```bash
# Backup all Sealed Secrets keys
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-keys-backup-$(date +%Y%m%d).yaml
```

Store backup in:
- Password manager (1Password, LastPass)
- Encrypted USB drive
- Secure file share (NOT in Git!)

### Restore to New Cluster

```bash
# 1. Apply backed-up keys
kubectl apply -f sealed-secrets-keys-backup-20250110.yaml

# 2. Install controller
kubectl apply -k apps/sealed-secrets-controller/base/

# 3. Restart controller
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system

# 4. Verify
kubectl get sealedsecrets -A
kubectl get secrets -A
```

## Troubleshooting

### SealedSecret not decrypting

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check SealedSecret status
kubectl get sealedsecret my-secret -n fineract-dev -o yaml

# Common errors:
# - "no key could decrypt secret" → Encrypted for wrong cluster
# - "unsupported algorithm" → Version mismatch
```

### Wrong cluster

Re-encrypt for correct cluster:

```bash
kubeseal --context production-cluster \
  < secret.yaml > secrets/production/secret-sealed.yaml
```

## References

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [GitOps Secrets Management](https://www.redhat.com/en/blog/a-guide-to-secrets-management-with-gitops-and-kubernetes)
