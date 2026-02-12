# GitHub SSH Deploy Key Setup for ArgoCD

This guide explains how to set up SSH deploy keys for ArgoCD authentication with the `ADORSYS-GIS/fineract-gitops` repository.

## Why SSH Deploy Keys?

SSH deploy keys are used instead of Personal Access Tokens (PAT) because:
- They work for repository collaborators who don't own the organization
- They are repository-specific (better security)
- They don't expire like PATs
- They provide read-only or read-write access per repository

## Prerequisites

- Access to the `ADORSYS-GIS/fineract-gitops` repository (as collaborator or admin)
- `kubectl` configured to access your EKS cluster
- `kubeseal` installed (for creating Sealed Secrets)
- SSH client installed (`ssh-keygen` command available)

## Step 1: Generate SSH Deploy Key

Generate a new ED25519 SSH key pair specifically for ArgoCD:

```bash
ssh-keygen -t ed25519 -C "argocd-fineract-gitops" -f ~/.ssh/argocd-dev/fineract-deployment -N ""
```

This creates two files:
- `~/.ssh/argocd-dev/fineract-deployment` (private key - keep secret!)
- `~/.ssh/argocd-dev/fineract-deployment.pub` (public key - safe to share)

**IMPORTANT**: Do not set a passphrase (use `-N ""`) as ArgoCD cannot handle passphrase-protected keys automatically.

## Step 2: Add Deploy Key to GitHub Repository

1. Copy the public key to your clipboard:
   ```bash
   cat ~/.ssh/argocd-dev/fineract-deployment.pub
   ```

2. Navigate to the GitHub repository:
   - Go to https://github.com/ADORSYS-GIS/fineract-gitops
   - Click **Settings** → **Deploy keys** → **Add deploy key**

3. Configure the deploy key:
   - **Title**: `ArgoCD Fineract GitOps (EKS)`
   - **Key**: Paste the public key content
   - **Allow write access**: ❌ Leave unchecked (read-only is sufficient)
   - Click **Add key**

## Step 3: Test SSH Authentication

Before deploying, verify SSH access works:

```bash
# Test SSH connection to GitHub
ssh -T -i ~/.ssh/argocd-dev/fineract-deployment git@github.com

# Expected output:
# Hi ADORSYS-GIS/fineract-gitops! You've successfully authenticated, but GitHub does not provide shell access.
```

If you see an error, check:
- The deploy key was added to the correct repository
- The private key file has correct permissions: `chmod 600 ~/.ssh/argocd-dev/fineract-deployment`
- You're using the correct SSH URL format: `git@github.com:ADORSYS-GIS/fineract-gitops.git`

## Step 4: Create Sealed Secret for ArgoCD

The repository includes a script to create the ArgoCD repository credentials as a Sealed Secret:

```bash
# Navigate to repository root
cd /path/to/fineract-gitops

# Run the seal script (it will use ~/.ssh/argocd-dev/fineract-deployment by default)
./scripts/seal-argocd-ssh-credentials.sh
```

This script:
1. Validates the SSH key exists
2. Creates a Kubernetes Secret with the SSH private key
3. Encrypts it using Sealed Secrets
4. Saves the encrypted secret to `secrets/system/argocd-repo-credentials-sealed.yaml`

### Manual Sealed Secret Creation (Alternative)

If you prefer to create the sealed secret manually:

```bash
# Set environment variables
export KUBECONFIG=/path/to/your/kubeconfig
export SSH_KEY_PATH="${HOME}/.ssh/argocd-dev/fineract-deployment"
export SECRET_NAME="repo-fineract-gitops"
export NAMESPACE="argocd"
export REPO_URL="git@github.com:ADORSYS-GIS/fineract-gitops.git"

# Create the secret
kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-file=sshPrivateKey="${SSH_KEY_PATH}" \
  --dry-run=client -o json | \
jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' | \
kubeseal --controller-namespace=sealed-secrets \
         --controller-name=sealed-secrets-controller \
         --format yaml \
         > secrets/system/argocd-repo-credentials-sealed.yaml
```

## Step 5: Deploy Infrastructure

Now that SSH authentication is configured, proceed with the deployment:

### 5.1 Deploy Infrastructure (Terraform)

```bash
# Validate prerequisites
make validate-prereqs

# Deploy AWS infrastructure (VPC, EKS, RDS)
make deploy-infrastructure-dev
```

This will create:
- VPC with public/private subnets
- EKS cluster with managed node groups
- RDS PostgreSQL database (with random passwords for Fineract and Keycloak)
- OAuth2 secrets (client and cookie secrets for OAuth2-Proxy)
- Load balancers and networking

