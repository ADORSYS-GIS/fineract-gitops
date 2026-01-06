# Automated Load Balancer DNS Management

**Last Updated:** 2025-01-06

## Overview

This document describes the **automated Load Balancer DNS management system** that enables **truly automatic deployments** without manual intervention for Load Balancer DNS updates.

### Problem Solved

Previously, when a Kubernetes cluster was deployed with a new Load Balancer:
- Load Balancer DNS was hardcoded in multiple configuration files
- Manual updates were required across 7+ different files
- OAuth2 Proxy configuration would break until manually updated
- ArgoCD syncs would fail due to DNS mismatches
- **Deployment was NOT truly automatic**

### Solution Implemented

**Centralized, automated Load Balancer DNS management** with:
- Single source of truth for all Load Balancer DNS references
- Automatic detection and update of Load Balancer DNS
- Consistent updates across all configuration files
- Automatic Git commits and pushes
- ArgoCD auto-triggered syncs
- Comprehensive health checks

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│            Load Balancer DNS Management System           │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ Centralized   │   │ Automated    │   │ GitHub      │
│ ConfigMap    │   │ Update Script│   │ Actions WF   │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Configuration Files (ALL Auto-Updated)                  │
├─────────────────────────────────────────────────────────────┤
│ • config/loadbalancer-dns-configmap.yaml               │
│ • environments/<env>/loadbalancer-config.yaml             │
│ • environments/<env>/fineract-oauth2-config-patch.yaml   │
│ • apps/ingress/overlays/<env>/ingress-config.yaml       │
│ • apps/oauth2-proxy/overlays/<env>/kustomization.yaml   │
│ • apps/keycloak/overlays/<env>/kustomization.yaml       │
│ • operations/keycloak-config/overlays/<env>/kustomization.yaml │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │ ArgoCD Sync │
                    └──────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Verified Deployment (All Services Healthy)                │
└─────────────────────────────────────────────────────────────┘
```

### Automation Flow

```
1. Terraform Apply
       ↓
2. Kubernetes Cluster Ready
       ↓
3. Ingress Controller Deployed
       ↓
4. AWS Assigns Load Balancer DNS (e.g., a123b.elb.amazonaws.com)
       ↓
5. ⚡ auto-update-lb-dns.sh ⚡
       ↓
6. Updates ALL configuration files with new DNS
       ↓
7. Git commit & push
       ↓
8. ArgoCD detects changes
       ↓
9. ArgoCD auto-syncs applications
       ↓
10. Health checks verify deployment
       ↓
11. Deployment Complete ✅
```

---

## Usage

### Quick Start (One-Command Deployment)

```bash
# Complete automated deployment with LB DNS management
./scripts/wait-for-lb-and-sync.sh dev
```

**This one command:**
1. Waits for Load Balancer DNS assignment
2. Updates all 7 configuration files
3. Commits and pushes to Git
4. Monitors ArgoCD sync
5. Runs health checks
6. Validates endpoints
7. Reports deployment status

**Duration:** ~15-20 minutes (fully automated, no manual intervention)

---

### Individual Components

#### 1. Centralized ConfigMap

**File:** `config/loadbalancer-dns-configmap.yaml`

**Purpose:** Single source of truth for all Load Balancer DNS references.

**Usage:** Applied to cluster, referenced by other components.

```bash
# Apply central ConfigMap
kubectl apply -f config/loadbalancer-dns-configmap.yaml

# View current Load Balancer DNS
kubectl get cm -n kube-system loadbalancer-dns -o yaml
```

---

#### 2. Automated Update Script

**Script:** `scripts/auto-update-lb-dns.sh`

**Purpose:** Automatically updates ALL configuration files with new Load Balancer DNS.

**Usage:**

```bash
# Update and display changes (no commit/push)
./scripts/auto-update-lb-dns.sh dev

# Update, commit, and push
./scripts/auto-update-lb-dns.sh dev --commit --push

