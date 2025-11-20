# Fineract GitOps Deployment Guide

This guide covers deploying the complete Fineract platform to Kubernetes using GitOps principles with ArgoCD.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Interactive Full Deployment](#interactive-full-deployment)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Deployment Steps Explained](#deployment-steps-explained)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Post-Deployment](#post-deployment)

---

## Prerequisites

### Required Tools

Ensure the following tools are installed:

> 📋 **Version Requirements:** See [docs/VERSION_MATRIX.md](docs/VERSION_MATRIX.md) for detailed version compatibility.
> 📖 **Installation Guide:** Complete setup instructions at [docs/PREREQUISITES.md](docs/PREREQUISITES.md)

**Required Tools:**
- **kubectl** (1.28+) - Kubernetes CLI
- **kustomize** (5.0+) - Configuration management
- **kubeseal** (0.27.0) - Sealed Secrets CLI
- **aws CLI** (2.0+) (if using EKS) - AWS authentication
- **terraform** (1.5+) - Infrastructure provisioning
- **jq** (optional) - JSON processing
- **git** (2.30+) - Version control

```bash
# Install on macOS
brew install kubectl kustomize kubeseal awscli terraform jq

# Verify installations (see docs/VERSION_MATRIX.md for required versions)
kubectl version --client
kustomize version
kubeseal --version  # Should be 0.27.0
aws --version
terraform version
```

### Environment Setup

1. **Kubernetes Cluster Access**:
   ```bash
   # For EKS (AWS)
   aws eks update-kubeconfig --region us-west-2 --name fineract-dev-eks

   # Set KUBECONFIG environment variable
   export KUBECONFIG=~/.kube/config-fineract-dev

   # Verify access
   kubectl cluster-info
   ```

2. **GitHub Personal Access Token**:
   ```bash
   # Create token at: https://github.com/settings/tokens
   # Required scopes: repo (all)

   export GITHUB_TOKEN="ghp_YourPersonalAccessToken"
   ```

3. **Terraform State** (if infrastructure not yet deployed):
   ```bash
   # Ensure Terraform backend is configured
   cd terraform/aws
   ./scripts/setup-terraform-backend.sh
   ```

### Validation

Run the prerequisites validation:

```bash
make validate-prereqs
```

Expected output:
```
✓ All required prerequisites validated
```

---

## Quick Start

Choose the deployment method that fits your use case:

### Method 1: Interactive Deployment (Recommended for Manual Operations)

**USE CASE**: Learning, troubleshooting, manual deployments, understanding the process

```bash
# Set required environment variables
export KUBECONFIG=~/.kube/config-fineract-dev
export GITHUB_TOKEN="ghp_YourToken"

# Run interactive deployment
make deploy-gitops
```

**Features**:
- User confirmations between each step
- Clear progress tracking
- Easy to pause and resume
- Best for understanding deployment flow

### Method 2: Automated Deployment (For CI/CD Pipelines)

**USE CASE**: Unattended deployments, CI/CD pipelines, scripted automation

```bash
# Set required environment variables
export KUBECONFIG=~/.kube/config-fineract-dev
export GITHUB_TOKEN="ghp_YourToken"

# Run fully automated deployment
make deploy  # Or: ./scripts/deploy-full-stack.sh dev
```

**Features**:
- No user interaction required
- Comprehensive logging to file
- Error handling and step tracking
- Best for CI/CD pipelines

---

## Interactive Full Deployment (Method 1)

The `deploy-gitops` target runs all steps sequentially with user confirmation:

```bash
make deploy-gitops
```

### What Happens:

```
========================================
 Fineract GitOps - Interactive Deploy
========================================

Step 1/5: Validate Prerequisites
→ Checking kubectl...
✓ kubectl v1.28.3
→ Checking kustomize...
✓ kustomize v5.2.1
→ Checking kubeseal...
✓ kubeseal v0.27.0
→ Checking AWS CLI...
✓ aws-cli/2.13.0
→ Checking KUBECONFIG...
✓ KUBECONFIG set: ~/.kube/config-fineract-dev
→ Checking cluster connectivity...
✓ Connected to: https://XXX.eks.amazonaws.com
→ Checking GITHUB_TOKEN...
✓ GITHUB_TOKEN is set
→ Checking Terraform state...
✓ Terraform state initialized

✓ Step 1 completed successfully!

Press [Enter] to continue to Step 2, or 'n' to exit...
```

After each successful step, you'll see:
- ✓ Green checkmarks for successful operations
- ⚠ Yellow warnings for non-critical issues
- ✗ Red errors for failures

---

## Step-by-Step Deployment

You can run each deployment step independently using Makefile targets:

### Step 1: Validate Prerequisites

```bash
make deploy-step-1
```

**Purpose**: Ensures all required tools and configurations are ready

**Validates**:
- Required CLI tools (kubectl, kustomize, kubeseal, aws)
- Environment variables (KUBECONFIG, GITHUB_TOKEN)
- Kubernetes cluster connectivity
- Terraform state initialization

**Expected Output**:
```
✓ kubectl v1.28.3
✓ kustomize v5.2.1
✓ kubeseal v0.27.0
✓ aws-cli/2.13.0
✓ KUBECONFIG set: ~/.kube/config-fineract-dev
✓ Connected to cluster
✓ GITHUB_TOKEN is set
✓ Terraform state initialized
```

---

### Step 2: Deploy Infrastructure

```bash
make deploy-step-2
```

**Purpose**: Deploys core Kubernetes infrastructure components

**Deploys**:
1. **gp3 StorageClass** - For persistent volumes (EBS CSI)
2. **Sealed Secrets Controller** - Encrypted secrets management
3. **ArgoCD** - GitOps continuous delivery
4. **ingress-nginx** - Ingress controller for AWS
5. **cert-manager** - TLS certificate management
6. **Self-signed ClusterIssuer** - For dev environment TLS

**Expected Output**:
```
→ Creating gp3 StorageClass...
✓ StorageClass created

→ Installing Sealed Secrets Controller...
✓ Sealed Secrets Controller ready (1/1)

→ Installing ArgoCD...
✓ ArgoCD ready (7/7 pods)

→ Installing ingress-nginx...
✓ ingress-nginx ready
LoadBalancer DNS: a1b2c3-123456.us-west-2.elb.amazonaws.com

→ Installing cert-manager...
✓ cert-manager ready (3/3 pods)

→ Creating self-signed ClusterIssuer...
✓ ClusterIssuer created
```

**Duration**: ~5-8 minutes

---

### Step 3: Setup ArgoCD

```bash
make deploy-step-3
```

**Purpose**: Configure ArgoCD with repository access and sealed secrets

**Actions**:
1. Creates ArgoCD GitHub repository credentials (using $GITHUB_TOKEN)
2. Creates namespace: `fineract-dev`
3. Applies all sealed secrets from `secrets/dev/`
4. Waits for secrets to unseal

**Expected Output**:
```
→ Creating ArgoCD repository credentials...
  Waiting for secret to unseal...
✓ ArgoCD repository credentials created

→ Creating namespaces...
✓ Namespaces created

→ Applying sealed secrets...
  Waiting for secrets to unseal...
✓ Sealed secrets applied (15 secrets ready)
```

**Duration**: ~30-60 seconds

---

### Step 4: Deploy Applications

```bash
make deploy-step-4
```

**Purpose**: Deploy all applications via ArgoCD app-of-apps pattern

**Deploys**:
1. Creates ArgoCD project (`project-dev.yaml`)
2. Deploys app-of-apps (`app-of-apps.yaml`)
3. Monitors ArgoCD sync progress

**Applications Deployed** (in sync-wave order):
- Wave -3: Network policies
- Wave -2: Database initialization
- Wave -1: Redis, Keycloak
- Wave 0: Fineract (read, write, batch)
- Wave 1: OAuth2 Proxy
- Wave 2: Web applications
- Wave 3: Ingress

**Expected Output**:
```
→ Creating ArgoCD project...
✓ Project created

→ Deploying app-of-apps...
✓ App-of-apps deployed

Watching ArgoCD sync progress...
This may take 5-10 minutes. Applications will deploy in order by sync-wave.

⏳ Checking sync status (10/60)...
✓ All applications synced (11/11)

Application Status:
NAME                    SYNC     HEALTH
database-init          Synced   Healthy
fineract-redis         Synced   Healthy
keycloak               Synced   Healthy
fineract-write         Synced   Healthy
fineract-read          Synced   Healthy
oauth2-proxy           Synced   Healthy
web-app                Synced   Healthy
ingress                Synced   Healthy
...
```

**Duration**: ~5-10 minutes

**Access ArgoCD UI**:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access at: https://localhost:8080
# Username: admin
```

---

### Step 5: Verify Deployment

```bash
make deploy-step-5
```

**Purpose**: Verify all components are running correctly

**Validates**:
- Redis StatefulSet in `fineract-dev` namespace (not default!)
- Keycloak deployment ready
- Fineract deployments (read, write, batch) ready
- LoadBalancer DNS assignment
- Generates /etc/hosts entries

**Expected Output**:
```
Verifying deployment...

→ Checking Redis...
✓ Redis running in fineract-dev (1/1 ready)

→ Checking Keycloak...
✓ Keycloak running (1/1 ready)

→ Checking Fineract...
✓ fineract-write running (2/2 ready)
✓ fineract-read running (2/2 ready)
✓ fineract-batch running (1/1 ready)

→ Getting LoadBalancer DNS...
LoadBalancer DNS: a1b2c3-123456.us-west-2.elb.amazonaws.com

Add these to /etc/hosts for local access:
52.12.34.56   apps.dev.fineract.com
52.12.34.56   auth.dev.fineract.com

✓ Deployment verification complete!

Next steps:
  1. Update /etc/hosts with LoadBalancer IP
  2. Access Fineract at: https://apps.dev.fineract.com
  3. Access Keycloak at: https://auth.dev.fineract.com
```

**Critical Check**: Redis **must** be in `fineract-dev` namespace, not `default`.

---

### Verify Namespaces

Additional namespace verification target:

```bash
make verify-namespaces
```

**Purpose**: Ensures all resources are in correct namespaces

**Output**:
```
✓ Redis in correct namespace: fineract-dev
✓ Fineract components in fineract-dev
```

---

## Deployment Steps Explained

### Why Step-by-Step?

The deployment is broken into discrete steps because:

1. **Infrastructure Dependencies**: ArgoCD, Sealed Secrets, ingress must be ready before apps
2. **Secret Unsealing**: Secrets must be unsealed before applications can use them
3. **Sync Waves**: Applications deploy in order (database → services → apps → ingress)
4. **Validation**: Each step can be validated before proceeding
5. **Troubleshooting**: Easy to identify which step failed

### Sync Wave Order

Applications deploy in this order via ArgoCD sync waves:

```
Wave -3: Network Policies          (security first)
Wave -2: Database Init             (create schemas)
Wave -1: Redis, Keycloak           (dependencies)
Wave  0: Fineract (read/write)     (core services)
Wave  1: OAuth2 Proxy              (authentication)
Wave  2: Web Apps                  (frontends)
Wave  3: Ingress                   (external access)
```

You can monitor sync waves:
```bash
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
WAVE:.metadata.annotations.argocd\\.argoproj\\.io/sync-wave,\
SYNC:.status.sync.status
```

---

## Verification

### Check All Components

```bash
# Check all pods in fineract-dev namespace
kubectl get pods -n fineract-dev

# Expected output:
NAME                              READY   STATUS    RESTARTS   AGE
fineract-read-xxx                 1/1     Running   0          5m
fineract-write-xxx                1/1     Running   0          5m
fineract-batch-xxx                1/1     Running   0          5m
keycloak-xxx                      1/1     Running   0          8m
fineract-redis-0                  1/1     Running   0          8m
oauth2-proxy-xxx                  1/1     Running   0          4m
```

### Check ArgoCD Applications

```bash
# List all applications
kubectl get applications -n argocd

# Get detailed status
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status
```

### Check Ingress

```bash
# Get LoadBalancer DNS
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Get ingress resources
kubectl get ingress -n fineract-dev
```

### Access Application

1. **Get LoadBalancer IP**:
   ```bash
   LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   LB_IP=$(dig +short $LB_DNS | head -1)
   echo $LB_IP
   ```

2. **Update /etc/hosts**:
   ```bash
   sudo tee -a /etc/hosts << EOF
   $LB_IP   apps.dev.fineract.com
   $LB_IP   auth.dev.fineract.com
   EOF
   ```

3. **Access Applications**:
   - Fineract API: https://apps.dev.fineract.com/fineract-provider/api/v1
   - Keycloak: https://auth.dev.fineract.com
   - Web App: https://apps.dev.fineract.com

---

## Troubleshooting

### Common Issues

#### 0. Namespaces Stuck in Terminating State ⚠️ **MOST COMMON**

**Error**:
```
Error from server (AlreadyExists): namespaces "argocd" already exists
Error from server (Forbidden): unable to create new content in namespace argocd because it is being terminated
```

**Cause**: Namespaces (argocd, fineract-dev, ingress-nginx) are stuck in "Terminating" state, usually due to:
- ArgoCD Application finalizers preventing deletion
- Resources with finalizers that won't clear
- CRDs being deleted while namespace is terminating

**Fix** (Run this command):
```bash
make cleanup-cluster
```

This will:
1. Remove all ArgoCD Applications (clears finalizers)
2. Force-delete stuck namespaces by removing finalizers
3. Delete CRDs safely
4. Wait for complete cleanup
5. Verify cluster is ready

**Manual verification**:
```bash
# Check namespace status
kubectl get namespaces

# Should NOT show any namespaces stuck in "Terminating"
# If you see "Terminating" for > 2 minutes, run: make cleanup-cluster
```

**After cleanup**, re-run deployment:
```bash
make deploy-gitops
# or
make deploy-step-2
```

**Alternative (if cleanup fails)**: Recreate the cluster
```bash
# Nuclear option - only if make cleanup-cluster fails
cd terraform/aws
terraform destroy
terraform apply
```

---

#### 1. GITHUB_TOKEN not set

**Error**:
```
✗ GITHUB_TOKEN not set
```

**Fix**:
```bash
export GITHUB_TOKEN="ghp_YourPersonalAccessToken"
```

#### 2. KUBECONFIG not set

**Error**:
```
✗ KUBECONFIG not set
```

**Fix**:
```bash
export KUBECONFIG=~/.kube/config-fineract-dev
# or
aws eks update-kubeconfig --region us-west-2 --name fineract-dev-eks
```

#### 3. Cluster not reachable

**Error**:
```
✗ Cannot connect to cluster
```

**Fix**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name fineract-dev-eks

# Test connection
kubectl cluster-info
```

#### 4. Terraform state not initialized

**Error**:
```
✗ Terraform state not initialized
```

**Fix**:
```bash
cd terraform/aws
./scripts/setup-terraform-backend.sh
terraform init
```

#### 5. Sealed Secrets not unsealing

**Error**:
```
Secrets not unsealing after 30 seconds
```

**Fix**:
```bash
# Check sealed-secrets-controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Re-apply sealed secrets
kubectl apply -f secrets/dev/
```

#### 6. Redis in wrong namespace

**Error**:
```
✗ Redis not in fineract-dev namespace (found in: default)
```

**Fix**: This should not happen with the fixed code. If it does:
```bash
# Check kustomization
cat apps/fineract-redis/base/kustomization.yaml | grep namespace

# Should show: namespace: fineract-dev
```

#### 7. ArgoCD applications not syncing

**Error**:
```
Applications stuck in OutOfSync
```

**Fix**:
```bash
# Check repository credentials
kubectl get secret repo-fineract-gitops -n argocd

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f

# Manually sync
kubectl patch application fineract-redis -n argocd \
  --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'
```

#### 8. Pods stuck in Pending (PVC issues)

**Error**:
```
Keycloak pod stuck in Pending
PVC: persistentvolumeclaim "keycloak-data" not found
```

**Fix**:
```bash
# Check PVC status
kubectl get pvc -n fineract-dev

# Check StorageClass
kubectl get storageclass

# Should see gp3 StorageClass
# If missing, re-run:
make deploy-step-2
```

#### 9. Certificate errors

**Error**:
```
x509: certificate signed by unknown authority
```

**Fix**: For dev environment with self-signed certs:
```bash
# Trust the self-signed CA (macOS)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/fineract-internal-ca.crt

# Or access with --insecure flag
curl -k https://apps.dev.fineract.com
```

#### 10. LoadBalancer stuck in Pending

**Error**:
```
LoadBalancer stuck in <pending>
```

**Fix**:
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify AWS permissions (IRSA)
kubectl describe sa ingress-nginx -n ingress-nginx | grep "eks.amazonaws.com/role-arn"

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=*eks*"
```

### Debug Commands

```bash
# View all resources in fineract-dev
kubectl get all -n fineract-dev

# Check events
kubectl get events -n fineract-dev --sort-by='.lastTimestamp'

# Describe pod for issues
kubectl describe pod <pod-name> -n fineract-dev

# View logs
kubectl logs <pod-name> -n fineract-dev -f

# Check ArgoCD application details
kubectl describe application fineract-redis -n argocd

# Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

## Post-Deployment

### 1. Configure Keycloak

```bash
# Get Keycloak admin password
kubectl get secret keycloak-admin -n fineract-dev \
  -o jsonpath='{.data.password}' | base64 -d

# Access Keycloak
# URL: https://auth.dev.fineract.com
# Username: admin
```

Configure:
- Create `fineract` realm
- Create clients: `fineract-oauth2-proxy`, `fineract-api`
- Create users and roles
- Map Fineract roles to Keycloak roles

See: `operations/keycloak-config/` for configurations

### 2. Verify API Access

```bash
# Get Keycloak token
TOKEN=$(curl -k -X POST https://auth.dev.fineract.com/realms/fineract/protocol/openid-connect/token \
  -d "client_id=fineract-oauth2-proxy" \
  -d "username=mifos" \
  -d "password=password" \
  -d "grant_type=password" | jq -r .access_token)

# Test Fineract API
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "X-Fineract-Platform-TenantId: default" \
  https://apps.dev.fineract.com/fineract-provider/api/v1/clients
```

### 3. Monitor Applications

Access ArgoCD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
```

### 4. Setup Monitoring (Optional)

Deploy monitoring stack:
```bash
kubectl apply -k environments/dev/monitoring
```

---

## Additional Resources

- [Architecture Documentation](docs/ARCHITECTURE.md)
- [Operations Guide](docs/OPERATIONS_GUIDE.md)
- [Secrets Management](docs/SECRETS_MANAGEMENT.md)
- [Terraform AWS Guide](terraform/aws/README.md)
- [Multi-Provider Implementation](docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md)
- [AWS Cost Analysis](docs/AWS_COST_ANALYSIS.md)
- [Quick Reference](docs/QUICK_REFERENCE.md)

---

## Summary

### Full Deployment (Interactive)

```bash
export KUBECONFIG=~/.kube/config-fineract-dev
export GITHUB_TOKEN="ghp_YourToken"
make deploy-gitops
```

### Individual Steps

```bash
make deploy-step-1  # Validate prerequisites
make deploy-step-2  # Deploy infrastructure
make deploy-step-3  # Setup ArgoCD
make deploy-step-4  # Deploy applications
make deploy-step-5  # Verify deployment
```

### Verification

```bash
make verify-namespaces
kubectl get all -n fineract-dev
kubectl get applications -n argocd
```

---

**Deployment Duration**: ~15-20 minutes for full stack

**Next Steps**: Configure Keycloak, load data, verify API access
