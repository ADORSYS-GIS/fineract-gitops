# Fineract Config CLI - Deployment Checklist

## Prerequisites

### ⚠️ 1. Add fineract-data-loader Secrets to Sealed Secret

The `fineract-data-loader` OAuth2 client credentials are **NOT yet present** in the sealed secret file.

**Required secrets**:
- `fineract-data-loader-client-id`
- `fineract-data-loader-client-secret`

**Status**: ❌ **MUST BE ADDED** - See `ADD_SECRETS_GUIDE.md` for detailed instructions

**Quick steps**:
1. Generate a secure random secret (32 characters)
2. Get existing secret values from cluster
3. Create new secret with all values (existing + new)
4. Seal with kubeseal
5. Commit sealed secret to Git
6. Verify secret updated in cluster

**Detailed guide**: See [ADD_SECRETS_GUIDE.md](./ADD_SECRETS_GUIDE.md)

### ⚠️ 2. Assign Super User Role to fineract-data-loader Service Account

The `fineract-data-loader` client is used by fineract-config-cli and needs **Super User** role.

**To assign the role:**

1. **Access Keycloak Admin Console**:
   ```bash
   # Port-forward to Keycloak
   kubectl port-forward -n fineract-dev svc/keycloak-service 8080:8080

   # Open: http://localhost:8080/auth
   # Login with admin credentials
   ```

2. **Navigate to Service Account Roles**:
   - Realm: **fineract**
   - Clients → **fineract-data-loader**
   - Tab: **Service Account Roles**

3. **Assign Super User Role**:
   - Filter: Realm Roles
   - Available Roles → Select **"admin"** or **"Super User"**
   - Click **"Add selected"**

4. **Verify**:
   ```bash
   # Get service account user
   kubectl exec -it -n fineract-dev keycloak-0 -- \
     /opt/keycloak/bin/kcadm.sh get users \
     -r fineract \
     --fields username,id \
     | grep "service-account-fineract-data-loader"

   # Check assigned roles (use ID from above)
   kubectl exec -it -n fineract-dev keycloak-0 -- \
     /opt/keycloak/bin/kcadm.sh get-roles \
     -r fineract \
     --uusername service-account-fineract-data-loader
   ```

**Why needed**: The CLI creates/updates/deletes entities across Fineract, requiring full API access.

### ✅ 3. Verify Fineract is Healthy
```bash
kubectl get pods -n fineract-dev | grep fineract

# All should be Running:
# fineract-write-0
# fineract-read-0 (or deployments)
# fineract-batch-0

# Check actuator health
kubectl exec -it -n fineract-dev fineract-write-0 -- \
  curl -k https://localhost:8443/fineract-provider/actuator/health
```

### ✅ 4. ArgoCD Application Deployed
```bash
argocd app get fineract-dev-fineract-config

# Or via kubectl
kubectl get application fineract-dev-fineract-config -n argocd
```

---

## Deployment Steps

### Step 1: Commit Changes
```bash
cd /Users/guymoyo/dev/fineract-gitops

# Review changes
git status

# Add all fineract-config files
git add operations/fineract-config/
git add argocd/applications/dev/fineract-config.yaml
git add argocd/applications/dev/kustomization.yaml

# Commit
git commit -m "feat: add fineract-config-cli Kubernetes job

Implements declarative Fineract configuration management using
fineract-config-cli, following keycloak-config-cli pattern.

Features:
- Kubernetes Job with ArgoCD PostSync hook (Wave 10)
- OAuth2 authentication via Keycloak (fineract-api client)
- Idempotent operations with checksum-based change detection
- Automatic re-sync when config files change (ConfigMap hash)
- Environment-specific settings (dev/uat/production)
- Comprehensive documentation

Components:
- Job with 2 init containers (wait-for-fineract, substitute-variables)
- RBAC (ServiceAccount, Role, RoleBinding)
- ConfigMapGenerator for config files
- ArgoCD Application with automated sync

Usage:
1. Add YAML config files to operations/fineract-config/base/config/
2. Update kustomization.yaml to include files
3. Commit and push - ArgoCD auto-syncs and runs job

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Step 2: Push to Remote
```bash
git push origin deploy-key
```

### Step 3: Monitor ArgoCD Sync
```bash
# Watch application sync
argocd app get fineract-dev-fineract-config --watch

# Or via kubectl
kubectl get application fineract-dev-fineract-config -n argocd -w
```

### Step 4: Verify Job Creation
```bash
# Wait for sync to complete
sleep 30

# Check if job was created
kubectl get jobs -n fineract-dev | grep apply-fineract-config

# Should see: apply-fineract-config
```

### Step 5: Monitor Job Execution
```bash
# Watch job status
kubectl get jobs -n fineract-dev apply-fineract-config -w

# View pod logs
kubectl logs -n fineract-dev job/apply-fineract-config -c wait-for-fineract
kubectl logs -n fineract-dev job/apply-fineract-config -c substitute-variables
kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli -f
```

---

## Testing with Sample Configuration

### Create Test Configuration
```bash
cd operations/fineract-config/base/config/

