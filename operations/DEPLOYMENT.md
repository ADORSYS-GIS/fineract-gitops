# Fineract Operations Deployment Guide

This guide provides step-by-step instructions for deploying Fineract operations components using ArgoCD and GitOps practices.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Deployment Workflow](#deployment-workflow)
5. [Phase 1: Keycloak Configuration](#phase-1-keycloak-configuration)
6. [Phase 2: Secrets Management](#phase-2-secrets-management)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)
9. [Rollback Procedures](#rollback-procedures)

## Overview

The Fineract operations deployment consists of two main components:

1. **Keycloak Configuration**: Sets up OAuth2/OIDC authentication realm and clients
2. **Secrets Management**: Manages OAuth2 credentials and API keys using SealedSecrets

All components are deployed using ArgoCD Applications following GitOps principles.

## Prerequisites

### Required Tools

```bash
# Check if tools are installed
kubectl version --client
argocd version
kubeseal --version
```

Install missing tools:

```bash
# ArgoCD CLI
brew install argocd

# kubeseal CLI (v0.27.0 - must match controller version)
brew install kubeseal

# Or on Linux
curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz | tar xz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Cluster Requirements

- Kubernetes cluster (1.23+)
- ArgoCD installed and configured
- SealedSecrets controller installed
- Keycloak service running
- Fineract service running

### Access Requirements

- kubectl access to target cluster
- ArgoCD admin credentials
- Git repository access

## Architecture

### Component Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│                    ArgoCD Applications                       │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼
    ┌──────────────┐ ┌─────────────┐
    │  Keycloak    │ │   Secrets   │
    │  Config      │ │   (Sealed)  │
    │ (Sync Wave 5)│ │             │
    └──────────────┘ └─────────────┘
           │                │
           │                │
           ▼                ▼
    ┌──────────────────────────────────────────┐
    │         Kubernetes Resources             │
    │  Jobs, Secrets, ConfigMaps, etc.        │
    └──────────────────────────────────────────┘
```

### Sync Wave Strategy

The deployment uses ArgoCD sync waves for ordered execution:

- **Wave 5**: Keycloak configuration (realm, clients, roles)

## Deployment Workflow

### High-Level Steps

1. Set up secrets (one-time)
2. Deploy ArgoCD Applications
3. Monitor sync progress
4. Verify data loading
5. Validate system readiness

### Environment-Specific Deployments

| Environment | Namespace | Demo Data | Sync Policy |
|-------------|-----------|-----------|-------------|
| Development | fineract-dev | Included | Auto-sync |
| UAT | fineract-uat | Included | Auto-sync |
| Production | fineract-production | Excluded | Manual |

## Phase 1: Keycloak and Secret Management

The Keycloak configuration and client secret management process is fully automated. When the Keycloak ArgoCD application is deployed, the following steps are executed:

1.  The `apply-keycloak-config` job runs, which configures the Keycloak realm, clients, and roles. This job automatically generates client secrets for the newly created clients.
2.  The `export-keycloak-secrets` job runs, which extracts the generated client secrets from Keycloak and creates a Kubernetes secret named `keycloak-client-secrets` in the target namespace.

### Step 1: Deploy Keycloak Config Application

```bash
# Apply the ArgoCD Application for Keycloak
kubectl apply -f argocd/applications/operations/keycloak-config.yaml

# Monitor the sync progress
argocd app wait keycloak-config
```

### Step 2: Verify Secret Creation

Once the sync is complete, verify that the `keycloak-client-secrets` secret has been created:

```bash
# Check for the secret in the target namespace (e.g., fineract-dev)
kubectl get secret keycloak-client-secrets -n fineract-dev
```

### Step 3: Seal the Client Secrets

After the `keycloak-client-secrets` secret has been created, you can seal it for other environments (e.g., UAT, production) using the following process:

1.  **Fetch the secret and pipe it to `kubeseal`**:

    ```bash
    # Seal for UAT
    kubectl get secret keycloak-client-secrets -n fineract-dev -o json | kubeseal --scope cluster-wide --controller-namespace sealed-secrets -o yaml > environments/uat/secrets/sealed-keycloak-client-secrets.yaml

    # Seal for Production
    kubectl get secret keycloak-client-secrets -n fineract-dev -o json | kubeseal --scope cluster-wide --controller-namespace sealed-secrets -o yaml > environments/production/secrets/sealed-keycloak-client-secrets.yaml
    ```

2.  **Commit the sealed secrets to Git**:

    ```bash
    git add environments/uat/secrets/sealed-keycloak-client-secrets.yaml
    git add environments/production/secrets/sealed-keycloak-client-secrets.yaml
    git commit -m "feat: add sealed Keycloak client secrets"
    git push
    ```

This automated process ensures that client secrets are generated and managed securely without any manual intervention.

## Verification

### System-Level Checks

```bash
# 1. Check all ArgoCD Applications are healthy
argocd app list | grep operations

# 2. Verify all secrets exist
for ns in fineract-dev fineract-uat fineract-production; do
  echo "=== $ns ==="
  kubectl get secrets -n $ns | grep -E "(fineract-admin|keycloak-client)"
done
```

### ArgoCD UI Verification

1. Open ArgoCD UI
2. Navigate to Applications
3. Check status of:
   - `keycloak-config`
4. Verify all are "Synced" and "Healthy"

## Troubleshooting

### Common Issues

#### 1. Keycloak Config Job Fails

**Symptom**: Job stays in pending or fails
**Solution**:
```bash
# Check job logs
kubectl logs -n fineract-dev job/apply-keycloak-config

# Common issues:
# - Keycloak not ready: Wait and retry
# - Secret missing: Verify keycloak-admin-credentials exists
# - Network issues: Check service connectivity

# Restart the job
kubectl delete job apply-keycloak-config -n fineract-dev
argocd app sync keycloak-config
```

#### 2. SealedSecret Won't Decrypt

**Symptom**: SealedSecret exists but Secret not created
**Solution**:
```bash
# Check SealedSecrets controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller

# Common issues:
# - Wrong namespace: Ensure namespace matches target
# - Certificate mismatch: Re-fetch cluster certificate
# - Controller not running: Check pod status

# Re-fetch certificate and re-seal
kubeseal --fetch-cert > pub-sealed-secrets.pem
./seal-secrets.sh
```


### Debug Commands

```bash
# View ArgoCD Application details
argocd app get APP_NAME

# Check sync status
argocd app history APP_NAME

# View application logs
argocd app logs APP_NAME

# Describe problematic resources
kubectl describe job JOB_NAME -n NAMESPACE

# Check events
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'

# View pod logs if job is running
kubectl logs -n NAMESPACE -l job-name=JOB_NAME
```

## Rollback Procedures

### Rolling Back Keycloak Configuration

```bash
# Rollback to previous sync
argocd app rollback keycloak-config REVISION_NUMBER

# Or delete and re-apply
kubectl delete -f argocd/applications/operations/keycloak-config.yaml
# Fix the issue in Git
git revert COMMIT_HASH
git push
kubectl apply -f argocd/applications/operations/keycloak-config.yaml
```

### Emergency Rollback

In case of critical issues:

```bash
# Pause all ArgoCD Applications
argocd app set keycloak-config --sync-policy=none

# Investigate and fix the issue

# Re-enable auto-sync after fix
argocd app set keycloak-config --sync-policy=automated
```

## Best Practices

### Security

1. Never commit unencrypted secrets to Git
2. Rotate client secrets regularly
3. Use RBAC to restrict access to secrets
4. Audit ArgoCD sync logs regularly
5. Use separate service accounts per environment

### Operations

1. Always test in dev before deploying to production
2. Monitor job execution during deployment
3. Verify data integrity after loading
4. Keep backups before major changes
5. Document any manual changes

### GitOps

1. All changes should go through Git
2. Use pull requests for production changes
3. Tag releases for traceability
4. Maintain clear commit messages
5. Review ArgoCD sync diffs before approval

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [SealedSecrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Fineract API Documentation](https://fineract.apache.org/docs/api/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review ArgoCD and job logs
3. Consult the Fineract community
4. Open an issue in the GitOps repository
