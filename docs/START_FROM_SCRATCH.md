# Start from Scratch - Clean Deployment Guide

**Date:** 2025-01-06
**Purpose:** Destroy all infrastructure and redeploy from scratch

---

## 🚨 WARNING

**This will DELETE ALL resources and data:**
- All AWS infrastructure (EKS, RDS, S3, VPC, etc.)
- All Kubernetes resources (namespaces, deployments, pods, etc.)
- All database data (IRREVERSIBLE!)
- All S3 bucket data (IRREVERSIBLE!)
- All Terraform state

**This operation is IRREVERSIBLE!**

---

## 🎯 Why Start from Scratch?

### Use Cases:
1. **Testing Fixes** - Verify our automation fixes work
2. **Clean Environment** - Remove accumulated technical debt
3. **Cost Management** - Stop unused resources
4. **Disaster Recovery** - Rebuild from known good state
5. **Learning** - Understand the full deployment process

### Benefits:
- ✅ Clean slate, no conflicts
- ✅ Test all automation scripts
- ✅ Verify Load Balancer DNS automation
- ✅ Validate OAuth2 Proxy fixes
- ✅ Confirm one-command deployment works

---

## 🚀 Quick Start

### Option 1: Automated Script (RECOMMENDED)

```bash
# Destroy everything and prepare for redeployment
./scripts/start-from-scratch.sh dev
```

**This script:**
1. Shows what will be destroyed
2. Asks for confirmation
3. Destroys all Terraform resources
4. Cleans up Kubernetes resources
5. Resets Load Balancer DNS configs
6. Provides redeployment steps

---

## 📋 Before Starting

### 1. Backup Critical Data

```bash
# Backup RDS databases (if important)
cd terraform/aws
RDS_ENDPOINT=$(terraform output -raw rds_instance_endpoint 2>/dev/null || echo "")
if [ -n "$RDS_ENDPOINT" ]; then
    echo "Backing up RDS databases..."
    pg_dump -h "$RDS_ENDPOINT" -U fineract -d fineract > fineract-backup-$(date +%Y%m%d).sql
    pg_dump -h "$RDS_ENDPOINT" -U keycloak -d keycloak > keycloak-backup-$(date +%Y%m%d).sql
fi
```

```bash
# Backup S3 data (if important)
aws s3 sync s3://apache-fineract-dev-docs-xxxxx ./s3-backup-documents/
aws s3 sync s3://apache-fineract-dev-backups-xxxxx ./s3-backup-backups/
```

### 2. Export Secrets

```bash
# Export important secrets for reference
aws secretsmanager get-secret-value \
    --secret-id fineract-dev-fineract-dev-db-credentials \
    --query SecretString --output text > secrets-backup.json
```

### 3. Document Current State

```bash
# Record current Load Balancer DNS
kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' > lb-dns-backup.txt

# Record application versions
kubectl get deployments -n fineract-dev -o jsonpath='{.items[*].spec.template.spec.containers[*].image}' > app-versions-backup.txt
```

---

## 🏗️ Destruction Process

### Step 1: Run Start from Scratch Script

```bash
./scripts/start-from-scratch.sh dev
```

**What happens:**
1. ✅ Checks existing resources (EKS, RDS, S3, etc.)
2. ✅ Shows destruction plan (what will be deleted)
3. ✅ Asks for confirmation (`DESTROY dev`)
4. ✅ Runs Terraform destroy
5. ✅ Cleans up Kubernetes namespace
6. ✅ Resets Load Balancer DNS configs to `PENDING_UPDATE`
7. ✅ Provides redeployment steps

**Duration:** ~10-15 minutes

---

### Step 2: Verify Destruction

```bash
# Check Terraform state (should be empty or not exist)
cd terraform/aws
terraform show
# Should return nothing or error

# Check AWS resources
aws eks describe-cluster --name apache-fineract-dev
# Should return error: ResourceNotFoundException

aws s3 ls | grep fineract-dev
# Should return nothing

aws rds describe-db-instances
# Should show no fineract instances

# Check Kubernetes
kubectl get ns fineract-dev
# Should return error: namespace not found
```

---

## 🔄 Redeployment Process

### Option 1: Fully Automated (RECOMMENDED)

```bash
# One-command complete deployment
./scripts/wait-for-lb-and-sync.sh dev
```

**This does EVERYTHING:**
1. ✅ Applies Terraform infrastructure
2. ✅ Waits for Load Balancer DNS
3. ✅ Updates ALL configuration files
4. ✅ Commits and pushes to Git
5. ✅ Monitors ArgoCD sync
6. ✅ Runs health checks
7. ✅ Validates endpoints

**Duration:** ~15-20 minutes (fully automated)

---

### Option 2: Manual Step-by-Step

