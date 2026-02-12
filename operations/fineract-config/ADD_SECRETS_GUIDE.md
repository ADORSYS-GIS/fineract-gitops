# Adding fineract-data-loader Secrets to Sealed Secrets

The `fineract-data-loader` OAuth2 client credentials need to be added to the `keycloak-client-secrets` sealed secret.

---

## Option 1: Using kubeseal (Recommended)

### Prerequisites
- Access to the dev Kubernetes cluster
- `kubeseal` CLI installed
- Sealed Secrets controller running in the cluster

### Steps

#### 1. Get Existing Secret Values

First, retrieve the existing secret to preserve all values:

```bash
# Get the current secret (if it exists)
kubectl get secret keycloak-client-secrets -n fineract-dev -o yaml > /tmp/keycloak-secrets-current.yaml

# Decode existing values
kubectl get secret keycloak-client-secrets -n fineract-dev -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
```

Save these values - you'll need them!

#### 2. Generate Client Secret

Generate a secure random secret for the fineract-data-loader client:

```bash
# Generate a 32-character random secret
FINERACT_DATA_LOADER_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
echo "Generated secret: $FINERACT_DATA_LOADER_SECRET"

# Save it somewhere secure!
```

#### 3. Create New Secret with All Values

Create a new secret including **all** existing keys plus the new ones:

```bash
# Set variables (use actual values from step 1)
ADMIN_CLI_CLIENT_ID="<from-existing-secret>"
ADMIN_CLI_CLIENT_SECRET="<from-existing-secret>"
FINERACT_API_CLIENT_ID="<from-existing-secret>"
FINERACT_API_CLIENT_SECRET="<from-existing-secret>"
OAUTH2_PROXY_CLIENT_ID="<from-existing-secret>"
OAUTH2_PROXY_CLIENT_SECRET="<from-existing-secret>"
OAUTH2_PROXY_COOKIE_SECRET="<from-existing-secret>"

# New values
FINERACT_DATA_LOADER_CLIENT_ID="fineract-data-loader"
FINERACT_DATA_LOADER_SECRET="<from-step-2>"

# Create the complete secret
kubectl create secret generic keycloak-client-secrets \
  --from-literal=admin-cli-client-id="${ADMIN_CLI_CLIENT_ID}" \
  --from-literal=admin-cli-client-secret="${ADMIN_CLI_CLIENT_SECRET}" \
  --from-literal=fineract-api-client-id="${FINERACT_API_CLIENT_ID}" \
  --from-literal=fineract-api-client-secret="${FINERACT_API_CLIENT_SECRET}" \
  --from-literal=oauth2-proxy-client-id="${OAUTH2_PROXY_CLIENT_ID}" \
  --from-literal=oauth2-proxy-client-secret="${OAUTH2_PROXY_CLIENT_SECRET}" \
  --from-literal=oauth2-proxy-cookie-secret="${OAUTH2_PROXY_COOKIE_SECRET}" \
  --from-literal=fineract-data-loader-client-id="${FINERACT_DATA_LOADER_CLIENT_ID}" \
  --from-literal=fineract-data-loader-client-secret="${FINERACT_DATA_LOADER_SECRET}" \
  --dry-run=client -o yaml > /tmp/keycloak-client-secrets-plain.yaml
```

#### 4. Seal the Secret

```bash
# Seal the secret
kubeseal --controller-name=sealed-secrets \
  --controller-namespace=kube-system \
  --format yaml \
  < /tmp/keycloak-client-secrets-plain.yaml \
  > secrets/dev/keycloak-client-secrets-sealed.yaml

# Verify it was created
cat secrets/dev/keycloak-client-secrets-sealed.yaml
```

#### 5. Update Keycloak Realm Configuration

Update the realm config to use the new secret value:

```bash
# Edit: operations/keycloak-config/overlays/dev/kustomization.yaml
# Add to configMapGenerator secrets replacement:

configMapGenerator:
  - name: keycloak-config-vars
    literals:
      # ... existing values ...
      - fineract-data-loader-secret=${FINERACT_DATA_LOADER_SECRET}
```

Or better, add to the secrets substitution in the init container.

#### 6. Commit and Deploy

```bash
# Commit the sealed secret
git add secrets/dev/keycloak-client-secrets-sealed.yaml
git commit -m "feat: add fineract-data-loader client credentials to sealed secret"
git push origin dev/fineract-deployment

# Wait for ArgoCD to sync or manually sync
argocd app sync sealed-secrets-dev
```

#### 7. Verify Secret Updated

```bash
# Check the secret was updated
kubectl get secret keycloak-client-secrets -n fineract-dev -o json | \
  jq -r '.data | keys'

# Should include:
# - fineract-data-loader-client-id
# - fineract-data-loader-client-secret
```

---

## Option 2: Manual Edit (If kubeseal not available)

If you don't have access to `kubeseal`, you can manually add the encrypted values:

### Steps

1. **Get the public key** from the sealed-secrets controller:
   ```bash
   kubeseal --fetch-cert > /tmp/sealed-secrets-cert.pem
   ```

