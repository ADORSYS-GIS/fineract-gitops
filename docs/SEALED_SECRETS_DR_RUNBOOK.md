# Sealed Secrets Disaster Recovery Runbook

**Purpose**: Quick-reference emergency runbook for Sealed Secrets controller key recovery
**Audience**: DevOps engineers, SREs, on-call responders
**Estimated Recovery Time**: 15-30 minutes
**Last Updated**: 2025-01-19

---

## Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| **Primary On-Call** | [Name] | [Phone/Slack] |
| **Backup On-Call** | [Name] | [Phone/Slack] |
| **DevOps Lead** | [Name] | [Phone/Slack] |
| **Security Team** | [Email] | [Email/Slack] |

---

## Quick Decision Tree

```
Sealed Secrets Issue?
│
├─ Controller Pod Crashed/Missing?
│  └─ Go to: Section 1 (Controller Recovery)
│
├─ Secrets Not Decrypting?
│  └─ Go to: Section 2 (Key Mismatch)
│
├─ Complete Cluster Loss?
│  └─ Go to: Section 3 (Full DR)
│
└─ Need to Rotate Keys?
   └─ Go to: Section 4 (Key Rotation)
```

---

## Section 1: Controller Pod Recovery (Non-Destructive)

**Scenario**: Controller pod crashed or deleted, but keys still exist
**Time Estimate**: 5-10 minutes
**Risk Level**: LOW

### Pre-Flight Checks

```bash
# Check if controller exists
kubectl get deployment -n kube-system sealed-secrets-controller

# Check if keys exist
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active
```

### Recovery Steps

```bash
# Step 1: Restart controller (if deployment exists)
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system

# Step 2: Wait for readiness (timeout: 2 minutes)
kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=120s

# Step 3: Verify controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Expected output: 1 pod in Running state with 1/1 READY
```

### Verification

```bash
# Test if controller can decrypt secrets
./scripts/validate-sealed-secrets-compatibility.sh

# Expected output: "✅ All critical sealed secrets are compatible"
```

### If This Fails

If controller won't start or verification fails, proceed to **Section 2**.

---

## Section 2: Key Mismatch Recovery

**Scenario**: Controller running but can't decrypt sealed secrets (key mismatch)
**Time Estimate**: 10-15 minutes
**Risk Level**: MEDIUM

### Symptoms

- SealedSecret resources exist in cluster
- Regular Secret resources are NOT created
- Controller logs show decryption errors:
  ```
  "error decrypting secret" error="no key could decrypt secret"
  ```

### Root Cause

Controller has wrong encryption key (common after reinstall or migration).

### Recovery Steps

```bash
# Step 1: Set environment variable
export ENV="dev"  # Change to: dev, uat, or production

# Step 2: Check current keys
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active
# Note the number of keys

# Step 3: Restore keys from AWS Secrets Manager
cd /Users/guymoyo/dev/fineract-gitops
./scripts/restore-sealed-secrets-keys.sh $ENV

# Follow prompts:
# - Confirm environment name
# - Confirm key replacement (if keys already exist)
# - Confirm controller restart

# Expected output:
# ✅ Keys restored successfully
# ✅ Controller restarted
```

### Verification

```bash
# Step 1: Validate key compatibility
./scripts/validate-sealed-secrets-compatibility.sh

# Step 2: Check that Secrets are being created
kubectl get secrets -n fineract-$ENV

# Expected: All secrets exist (fineract-db-credentials, keycloak-admin-credentials, etc.)

# Step 3: Check a sample secret was decrypted
kubectl get secret fineract-db-credentials -n fineract-$ENV -o jsonpath='{.data.password}' | base64 -d
# Should output the actual password (not encrypted gibberish)
```

### If This Fails

- **Check AWS credentials**: Ensure you have access to AWS Secrets Manager
  ```bash
  aws secretsmanager get-secret-value --secret-id /fineract/$ENV/sealed-secrets/master-key --region us-east-1
  ```
- **Verify backup exists**: Check AWS console for secret existence
- **Contact Security Team**: If backup is missing, escalate immediately

---

## Section 3: Complete Cluster Disaster Recovery

**Scenario**: Cluster destroyed, need to restore from scratch
**Time Estimate**: 20-30 minutes (excludes infrastructure provisioning)
**Risk Level**: HIGH

### Prerequisites

- [ ] New Kubernetes cluster provisioned
- [ ] kubectl configured with cluster access
- [ ] AWS CLI configured with appropriate IAM permissions
- [ ] Git repository cloned locally

### Recovery Steps

