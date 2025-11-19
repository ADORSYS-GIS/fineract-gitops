# LoadBalancer DNS Management

## Overview

This document describes the centralized approach for managing LoadBalancer DNS configuration across environments.

## Problem Statement

When deploying Fineract to AWS EKS, the Nginx Ingress Controller creates an AWS Elastic Load Balancer (ELB) with a dynamically assigned DNS name. This DNS name:

1. **Changes** when the cluster is recreated
2. **Differs** between environments (dev, uat, production)
3. **Was previously hardcoded** in multiple files, causing maintenance issues

**Previous approach (problematic)**:
```
apps/ingress/overlays/dev/kustomization.yaml           ← Hardcoded
apps/keycloak/overlays/dev/kustomization.yaml          ← Hardcoded
operations/keycloak-config/overlays/dev/kustomization.yaml ← Hardcoded
environments/dev/fineract-oauth2-config-patch.yaml     ← Hardcoded
```

When the LoadBalancer DNS changed, all 4 files needed manual updates, leading to:
- Errors and inconsistencies
- Deployment failures
- Time-consuming manual updates

## Solution: Centralized Configuration

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AWS EKS Cluster                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │    Nginx Ingress LoadBalancer Service             │  │
│  │    DNS: ab98d58...elb.us-east-2.amazonaws.com     │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓
          scripts/update-loadbalancer-dns.sh
        (Extracts DNS from cluster automatically)
                         ↓
┌─────────────────────────────────────────────────────────┐
│   environments/{env}/loadbalancer-config.yaml           │
│   ┌───────────────────────────────────────────────┐     │
│   │  LOADBALANCER_DNS: "ab98d58...amazonaws.com"  │     │
│   │  APPS_HOSTNAME: "ab98d58...amazonaws.com"     │     │
│   │  AUTH_HOSTNAME: "ab98d58...amazonaws.com"     │     │
│   └───────────────────────────────────────────────┘     │
│             SINGLE SOURCE OF TRUTH                      │
└─────────────────────────────────────────────────────────┘
                         ↓
    ┌────────────────┬────────────────┬────────────────┐
    ↓                ↓                ↓                ↓
 Ingress        Keycloak      Keycloak Config    Fineract
 Config         Config        Job Vars           OAuth2
```

### Components

#### 1. Centralized Configuration File

**Location**: `environments/{env}/loadbalancer-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: loadbalancer-config
  namespace: fineract-{env}
data:
  LOADBALANCER_DNS: "a248fc3d904694d09b61c2bbdb848eb9-a61d9dde0b2567a1.elb.us-east-2.amazonaws.com"
  APPS_HOSTNAME: "a248fc3d904694d09b61c2bbdb848eb9-a61d9dde0b2567a1.elb.us-east-2.amazonaws.com"
  AUTH_HOSTNAME: "a248fc3d904694d09b61c2bbdb848eb9-a61d9dde0b2567a1.elb.us-east-2.amazonaws.com"
```

**Purpose**:
- Single source of truth for LoadBalancer DNS
- Git-tracked for auditability
- Environment-specific (dev, uat, production)

#### 2. Automation Script

**Location**: `scripts/update-loadbalancer-dns.sh`

**Usage**:
```bash
# Update dev environment
./scripts/update-loadbalancer-dns.sh dev

# Update UAT environment
./scripts/update-loadbalancer-dns.sh uat