2. **Create a plain secret with ONLY the new values**:
   ```bash
   kubectl create secret generic temp-secret \
     --from-literal=fineract-data-loader-client-id="fineract-data-loader" \
     --from-literal=fineract-data-loader-client-secret="<your-secret>" \
     --dry-run=client -o yaml | \
     kubeseal --cert=/tmp/sealed-secrets-cert.pem \
     --format yaml > /tmp/new-values-sealed.yaml
   ```

3. **Extract the encrypted values**:
   ```bash
   # Get encrypted values
   cat /tmp/new-values-sealed.yaml | yq '.spec.encryptedData'
   ```

4. **Manually add to existing sealed secret**:
   ```yaml
   # Edit: secrets/dev/keycloak-client-secrets-sealed.yaml
   # Add under spec.encryptedData:

   spec:
     encryptedData:
       # ... existing keys ...
       fineract-data-loader-client-id: AgC... <copied-from-step-3>
       fineract-data-loader-client-secret: AgC... <copied-from-step-3>
   ```

---

## Option 3: Using Web UI (Sealed Secrets Dashboard)

If you have the Sealed Secrets web UI deployed:

1. Navigate to the Sealed Secrets dashboard
2. Select namespace: `fineract-dev`
3. Select secret: `keycloak-client-secrets`
4. Click "Add Key"
5. Add:
   - Key: `fineract-data-loader-client-id`, Value: `fineract-data-loader`
   - Key: `fineract-data-loader-client-secret`, Value: `<your-secret>`
6. Download the sealed secret YAML
7. Replace `secrets/dev/keycloak-client-secrets-sealed.yaml`

---

## Verify Client Secret in Keycloak

After adding the secret, verify it matches in Keycloak:

```bash
# Port-forward to Keycloak
kubectl port-forward -n fineract-dev svc/keycloak-service 8080:8080

# Login to Keycloak admin console
# http://localhost:8080/auth

# Navigate to:
# Fineract realm → Clients → fineract-data-loader → Credentials

# The secret shown there should match what you sealed
```

---

## Troubleshooting

### Error: "sealed-secrets controller not found"

The sealed-secrets controller might not be running:

```bash
kubectl get pods -n kube-system | grep sealed-secrets

# If not running, check the ArgoCD app
argocd app get sealed-secrets-controller
```

### Error: "Failed to seal secret"

Check if you have the correct certificate:

```bash
kubeseal --fetch-cert --controller-name=sealed-secrets \
  --controller-namespace=kube-system

# Should output a PEM certificate
```

### Secret not updating in cluster

Force a re-sync:

```bash
# Delete the existing secret (will be recreated from sealed secret)
kubectl delete secret keycloak-client-secrets -n fineract-dev

# Sync ArgoCD app
argocd app sync sealed-secrets-dev --force
```

---

## Security Best Practices

1. **Never commit plain-text secrets to Git**
   - Only commit sealed (encrypted) secrets
   - Delete plain-text files after sealing: `rm /tmp/keycloak-client-secrets-plain.yaml`

2. **Store generated secrets securely**
   - Save the plain-text client secret in a password manager
   - You'll need it to update Keycloak realm configuration

3. **Rotate secrets regularly**
   - Update both the sealed secret and Keycloak client
   - Test after rotation

4. **Use strong secrets**
   - Minimum 32 characters
   - Random, cryptographically secure
   - No dictionary words

---

## Example: Complete Workflow

```bash
# 1. Generate secret
CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
echo "Secret: $CLIENT_SECRET" | tee ~/fineract-data-loader-secret.txt

# 2. Get existing values
kubectl get secret keycloak-client-secrets -n fineract-dev -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"' > /tmp/existing-values.txt

# 3. Create complete secret (fill in values)
kubectl create secret generic keycloak-client-secrets \
  --from-literal=admin-cli-client-id="admin-cli" \
  --from-literal=admin-cli-client-secret="<existing>" \
  --from-literal=fineract-api-client-id="fineract-api" \
  --from-literal=fineract-api-client-secret="<existing>" \
  --from-literal=oauth2-proxy-client-id="oauth2-proxy" \
  --from-literal=oauth2-proxy-client-secret="<existing>" \
  --from-literal=oauth2-proxy-cookie-secret="<existing>" \
  --from-literal=fineract-data-loader-client-id="fineract-data-loader" \
  --from-literal=fineract-data-loader-client-secret="${CLIENT_SECRET}" \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets \
    --controller-namespace=kube-system \
    --format yaml > secrets/dev/keycloak-client-secrets-sealed.yaml

# 4. Verify
head -20 secrets/dev/keycloak-client-secrets-sealed.yaml

# 5. Commit
git add secrets/dev/keycloak-client-secrets-sealed.yaml
git commit -m "feat: add fineract-data-loader secrets"
git push

# 6. Verify in cluster
sleep 30
kubectl get secret keycloak-client-secrets -n fineract-dev -o json | jq -r '.data | keys'

# 7. Clean up sensitive files
rm /tmp/existing-values.txt ~/fineract-data-loader-secret.txt
```

---

## Next Steps

After adding the secrets:

1. ✅ Update Keycloak realm with the new client secret
2. ✅ Assign Super User role to the service account
3. ✅ Deploy fineract-config-cli job
4. ✅ Test with sample configuration

---

**Created**: 2025-11-20
**Status**: Pending - secrets need to be added
