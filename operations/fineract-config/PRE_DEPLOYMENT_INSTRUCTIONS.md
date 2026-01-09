# Pre-Deployment Instructions for fineract-config

**Status**: 🔴 **DEPLOYMENT BLOCKED** - Critical prerequisites must be completed first

**Last Updated**: 2025-11-20

---

## 🚨 Critical Blockers (Must Fix Before Deployment)

### Blocker 1: Missing Secrets in Sealed Secret (Priority: P0)

**Problem**: The `fineract-data-loader-client-id` and `fineract-data-loader-client-secret` keys are **NOT present** in `secrets/dev/keycloak-client-secrets-sealed.yaml`.

**Impact**: The fineract-config-cli job will fail to start with `CreateContainerConfigError` because required environment variables cannot be resolved.

**Solution**: Add the missing secrets to the sealed secret file.

#### Quick Steps

1. **Generate a secure random secret**:
   ```bash
   FINERACT_DATA_LOADER_SECRET=$(openssl rand -base64 32)
   echo "Generated secret: $FINERACT_DATA_LOADER_SECRET"
   # Save this value securely - you'll need it!
   ```

   **Generated value** (for reference):
   ```
   OmbzuRzFcSfdfp2tnd1naRlFP5QtiHKqk3psh88uRhU=
   ```

2. **Fetch the sealed-secrets certificate**:
   ```bash
   kubeseal --fetch-cert \
     --controller-name=sealed-secrets \
     --controller-namespace=kube-system \
     > /tmp/sealed-secrets-cert.pem
   ```

3. **Get existing secret values from the cluster**:
   ```bash
   kubectl get secret keycloak-client-secrets -n fineract-dev -o json | \
     jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"' \
     > /tmp/existing-values.txt
   ```

4. **Create complete secret with all values**:
   ```bash
   # Extract existing values
   ADMIN_CLI_CLIENT_ID=$(grep "admin-cli-client-id:" /tmp/existing-values.txt | cut -d' ' -f2)
   ADMIN_CLI_CLIENT_SECRET=$(grep "admin-cli-client-secret:" /tmp/existing-values.txt | cut -d' ' -f2)
   FINERACT_API_CLIENT_ID=$(grep "fineract-api-client-id:" /tmp/existing-values.txt | cut -d' ' -f2)
   FINERACT_API_CLIENT_SECRET=$(grep "fineract-api-client-secret:" /tmp/existing-values.txt | cut -d' ' -f2)
   OAUTH2_PROXY_CLIENT_ID=$(grep "oauth2-proxy-client-id:" /tmp/existing-values.txt | cut -d' ' -f2)
   OAUTH2_PROXY_CLIENT_SECRET=$(grep "oauth2-proxy-client-secret:" /tmp/existing-values.txt | cut -d' ' -f2)
   OAUTH2_PROXY_COOKIE_SECRET=$(grep "oauth2-proxy-cookie-secret:" /tmp/existing-values.txt | cut -d' ' -f2)

   # Create complete secret
   kubectl create secret generic keycloak-client-secrets \
     --from-literal=admin-cli-client-id="${ADMIN_CLI_CLIENT_ID}" \
     --from-literal=admin-cli-client-secret="${ADMIN_CLI_CLIENT_SECRET}" \
     --from-literal=fineract-api-client-id="${FINERACT_API_CLIENT_ID}" \
     --from-literal=fineract-api-client-secret="${FINERACT_API_CLIENT_SECRET}" \
     --from-literal=oauth2-proxy-client-id="${OAUTH2_PROXY_CLIENT_ID}" \
     --from-literal=oauth2-proxy-client-secret="${OAUTH2_PROXY_CLIENT_SECRET}" \
     --from-literal=oauth2-proxy-cookie-secret="${OAUTH2_PROXY_COOKIE_SECRET}" \
     --from-literal=fineract-data-loader-client-id="fineract-data-loader" \
     --from-literal=fineract-data-loader-client-secret="${FINERACT_DATA_LOADER_SECRET}" \
     --dry-run=client -o yaml > /tmp/keycloak-client-secrets-plain.yaml
   ```

5. **Seal the secret**:
   ```bash
   kubeseal --controller-name=sealed-secrets \
     --controller-namespace=kube-system \
     --format yaml \
     < /tmp/keycloak-client-secrets-plain.yaml \
     > secrets/dev/keycloak-client-secrets-sealed.yaml
   ```

6. **Verify the sealed secret**:
   ```bash
   # Check that both new keys are present
   grep "fineract-data-loader-client-id:" secrets/dev/keycloak-client-secrets-sealed.yaml
   grep "fineract-data-loader-client-secret:" secrets/dev/keycloak-client-secrets-sealed.yaml
   ```

7. **Clean up sensitive files**:
   ```bash
   rm /tmp/keycloak-client-secrets-plain.yaml
   rm /tmp/existing-values.txt
   ```

**Detailed Guide**: See [ADD_SECRETS_GUIDE.md](./ADD_SECRETS_GUIDE.md)