# Update using existing DNS (skip waiting)
./scripts/auto-update-lb-dns.sh production --skip-wait
```

**Files Updated:**
1. `config/loadbalancer-dns-configmap.yaml`
2. `environments/<env>/loadbalancer-config.yaml`
3. `environments/<env>/fineract-oauth2-config-patch.yaml`
4. `apps/ingress/overlays/<env>/ingress-config.yaml`
5. `apps/oauth2-proxy/overlays/<env>/kustomization.yaml`
6. `apps/keycloak/overlays/<env>/kustomization.yaml`
7. `operations/keycloak-config/overlays/<env>/kustomization.yaml`

**Features:**
- ✅ Waits for Load Balancer DNS assignment
- ✅ Updates ALL files consistently
- ✅ Validates consistency across files
- ✅ Creates backups before updating
- ✅ Optionally commits and pushes to Git
- ✅ Cleans up old backups
- ✅ Color-coded logging for easy troubleshooting

---

#### 3. Wait-and-Sync Script

**Script:** `scripts/wait-for-lb-and-sync.sh`

**Purpose:** Complete automated deployment orchestration from Load Balancer assignment to verified health.

**Usage:**

```bash
# Full automated deployment
./scripts/wait-for-lb-and-sync.sh dev
```

**Steps:**
1. ✅ Wait for Ingress Controller to be ready
2. ✅ Wait for Load Balancer DNS assignment
3. ✅ Update all configuration files
4. ✅ Commit and push to Git
5. ✅ Monitor ArgoCD sync completion
6. ✅ Run health checks on all components
7. ✅ Validate application endpoints

**Duration:** ~15-20 minutes

---

#### 4. GitHub Actions Workflow

**File:** `.github/workflows/auto-update-lb-dns.yml`

**Purpose:** CI/CD automation for Load Balancer DNS updates.

**Triggers:**

```yaml
# Manual trigger (with options)
workflow_dispatch:
  - environment (dev/uat/production)
  - commit_and_push (true/false)

# Scheduled (every 6 hours)
schedule:
  - cron: '0 */6 * * *'

# Can also trigger via repository_dispatch
```

**Usage:**

```bash
# Manual trigger via GitHub UI
1. Go to: Actions → "Auto-Update Load Balancer DNS"
2. Click "Run workflow"
3. Select environment: dev/uat/production
4. Enable "Commit and push changes"
5. Click "Run workflow"
```

**Automatic:**
- Runs every 6 hours automatically
- Checks for new Load Balancer DNS
- Updates configuration files
- Commits and pushes if changes detected

---

## Integration with Deployment Flows

### Option 1: Terraform → Post-Terraform Setup → Deploy

```bash
# Step 1: Apply Terraform
cd terraform/aws
terraform apply -var-file=environments/dev.tfvars

# Step 2: Run post-terraform setup (includes LB DNS update)
./scripts/post-terraform-setup.sh dev
# This now uses centralized auto-update-lb-dns.sh!

# Step 3: Deploy applications
kubectl apply -k environments/dev

# Step 4: Wait for sync and health checks
./scripts/wait-for-lb-and-sync.sh dev
```

### Option 2: One-Command Full Deployment (RECOMMENDED)

```bash
# Single command for complete automated deployment
./scripts/wait-for-lb-and-sync.sh dev
```

**This replaces ALL of the above steps with ONE command!**

### Option 3: CI/CD Automated

```yaml
# In .github/workflows/deploy.yml
- name: Update Load Balancer DNS
  run: ./scripts/auto-update-lb-dns.sh dev --commit --push

- name: Wait for ArgoCD Sync
  run: ./scripts/wait-for-argocd-sync.sh dev

- name: Health Checks
  run: ./scripts/deployment-health-check.sh dev
```

---

## Troubleshooting

### Load Balancer DNS Not Found

**Error:**
```
❌ Failed to retrieve LoadBalancer DNS
```

**Causes:**
1. Ingress Controller not deployed
2. Load Balancer not provisioned
3. Network/Security Group issues

**Solutions:**

```bash
# Check if ingress-nginx is deployed
kubectl get deployment -n ingress-nginx ingress-nginx-controller

# Check Load Balancer service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Check events
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'
```

---

### Files Not Updated

**Error:**
```
❌ Failed to update Load Balancer DNS using centralized script
```

**Causes:**
1. Wrong environment name
2. Permission issues
3. Script not executable

**Solutions:**

```bash
# Check script permissions
ls -l scripts/auto-update-lb-dns.sh
# Should be: -rwxr-xr-x (executable)

# Make executable
chmod +x scripts/auto-update-lb-dns.sh

# Test with verbose output
./scripts/auto-update-lb-dns.sh dev 2>&1 | tee lb-update.log
```

---

### ArgoCD Not Syncing

**Error:**
```
⚠ ArgoCD sync not complete within timeout
```

**Causes:**
1. Git changes not pushed
2. ArgoCD repository webhook issue
3. Application configuration errors

**Solutions:**

```bash
# Check if changes are pushed
git log origin/main..HEAD

