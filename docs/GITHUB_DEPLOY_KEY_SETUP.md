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
ssh-keygen -t ed25519 -C "argocd-fineract-gitops" -f ~/.ssh/argocd-deploy-key -N ""
```

This creates two files:
- `~/.ssh/argocd-deploy-key` (private key - keep secret!)
- `~/.ssh/argocd-deploy-key.pub` (public key - safe to share)

**IMPORTANT**: Do not set a passphrase (use `-N ""`) as ArgoCD cannot handle passphrase-protected keys automatically.

## Step 2: Add Deploy Key to GitHub Repository

1. Copy the public key to your clipboard:
   ```bash
   cat ~/.ssh/argocd-deploy-key.pub
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
ssh -T -i ~/.ssh/argocd-deploy-key git@github.com

# Expected output:
# Hi ADORSYS-GIS/fineract-gitops! You've successfully authenticated, but GitHub does not provide shell access.
```

If you see an error, check:
- The deploy key was added to the correct repository
- The private key file has correct permissions: `chmod 600 ~/.ssh/argocd-deploy-key`
- You're using the correct SSH URL format: `git@github.com:ADORSYS-GIS/fineract-gitops.git`

## Step 4: Create Sealed Secret for ArgoCD

The repository includes a script to create the ArgoCD repository credentials as a Sealed Secret:

```bash
# Navigate to repository root
cd /path/to/fineract-gitops

# Run the seal script (it will use ~/.ssh/argocd-deploy-key by default)
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
export SSH_KEY_PATH="${HOME}/.ssh/argocd-deploy-key"
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
- RDS PostgreSQL database
- Load balancers and networking

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
- Data loader jobs

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

### Check Fineract Data Loader Jobs

```bash
# Check job status
kubectl get jobs -n fineract-dev | grep fineract-data-loader

# View logs for a specific wave
kubectl logs -n fineract-dev job/fineract-data-loader-wave-05 -f
```

## Troubleshooting

### SSH Authentication Failures

If ArgoCD shows "authentication failed" for the repository:

1. **Verify the SSH key in ArgoCD secret**:
   ```bash
   kubectl get secret repo-fineract-gitops -n argocd -o jsonpath='{.data.sshPrivateKey}' | base64 -d
   ```
   Compare with `cat ~/.ssh/argocd-deploy-key`

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
   chmod 600 ~/.ssh/argocd-deploy-key
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
