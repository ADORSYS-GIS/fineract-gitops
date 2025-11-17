# Operations Applications

This directory contains ArgoCD Application manifests for operational tasks and utilities that require manual deployment.

## Applications

### Database Operations
- **database-init.yaml** - Database initialization job (one-time setup)
- **database-setup.yaml** - Database configuration and schema setup

### Data Management
- **fineract-data-dev.yaml** - Development environment data loading
- **fineract-data-uat.yaml** - UAT environment data loading
- **fineract-data-production.yaml** - Production environment data loading

### Identity & Access
- **keycloak-config.yaml** - Keycloak realm and client configuration

### Services
- **user-sync-service.yaml** - User synchronization service between Keycloak and Fineract

## Deployment

These applications are **NOT** managed by the app-of-apps pattern and require manual deployment.

### Deploy Individual Application
```bash
kubectl apply -f argocd/applications/operations/<application-name>.yaml
```

### Deploy All Operations Applications
```bash
kubectl apply -k argocd/applications/operations/
```

## Why Manual Deployment?

Operations applications are deployed manually because they:
1. Run as one-time jobs or on-demand tasks
2. Require specific timing (e.g., after infrastructure is ready)
3. Need manual verification before execution
4. Are environment-specific and may not apply to all deployments

## Integration with Environments

Some operations applications reference environment-specific configurations:
- Database operations use credentials from each environment's sealed secrets
- Data loading jobs target specific namespaces (fineract-dev, fineract-uat, fineract-production)
- Keycloak config syncs with the active Keycloak instance per environment