# Check ArgoCD applications
kubectl get applications -n argocd

# Manually sync stuck apps
kubectl patch application myapp -n argocd --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
```

---

### Health Checks Failing

**Error:**
```
⚠ Some health checks failed, but deployment may still be functional
```

**Causes:**
1. Pods not ready
2. DNS propagation delay
3. Configuration errors

**Solutions:**

```bash
# Check pod status
kubectl get pods -n fineract-dev

# Describe failing pod
kubectl describe pod <pod-name> -n fineract-dev

# Check logs
kubectl logs <pod-name> -n fineract-dev -f

# Restart deployment
kubectl rollout restart deployment/<deployment-name> -n fineract-dev
```

---

### DNS Propagation Issues

**Error:**
```
⚠ LoadBalancer endpoint not accessible (timed out or DNS not propagated)
```

**Causes:**
1. AWS DNS propagation delay
2. Local DNS cache
3. Network/firewall issues

**Solutions:**

```bash
# Check if LoadBalancer DNS resolves
dig +short a07aeb697903842c88211f203f81bd30-ba97476a7e017252.elb.eu-central-1.amazonaws.com

# Test directly (bypass DNS)
curl -k https://$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Wait for DNS propagation (can take up to 60 seconds)
watch -n 5 "dig +short $(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

---

## Best Practices

### 1. Always Use Centralized Script

**❌ Don't:**
```bash
# Manual updates (error-prone)
sed -i.bak "s|old-dns|new-dns|" apps/ingress/overlays/dev/kustomization.yaml
sed -i.bak "s|old-dns|new-dns|" apps/oauth2-proxy/overlays/dev/kustomization.yaml
# ... 5 more files to update manually
```

**✅ Do:**
```bash
# Automated updates (consistent)
./scripts/auto-update-lb-dns.sh dev --commit --push
```

---

### 2. Use One-Command Deployment

**❌ Don't:**
```bash
# Multiple manual steps
terraform apply
./scripts/post-terraform-setup.sh dev
kubectl apply -k environments/dev
kubectl wait for deployment/ingress-nginx-controller
kubectl get svc ingress-nginx-controller
# Update 7 files manually
git add ...
git commit ...
git push ...
# Monitor ArgoCD manually
# Run health checks manually
```

**✅ Do:**
```bash
# One automated command
./scripts/wait-for-lb-and-sync.sh dev
```

---

### 3. Enable GitHub Actions for Auto-Updates

**❌ Don't:**
```bash
# Manual DNS updates every time Load Balancer changes
./scripts/auto-update-lb-dns.sh dev --commit --push
```

**✅ Do:**
```yaml
# GitHub Actions handles it automatically
# Configure scheduled runs in .github/workflows/auto-update-lb-dns.yml
schedule:
  - cron: '0 */6 * * *'  # Every 6 hours
```

---

### 4. Use Environment-Specific Configurations

**❌ Don't:**
```bash
# Using same DNS for all environments
lb-dns: "a07aeb.elb.amazonaws.com"  # Same for dev, uat, production
```

**✅ Do:**
```bash
# Separate DNS per environment
./scripts/auto-update-lb-dns.sh dev      # Updates dev config
./scripts/auto-update-lb-dns.sh uat      # Updates UAT config
./scripts/auto-update-lb-dns.sh production  # Updates production config
```

---

### 5. Backup Before Updates

The scripts automatically create backups, but keep them safe:

```bash
# Backups are created automatically
environments/dev/loadbalancer-config.yaml.backup.20250106_120000
apps/ingress/overlays/dev/ingress-config.yaml.backup.20250106_120000
# ... etc

# Cleanup old backups automatically (keeps last 5)
# No manual cleanup required!
```

---

## File Changes Summary

### Files Created

1. `config/loadbalancer-dns-configmap.yaml` - Central ConfigMap
2. `scripts/auto-update-lb-dns.sh` - Automated update script
3. `scripts/wait-for-lb-and-sync.sh` - Complete deployment script
4. `.github/workflows/auto-update-lb-dns.yml` - CI/CD workflow

### Files Updated

1. `scripts/post-terraform-setup.sh` - Now uses centralized script

### Files Managed (Auto-Updated)

