# Fineract Data Loader - Deployment Guide

## Overview

This guide explains how to deploy and manage the Fineract data loader system, which automatically initializes a Fineract instance with configuration and master data.

## Architecture

The data loader system consists of:
1. **Python loader scripts** - Each handles a specific entity type
2. **YAML data files** - Declarative configuration in GitOps style
3. **Kubernetes Jobs** - Execute loaders in proper dependency order
4. **ConfigMaps** - Store scripts and data in Kubernetes

## Prerequisites

- Kubernetes cluster with `fineract-dev` namespace
- Fineract instance running and accessible
- kubectl configured with cluster access
- kustomize (or kubectl with kustomize support)

## Directory Structure

```
operations/fineract-data/
├── data/                     # YAML data files
│   └── dev/                 # Environment-specific data
├── scripts/
│   └── loaders/             # Python loader scripts
├── kubernetes/              # Kubernetes deployment
│   ├── jobs/               # Job manifests
│   ├── kustomization.yaml  # Kustomize configuration
│   └── deploy.sh           # Deployment script
└── DEPLOYMENT_GUIDE.md     # This file
```

## Deployment Steps

### 1. Create Required Secrets

First, create the necessary credentials:

```bash
# Fineract admin credentials
kubectl create secret generic fineract-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=your-password \
  -n fineract-dev

# Keycloak credentials (for staff loader)
kubectl create secret generic keycloak-admin-credentials \
  --from-literal=client-id=admin-cli \
  --from-literal=client-secret=your-secret \
  -n fineract-dev
```

### 2. Deploy Using Kustomize

```bash
cd operations/fineract-data/kubernetes

# Preview what will be deployed
kubectl kustomize .

# Deploy all resources
kubectl apply -k .

# Or use the deployment script
./deploy.sh
```

### 3. Monitor Progress

Watch job execution:

```bash
# Monitor all data loader jobs
kubectl get jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader -w

# Check specific job logs
kubectl logs job/fineract-data-code-values -n fineract-dev

# Use the monitoring script
./deploy.sh  # Includes automatic monitoring
```

## Job Execution Order

Jobs execute in waves to respect dependencies:

| Wave | Jobs | Purpose |
|------|------|---------|
| 1 | code-values | System codes and values |
| 2 | offices | Organization hierarchy |
| 3 | staff, roles, currency-config, working-days | Users and system config |
| 10 | chart-of-accounts | GL account structure |
| 11 | tax-groups | Tax configuration |
| 12 | floating-rates | Interest rate references |
| 15 | charges | Fees and charges |
| 20 | loan-products, savings-products | Product definitions |
| 21 | savings-product-accounting, financial-activity-mappings | Accounting mappings |

## Data Management

### Adding New Data

1. Create YAML files in `data/dev/` following the schema
2. Validate with: `python3 scripts/validate_yaml_data.py data/dev/your-dir`
3. Redeploy the ConfigMap and jobs

### Modifying Existing Data

1. Edit YAML files in `data/dev/`
2. Delete and recreate the relevant job:
   ```bash
   kubectl delete job fineract-data-<loader> -n fineract-dev
   kubectl apply -f kubernetes/jobs/job-<loader>.yaml
   ```

### Environment-Specific Data

Create separate directories for each environment:
```
data/
├── dev/      # Development data
├── uat/      # UAT data
└── prod/     # Production data
```

## Troubleshooting

### Common Issues

#### Job Failed

Check logs:
```bash
kubectl logs job/fineract-data-<loader> -n fineract-dev
```

Common causes:
- API endpoint unavailable
- Invalid credentials
- Missing dependencies (wrong execution order)
- Malformed YAML data

#### Job Stuck in Pending

Check events:
```bash
kubectl describe job fineract-data-<loader> -n fineract-dev
```

Common causes:
- ConfigMap not created
- Secret missing
- Resource constraints

#### Data Not Loading

1. Verify Fineract is accessible:
   ```bash
   kubectl exec -it deployment/fineract -n fineract-dev -- curl http://localhost:8080/fineract-provider/api/v1/
   ```

2. Check loader script:
   ```bash
   python3 scripts/loaders/<loader>.py --help
   ```

3. Test locally:
   ```bash
   ./scripts/test_loaders_locally.sh --loader <loader-name>
   ```

### Rerunning Jobs

To rerun a failed or completed job:

```bash
# Delete the job
kubectl delete job fineract-data-<loader> -n fineract-dev

# Reapply
kubectl apply -f kubernetes/jobs/job-<loader>.yaml
```

### Cleanup

To remove all data loader resources:

```bash
kubectl delete jobs -n fineract-dev -l app.kubernetes.io/name=fineract-data-loader
kubectl delete configmap fineract-loader-scripts fineract-data-dev -n fineract-dev
kubectl delete serviceaccount fineract-data-loader -n fineract-dev
```

## Advanced Configuration

### Custom Job Settings

Edit job manifests to adjust:
- `backoffLimit`: Number of retries (default: 3)
- `ttlSecondsAfterFinished`: Cleanup time (default: 300s)
- `resources`: Memory/CPU limits
- `parallelism`: Parallel pod execution

### Using Persistent Volumes

For large datasets exceeding ConfigMap limits (1MB):

1. Create a PersistentVolume with data
2. Mount in jobs instead of ConfigMap
3. Update job manifests to use PV

### ArgoCD Integration

The jobs use ArgoCD annotations for GitOps:
- `argocd.argoproj.io/sync-wave`: Execution order
- `argocd.argoproj.io/hook`: PostSync execution

## Testing

### Local Testing

Test individual loaders:
```bash
cd operations/fineract-data

# Test single loader
python3 scripts/loaders/code_values.py \
  --yaml-dir data/dev/codes-and-values \
  --fineract-url https://api.dev.fineract.com \
  --tenant default
```

### Dry Run

Preview Kubernetes changes:
```bash
kubectl apply -k kubernetes/ --dry-run=client
```

## Security Considerations

1. **Secrets Management**: Use external secret managers in production
2. **RBAC**: ServiceAccount has minimal required permissions
3. **Network Policies**: Consider restricting job network access
4. **Audit Logging**: Enable for tracking data changes

## Performance Optimization

1. **Parallel Execution**: Jobs in same wave run in parallel
2. **Resource Allocation**: Adjust based on data volume
3. **ConfigMap Size**: Split large datasets across multiple ConfigMaps
4. **Caching**: Loaders cache lookups within execution

## Monitoring & Observability

1. **Job Metrics**: Export to Prometheus
2. **Logging**: Centralize with Fluentd/Elasticsearch
3. **Alerts**: Configure for job failures
4. **Dashboards**: Create Grafana dashboards

## Maintenance

### Regular Tasks

- Review and cleanup completed jobs
- Update loader scripts for API changes
- Validate data integrity
- Backup configuration data

### Upgrading

1. Test new loaders in development
2. Update YAML schemas if needed
3. Deploy to UAT for validation
4. Production deployment with rollback plan

## Support

For issues or questions:
1. Check logs: `kubectl logs job/fineract-data-<loader> -n fineract-dev`
2. Review this guide
3. Check loader README: `scripts/loaders/README.md`
4. Open an issue in the repository

## Summary

The Fineract data loader provides:
- **Automated** data initialization
- **GitOps** configuration management
- **Dependency** handling
- **Idempotent** operations
- **Environment** separation
- **Audit** trail

With proper configuration and monitoring, it ensures consistent, reliable Fineract deployments across all environments.