```bash
# Step 0: Set environment
export ENV="production"  # Change as needed
export KUBECONFIG=/path/to/new/cluster/kubeconfig

# Step 1: Verify cluster access
kubectl cluster-info
kubectl get nodes

# Step 2: Create namespaces
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace fineract-$ENV

# Step 3: Deploy Sealed Secrets controller
cd /Users/guymoyo/dev/fineract-gitops
kubectl apply -k apps/sealed-secrets-controller/base/

# Step 4: Wait for controller to initialize (generates new key)
kubectl wait --for=condition=available --timeout=120s \
  deployment/sealed-secrets-controller -n kube-system

# Step 5: IMMEDIATELY replace with backed-up keys
./scripts/restore-sealed-secrets-keys.sh $ENV

# CRITICAL: Say YES to replace keys when prompted
# CRITICAL: Say YES to restart controller when prompted

# Step 6: Verify controller is healthy
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=50

# Expected: No error messages, "controller started" message

# Step 7: Deploy sealed secrets
kubectl apply -k secrets/$ENV/

# Step 8: Verify secrets were decrypted
kubectl get secrets -n fineract-$ENV

# Expected: Regular Secrets created from SealedSecrets
```

### Verification

```bash
# Test 1: Controller health
kubectl get deployment sealed-secrets-controller -n kube-system

# Test 2: Key compatibility
./scripts/validate-sealed-secrets-compatibility.sh

# Test 3: Sample secret decryption
kubectl get secret fineract-db-credentials -n fineract-$ENV -o yaml

# Test 4: Application deployment
kubectl apply -k environments/$ENV/
kubectl get pods -n fineract-$ENV

# Expected: Fineract pods start successfully (not CrashLoopBackOff)
```

### Post-Recovery Actions

```bash
# 1. Notify team
# - Update incident ticket
# - Notify stakeholders of recovery completion

# 2. Verify backup exists
./scripts/backup-sealed-secrets-keys.sh $ENV

# 3. Document incident
# - Update operations/sealed-secrets-key-audit.yaml
# - Record recovery time, root cause, actions taken

# 4. Test applications
# - Verify Fineract API responds
# - Verify Keycloak authentication works
# - Run smoke tests
```

---

## Section 4: Key Rotation (Planned Maintenance)

**Scenario**: Routine 90-day key rotation
**Time Estimate**: 30-45 minutes
**Risk Level**: LOW (planned maintenance)

### Prerequisites

- [ ] Maintenance window scheduled
- [ ] Team notified
- [ ] Backup of current keys completed

### Rotation Steps

```bash
# Step 0: Set environment
export ENV="dev"  # Start with dev, then uat, then production

# Step 1: Backup current keys
./scripts/backup-sealed-secrets-keys.sh $ENV

# Verify backup succeeded:
aws secretsmanager list-secret-version-ids --secret-id /fineract/$ENV/sealed-secrets/master-key

# Step 2: Delete current keys (controller will generate new key)
kubectl delete secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active

# Step 3: Restart controller to generate new key
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system
kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=120s

# Step 4: Verify new key generated
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active
# Should see 1 new key with recent creation timestamp

# Step 5: Backup new key
./scripts/backup-sealed-secrets-keys.sh $ENV

# Step 6: Regenerate all sealed secrets with new key
./scripts/regenerate-sealed-secrets.sh $ENV

# This will:
# - Fetch new public key from controller
# - Re-seal all Terraform secrets
# - Re-seal all application secrets
# - Commit changes to Git

# Step 7: Apply regenerated secrets
git add secrets/$ENV/
git commit -m "chore: rotate sealed secrets keys for $ENV environment"
git push origin main

# ArgoCD will automatically sync (or manually sync):
kubectl apply -k secrets/$ENV/

# Step 8: Verify all secrets decrypted
./scripts/validate-sealed-secrets-compatibility.sh

# Step 9: Update audit log
# Edit operations/sealed-secrets-key-audit.yaml with rotation details
```

### Verification

```bash
# Test 1: All sealed secrets valid
./scripts/validate-sealed-secrets-compatibility.sh

# Test 2: Applications still running
kubectl get pods -n fineract-$ENV

# Test 3: No decryption errors in controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=100 | grep -i error

# Expected: No "decryption failed" errors
```

### Rollback (If Needed)

```bash
# If rotation causes issues, restore previous keys:

# Step 1: List previous key versions
aws secretsmanager list-secret-version-ids --secret-id /fineract/$ENV/sealed-secrets/master-key

# Step 2: Get previous version ID (second in list)
export PREVIOUS_VERSION="<version-id>"

# Step 3: Download previous key
aws secretsmanager get-secret-value \
  --secret-id /fineract/$ENV/sealed-secrets/master-key \
  --version-id $PREVIOUS_VERSION \
  --query SecretString --output text > /tmp/old-keys.json

# Step 4: Extract and apply old keys
echo "$(cat /tmp/old-keys.json | jq -r '.keys')" | base64 -d | kubectl apply -f -

# Step 5: Restart controller
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system

# Step 6: Verify
./scripts/validate-sealed-secrets-compatibility.sh
```