1. `config/loadbalancer-dns-configmap.yaml`
2. `environments/<env>/loadbalancer-config.yaml`
3. `environments/<env>/fineract-oauth2-config-patch.yaml`
4. `apps/ingress/overlays/<env>/ingress-config.yaml`
5. `apps/oauth2-proxy/overlays/<env>/kustomization.yaml`
6. `apps/keycloak/overlays/<env>/kustomization.yaml`
7. `operations/keycloak-config/overlays/<env>/kustomization.yaml`

---

## Migration Guide

### From Manual to Automated

**Before (Manual):**
```bash
# 1. Deploy Terraform
terraform apply

# 2. Get Load Balancer DNS manually
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Copy: a07aeb697903842c88211f203f81bd30-ba97476a7e017252.elb.eu-central-1.amazonaws.com

# 3. Update 7 files manually (error-prone!)
nano environments/dev/loadbalancer-config.yaml
nano apps/ingress/overlays/dev/ingress-config.yaml
nano apps/oauth2-proxy/overlays/dev/kustomization.yaml
# ... 4 more files

# 4. Commit and push manually
git add ...
git commit -m "Update Load Balancer DNS"
git push

# 5. Monitor ArgoCD manually
kubectl get applications -n argocd

# 6. Run health checks manually
kubectl get pods -n fineract-dev
```

**After (Automated):**
```bash
# One command does EVERYTHING
./scripts/wait-for-lb-and-sync.sh dev
```

---

## Comparison: Manual vs Automated

| Step | Manual | Automated |
|------|---------|------------|
| Wait for Load Balancer | Manual `kubectl wait` | Auto |
| Extract Load Balancer DNS | Manual copy-paste | Auto |
| Update config files | Manual (7 files) | Auto |
| Validate consistency | Manual review | Auto |
| Commit to Git | Manual | Auto (optional) |
| Push to Git | Manual | Auto (optional) |
| Monitor ArgoCD sync | Manual | Auto |
| Health checks | Manual | Auto |
| **Total Time** | ~30-60 min | **~15-20 min** |
| **Human Error Risk** | **High** | **None** |
| **True Automation** | ❌ No | ✅ **Yes** |

---

## FAQs

### Q: Can I still update Load Balancer DNS manually?

**A:** Yes, but it's not recommended. The automated script ensures all files are updated consistently. If you must update manually:

```bash
# Update all 7 files manually
# (Not recommended - see script for list)
```

### Q: What if the Load Balancer DNS changes?

**A:** Re-run the automated update script:

```bash
# Update with new Load Balancer DNS
./scripts/auto-update-lb-dns.sh dev --commit --push

# Or use one-command deployment (includes LB DNS update)
./scripts/wait-for-lb-and-sync.sh dev
```

### Q: How do I disable automatic commits?

**A:** Omit the `--commit` and `--push` flags:

```bash
# Update files only (no commit/push)
./scripts/auto-update-lb-dns.sh dev

# Review changes
git diff

# Commit manually if desired
git add -A && git commit -m "Update Load Balancer DNS" && git push
```

### Q: Can I use this with ArgoCD ApplicationSets?

**A:** Yes! The Load Balancer DNS updates work with any GitOps tool. ArgoCD will automatically sync the updated configuration files.

### Q: What about OAuth2 Proxy configuration?

**A:** OAuth2 Proxy configuration is automatically updated via the `apps/oauth2-proxy/overlays/<env>/kustomization.yaml` file. The script updates the `ingress-config` ConfigMap used by OAuth2 Proxy.

### Q: How do I test the automation?

**A:** Use the `--skip-wait` flag to test without waiting for Load Balancer:

```bash
# Test using existing Load Balancer DNS (no waiting)
./scripts/auto-update-lb-dns.sh dev --skip-wait --commit --push
```

---

## Additional Resources

- **Main Documentation:** [README.md](../README.md)
- **Deployment Guide:** [DEPLOYMENT.md](../DEPLOYMENT.md)
- **Secrets Management:** [SECRETS_MANAGEMENT.md](../docs/SECRETS_MANAGEMENT.md)
- **Operations Guide:** [OPERATIONS_GUIDE.md](../docs/OPERATIONS_GUIDE.md)

---

## Support

For issues or questions:
1. Check this documentation
2. Review troubleshooting section
3. Check script logs (`./scripts/auto-update-lb-dns.sh dev 2>&1 | tee lb-update.log`)
4. Open GitHub issue with logs

---

**Last Updated:** 2025-01-06
**Version:** 1.0.0
**Status:** ✅ Production Ready
