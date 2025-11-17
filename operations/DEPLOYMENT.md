# Fineract Operations Deployment Guide

This guide provides step-by-step instructions for deploying Fineract operations components using ArgoCD and GitOps practices.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Deployment Workflow](#deployment-workflow)
5. [Phase 1: Keycloak Configuration](#phase-1-keycloak-configuration)
6. [Phase 2: Secrets Management](#phase-2-secrets-management)
7. [Phase 3: Fineract Data Loading](#phase-3-fineract-data-loading)
8. [Verification](#verification)
9. [Troubleshooting](#troubleshooting)
10. [Rollback Procedures](#rollback-procedures)

## Overview

The Fineract operations deployment consists of three main components:

1. **Keycloak Configuration**: Sets up OAuth2/OIDC authentication realm and clients
2. **Secrets Management**: Manages OAuth2 credentials and API keys using SealedSecrets
3. **Fineract Data Loading**: Loads configuration and demo data in sequence using ArgoCD sync waves

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

# kubeseal CLI
brew install kubeseal

# Or on Linux
curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz | tar xz
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
              ▼               ▼               ▼
    ┌──────────────┐ ┌─────────────┐ ┌──────────────┐
    │  Keycloak    │ │   Secrets   │ │   Fineract   │
    │  Config      │ │   (Sealed)  │ │   Data       │
    │ (Sync Wave 5)│ │             │ │ (PostSync)   │
    └──────────────┘ └─────────────┘ └──────────────┘
           │                │                 │
           │                │                 │
           ▼                ▼                 ▼
    ┌──────────────────────────────────────────┐
    │         Kubernetes Resources             │
    │  Jobs, Secrets, ConfigMaps, etc.        │
    └──────────────────────────────────────────┘
```

### Sync Wave Strategy

The deployment uses ArgoCD sync waves for ordered execution:

- **Wave 5**: Keycloak configuration (realm, clients, roles)
- **Wave 10**: Fineract data loading orchestration
- **PostSync Waves 1-40**: Individual data loading jobs
  - Waves 1-14: System configuration
  - Waves 15-29: Products and accounting
  - Waves 30-39: Demo data (dev/uat only)
  - Wave 40: Calendar data

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

## Phase 3: Fineract Data Loading

### Step 1: Deploy Fineract Data Applications

Deploy for each environment:

```bash
# Deploy all data loading applications
kubectl apply -f argocd/applications/operations/fineract-data-dev.yaml
kubectl apply -f argocd/applications/operations/fineract-data-uat.yaml
kubectl apply -f argocd/applications/operations/fineract-data-production.yaml
```

Or deploy all at once using Kustomize:

```bash
kubectl apply -k argocd/applications/operations/
```

### Step 2: Monitor Sync Progress

```bash
# Watch ArgoCD sync progress
argocd app wait fineract-data-dev --timeout 600

# Or use kubectl
kubectl get applications -n argocd | grep fineract-data

# Monitor jobs by sync wave
kubectl get jobs -n fineract-dev --sort-by=.metadata.annotations."argocd\.argoproj\.io/sync-wave"
```

### Step 3: Monitor Individual Job Execution

```bash
# Watch job progress in real-time
watch kubectl get jobs -n fineract-dev

# View logs from a specific job
kubectl logs -n fineract-dev job/load-code-values -f

# Check for failed jobs
kubectl get jobs -n fineract-dev --field-selector status.successful!=1
```

### Step 4: Verify Data Loading Completion

```bash
# Count completed jobs
kubectl get jobs -n fineract-dev -o json | \
  jq '.items | map(select(.status.succeeded == 1)) | length'

# Expected: All jobs should be completed
# Dev/UAT: ~44 jobs (including demo data)
# Production: ~35 jobs (excluding demo data)

# Check for any failed jobs
kubectl get jobs -n fineract-dev -o json | \
  jq '.items | map(select(.status.failed > 0)) | length'

# Expected: 0 failed jobs
```

## Granular Data Rollback

While the primary data loading process is automated, situations may arise where specific data entries need to be rolled back or modified outside of a full database restore. The `fineract-api-executor` job provides a flexible mechanism to execute arbitrary Fineract API calls, enabling granular data manipulation, including rollbacks.

### How to Use the `fineract-api-executor` for Rollback

The `fineract-api-executor` job is designed to be instantiated with specific API parameters to perform targeted actions.

1.  **Define the API Call**: Determine the Fineract API endpoint, HTTP method (e.g., `DELETE`, `PUT`, `POST`), and any required request body for the desired rollback action. Refer to the [Fineract API Documentation](https://fineract.apache.org/docs/api/) for available endpoints.

2.  **Create a Custom Job Manifest**: Create a new Kubernetes Job manifest based on `operations/fineract-data/jobs/base/fineract-api-executor.yaml`. You will need to override the default environment variables (`API_ENDPOINT`, `API_METHOD`, `API_BODY`) with your specific values.

    **Example: Deleting a Specific Code Value**

    Let's say you want to delete a code value with `codeId=1` and `codevalueId=10` that was mistakenly loaded.

    Create a file named `delete-code-value-job.yaml` (or similar) in your environment's overlay (e.g., `environments/dev/jobs/`):

    ```yaml
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: delete-code-value-1-10
      annotations:
        argocd.argoproj.io/hook: Sync
        argocd.argoproj.io/sync-wave: "50" # Ensure it runs after data loading
        argocd.argoproj.io/hook-delete-policy: HookSucceeded
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: api-executor
            image: curlimages/curl:latest
            env:
            - name: FINERACT_API_BASE_URL
              value: "http://fineract-service:8443/fineract-provider/api/v1" # Override if needed
            - name: KEYCLOAK_AUTH_URL
              value: "http://keycloak-service:8080" # Override if needed
            - name: FINERACT_USERNAME
              valueFrom:
                secretKeyRef:
                  name: fineract-admin-credentials
                  key: username
            - name: FINERACT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-admin-credentials
                  key: password
            - name: API_ENDPOINT
              value: "/codes/1/codevalues/10" # Specific endpoint for deletion
            - name: API_METHOD
              value: "DELETE"
            # API_BODY is not needed for DELETE requests
            command:
            - /bin/sh
            - -c
            - |
              TOKEN=$(curl -s -X POST "${KEYCLOAK_AUTH_URL}/realms/fineract/protocol/openid-connect/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "grant_type=password" \
                -d "username=${FINERACT_USERNAME}" \
                -d "password=${FINERACT_PASSWORD}" \
                -d "scope=read" \
                -d "client_id=fineract-data-loader" \
                -d "client_secret=${FINERACT_PASSWORD}" | jq -r '.access_token')

              if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
                echo "Failed to obtain access token."
                exit 1
              fi

              echo "Executing API call: ${API_METHOD} ${FINERACT_API_BASE_URL}${API_ENDPOINT}"

              if [ -n "$API_BODY" ]; then
                curl -v -X ${API_METHOD} \
                  -H "Authorization: Bearer ${TOKEN}" \
                  -H "Content-Type: application/json" \
                  -d "${API_BODY}" \
                  "${FINERACT_API_BASE_URL}${API_ENDPOINT}"
              else
                curl -v -X ${API_METHOD} \
                  -H "Authorization: Bearer ${TOKEN}" \
                  "${FINERACT_API_BASE_URL}${API_ENDPOINT}"
              fi
    ```

3.  **Apply the Custom Job**: Apply this manifest to your Kubernetes cluster. If using ArgoCD, ensure it's part of an application that targets the correct environment.

    ```bash
    kubectl apply -f environments/dev/jobs/delete-code-value-1-10.yaml
    ```

4.  **Monitor Job Execution**: Monitor the job logs to ensure the API call was successful.

    ```bash
    kubectl get job delete-code-value-1-10 -n fineract-dev
    kubectl logs -f job/delete-code-value-1-10 -n fineract-dev
    ```

This approach provides the flexibility to perform targeted data rollbacks or modifications by leveraging the Fineract API directly through a Kubernetes Job.

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

# 3. Check job completion
for ns in fineract-dev fineract-uat fineract-production; do
  echo "=== $ns ==="
  kubectl get jobs -n $ns --no-headers | wc -l
done
```

### Data-Level Checks

Verify data was loaded correctly by querying the Fineract API:

```bash
# Get OAuth2 token
TOKEN=$(curl -X POST "http://keycloak-service:8080/realms/fineract/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=fineract-data-loader" \
  -d "client_secret=YOUR_CLIENT_SECRET" | jq -r '.access_token')

# Check code values
curl -H "Authorization: Bearer $TOKEN" \
  "http://fineract-service:8443/fineract-provider/api/v1/codes" | jq

# Check offices
curl -H "Authorization: Bearer $TOKEN" \
  "http://fineract-service:8443/fineract-provider/api/v1/offices" | jq

# Check loan products
curl -H "Authorization: Bearer $TOKEN" \
  "http://fineract-service:8443/fineract-provider/api/v1/loanproducts" | jq
```

### ArgoCD UI Verification

1. Open ArgoCD UI
2. Navigate to Applications
3. Check status of:
   - `keycloak-config`
   - `fineract-data-dev`
   - `fineract-data-uat`
   - `fineract-data-production`
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

#### 3. Data Loading Job Fails

**Symptom**: Individual data loading job fails
**Solution**:
```bash
# Identify the failed job
kubectl get jobs -n fineract-dev --field-selector status.successful!=1

# Check job logs
kubectl logs -n fineract-dev job/FAILED_JOB_NAME

# Common issues:
# - OAuth2 auth failed: Check fineract-admin-credentials secret
# - Data validation error: Check YAML data format
# - Dependency missing: Ensure previous wave jobs completed

# Fix the issue and re-run specific job
kubectl delete job FAILED_JOB_NAME -n fineract-dev
argocd app sync fineract-data-dev
```

#### 4. Production Demo Data Leaked

**Symptom**: Demo data jobs running in production
**Solution**:
```bash
# Verify production overlay excludes demo data
cat operations/fineract-data/jobs/overlays/production/kustomization.yaml

# Should contain patch with annotationSelector for waves 30-39

# If demo data was loaded, you'll need to:
# 1. Delete demo entities via Fineract API
# 2. Or restore database from backup
# 3. Re-sync with fixed configuration
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

### Rolling Back Data Loading

```bash
# Rollback ArgoCD Application
argocd app rollback fineract-data-dev REVISION_NUMBER

# Or delete data and re-load
# WARNING: This will delete all loaded data!
kubectl delete jobs -n fineract-dev -l app.kubernetes.io/part-of=fineract-data

# Restore database from backup (recommended approach)
# 1. Stop Fineract
# 2. Restore database
# 3. Restart Fineract
# 4. Re-sync ArgoCD
```

### Emergency Rollback

In case of critical issues:

```bash
# Pause all ArgoCD Applications
argocd app set keycloak-config --sync-policy=none
argocd app set fineract-data-dev --sync-policy=none
argocd app set fineract-data-uat --sync-policy=none
argocd app set fineract-data-production --sync-policy=none

# Investigate and fix the issue

# Re-enable auto-sync after fix
argocd app set keycloak-config --sync-policy=automated
argocd app set fineract-data-dev --sync-policy=automated
argocd app set fineract-data-uat --sync-policy=automated
# Note: Production uses manual sync by default
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
