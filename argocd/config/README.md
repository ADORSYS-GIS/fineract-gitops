# ArgoCD Configuration

This directory contains the ArgoCD configuration files for the Fineract GitOps repository.

## Files

### `argocd-cm.yaml` - ArgoCD ConfigMap

Main configuration for ArgoCD server including:

- **Repository Configuration**: Git repository URLs and credentials
- **Resource Tracking**: How ArgoCD tracks deployed resources (annotation-based)
- **Kustomize Options**: Build options for Kustomize
- **Resource Exclusions**: Resources to ignore during sync
- **Health Checks**: Custom health check logic for applications
- **Timeout Settings**: Reconciliation timeout (5 minutes)
- **SSO Configuration**: Dex connector for OIDC (optional, for production)

### `argocd-rbac-cm.yaml` - ArgoCD RBAC ConfigMap

Role-Based Access Control (RBAC) policies for ArgoCD including:

- **Built-in Roles**: Platform admins, SRE team
- **Environment-specific Roles**: Dev, UAT, production access
- **Project-specific Roles**: Granular permissions per AppProject
- **Team Roles**: Developers, QA team, release managers, support team

## Installation

### Prerequisites

1. Kubernetes cluster (v1.24+)
2. kubectl configured
3. ArgoCD installed (see [ArgoCD Installation Guide](https://argo-cd.readthedocs.io/en/stable/getting_started/))

### Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Apply Configuration

```bash
# Apply ArgoCD configuration
kubectl apply -f argocd/config/argocd-cm.yaml
kubectl apply -f argocd/config/argocd-rbac-cm.yaml

# Restart ArgoCD server to apply changes
kubectl rollout restart deployment/argocd-server -n argocd
```

### Access ArgoCD UI

```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Open browser
# https://localhost:8080
# Username: admin
# Password: (from previous command)
```

## RBAC Roles

### Platform Roles

| Role | Permissions | Groups |
|------|-------------|--------|
| `role:admin` | Full access to everything | `platform-admins` |
| `role:sre` | Full access to all environments | `sre-team` |
| `role:viewer` | Read-only access to all environments | `viewers` |

### Environment-specific Roles

#### Development Environment (`fineract-dev`)

| Role | Permissions | Groups |
|------|-------------|--------|
| `role:dev-lead` | Full access to dev apps | `dev-leads` |
| `role:developer` | Read + sync for dev apps | `developers` |

#### UAT Environment (`fineract-uat`)

| Role | Permissions | Groups |
|------|-------------|--------|
| `role:qa-lead` | Full access to UAT apps | `qa-leads` |
| `role:qa` | Read + sync for UAT apps | `qa-team` |

#### Production Environment (`fineract-production`)

| Role | Permissions | Groups |
|------|-------------|--------|
| `role:release-manager` | Deploy to production (with approval) | `release-managers` |
| `role:support` | Read-only access to production | `support-team` |

### Project-specific Roles

Each AppProject defines its own roles:

- `proj:fineract-dev:admin` - Full access to dev project
- `proj:fineract-dev:read-only` - Read-only access to dev project
- `proj:fineract-UAT:deployer` - Deploy to UAT
- `proj:fineract-UAT:read-only` - Read-only access to UAT
- `proj:fineract-production:deployer` - Deploy to production
- `proj:fineract-production:admin` - Full access to production project
- `proj:fineract-production:read-only` - Read-only access to production

## Configuration Options

### Repository Configuration

Update the repository URL in `argocd-cm.yaml`:

```yaml
repositories: |
  - url: https://github.com/YOUR-ORG/fineract-gitops.git
    name: fineract-gitops
    type: git
```

### Repository Credentials

For private repositories, create a secret:

```bash
kubectl create secret generic github-creds \
  --from-literal=username=YOUR_USERNAME \
  --from-literal=password=YOUR_TOKEN \
  -n argocd
```

Then uncomment the `repository.credentials` section in `argocd-cm.yaml`.

### SSO Configuration (Production)

For production deployments, configure SSO using Dex:

1. Uncomment the `dex.config` section in `argocd-cm.yaml`
2. Update the OIDC issuer URL and client credentials
3. Create a secret for the client secret:

```bash
kubectl create secret generic dex-keycloak-client \
  --from-literal=clientSecret=YOUR_CLIENT_SECRET \
  -n argocd
```

### RBAC Group Mapping

If using SSO, map OIDC groups to ArgoCD roles by updating the group names in `argocd-rbac-cm.yaml`:

```csv
g, platform-admins, role:admin
g, your-oidc-admin-group, role:admin
```

## Sync Windows

Sync windows restrict when applications can be deployed:

- **Development**: No restrictions
- **Staging**: Mon-Fri, 9 AM - 5 PM (see `project-UAT.yaml`)
- **Production**: Tue-Thu, 10 AM - 4 PM (see `project-production.yaml`)

Manual sync is always allowed for emergency deployments.

## Resource Tracking

ArgoCD uses **annotation-based tracking** to identify resources it manages:

```yaml
application.resourceTrackingMethod: annotation
```

This adds the following annotation to all managed resources:

```yaml
argocd.argoproj.io/tracking-id: fineract-app:argoproj.io/Application:fineract-dev/fineract-app
```

## Health Checks

Custom health checks are defined for:

- **Applications**: Check sync status and health status
- **StatefulSets**: Check `readyReplicas == replicas`
- **Deployments**: Check `updatedReplicas == availableReplicas == replicas`
- **Jobs**: Check `succeeded > 0`

## Troubleshooting

### Configuration not applied

If changes to the ConfigMaps are not reflected:

```bash
# Restart ArgoCD server
kubectl rollout restart deployment/argocd-server -n argocd

# Check logs
kubectl logs -f deployment/argocd-server -n argocd
```

### RBAC issues

Check RBAC policies:

```bash
# Get current RBAC config
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Test RBAC for a user
argocd account can-i sync applications fineract-dev/fineract-app
```

### Repository connection issues

Test repository connection:

```bash
# List repositories
argocd repo list

# Test connection
argocd repo get https://github.com/YOUR-ORG/fineract-gitops.git
```

## Security Best Practices

1. **Disable anonymous access** in production:
   ```yaml
   users.anonymous.enabled: "false"
   ```

2. **Use Sealed Secrets** for sensitive data:
   - Repository credentials (see `scripts/seal-argocd-github-credentials.sh`)
   - SSO client secrets
   - OIDC tokens

3. **Enable GPG signature verification** for production:
   ```yaml
   signatureKeys:
     - keyID: ABCDEF1234567890
   ```

4. **Restrict exec access**:
   ```yaml
   exec.enabled: "false"
   ```

5. **Use SSO/OIDC** instead of local users for production

6. **Enable audit logging** via ArgoCD server configuration

## References

- [ArgoCD RBAC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [ArgoCD Configuration Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)
- [ArgoCD User Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [Dex OIDC Configuration](https://dexidp.io/docs/connectors/)
