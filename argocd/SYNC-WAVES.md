# ArgoCD Sync Wave Ordering

This document defines the standardized sync wave ordering for all Fineract GitOps deployments.

## Overview

Sync waves control the order in which ArgoCD synchronizes resources. Lower wave numbers deploy first, and ArgoCD waits for each wave to become healthy before proceeding to the next.

## Standardized Wave Order

| Wave | Components | Purpose | Wait for Health |
|------|------------|---------|-----------------|
| **-5** | Sealed Secrets Controller | Decrypt secrets before any app needs them | Yes |
| **0** | Network Policies, Namespaces | Establish network boundaries and namespaces | Yes |
| **1** | Keycloak Config (Realms, Clients) | Configure auth before Keycloak starts | No |
| **2** | Database Setup (Schema/Init Jobs) | Initialize database schemas | Yes |
| **3** | Databases (PostgreSQL), Redis, Keycloak | Core infrastructure services | Yes |
| **5** | OAuth2 Proxy | Authentication proxy (after Keycloak + Redis) | Yes |
| **6** | Ingress Controllers, Cert-Manager | Routing and TLS certificates | Yes |
| **10** | Fineract Backend | Main application | Yes |
| **11** | Web App (Frontend) | User interface | Yes |

## Implementation by Environment

### Development Environment

```
Wave -5:  sealed-secrets-controller
Wave  0:  network-policies
Wave  1:  keycloak-config
Wave  2:  database-setup
Wave  3:  keycloak, fineract-redis
Wave  5:  oauth2-proxy
Wave  6:  fineract-ingress
Wave 10:  fineract (backend)
Wave 11:  web-app (frontend)
```

### UAT Environment

```
Wave  0:  network-policies
Wave  1:  monitoring (Prometheus/Grafana)
Wave  2:  logging (Loki/Promtail)
Wave  3:  keycloak, fineract-redis
Wave  5:  oauth2-proxy
Wave  6:  fineract-ingress
Wave 10:  fineract (backend)
```

### Production Environment

Same as UAT, with stricter health checks and manual sync policies.

## Rationale

### Why These Waves?

1. **Wave -5 (Sealed Secrets)**: Must decrypt secrets before any application tries to use them
2. **Wave 0 (Network Policies)**: Security boundaries established first
3. **Wave 1 (Keycloak Config)**: Realm/client configuration must exist before Keycloak pods start
4. **Wave 2 (Database Setup)**: Schema must exist before apps connect
5. **Wave 3 (Infrastructure)**: Databases and core services
6. **Wave 5 (OAuth2 Proxy)**: Depends on Keycloak (Wave 3) being healthy
7. **Wave 6 (Ingress/TLS)**: Routing configured after apps are ready
8. **Wave 10 (Fineract)**: Main application after all dependencies
9. **Wave 11 (Web App)**: Frontend after backend is healthy

## Adding Sync Waves

To add a sync wave annotation to an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # Deploy in wave 10
spec:
  # ... rest of application spec
```

## Health Checks

ArgoCD considers a wave complete when all applications in that wave report healthy. Configure appropriate health checks for each component:

- **Databases**: Check for ready pods
- **Keycloak**: Check HTTP endpoint returns 200
- **Fineract**: Check `/fineract-provider/actuator/health`
- **Jobs**: Check for successful completion

## Troubleshooting

### App Stuck in Wave

If an application is stuck and blocking subsequent waves:

1. Check the application health status:
   ```bash
   argocd app get <app-name>
   ```

2. View the sync operation status:
   ```bash
   kubectl get application <app-name> -n argocd -o yaml
   ```

3. Temporarily skip the wave by removing the annotation (not recommended for production)

### Circular Dependencies

If you encounter circular dependencies:

1. Review the dependency graph
2. Consider using PreSync/PostSync hooks instead of waves
3. Break the dependency by using init containers

## Best Practices

1. **Leave gaps**: Use waves 0, 3, 5, 10, 20 instead of 1, 2, 3, 4, 5 to allow insertions
2. **Document rationale**: Add comments explaining why a specific wave was chosen
3. **Test ordering**: Deploy to dev environment first to validate wave order
4. **Monitor duration**: Each wave should complete within 5 minutes ideally
5. **Consistent across envs**: Use same wave numbers across dev/uat/production

## References

- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
