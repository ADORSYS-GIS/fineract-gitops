# GitHub Token Setup for ArgoCD

This document explains how to manage GitHub Personal Access Tokens (PAT) for ArgoCD Git repository access.

## Overview

ArgoCD needs access to the GitHub repository to sync applications. We use GitHub Personal Access Tokens stored as Sealed Secrets for secure authentication.

## Creating a GitHub Personal Access Token

### 1. Generate Token on GitHub

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Direct link: https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Configure the token:
   - **Note**: `fineract-gitops-argocd-access`
   - **Expiration**: 90 days (recommended) or as per security policy
   - **Scopes**: Select only `repo` (Full control of private repositories)
4. Click "Generate token"
5. **IMPORTANT**: Copy the token immediately - you won't be able to see it again!

### 2. Store Token in macOS Keychain (Recommended)

Store the token securely in your macOS Keychain for future use:

```bash
# Add token to Keychain (you'll be prompted to paste the token)
security add-internet-password \
  -s github.com \
  -a guymoyo \
  -l "GitHub PAT for fineract-gitops ArgoCD" \
  -w
```

### 3. Retrieve Token from Keychain

When you need to use the token:

```bash
# Retrieve the token (will prompt for system password)
security find-internet-password -s github.com -a guymoyo -w
```

## Creating ArgoCD Repository Credential

### Automated Method (Recommended)

Use the provided script to create the sealed secret:

```bash
# From repository root
./scripts/seal-argocd-github-credentials.sh

# The script will:
# 1. Prompt for your GitHub token (or retrieve from Keychain)
# 2. Create a sealed secret
# 3. Save to: secrets/system/argocd-repo-credentials-sealed.yaml
```

### Manual Method

If you need to create the secret manually:

```bash
# Set your GitHub token
export GITHUB_TOKEN="ghp_your_token_here"

# Create the secret
kubectl create secret generic repo-fineract-gitops \
  --namespace=argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/ADORSYS-GIS/fineract-gitops.git \
  --from-literal=password=$GITHUB_TOKEN \
  --from-literal=username=not-used \
  --dry-run=client -o yaml | \
kubeseal --format=yaml --cert <(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d) \
  > secrets/system/argocd-repo-credentials-sealed.yaml

# Add label to mark it as ArgoCD repository credential
kubectl label -f secrets/system/argocd-repo-credentials-sealed.yaml \
  argocd.argoproj.io/secret-type=repository --local -o yaml | \
  sponge secrets/system/argocd-repo-credentials-sealed.yaml
```

## Applying the Secret to ArgoCD

### First-Time Setup

```bash
# Apply the sealed secret to the cluster
kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml

# Verify the secret was created in ArgoCD namespace
kubectl get secret repo-fineract-gitops -n argocd

# Verify ArgoCD can access the repository
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

### Testing Repository Access

```bash
# Check ArgoCD logs for authentication issues
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50 | grep -i auth

# Test sync of an application
kubectl get applications -n argocd
```

## Token Rotation

GitHub tokens should be rotated periodically for security. Here's how:

### When Token Expires or Needs Rotation

1. **Generate new token** following the steps above
2. **Update Keychain** (if using):
   ```bash
   # Delete old entry
   security delete-internet-password -s github.com -a guymoyo

   # Add new token
   security add-internet-password -s github.com -a guymoyo \
     -l "GitHub PAT for fineract-gitops ArgoCD" -w
   ```

3. **Regenerate sealed secret**:
   ```bash
   ./scripts/seal-argocd-github-credentials.sh
   ```

4. **Apply updated secret**:
   ```bash
   kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml

   # Restart ArgoCD components to pick up new credentials
   kubectl rollout restart deployment -n argocd argocd-repo-server
   kubectl rollout restart deployment -n argocd argocd-server
   ```

5. **Commit to Git**:
   ```bash
   git add secrets/system/argocd-repo-credentials-sealed.yaml
   git commit -m "security: rotate GitHub PAT for ArgoCD"
   git push
   ```

## Troubleshooting

### ArgoCD Cannot Sync - Authentication Required

**Symptoms:**
- Applications show "ComparisonError"
- Error message: "authentication required: Repository not found"

**Solution:**
1. Verify the sealed secret exists:
   ```bash
   kubectl get sealedsecret -n argocd repo-fineract-gitops
   ```

2. Check if it was decrypted properly:
   ```bash
   kubectl get secret -n argocd repo-fineract-gitops
   ```

3. Verify the label is present:
   ```bash
   kubectl get secret -n argocd repo-fineract-gitops -o yaml | grep argocd.argoproj.io/secret-type
   ```

4. If missing, regenerate using the script

### Token Not Found in Keychain

**Symptoms:**
- `security find-internet-password` returns empty or error

**Solution:**
- The token was never stored or was deleted
- Generate a new token and store it following the steps above
- Alternatively, keep the token in a secure password manager

### Sealed Secret Won't Decrypt

**Symptoms:**
- SealedSecret exists but Secret is not created
- Sealed Secrets controller logs show decryption errors

**Solution:**
1. Check Sealed Secrets controller:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
   kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets
   ```

2. Verify the sealed secret was created for the correct cluster:
   ```bash
   # Get current cluster certificate
   kubeseal --fetch-cert > /tmp/current-cert.pem

   # Compare with certificate used during sealing
   # If different, recreate the sealed secret
   ./scripts/seal-argocd-github-credentials.sh
   ```

## Security Best Practices

1. **Never commit plaintext tokens** to Git
2. **Use token expiration** - Set tokens to expire after 90 days
3. **Minimal scope** - Only grant `repo` scope, nothing more
4. **Rotate regularly** - Rotate tokens every 90 days or when compromised
5. **One token per use case** - Don't reuse tokens across different tools
6. **Audit access** - Regularly review GitHub token usage in Settings
7. **Sealed Secrets only** - Always seal secrets before committing to Git

## File Locations

- **Sealed secret**: `secrets/system/argocd-repo-credentials-sealed.yaml` (safe to commit)
- **Sealing script**: `scripts/seal-argocd-github-credentials.sh`
- **Cluster secret**: `argocd/repo-fineract-gitops` secret in `argocd` namespace (not in Git)

## References

- [GitHub Personal Access Tokens Documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [ArgoCD Private Repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [macOS Keychain CLI Reference](https://ss64.com/osx/security.html)

## Quick Reference

```bash
# Create new token → Store in Keychain
security add-internet-password -s github.com -a guymoyo \
  -l "GitHub PAT for fineract-gitops ArgoCD" -w

# Retrieve token from Keychain
security find-internet-password -s github.com -a guymoyo -w

# Create sealed secret (automated)
./scripts/seal-argocd-github-credentials.sh

# Apply to cluster
kubectl apply -f secrets/system/argocd-repo-credentials-sealed.yaml

# Verify
kubectl get secret -n argocd repo-fineract-gitops
```