**Important:** Terraform generates persistent random passwords for:
- RDS database credentials (Fineract and Keycloak users)
- OAuth2 client secret (shared by OAuth2-Proxy and Keycloak)
- OAuth2 cookie secret (for session encryption)

These secrets are stored in Terraform state and used by the sealed secrets scripts.

### 5.2 Configure kubectl

After infrastructure is ready, configure kubectl access:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-2 --name fineract-dev-eks
```

### 5.3 Deploy Kubernetes Resources

```bash
# Deploy cluster-scoped resources (ArgoCD, Sealed Secrets, etc.)
make deploy-k8s-with-loadbalancer-dns-dev
```

This will:
1. Install Sealed Secrets controller
2. Install ArgoCD
3. Create the ArgoCD repository credentials using the SSH deploy key
4. Apply all sealed secrets
5. Configure DNS with the load balancer

### 5.4 Deploy GitOps Applications

```bash
# Deploy ArgoCD applications (bootstraps entire stack)
make deploy-gitops ENV=dev
```

This bootstraps all Fineract applications via ArgoCD:
- PostgreSQL HA cluster
- Redis
- Keycloak
- OAuth2 Proxy
- Fineract (read/write/batch)

## Step 6: Verify Deployment

### Check ArgoCD Repository Connection

```bash
# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Password: $ARGOCD_PASSWORD"

# Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
# Login: admin / <password from above>
```

In the ArgoCD UI:
1. Go to **Settings** → **Repositories**
2. Verify `git@github.com:ADORSYS-GIS/fineract-gitops.git` shows **CONNECTION STATUS: Successful**

### Check Application Sync Status

```bash
# List all ArgoCD applications
kubectl get applications -n argocd

# Check specific application
kubectl get application fineract-dev-fineract -n argocd -o yaml
```

## Sealed Secrets Management

### Understanding Sealed Secrets and Key Management

Sealed secrets are **encrypted for a specific cluster's public key**. This has important implications for your deployment workflow:

#### For Development (dev):
- **Sealed secrets are NOT committed to Git**
- Each cluster deployment regenerates secrets with fresh keys
- More secure (cluster isolation)
- Prevents key mismatch issues when redeploying

#### For Production (uat/production):
- **Sealed secrets ARE committed to Git** (after key backup)
- Controller keys backed up to AWS Secrets Manager
- Enables disaster recovery and multi-cluster deployments
- Git becomes source of truth

### Automatic Key Mismatch Detection

The deployment script automatically detects if sealed secrets in Git are incompatible with the cluster:

```
→ Validating sealed secrets compatibility...
✓ Sealed secrets are compatible with cluster
```

**Or, if there's a mismatch:**

```
✗ Sealed secrets key mismatch detected!

Sealed secrets in Git were encrypted with a different cluster's key

This happens when:
  • Deploying to a fresh cluster (new encryption keys)
  • Controller was reinstalled (keys regenerated)

Options:
  1) Auto-regenerate all sealed secrets (recommended for dev)
  2) Restore backed-up keys from AWS (for prod/disaster recovery)
  3) Continue anyway (applications will fail to start)