---

## Section 5: Common Issues & Troubleshooting

### Issue: "No key could decrypt secret"

**Symptom**: SealedSecret exists but Secret not created
**Cause**: Key mismatch between controller and sealed secret

**Fix**:
```bash
# Option 1: Restore backed-up keys (recommended)
./scripts/restore-sealed-secrets-keys.sh $ENV

# Option 2: Regenerate sealed secrets with current key
./scripts/regenerate-sealed-secrets.sh $ENV
```

---

### Issue: Controller pod CrashLoopBackOff

**Symptom**: Controller pod repeatedly crashing
**Cause**: Usually resource limits or corrupted keys

**Diagnostic**:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=100
kubectl describe pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

**Common Fixes**:
```bash
# Fix 1: Increase resource limits
kubectl patch deployment sealed-secrets-controller -n kube-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"256Mi"}]'

# Fix 2: Delete and redeploy
kubectl delete deployment sealed-secrets-controller -n kube-system
kubectl apply -k apps/sealed-secrets-controller/base/
./scripts/restore-sealed-secrets-keys.sh $ENV
```

---

### Issue: AWS Secrets Manager access denied

**Symptom**: restore-sealed-secrets-keys.sh fails with "AccessDeniedException"
**Cause**: Insufficient IAM permissions

**Fix**:
```bash
# Check your AWS identity
aws sts get-caller-identity

# Verify IAM policy allows:
# - secretsmanager:GetSecretValue
# - secretsmanager:ListSecretVersionIds
# On resource: arn:aws:secretsmanager:*:*:secret:/fineract/*

# If using IAM role, assume correct role:
aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/FineractAdmin --role-session-name DR-Recovery
```

---

### Issue: Multiple keys in cluster

**Symptom**: Controller has multiple keys (not just 1)
**Cause**: Key rotation in progress or incomplete cleanup

**Is This Normal?**: YES, during rotation. Controller keeps old keys to decrypt existing secrets.

**When to Worry**: If you have >5 keys (something went wrong with rotation)

**Cleanup**:
```bash
# List all keys with ages
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp

# Delete old keys (keep only latest 2)
# WARNING: Only delete if ALL sealed secrets have been regenerated with new key
kubectl delete secret <old-key-name> -n kube-system
```

---

### Issue: Sealed secret valid but Secret not appearing

**Symptom**: SealedSecret resource exists, but corresponding Secret never created
**Cause**: Usually namespace mismatch or controller not watching namespace

**Diagnostic**:
```bash
# Check SealedSecret details
kubectl get sealedsecret fineract-db-credentials -n fineract-$ENV -o yaml

# Check controller logs for decryption attempts
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=200 | grep fineract-db-credentials
```

**Fix**:
```bash
# Delete and recreate SealedSecret
kubectl delete sealedsecret fineract-db-credentials -n fineract-$ENV
kubectl apply -f secrets/$ENV/fineract-db-credentials-sealed.yaml

# Verify Secret created within 10 seconds
kubectl get secret fineract-db-credentials -n fineract-$ENV
```

---

## Section 6: Emergency Commands Reference

### Quick Status Checks

```bash
# Controller status
kubectl get deployment sealed-secrets-controller -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Key count
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active | wc -l

# Sealed secrets inventory
kubectl get sealedsecrets -A

# Regular secrets inventory
kubectl get secrets -n fineract-dev
kubectl get secrets -n fineract-uat
kubectl get secrets -n fineract-production
```

### Controller Logs

```bash
# Recent logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=100

# Follow logs (real-time)
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f

# Search for errors
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=500 | grep -i error
```

### Key Management

```bash
# List all keys
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active

# Get public key (for manual sealing)
kubeseal --fetch-cert --controller-name sealed-secrets-controller --controller-namespace kube-system

# Backup keys
./scripts/backup-sealed-secrets-keys.sh <env>

# Restore keys
./scripts/restore-sealed-secrets-keys.sh <env>

# Validate compatibility
./scripts/validate-sealed-secrets-compatibility.sh
```

### AWS Secrets Manager

```bash
# List backups
aws secretsmanager list-secrets --filters Key=name,Values=/fineract/

# Get latest backup
aws secretsmanager get-secret-value --secret-id /fineract/dev/sealed-secrets/master-key

# List versions
aws secretsmanager list-secret-version-ids --secret-id /fineract/dev/sealed-secrets/master-key

# Get specific version
aws secretsmanager get-secret-value --secret-id /fineract/dev/sealed-secrets/master-key --version-id <version-id>
```