```bash
# 1. Deploy Infrastructure
cd terraform/aws
terraform init
terraform apply -var-file=environments/dev-eks.tfvars

# 2. Run Post-Terraform Setup
cd ../..
./scripts/post-terraform-setup.sh dev

# 3. Deploy Applications
kubectl apply -k environments/dev

# 4. Monitor ArgoCD
kubectl get applications -n argocd -w

# 5. Health Checks
kubectl get pods -n fineract-dev
```

**Duration:** ~30-40 minutes (manual steps)

---

## ✅ What Gets Fixed

### 1. Load Balancer DNS Automation

**Before:**
- Load Balancer DNS hardcoded in 7+ files
- Manual updates required when DNS changes
- OAuth2 Proxy misconfiguration in UAT/Production

**After:**
- ✅ Single source of truth (`config/loadbalancer-dns-configmap.yaml`)
- ✅ Automatic detection and update
- ✅ All environments work correctly
- ✅ Zero manual intervention

### 2. OAuth2 Proxy Configuration

**Before:**
- UAT/Production missing ConfigMap (deployment FAILS)
- OIDC issuer URL missing `/auth` path
- Hardcoded domain names

**After:**
- ✅ All environments have ConfigMap
- ✅ Correct OIDC issuer URL path
- ✅ Dynamic Load Balancer DNS usage
- ✅ No deployment failures

### 3. One-Command Deployment

**Before:**
- Multiple manual steps
- Manual Git commits
- Manual health checks
- 30-60 minutes, human error prone

**After:**
- ✅ Single command: `./scripts/wait-for-lb-and-sync.sh dev`
- ✅ Automatic Git commits
- ✅ Automatic health checks
- ✅ 15-20 minutes, error-free

---

## 📊 Environment Comparison

| Environment | Cleanup Time | Redeploy Time | Total | Auto-Deploy? |
|-------------|---------------|----------------|--------|--------------|
| Dev | ~10 min | ~15 min | ~25 min | ✅ YES |
| UAT | ~10 min | ~20 min | ~30 min | ✅ YES |
| Production | ~15 min | ~25 min | ~40 min | ✅ YES |

---

## 🔍 Verification Steps

### 1. Verify Automation Fixes

```bash
# Check Load Balancer DNS is auto-updated
cat config/loadbalancer-dns-configmap.yaml | grep lb-dns
# Should show: lb-dns: "<actual-elb-dns>"

# Check OAuth2 Proxy has ConfigMap (all environments)
for env in dev uat production; do
  echo "=== $env ==="
  grep -A 2 "oauth2-proxy-config-static" apps/oauth2-proxy/overlays/$env/kustomization.yaml
done

# Check OIDC issuer URL path is correct
grep "OIDC_ISSUER_URL" apps/oauth2-proxy/overlays/{dev,uat,production}/kustomization.yaml
# Should all show: http://keycloak-service:8080/auth/realms/${REALM_NAME}
#                                                         ^^^^ Has /auth path!
```

### 2. Verify Deployment Works

```bash
# Check all pods are running
kubectl get pods -n fineract-dev

# Expected output:
NAME                              READY   STATUS    RESTARTS   AGE
fineract-read-xxx                 1/1     Running   0          5m
fineract-write-xxx                1/1     Running   0          5m
fineract-batch-xxx                1/1     Running   0          5m
fineract-redis-0                  1/1     Running   0          8m
keycloak-xxx                      1/1     Running   0          8m
oauth2-proxy-xxx                  1/1     Running   0          5m
```

### 3. Verify Load Balancer DNS

```bash
# Check Load Balancer DNS is assigned
kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check configuration files have correct DNS
cat apps/ingress/overlays/dev/ingress-config.yaml | grep apps-hostname
# Should show actual Load Balancer DNS (not PENDING_UPDATE)
```

### 4. Verify ArgoCD Sync

```bash
# Check all applications are synced
kubectl get applications -n argocd

# Expected output:
NAME                    SYNC     HEALTH
database-init          Synced   Healthy
fineract-redis         Synced   Healthy
keycloak               Synced   Healthy
fineract-write         Synced   Healthy
fineract-read          Synced   Healthy
fineract-batch         Synced   Healthy
oauth2-proxy           Synced   Healthy
web-app                Synced   Healthy
```

---

## 🐛 Troubleshooting

### Issue 1: Start Script Fails

**Problem:**
```
Error: Terraform not initialized, nothing to destroy
```

**Solution:**
```bash
# Initialize Terraform first
cd terraform/aws
terraform init

# Then rerun
cd ../..
./scripts/start-from-scratch.sh dev
```

---

### Issue 2: Namespace Stuck in Terminating

**Problem:**
```
Error from server (Conflict): namespace "fineract-dev" is being terminated
```

**Solution:**
```bash
# Force delete namespace
kubectl get namespace fineract-dev -o yaml | \
  kubectl replace --raw -

# Or use make cleanup-cluster
make cleanup-cluster
```