# Update production environment
./scripts/update-loadbalancer-dns.sh production
```

**What it does**:
1. Queries the Nginx Ingress LoadBalancer service
2. Extracts the LoadBalancer DNS/hostname
3. Updates `environments/{env}/loadbalancer-config.yaml`
4. Creates a backup of the previous configuration
5. Shows a diff of changes

**When to run**:
- After initial cluster deployment
- After cluster recreation
- When LoadBalancer DNS changes

## Usage Guide

### For New Deployments

1. **Deploy infrastructure** (EKS, RDS, S3):
   ```bash
   make deploy-infrastructure-dev
   ```

2. **Wait for Nginx Ingress Controller** to create LoadBalancer (1-2 minutes)

3. **Update LoadBalancer DNS** configuration:
   ```bash
   ./scripts/update-loadbalancer-dns.sh dev
   ```

4. **Review and commit** the changes:
   ```bash
   git add environments/dev/loadbalancer-config.yaml
   git commit -m "chore: update LoadBalancer DNS for dev environment"
   git push origin eks
   ```

5. **Deploy ArgoCD apps** (they will use the new DNS):
   ```bash
   # ArgoCD auto-syncs from Git, or manually trigger:
   kubectl apply -f argocd/applications/dev/
   ```

### After Cluster Recreation

If you destroy and recreate the cluster, the LoadBalancer DNS will change:

1. **Deploy infrastructure**:
   ```bash
   make deploy-infrastructure-dev
   ```

2. **Update LoadBalancer DNS** (automated):
   ```bash
   ./scripts/update-loadbalancer-dns.sh dev
   ```

3. **Commit and push**:
   ```bash
   git add environments/dev/loadbalancer-config.yaml
   git commit -m "chore: update LoadBalancer DNS after cluster recreation"
   git push origin eks
   ```

4. **ArgoCD syncs automatically** and applies the new configuration

### Migration to Production Domains

When moving to production with custom domains (e.g., `apps.fineract.com`, `auth.fineract.com`):

1. **Update** `environments/production/loadbalancer-config.yaml`:
   ```yaml
   data:
     LOADBALANCER_DNS: "ab98d58...amazonaws.com"  # Keep for reference
     APPS_HOSTNAME: "apps.fineract.com"           # Custom domain
     AUTH_HOSTNAME: "auth.fineract.com"           # Custom domain
   ```

2. **Configure DNS records**:
   ```
   apps.fineract.com  →  CNAME  →  ab98d58...elb.amazonaws.com
   auth.fineract.com  →  CNAME  →  ab98d58...elb.amazonaws.com
   ```

3. **Update certificates** to use real domains instead of self-signed

## Current State (Transition Period)

**Status**: ✅ Centralized config created, automation script ready

**Current approach**:
- LoadBalancer DNS is still hardcoded in the 4 kustomization files (commit 3ff8e26)
- Centralized `loadbalancer-config.yaml` file created
- Automation script `update-loadbalancer-dns.sh` ready to use

**Next steps** (future enhancement):
- Migrate kustomization files to reference centralized config using Kustomize replacements
- Remove hardcoded DNS values from all files
- Update deployment documentation

## Benefits

### Before (Hardcoded Approach)
- ❌ Manual updates required in 4 files
- ❌ Error-prone (easy to miss a file)
- ❌ Breaks after cluster recreation
- ❌ No single source of truth

### After (Centralized Approach)
- ✅ Single command to update: `./scripts/update-loadbalancer-dns.sh dev`
- ✅ Automatic extraction from cluster
- ✅ Git-tracked for auditability
- ✅ Easy migration to custom domains
- ✅ Survives cluster recreation

## Troubleshooting

### Script fails to get LoadBalancer DNS

**Problem**: `Failed to retrieve LoadBalancer DNS`

**Solutions**:
1. Check Nginx Ingress Controller is deployed:
   ```bash
   kubectl get pods -n ingress-nginx
   ```

2. Check LoadBalancer service exists:
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller
   ```

3. Wait for LoadBalancer provisioning (can take 1-2 minutes):
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller -w
   ```

### Changes not applied after commit

**Problem**: Updated config but apps still use old DNS

**Solutions**:
1. Verify ArgoCD has synced:
   ```bash
   kubectl get applications -n argocd
   ```

2. Manually trigger sync:
   ```bash
   kubectl patch app fineract-dev-ingress -n argocd -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "normal"}}}' --type merge
   ```

3. Check pod logs for configuration:
   ```bash
   kubectl logs -n fineract-dev -l app=keycloak
   ```

## See Also

- [Deployment Guide](DEPLOYMENT.md) - Complete deployment process
- [Secrets Management](SECRETS_MANAGEMENT.md) - Managing sensitive configuration
- [ArgoCD Workflows](../argocd/README.md) - GitOps deployment patterns