Choice [1-3]:
```

**Recommendation:**
- **For dev**: Choose option 1 (auto-regenerate)
- **For prod**: Choose option 2 (restore keys) if you have backups

### Manual Sealed Secrets Operations

**Regenerate sealed secrets:**
```bash
./scripts/regenerate-all-sealed-secrets.sh dev
```

This will:
1. Extract infrastructure secrets from Terraform state (RDS passwords, OAuth2 secrets)
2. Generate application secrets (Redis, Keycloak admin, Grafana)
3. Create sealed secrets encrypted with current cluster's key
4. Apply them to the cluster
5. For dev: NOT commit to Git (cluster-specific)
6. For prod: Prompt to commit (if keys are backed up)

**Note:** OAuth2 secrets must be generated by Terraform first. If you see an error about missing `oauth2_client_secret` or `oauth2_cookie_secret`, run `terraform apply` to create them.

**Backup controller keys (production):**
```bash
./scripts/backup-sealed-secrets-keys.sh production us-east-2
```

Keys are stored in AWS Secrets Manager at: `/fineract/production/sealed-secrets/master-key`

**Restore controller keys (disaster recovery):**
```bash
./scripts/restore-sealed-secrets-keys.sh production us-east-2
```

This restores the encryption keys, allowing sealed secrets from Git to decrypt properly.

**Validate compatibility:**
```bash
./scripts/validate-sealed-secrets-compatibility.sh dev
```

Exit codes:
- `0`: Compatible (secrets can decrypt)
- `1`: Incompatible (key mismatch - regeneration needed)
- `2`: Controller not ready
- `3`: No sealed secrets found

### Why Dev Secrets Aren't Committed

**Problem with committing dev secrets:**
1. Dev cluster A generates sealed secrets with key A
2. Secrets committed to Git
3. Dev cluster A destroyed
4. Dev cluster B created (generates NEW key B)
5. ArgoCD pulls secrets from Git (encrypted with key A)
6. Cluster B can't decrypt (has key B, not key A)
7. **All applications fail to start**

**Solution:**
- Dev secrets are regenerated per-cluster
- No commit to Git (avoids false sense of GitOps)
- Each dev deployment is self-contained

**For production:**
- Backup keys to AWS
- Restore keys on new clusters
- Sealed secrets in Git work everywhere
- True GitOps workflow

## Troubleshooting

### SSH Authentication Failures

If ArgoCD shows "authentication failed" for the repository:

1. **Verify the SSH key in ArgoCD secret**:
   ```bash
   kubectl get secret repo-fineract-gitops -n argocd -o jsonpath='{.data.sshPrivateKey}' | base64 -d
   ```
   Compare with `cat ~/.ssh/argocd-dev/fineract-deployment`

2. **Check deploy key in GitHub**:
   - Go to repository Settings → Deploy keys
   - Verify the key is active (not greyed out)

3. **Test SSH from a pod**:
   ```bash
   kubectl run -it --rm ssh-test --image=alpine/git --restart=Never -- sh
   # Inside pod:
   apk add openssh-client
   ssh -T git@github.com
   ```

### Sealed Secrets Not Unsealing

If secrets remain as SealedSecrets and don't create actual Secrets:

```bash
# Check sealed-secrets controller logs
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller

# Verify SealedSecret resource exists
kubectl get sealedsecrets -n argocd

# Check if Secret was created
kubectl get secret repo-fineract-gitops -n argocd
```

### Repository Connection Timeout

If ArgoCD shows connection timeout:

1. **Check cluster's internet access** (pods need to reach github.com:22)
2. **Verify security groups** allow outbound SSH (port 22)
3. **Check VPC NAT gateway** is functional

## Security Best Practices

1. **Protect the private key**:
   ```bash
   chmod 600 ~/.ssh/argocd-dev/fineract-deployment
   ```

2. **Never commit the private key to Git** (it's in `.gitignore`)

3. **Use read-only deploy keys** (unless write access is required)

4. **Rotate deploy keys periodically**:
   - Generate new key pair
   - Add new public key to GitHub
   - Update sealed secret
   - Remove old deploy key from GitHub

5. **Monitor deploy key usage** in GitHub repository settings

## Key Differences from PAT Authentication

| Aspect | SSH Deploy Key | Personal Access Token |
|--------|---------------|----------------------|
| **Scope** | Single repository | Multiple repositories |
| **Ownership** | Repository-specific | User account |
| **Expiration** | Never expires | Can expire |
| **Permissions** | Read or Read/Write | Scoped to token permissions |
| **Org Membership** | Not required | May require org membership |
| **Revocation** | Per repository | Affects all repos |

## Files Updated for SSH Authentication

The following files were updated to use SSH URLs (`git@github.com:...`) instead of HTTPS:

1. **ArgoCD Configuration**:
   - `argocd/config/repository-config.yaml`
   - `argocd/config/argocd-cm.yaml`

2. **Kustomize ConfigMaps** (6 files):
   - `argocd/applications/dev/argocd-config.yaml`
   - `argocd/applications/uat/argocd-config.yaml`
   - `argocd/applications/prod/argocd-config.yaml`
   - `argocd/applications/operations/argocd-config.yaml`
   - `argocd/applications/cluster-scoped/argocd-config.yaml`
   - `argocd/applications/system/argocd-config.yaml`

3. **ApplicationSet**:
   - `argocd/applications/fineract-applicationset.yaml`

4. **Bootstrap Applications**:
   - `argocd/bootstrap/dev/app-of-apps.yaml`
   - `argocd/bootstrap/uat/app-of-apps.yaml`
   - `argocd/bootstrap/prod/app-of-apps.yaml`

5. **Deployment Script**:
   - `scripts/steps/03-setup-argocd.sh`

## Summary

By using SSH deploy keys:
- ✅ Repository collaborators can deploy without org ownership
- ✅ More secure (repository-scoped credentials)
- ✅ No token expiration issues
- ✅ Standard Git SSH authentication workflow
- ✅ Compatible with GitOps best practices

The SSH URL format (`git@github.com:ADORSYS-GIS/fineract-gitops.git`) is now used throughout the repository, and ArgoCD authenticates using the SSH private key stored in the sealed secret.