---

### Blocker 2: Verify fineract-config-cli Image Exists (Priority: P0)

**Problem**: The Docker image `ghcr.io/adorsys-gis/fineract-config-cli:latest` may not exist or may be private.

**Impact**: Job will fail with `ImagePullBackOff` if the image doesn't exist or isn't accessible.

**Solution**: Verify the image exists and is accessible.

#### Verification Steps

1. **Check if the image exists**:
   ```bash
   docker manifest inspect ghcr.io/adorsys-gis/fineract-config-cli:latest
   ```

   **Expected**: Manifest details with layers and digest

   **If it fails with "denied" or "not found"**:
   - Check if you're authenticated to GHCR: `docker login ghcr.io`
   - Verify the image repository exists
   - Check if the image has been built and pushed

2. **If image doesn't exist**, you have two options:

   **Option A: Build and push the image** (recommended)
   ```bash
   # Navigate to fineract-config-cli repository
   cd /path/to/fineract-config-cli

   # Build the image
   docker build -t ghcr.io/adorsys-gis/fineract-config-cli:latest .

   # Push to registry
   docker push ghcr.io/adorsys-gis/fineract-config-cli:latest
   ```

   **Option B: Temporarily disable the application**
   ```bash
   # Comment out the fineract-config application in ArgoCD kustomization
   # Edit: argocd/applications/dev/kustomization.yaml
   # Comment out: - fineract-config.yaml
   ```

---

### Blocker 3: Update Keycloak Realm Configuration (Priority: P1)

**Problem**: The Keycloak realm must have the `fineract-data-loader` client created with the correct secret.

**Impact**: OAuth2 authentication will fail with 401 Unauthorized.

**Solution**: The keycloak-config job has been updated to pass the environment variables. The realm configuration already references these via `${FINERACT_DATA_LOADER_CLIENT_ID}` and `${FINERACT_DATA_LOADER_SECRET}` placeholders.

**What was fixed**:
- ✅ Updated `operations/keycloak-config/base/jobs/apply-keycloak-config.yaml` to pass `FINERACT_DATA_LOADER_CLIENT_ID` and `FINERACT_DATA_LOADER_SECRET` environment variables to the substitute-variables init container

**No action needed** - This has been completed as part of this fix.

---

## 📋 Post-Deployment Manual Steps (Priority: P1)

### Manual Step 1: Assign Super User Role to fineract-data-loader

**When to do this**: After the keycloak-config job has run and created the `fineract-data-loader` client.

**Why needed**: The fineract-config-cli requires full API access to create/update/delete entities in Fineract.

**Steps**:

1. **Access Keycloak Admin Console**:
   ```bash
   kubectl port-forward -n fineract-dev svc/keycloak-service 8080:8080
   ```
   Open: http://localhost:8080/auth

2. **Navigate to Service Account Roles**:
   - Realm: **fineract**
   - Clients → **fineract-data-loader**
   - Tab: **Service Account Roles**

3. **Assign Super User Role**:
   - Filter: Realm Roles
   - Available Roles → Select **"Super User"**
   - Click **"Add selected"**

4. **Verify**:
   ```bash
   kubectl exec -it -n fineract-dev keycloak-0 -- \
     /opt/keycloak/bin/kcadm.sh get users \
     -r fineract \
     --fields username,id \
     | grep "service-account-fineract-data-loader"
   ```

---

## ✅ Pre-Deployment Checklist

Before pushing this code, verify:

- [ ] **Blocker 1**: Added `fineract-data-loader-client-id` and `fineract-data-loader-client-secret` to sealed secret
- [ ] **Blocker 2**: Verified `ghcr.io/adorsys-gis/fineract-config-cli:latest` image exists and is accessible
- [ ] **Blocker 3**: Keycloak-config job updated with new environment variables (✅ DONE)
- [ ] Fineract is healthy and running in the cluster
- [ ] ArgoCD is accessible and syncing properly

**Only proceed when all blockers are resolved!**

---

## 🚀 Deployment Steps (After Resolving Blockers)

### Step 1: Commit and Push Changes

