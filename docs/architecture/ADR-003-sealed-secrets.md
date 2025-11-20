# ADR-003: Sealed Secrets for GitOps

**Status**: ACCEPTED (migrated FROM External Secrets Operator in January 2025)
**Date**: 2025-10-26 (Updated: 2025-01-10)
**Decision**: Use Bitnami Sealed Secrets for encrypting Kubernetes secrets in Git

**UPDATE (2025-01-10)**: This ADR remains active. The project has migrated FROM External Secrets Operator back TO **Sealed Secrets** for better cloud portability, simpler architecture, and pure GitOps principles. See [SECRETS_MANAGEMENT.md](../SECRETS_MANAGEMENT.md) for current practices and [MIGRATION_TO_SEALED_SECRETS.md](../migrations/MIGRATION_TO_SEALED_SECRETS.md) for migration details

---

## Context

GitOps requires all configuration in Git, but Kubernetes Secrets are base64-encoded, not encrypted:

```yaml
apiVersion: v1
kind: Secret
data:
  password: cGFzc3dvcmQxMjM=  # Just base64, NOT secure!
```

Challenges:
- Can't commit plaintext secrets to Git
- Need secrets for GitOps workflow
- Must maintain security and auditability
- Should avoid external secret stores if possible

---

## Decision

Use **Bitnami Sealed Secrets** for encrypting secrets in Git.

### How it Works

```
1. Developer creates plaintext secret locally
2. kubeseal encrypts with cluster public key
3. SealedSecret committed to Git safely
4. Sealed Secrets controller decrypts in cluster
5. Kubernetes Secret created and used by pods
```

### Example

```bash
# Create plaintext secret
kubectl create secret generic db-credentials \
  --from-literal=username=fineract \
  --from-literal=password=secret123 \
  --dry-run=client -o yaml > secret.yaml

# Seal it (encrypt)
kubeseal -f secret.yaml -o yaml > sealed-secret.yaml

# Commit sealed version to Git
git add sealed-secret.yaml
git commit -m "Add database credentials"
git push

# ArgoCD deploys sealed secret
# Controller decrypts automatically
```

---

## Consequences

### Positive

✅ **Git-friendly** - Encrypted secrets safe in version control
✅ **GitOps compatible** - Works seamlessly with ArgoCD
✅ **Simple** - No external secret store needed
✅ **Cluster-scoped** - Encryption key never leaves cluster
✅ **Auditability** - All secret changes tracked in Git
✅ **No additional infrastructure** - Just a controller

### Negative

⚠️ **Cluster coupling** - Secrets encrypted for specific cluster
⚠️ **Key management** - Must backup encryption keys
⚠️ **Migration complexity** - Re-seal for different clusters
⚠️ **Single point of failure** - Controller must be highly available

---

## Implementation Details

### Controller Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sealed-secrets-controller
  namespace: kube-system
spec:
  replicas: 2  # HA
  template:
    spec:
      containers:
      - name: sealed-secrets-controller
        image: quay.io/bitnami/sealed-secrets-controller:v0.27.0
```

### Secret Types Sealed

All secrets encrypted as SealedSecrets:
- Database credentials (PostgreSQL, Redis)
- API keys (MinIO, external services)
- OAuth secrets (Keycloak, frontend apps)
- TLS certificates (if not using cert-manager)
- Service account tokens
- Webhook secrets

### Directory Structure

```
secrets/
├── base/                    # Secret templates (not sealed)
│   ├── .gitignore           # Ignore plaintext secrets
│   └── *.template.yaml
├── dev/                     # Dev sealed secrets
│   ├── db-credentials-sealed.yaml
│   ├── redis-password-sealed.yaml
│   └── ...
├── uat/                     # UAT sealed secrets
│   └── ...
└── production/              # Production sealed secrets
    └── ...
```

### Automation

Created `scripts/create-all-sealed-secrets.sh` to:
1. Generate strong random passwords
2. Create secrets programmatically
3. Seal automatically
4. Save to correct environment directory

---

## Security Considerations

### Encryption

- **Algorithm**: RSA-2048 or RSA-4096
- **Key Storage**: Kubernetes Secret in `kube-system`
- **Key Rotation**: Supported, old keys retained for decryption
- **Scope**: Cluster-wide, namespace, or strict

### Access Control

- Controller runs in `kube-system` namespace
- Only controller can decrypt
- RBAC prevents unauthorized secret access
- Audit logs track secret usage

### Key Backup

**Critical**: Backup sealing keys for disaster recovery

```bash
# Export sealing key
kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealing-key-backup.yaml

# Store securely (encrypted storage, vault, etc.)
gpg --encrypt sealing-key-backup.yaml
```

---

## Alternatives Considered

### 1. External Secret Stores (Vault, AWS Secrets Manager)

**Rejected**:
- Adds infrastructure complexity
- Requires external dependencies
- Harder to manage in GitOps
- Costs more

### 2. Mozilla SOPS

**Rejected**:
- Requires GPG key management
- Less Kubernetes-native
- More complex workflow

### 3. Git-crypt

**Rejected**:
- Encrypts entire files
- Doesn't integrate with Kubernetes
- No controller pattern

### 4. Manual Secret Management

**Rejected**:
- Not GitOps
- No version control
- Hard to audit
- Error-prone

---

## Disaster Recovery

### Scenario: Cluster Lost

1. **Restore cluster** from backups
2. **Restore sealing keys** from secure backup
3. **Deploy Sealed Secrets controller** with restored keys
4. **ArgoCD syncs** SealedSecrets from Git
5. **Controller decrypts** and creates Secrets
6. **Applications start** with restored secrets

### Scenario: Key Rotation

1. **Controller generates new key** automatically or manually
2. **Old keys retained** for decrypting existing secrets
3. **Re-seal secrets** with new key at leisure
4. **Remove old keys** after all secrets re-sealed

---

## CI/CD Integration

### Pre-Commit Check

```yaml
# .github/workflows/security-check.yml
- name: Check for Plaintext Secrets
  run: ./scripts/check-plaintext-secrets.sh
```

### Secret Validation

```yaml
- name: Validate Sealed Secrets
  run: |
    for file in secrets/*/*.yaml; do
      if ! grep -q "kind: SealedSecret" "$file"; then
        echo "ERROR: $file is not a SealedSecret"
        exit 1
      fi
    done
```

---

## References

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Secrets Management Guide](../SECRETS_MANAGEMENT.md)
- [Migration to Sealed Secrets](../migrations/MIGRATION_TO_SEALED_SECRETS.md)

## Operational Documentation

For day-to-day operations and emergency procedures:
- **[Sealed Secrets DR Runbook](../SEALED_SECRETS_DR_RUNBOOK.md)** - Emergency recovery procedures
- **[Sealed Secrets Deployment Guide](../SEALED_SECRETS_DEPLOYMENT_GUIDE.md)** - Initial deployment instructions
- **[Disaster Recovery Guide](../DISASTER_RECOVERY.md)** - Comprehensive DR procedures
- **[Multi-Region DR Strategy](../MULTI_REGION_DR_STRATEGY.md)** - Cross-region failover strategy
- **[Key Rotation Audit Log](../../operations/sealed-secrets-key-audit.yaml)** - Track all key operations