---

### Issue 3: Load Balancer DNS Not Updating

**Problem:**
Configuration files still show `PENDING_UPDATE` after deployment.

**Solution:**
```bash
# Run auto-update script manually
./scripts/auto-update-lb-dns.sh dev --commit --push

# Or use wait-for-lb-and-sync.sh
./scripts/wait-for-lb-and-sync.sh dev
```

---

### Issue 4: Terraform Destroy Stuck

**Problem:**
```
Error: Timeout waiting for resource deletion
```

**Solution:**
```bash
# Check what's holding up deletion
aws ec2 describe-instances --filters "Name=tag:Name,Values=fineract*"

# Manually terminate instances
aws ec2 terminate-instances --instance-ids i-xxxxxxxx

# Retry destroy
cd terraform/aws
terraform destroy -var-file=environments/dev-eks.tfvars
```

---

### Issue 5: S3 Bucket Not Empty

**Problem:**
```
Error: deleting S3 Bucket: BucketNotEmpty
```

**Solution:**
```bash
# Empty S3 bucket manually
aws s3 rm s3://apache-fineract-dev-docs-xxxxx --recursive
aws s3 rm s3://apache-fineract-dev-backups-xxxxx --recursive

# Retry destroy
cd terraform/aws
terraform destroy -var-file=environments/dev-eks.tfvars
```

---

## 📝 Post-Deployment Checklist

After redeployment, verify:

### Infrastructure
- [ ] EKS cluster created
- [ ] RDS instances accessible
- [ ] S3 buckets created
- [ ] Load Balancer DNS assigned
- [ ] VPC and networking correct

### Kubernetes
- [ ] Namespace `fineract-dev` created
- [ ] All pods running (READY=1/1)
- [ ] All services accessible
- [ ] Ingress configured

### Applications
- [ ] Keycloak accessible
- [ ] OAuth2 Proxy accessible
- [ ] Fineract API accessible
- [ ] Frontend applications accessible
- [ ] All ArgoCD applications synced

### Automation
- [ ] Load Balancer DNS auto-updated
- [ ] Configuration files updated
- [ ] Git commit created (if enabled)
- [ ] Health checks passed
- [ ] Endpoints validated

---

## 💰 Cost Analysis

### Monthly Savings by Destroying

| Environment | Current Monthly | After Destroy | Savings |
|-------------|----------------|---------------|----------|
| Dev | ~$110 | $0 | **~$110** |
| UAT | ~$300 | $0 | **~$300** |
| Production | ~$700 | $0 | **~$700** |

### Annual Savings

| Environment | Annual Savings |
|-------------|---------------|
| Dev | **~$1,320** |
| UAT | **~$3,600** |
| Production | **~$8,400** |

**Total (all 3 environments): ~$13,320/year**

---

## 🎯 Success Criteria

Your redeployment is successful if:

1. ✅ All Terraform resources destroyed
2. ✅ No orphaned AWS resources
3. ✅ Kubernetes namespace deleted
4. ✅ Load Balancer DNS configs reset
5. ✅ Infrastructure redeployed
6. ✅ Load Balancer DNS auto-updated
7. ✅ All pods running
8. ✅ ArgoCD applications synced
9. ✅ All endpoints accessible
10. ✅ One-command deployment works

---

## 📖 Related Documentation

- [Automated Load Balancer DNS Management](AUTOMATED_LB_DNS_MANAGEMENT.md) - Complete automation guide
- [Critical Deployment Blockers](CRITICAL_DEPLOYMENT_BLOCKERS.md) - Issues found and fixed
- [Terraform Destroy Guide](../terraform/aws/DESTROY_GUIDE.md) - Detailed destruction guide
- [Deployment Guide](../DEPLOYMENT.md) - Full deployment documentation
- [Secrets Management](../docs/SECRETS_MANAGEMENT.md) - Sealed Secrets guide

---

## 🔗 Quick Links

### Start from Scratch Script
```bash
./scripts/start-from-scratch.sh dev
```

### Redeploy (Full Automation)
```bash
./scripts/wait-for-lb-and-sync.sh dev
```

### Verify Health
```bash
kubectl get pods -n fineract-dev
kubectl get applications -n argocd
```

### Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

**Last Updated:** 2025-01-06
**Status:** ✅ Ready for Clean Redeployment

---

## 🚀 Ready to Start Fresh?

Run this command to destroy everything and redeploy from scratch:

```bash
./scripts/start-from-scratch.sh dev
```

This will:
1. ✅ Show you what will be destroyed
2. ✅ Ask for your confirmation
3. ✅ Destroy all resources
4. ✅ Clean up Kubernetes
5. ✅ Reset configs
6. ✅ Guide you through redeployment

**Warning: This is IRREVERSIBLE! Make sure you have backups if needed!**