```bash
cd /Users/guymoyo/dev/fineract-gitops

# Review changes
git status

# Should show:
# - M operations/keycloak-config/base/jobs/apply-keycloak-config.yaml
# - M secrets/dev/keycloak-client-secrets-sealed.yaml (after fixing Blocker 1)
# - ?? operations/fineract-config/
# - ?? argocd/applications/dev/fineract-config.yaml
# - M argocd/applications/dev/kustomization.yaml

# Add all changes
git add operations/keycloak-config/base/jobs/apply-keycloak-config.yaml
git add secrets/dev/keycloak-client-secrets-sealed.yaml
git add operations/fineract-config/
git add argocd/applications/dev/fineract-config.yaml
git add argocd/applications/dev/kustomization.yaml

# Commit
git commit -m "feat: add fineract-config-cli with prerequisites

Implements declarative Fineract configuration management using
fineract-config-cli, following keycloak-config-cli pattern.

Changes:
1. Added fineract-config ArgoCD application and Kubernetes manifests
2. Updated keycloak-config job to pass fineract-data-loader credentials
3. Added fineract-data-loader client secrets to sealed secret
4. Created comprehensive deployment documentation

Components:
- Job with 2 init containers (wait-for-fineract, substitute-variables)
- RBAC (ServiceAccount, Role, RoleBinding)
- ConfigMapGenerator for config files
- ArgoCD Application with automated sync (Wave 4, PostSync Wave 10)

Features:
- OAuth2 authentication via Keycloak (fineract-data-loader client)
- Idempotent operations with checksum-based change detection
- Automatic re-sync when config files change (ConfigMap hash)
- Environment-specific settings (dev/uat/production)

Prerequisites resolved:
✅ Added fineract-data-loader secrets to keycloak-client-secrets
✅ Updated keycloak-config to pass new environment variables
✅ Verified image availability (or documented workaround)

Post-deployment manual step required:
- Assign Super User role to fineract-data-loader service account

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Step 2: Push to Remote

```bash
git push origin dev/fineract-deployment
```

### Step 3: Monitor ArgoCD Sync

```bash
# Watch all applications
argocd app list --watch

# Specifically watch sealed-secrets (should sync first)
argocd app get sealed-secrets-dev --watch

# Then watch keycloak-config (Wave 2)
argocd app get fineract-dev-keycloak-config --watch

# Finally watch fineract-config (Wave 4)
argocd app get fineract-dev-fineract-config --watch
```

### Step 4: Verify Secret Updated

```bash
# Check that the secret was updated
kubectl get secret keycloak-client-secrets -n fineract-dev -o json | \
  jq -r '.data | keys'

# Should include:
# - fineract-data-loader-client-id
# - fineract-data-loader-client-secret
```

### Step 5: Verify Keycloak Client Created

```bash
# Check if fineract-data-loader client exists
kubectl exec -it -n fineract-dev keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh get clients \
  -r fineract \
  --fields clientId,id \
  | grep "fineract-data-loader"
```

### Step 6: Assign Super User Role (Manual Step)

See "Manual Step 1: Assign Super User Role to fineract-data-loader" above.

### Step 7: Monitor fineract-config Job

```bash
# Watch job status
kubectl get jobs -n fineract-dev apply-fineract-config -w

# View init container logs
kubectl logs -n fineract-dev job/apply-fineract-config -c wait-for-fineract
kubectl logs -n fineract-dev job/apply-fineract-config -c substitute-variables

# View main container logs
kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli -f
```

---

## 🔍 Expected Outcomes

### If All Blockers Resolved

✅ Sealed secrets sync successfully
✅ Keycloak-config job completes and creates fineract-data-loader client
✅ Manual role assignment completed
✅ Fineract-config job completes successfully
✅ ArgoCD application shows "Healthy" and "Synced"

### If Blocker 1 Not Resolved (Missing Secrets)

❌ Keycloak-config job fails (substitute-variables init container)
❌ Fineract-config job fails (CreateContainerConfigError)
❌ Error: `key "fineract-data-loader-client-id" not found in secret "keycloak-client-secrets"`

### If Blocker 2 Not Resolved (Missing Image)

❌ Fineract-config job pod stuck in `ImagePullBackOff`
❌ Error: `Failed to pull image "ghcr.io/adorsys-gis/fineract-config-cli:latest"`
❌ ArgoCD application stuck in `Progressing` state

### If Manual Step Not Completed (Missing Super User Role)

❌ Fineract-config job fails with OAuth2/API errors
❌ Error: `401 Unauthorized` or `403 Forbidden` when calling Fineract API
❌ Job retries until backoffLimit reached

---

## 📚 Additional Documentation

- [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md) - Full deployment checklist
- [ADD_SECRETS_GUIDE.md](./ADD_SECRETS_GUIDE.md) - Detailed sealed secrets guide
- [README.md](./README.md) - Overview and architecture
- [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md) - Technical details

---

## 🆘 Troubleshooting

### Issue: Cannot fetch sealed-secrets certificate

**Error**: `Error from server (NotFound): services "sealed-secrets" not found`

**Solution**: Check if sealed-secrets controller is running
```bash
kubectl get pods -n kube-system | grep sealed-secrets

# If not running, sync the ArgoCD app
argocd app sync sealed-secrets-controller
```

### Issue: Cannot access cluster

**Error**: `Unable to connect to the server`

**Solution**: Update kubeconfig
```bash
aws eks update-kubeconfig --name fineract-dev --region us-east-1

# Or use your specific kubeconfig
export KUBECONFIG=/Users/guymoyo/.kube/config-fineract-dev
```

### Issue: Secret decryption fails

**Error**: `error: sealed-secrets controller not found`

**Alternative**: Use Option 2 from ADD_SECRETS_GUIDE.md (manual encryption of new values only)

---

**Generated**: 2025-11-20
**Author**: DevOps Team
**Status**: 🔴 Pending blocker resolution