cat > 01-test-office.yml <<'EOF'
tenant: default

offices:
  - name: Test Office
    externalId: TEST001
    openingDate: [2024, 11, 20]
EOF
```

### Update Kustomization
```bash
cd ../

# Edit kustomization.yaml - change:
# FROM:
configMapGenerator:
  - name: fineract-config-data
    files:
      - config/.gitkeep
    options:
      disableNameSuffixHash: false

# TO:
configMapGenerator:
  - name: fineract-config-data
    files:
      - config/.gitkeep
      - config/01-test-office.yml
    options:
      disableNameSuffixHash: false
```

### Commit and Push
```bash
git add operations/fineract-config/
git commit -m "test: add test office configuration"
git push origin deploy-key
```

### Verify in Fineract
```bash
# Wait for job to complete
sleep 60

# Check offices via API
FINERACT_POD=$(kubectl get pods -n fineract-dev -l app=fineract-write -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it -n fineract-dev $FINERACT_POD -- \
  curl -k -u mifos:password \
  https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -H "Content-Type: application/json" | jq .

# Look for "Test Office" with externalId "TEST001"
```

---

## Troubleshooting

### Job Fails with "401 Unauthorized"

**Check 1**: Verify OAuth2 client credentials
```bash
kubectl get secret keycloak-client-secrets -n fineract-dev -o jsonpath='{.data.fineract-data-loader-client-id}' | base64 -d
kubectl get secret keycloak-client-secrets -n fineract-dev -o jsonpath='{.data.fineract-data-loader-client-secret}' | base64 -d
```

**Check 2**: Test OAuth2 token manually
```bash
KEYCLOAK_POD=$(kubectl get pods -n fineract-dev -l app=keycloak -o jsonpath='{.items[0].metadata.name}')

CLIENT_ID=$(kubectl get secret keycloak-client-secrets -n fineract-dev -o jsonpath='{.data.fineract-data-loader-client-id}' | base64 -d)
CLIENT_SECRET=$(kubectl get secret keycloak-client-secrets -n fineract-dev -o jsonpath='{.data.fineract-data-loader-client-secret}' | base64 -d)

kubectl exec -it -n fineract-dev $KEYCLOAK_POD -- \
  curl -X POST http://localhost:8080/realms/fineract/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID \
  -d client_secret=$CLIENT_SECRET
```

**Check 3**: Verify Super User role assigned (see Prerequisites section)

### Job Fails with "Fineract not ready"

**Check**: Fineract health
```bash
kubectl get pods -n fineract-dev | grep fineract

kubectl exec -it -n fineract-dev fineract-write-0 -- \
  curl -k https://localhost:8443/fineract-provider/actuator/health
```

**Solution**: Wait for Fineract to be fully ready, then re-sync ArgoCD app

### Job Succeeds but No Configuration Applied

**Expected**: If checksum unchanged (idempotent behavior)

**Check logs**:
```bash
kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli | grep -i checksum
```

**Force re-import**:
```yaml
# In overlays/dev/patches/job-config.yaml
- name: IMPORT_FORCE
  value: "true"
```

### ConfigMap Changes Don't Trigger Re-sync

**Check 1**: Verify hash suffix enabled
```bash
kubectl get configmap -n fineract-dev | grep fineract-config-data
# Should show hash suffix: fineract-config-data-abc123xyz
```

**Check 2**: Verify selfHeal enabled
```bash
argocd app get fineract-dev-fineract-config -o yaml | grep selfHeal
# Should show: selfHeal: true
```

**Manual sync**:
```bash
argocd app sync fineract-dev-fineract-config
```

---

## Post-Deployment Verification

### ✅ Checklist

- [ ] Job created successfully
- [ ] Job completed (status: Completed)
- [ ] No errors in job logs
- [ ] Test configuration applied in Fineract
- [ ] Idempotency verified (re-run doesn't create duplicates)
- [ ] ConfigMap change triggers re-sync
- [ ] ArgoCD application healthy

### Verification Commands
```bash
# 1. Job status
kubectl get job apply-fineract-config -n fineract-dev

# 2. Job logs (check for "Import completed")
kubectl logs -n fineract-dev job/apply-fineract-config -c fineract-config-cli | tail -50

# 3. ArgoCD app status
argocd app get fineract-dev-fineract-config

# 4. Test in Fineract
kubectl exec -it -n fineract-dev fineract-write-0 -- \
  curl -k -u mifos:password \
  https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" | jq .
```

---

## Next Steps After Successful Deployment

1. **Add more configuration files** to `base/config/`
2. **Document your entity configurations** in config README
3. **Set up monitoring** (Prometheus, Grafana)
4. **Configure alerts** for job failures
5. **Plan rollout to UAT** environment
6. **Prepare production configuration**

---

**Status**: 🟡 Awaiting deployment
**Updated**: 2025-11-20
**Owner**: DevOps Team