---

## Section 7: Pre-Flight Checklist

Before starting ANY recovery operation:

- [ ] Identify the environment (dev/uat/production)
- [ ] Set `$ENV` environment variable
- [ ] Verify kubectl access: `kubectl cluster-info`
- [ ] Verify AWS CLI access: `aws sts get-caller-identity`
- [ ] Locate backup in AWS Secrets Manager
- [ ] Notify team in Slack/incident channel
- [ ] Start timer (for RTO tracking)

---

## Section 8: Post-Recovery Checklist

After completing recovery:

- [ ] Verify controller is running
- [ ] Run `validate-sealed-secrets-compatibility.sh`
- [ ] Check that all Secrets exist in cluster
- [ ] Test application functionality (Fineract API, Keycloak)
- [ ] Create new backup: `backup-sealed-secrets-keys.sh $ENV`
- [ ] Update `operations/sealed-secrets-key-audit.yaml`
- [ ] Document incident in runbook notes
- [ ] Update incident ticket with resolution
- [ ] Notify stakeholders of completion
- [ ] Schedule post-mortem (for production incidents)

---

## Section 9: Escalation Path

If recovery fails after 30 minutes:

1. **Check documentation**: Review `/docs/DISASTER_RECOVERY.md` for detailed procedures
2. **Contact DevOps Lead**: See Emergency Contacts section
3. **Engage Security Team**: If keys are missing or compromised
4. **Review ADR-003**: `/docs/architecture/ADR-003-sealed-secrets.md` for architecture context

---

## Section 10: Related Documentation

- **Comprehensive DR Guide**: `/docs/DISASTER_RECOVERY.md`
- **Secrets Management**: `/docs/SECRETS_MANAGEMENT.md`
- **Deployment Guide**: `/docs/SEALED_SECRETS_DEPLOYMENT_GUIDE.md`
- **Architecture Decision**: `/docs/architecture/ADR-003-sealed-secrets.md`
- **Script Documentation**: `/scripts/README.md` (if exists)
- **Operations Guide**: `/operations/disaster-recovery/DR_GUIDE.md`

---

## Section 11: Testing This Runbook

**Recommendation**: Test this runbook quarterly in a non-production environment.

```bash
# Quarterly DR Drill (Development Environment)

# 1. Backup current keys
./scripts/backup-sealed-secrets-keys.sh dev

# 2. Simulate key loss
kubectl delete secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active

# 3. Restart controller (generates new key)
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system

# 4. Observe failure (sealed secrets won't decrypt)
./scripts/validate-sealed-secrets-compatibility.sh
# Expected: FAILURE

# 5. Execute recovery using this runbook
./scripts/restore-sealed-secrets-keys.sh dev

# 6. Verify success
./scripts/validate-sealed-secrets-compatibility.sh
# Expected: SUCCESS

# 7. Document drill results
# - Time to recover: ___ minutes
# - Issues encountered: ___
# - Runbook updates needed: ___
```

---

## Appendix A: Time Estimates by Scenario

| Scenario | Estimated Time | Downtime Impact |
|----------|----------------|-----------------|
| Controller pod restart | 5 minutes | None (existing secrets still work) |
| Key mismatch recovery | 10-15 minutes | None (if keys restored) |
| Complete cluster DR | 20-30 minutes | Full outage until recovery |
| Planned key rotation | 30-45 minutes | None (zero-downtime) |

---

## Appendix B: Script Locations

All scripts are in `/scripts/` directory:

| Script | Purpose | Usage |
|--------|---------|-------|
| `backup-sealed-secrets-keys.sh` | Backup to AWS | `./backup-sealed-secrets-keys.sh dev` |
| `restore-sealed-secrets-keys.sh` | Restore from AWS | `./restore-sealed-secrets-keys.sh dev` |
| `validate-sealed-secrets-compatibility.sh` | Test decryption | `./validate-sealed-secrets-compatibility.sh` |
| `regenerate-sealed-secrets.sh` | Re-seal all secrets | `./regenerate-sealed-secrets.sh dev` |
| `seal-terraform-secrets.sh` | Seal Terraform secrets | `./seal-terraform-secrets.sh dev` |
| `create-complete-sealed-secrets.sh` | Create app secrets | `./create-complete-sealed-secrets.sh dev` |

---

**Document Version**: 1.0
**Last Tested**: [Date]
**Next Review**: [Date + 90 days]
**Maintained By**: DevOps Team
