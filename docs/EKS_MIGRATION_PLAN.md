# K3s to AWS EKS Migration Plan - Complete Implementation Guide

**Document Version**: 1.0
**Created**: 2025-01-15
**Status**: Ready for Implementation
**Estimated Timeline**: 2 weeks
**Expected Cost Savings**: 23-29% ($220-240/month vs current $312/month)

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Target Architecture](#target-architecture)
4. [Implementation Phases](#implementation-phases)
5. [DNS and Domain Configuration](#dns-and-domain-configuration)
6. [Resource Requirements](#resource-requirements)
7. [Credential Management](#credential-management)
8. [Terraform State Security](#terraform-state-security)
9. [IAM Permissions](#iam-permissions)
10. [Automation Strategy](#automation-strategy)
11. [Files to Create/Modify](#files-to-createmodify)
12. [Success Criteria](#success-criteria)
13. [Future Enhancements](#future-enhancements)

---

## Executive Summary

### Migration Goals
- ✅ Migrate from K3s (2x t3.xlarge) to AWS EKS (2x t3.large with auto-scaling)
- ✅ Implement production-grade DNS with Route53
- ✅ Replace NodePort with AWS LoadBalancer
- ✅ Automate Let's Encrypt certificates
- ✅ Enable cluster auto-scaling for loader jobs
- ✅ Remove Prometheus/Grafana (use AWS CloudWatch)
- ✅ Enhance credential management with validation
- ✅ Achieve 23-29% cost savings

### Why EKS?
- Managed control plane (reduce operational overhead)
- Better AWS integration (IRSA, VPC CNI, EBS CSI)
- Native auto-scaling capabilities
- Enterprise compliance requirements

### Key Benefits
- **Cost**: $220-240/month (down from $312)
- **Reliability**: Managed control plane, auto-healing
- **Security**: IRSA (pod-level IAM roles) vs instance profiles
- **Scalability**: Auto-scales 2→4 nodes for bursts
- **Automation**: Zero manual steps, fully scripted

---

## Current State Analysis

### Existing Infrastructure (K3s-Based)

**Compute**:
- 2x t3.xlarge EC2 instances (4 vCPU, 16GB RAM each)
- Total: 8 vCPU, 32GB RAM
- K3s lightweight Kubernetes distribution

**Database**:
- AWS RDS PostgreSQL (db.t4g.micro)
- 2 databases: Fineract + Keycloak

**Storage**:
- S3 buckets: Documents + Backups
- Local-path storage class (K3s default)

**Networking**:
- Direct node exposure via Elastic IP
- NGINX Ingress on NodePort
- Manual /etc/hosts DNS configuration
- Self-signed TLS certificates

**Monitoring**:
- In-cluster Prometheus + Grafana + Loki
- High resource consumption (800m CPU, 2.8GB RAM)

**Cost**: ~$312/month

### Resource Utilization
| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Fineract Services | 900m | 3500m | 2560Mi | 5120Mi |
| Auth Services | 550m | 1800m | 1088Mi | 2176Mi |
| Redis | 125m | 250m | 288Mi | 576Mi |
| Frontend | 100m | 300m | 192Mi | 384Mi |
| **Monitoring** | **800m** | **2500m** | **2816Mi** | **6656Mi** |
| **Total** | **2475m** | **8350m** | **6944Mi** | **14912Mi** |

**Current utilization**: 32% CPU, 22% RAM (significantly over-provisioned)

### Known Issues
1. ❌ No Route53 DNS automation (manual /etc/hosts)
2. ❌ Self-signed certificates (browser warnings)
3. ❌ Single node exposure (no load balancing)
4. ❌ No horizontal scaling for traffic spikes
5. ⚠️ Credential management issues (documented in past migrations)
6. ⚠️ kubectl access requires port-forwarding or manual IP management

---

## Target Architecture

### EKS Cluster Configuration

**Nodes**:
- Base: 2x t3.large (2 vCPU, 8GB RAM each)
- Auto-scaling: Min=2, Max=4 nodes
- Cluster Autoscaler handles loader job bursts

**Capacity Analysis**:
```
Steady State (2 nodes):
- Total: 4 vCPU, 16GB RAM
- Available after EKS overhead: ~3.3 vCPU, 14.5GB RAM
- Workload (without monitoring): 1.7 vCPU, 4.1GB RAM
- Utilization: 51% CPU, 28% RAM ✅ Comfortable

During Loader Jobs (3-4 nodes):
- Total: 6-8 vCPU, 24-32GB RAM
- Can handle heavy init jobs + applications
- Auto-scales back down after completion
```

### Service Exposure - New Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     EXTERNAL USERS                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│         Route53 DNS (apps.dev.fineract.com)                 │
│                                                              │
│  A Record → AWS Network Load Balancer DNS                   │
│  Automated via Terraform                                     │
│  Let's Encrypt TLS certificates (automatic renewal)         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│      AWS Network Load Balancer (Auto-Provisioned)           │
│                                                              │
│  - Multi-AZ distribution                                     │
│  - Health checks on ingress controller                       │
│  - Cross-zone load balancing                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│   NGINX Ingress Controller (type: LoadBalancer)             │
│                                                              │
│  - Automatically gets NLB endpoint                           │
│  - TLS termination with Let's Encrypt certs                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              Ingress Resources + OAuth2 Proxy                │
│                                                              │
│  - fineract-oauth2-protected → OAuth2 authentication        │
│  - fineract-web-app-protected → Web app with auth           │
│  - keycloak-ingress → Keycloak server                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                Backend Services (Pods)                       │
│                                                              │
│  - Fineract Read/Write/Batch                                │
│  - Keycloak                                                  │
│  - Web App                                                   │
│  - Redis                                                     │
└─────────────────────────────────────────────────────────────┘
```

### Cost Comparison

| Component | Current (K3s) | EKS Migration | Savings |
|-----------|---------------|---------------|---------|
| **Compute** | 2x t3.xlarge<br>$240/month | 2x t3.large<br>$140/month + occasional scale-up | $70-100 |
| **Control Plane** | $0 (self-managed) | $72/month (AWS managed) | -$72 |
| **Monitoring** | In-cluster | CloudWatch (~$10/month) | Minimal |
| **Database** | RDS $12/month | RDS $12/month | $0 |
| **Storage** | S3 $5-8/month | S3 $5-8/month | $0 |
| **Total** | **$312/month** | **$220-240/month** | **$72-92** |
| **Annual** | **$3,744** | **$2,640-2,880** | **$864-1,104** |
| **Savings** | — | — | **23-29%** |

---

## Implementation Phases

### Phase 1: Foundation Setup (Week 1, Days 1-2)

**Objective**: Prepare infrastructure modules and automation scripts

#### 1.1 Create EKS Terraform Module
**Location**: `terraform/aws/modules/eks/`

**Files**:
- `main.tf` - EKS cluster, VPC configuration
- `node_groups.tf` - Managed node groups (2x t3.large)
- `autoscaling.tf` - Cluster Autoscaler IAM + Kubernetes deployment
- `irsa.tf` - OIDC provider + Fineract IRSA role
- `addons.tf` - VPC-CNI, EBS CSI driver, CloudWatch Container Insights
- `security.tf` - Security groups for EKS
- `variables.tf` - Configurable parameters
- `outputs.tf` - Cluster endpoint, OIDC provider URL, security groups

**Key Configuration**:
```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name    = "fineract-dev"
  cluster_version = "1.31"

  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  node_groups = {
    general = {
      instance_types = ["t3.large"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      capacity_type  = "ON_DEMAND"
    }
  }

  enable_cluster_autoscaler          = true
  enable_cloudwatch_container_insights = true
}
```

#### 1.2 Create Route53 Module
**Location**: `terraform/aws/modules/route53/`

**Files**:
- `main.tf` - Hosted zone creation
- `records.tf` - A records for apps/auth subdomains
- `variables.tf` - Domain name, environment
- `outputs.tf` - Zone ID, nameservers

**Key Configuration**:
```hcl
module "route53" {
  source = "./modules/route53"

  domain_name = var.domain_name  # e.g., "yourdomain.com"
  environment = var.environment  # e.g., "dev"

  # Creates:
  # - apps.dev.yourdomain.com → NLB
  # - auth.dev.yourdomain.com → NLB
}
```

#### 1.3 Create Automation Scripts

**New Scripts** (`scripts/` directory):

1. **`setup-terraform-backend.sh`**
   - Creates S3 bucket + DynamoDB table (idempotent)
   - Enables versioning, encryption, public access block
   - Enables access logging
   - Configures DynamoDB point-in-time recovery

2. **`validate-terraform-outputs.sh`**
   - Validates RDS endpoint reachable (pg_isready)
   - Validates S3 buckets exist (aws s3 ls)
   - Validates IRSA role configured (aws iam get-role)
   - Validates OIDC provider matches EKS cluster
   - Exit 0 if pass, 1 if fail

3. **`seal-terraform-secrets-enhanced.sh`**
   - Calls `validate-terraform-outputs.sh` first
   - Standardizes secret keys (host, port, database, username, password)
   - Validates sealed secrets after creation
   - Creates detailed commit message with metadata

4. **`get-endpoints.sh`**
   - Retrieves LoadBalancer DNS from kubectl
   - Lists Route53 DNS records
   - Tests DNS propagation
   - Displays kubeconfig command
   - Saves to `deployment-info.txt` for CI/CD

5. **`verify-irsa-credentials.sh`**
   - Tests IRSA environment variables in pods
   - Tests database connectivity
   - Tests S3 access via IRSA
   - Returns detailed health report

6. **`install-cluster-autoscaler.sh`**
   - Installs Cluster Autoscaler via Helm or manifest
   - Configures IAM role via IRSA
   - Tests auto-scaling functionality

7. **`install-ebs-csi-driver.sh`**
   - Installs AWS EBS CSI driver
   - Creates gp3 StorageClass
   - Tests volume provisioning

8. **`setup-letsencrypt.sh`**
   - Configures cert-manager with Let's Encrypt
   - Uses DNS-01 challenge with Route53
   - Creates ClusterIssuer
   - Tests certificate issuance

---

### Phase 2: Kubernetes Manifest Updates (Week 1, Days 3-4)

#### 2.1 Remove Monitoring Stack

**Delete directories**:
- `apps/monitoring/` (Prometheus, Grafana)
- `apps/logging/` (Loki, Promtail)

**Update files**:
- `environments/dev/kustomization.yaml`:
  Remove references to monitoring apps

- `argocd/bootstrap/dev/app-of-apps.yaml`:
  Remove Prometheus, Grafana, Loki application definitions

**Resource savings**: -800m CPU, -2816Mi RAM

#### 2.2 Update Storage Classes

**Files to modify**:
- `apps/keycloak/base/statefulset.yaml`:
  ```yaml
  # Before
  storageClassName: local-path

  # After
  storageClassName: gp3
  ```

- `apps/fineract-redis/base/statefulset.yaml`:
  Same change

#### 2.3 Add IRSA Service Account Annotations

**File**: `apps/fineract/base/serviceaccount.yaml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fineract-aws
  namespace: fineract-dev
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::${AWS_ACCOUNT_ID}:role/fineract-dev-irsa"
automountServiceAccountToken: true
```

#### 2.4 Configure NGINX Ingress for LoadBalancer

**File**: `apps/ingress/base/ingress-nginx-values.yaml`
```yaml
controller:
  service:
    type: LoadBalancer  # Changed from NodePort
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
```

#### 2.5 Add ArgoCD Sync Waves

**Add to all sealed secrets** (`secrets/dev/*-sealed.yaml`):
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "10"
```

**Add to applications**:
- Init jobs: `argocd.argoproj.io/sync-wave: "20"`
- Core services: `argocd.argoproj.io/sync-wave: "30"`
- Frontend: `argocd.argoproj.io/sync-wave: "40"`

---

### Phase 3: Terraform Configuration (Week 1, Day 5)

#### 3.1 Update Main Terraform Configuration

**File**: `terraform/aws/main.tf`

**Changes**:
1. Remove K3s module and conditionals
2. Add EKS module integration
3. Add Route53 module integration
4. Update RDS security groups to reference EKS node SG

```hcl
# Remove K3s module
# module "k3s" { ... }  ← DELETE

# Add EKS module
module "eks" {
  source = "./modules/eks"

  cluster_name = "${var.project}-${var.environment}"
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnet_ids

  # ... configuration from Phase 1.1
}

# Add Route53 module
module "route53" {
  source = "./modules/route53"

  domain_name    = var.domain_name
  environment    = var.environment
  nlb_dns_name   = module.eks.load_balancer_dns
  nlb_zone_id    = module.eks.load_balancer_zone_id
}

# Update RDS security group
resource "aws_security_group_rule" "rds_from_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.security_group_id
  source_security_group_id = module.eks.node_security_group_id
}
```

#### 3.2 Create Environment-Specific Config

**File**: `terraform/aws/environments/dev-eks.tfvars`
```hcl
# Environment
project     = "fineract"
environment = "dev"
region      = "us-east-2"

# EKS Configuration
deployment_type      = "eks"
cluster_version      = "1.31"
node_instance_types  = ["t3.large"]
node_desired_size    = 2
node_min_size        = 2
node_max_size        = 4

# DNS Configuration
domain_name = "yourdomain.com"  # ← CHANGE THIS TO YOUR DOMAIN

# Features
enable_cluster_autoscaler          = true
enable_cloudwatch_container_insights = true
enable_cloudwatch_logs             = true

# Database
rds_instance_class = "db.t4g.micro"
rds_allocated_storage = 20

# Cost Optimization
use_spot_instances = false  # Set true for further savings
```

#### 3.3 Update Outputs

**File**: `terraform/aws/outputs.tf`

**Add**:
```hcl
# EKS Outputs
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "load_balancer_dns" {
  value = module.eks.load_balancer_dns
}

# Route53 Outputs
output "route53_zone_id" {
  value = module.route53.zone_id
}

output "route53_nameservers" {
  value       = module.route53.nameservers
  description = "Configure these at your domain registrar"
}

output "apps_url" {
  value = "https://apps.${var.environment}.${var.domain_name}"
}

output "auth_url" {
  value = "https://auth.${var.environment}.${var.domain_name}"
}
```

---

### Phase 4: Enhanced Deployment Script (Week 2, Day 1)

**File**: `scripts/deploy-full-stack.sh` (enhanced)

```bash
#!/bin/bash
set -euo pipefail

ENV=${1:-dev}
LOG_DIR="logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p $LOG_DIR

echo "🚀 Starting EKS deployment for $ENV environment"

# Step 1: Validate prerequisites
echo "📋 Step 1/15: Validating prerequisites..."
./scripts/validate-prerequisites.sh | tee $LOG_DIR/01-prereqs.log

# Step 2: Setup Terraform backend (idempotent)
echo "🔐 Step 2/15: Setting up Terraform backend..."
./scripts/setup-terraform-backend.sh | tee $LOG_DIR/02-backend.log

# Step 3: Deploy infrastructure (Terraform)
echo "🏗️  Step 3/15: Deploying infrastructure..."
./scripts/deploy-infrastructure.sh $ENV | tee $LOG_DIR/03-infra.log

# Step 4: Validate Terraform outputs
echo "✅ Step 4/15: Validating Terraform outputs..."
./scripts/validate-terraform-outputs.sh $ENV | tee $LOG_DIR/04-validate.log

# Step 5: Setup kubeconfig (EKS)
echo "🔑 Step 5/15: Configuring kubectl..."
aws eks update-kubeconfig --name fineract-$ENV --region us-east-2
export KUBECONFIG=~/.kube/config

# Step 6: Install Cluster Autoscaler
echo "📈 Step 6/15: Installing Cluster Autoscaler..."
./scripts/install-cluster-autoscaler.sh | tee $LOG_DIR/06-autoscaler.log

# Step 7: Install EBS CSI Driver
echo "💾 Step 7/15: Installing EBS CSI Driver..."
./scripts/install-ebs-csi-driver.sh | tee $LOG_DIR/07-ebs-csi.log

# Step 8: Bootstrap ArgoCD + Ingress
echo "🔧 Step 8/15: Bootstrapping ArgoCD and Ingress..."
./scripts/bootstrap-argocd.sh | tee $LOG_DIR/08-argocd.log

# Step 9: Wait for LoadBalancer provisioning
echo "⏳ Step 9/15: Waiting for LoadBalancer..."
./scripts/wait-for-loadbalancer.sh | tee $LOG_DIR/09-lb.log

# Step 10: Configure Let's Encrypt
echo "🔒 Step 10/15: Setting up Let's Encrypt..."
./scripts/setup-letsencrypt.sh $ENV | tee $LOG_DIR/10-letsencrypt.log

# Step 11: Create and seal secrets
echo "🔐 Step 11/15: Creating sealed secrets..."
./scripts/seal-terraform-secrets-enhanced.sh $ENV | tee $LOG_DIR/11-secrets.log

# Step 12: Deploy applications
echo "📦 Step 12/15: Deploying applications..."
./scripts/deploy-app-of-apps.sh $ENV | tee $LOG_DIR/12-apps.log

# Step 13: Wait for sync
echo "⏳ Step 13/15: Waiting for ArgoCD sync..."
./scripts/wait-for-sync.sh | tee $LOG_DIR/13-sync.log

# Step 14: Display endpoints
echo "🌐 Step 14/15: Retrieving service endpoints..."
./scripts/get-endpoints.sh | tee $LOG_DIR/14-endpoints.log

# Step 15: Run health checks
echo "🏥 Step 15/15: Running health checks..."
./scripts/deployment-health-check.sh | tee $LOG_DIR/15-health.log

echo ""
echo "✅ DEPLOYMENT COMPLETE!"
echo "📊 Logs saved to: $LOG_DIR"
echo "📄 Service endpoints: deployment-info.txt"
echo ""
echo "🌐 Access your services:"
cat deployment-info.txt
```

---

## DNS and Domain Configuration

### ⚠️ IMPORTANT: Domain Ownership Required

**Current Code Uses**: `fineract.com` (example placeholder)

**You Must Choose One**:

#### Option 1: You Own a Domain ✅ RECOMMENDED
If you own a domain (e.g., `mycompany.com`):

1. **Update tfvars**:
   ```hcl
   # terraform/aws/environments/dev-eks.tfvars
   domain_name = "mycompany.com"
   ```

2. **Terraform will create**:
   - Route53 hosted zone for `mycompany.com`
   - DNS records:
     - `apps.dev.mycompany.com` → LoadBalancer
     - `auth.dev.mycompany.com` → LoadBalancer

3. **Update your domain registrar**:
   After Terraform completes, copy nameservers:
   ```bash
   terraform output route53_nameservers
   ```
   Configure these at your domain registrar (GoDaddy, Namecheap, etc.)

4. **Wait for DNS propagation**: 15 minutes to 48 hours

#### Option 2: Register New Domain
If you don't have a domain:

1. **Register on Route53** ($12/year):
   ```bash
   aws route53domains register-domain \
     --domain-name yourcompany.com \
     --duration-in-years 1 \
     --admin-contact file://contact.json \
     --registrant-contact file://contact.json \
     --tech-contact file://contact.json
   ```

2. **Or use other registrar**: GoDaddy, Namecheap, Google Domains

3. **Update tfvars** with your new domain

#### Option 3: Subdomain of Existing Domain
If you have `company.com` but want `fineract.company.com`:

1. **Update tfvars**:
   ```hcl
   domain_name = "fineract.company.com"
   ```

2. **Create NS delegation** in parent zone:
   - Get Route53 nameservers for `fineract.company.com`
   - Add NS records in `company.com` zone pointing to these

#### Option 4: Development Without Domain (NOT RECOMMENDED)
If you want to test without a domain:

1. **Skip Route53 module** (comment out in main.tf)
2. **Use LoadBalancer DNS directly**:
   ```bash
   # Get LB DNS
   LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

   # Update /etc/hosts
   echo "$LB_DNS apps.dev.fineract.local" | sudo tee -a /etc/hosts
   echo "$LB_DNS auth.dev.fineract.local" | sudo tee -a /etc/hosts
   ```
3. **Accept self-signed certificates** in browser
4. **Not production-ready** - for development only

### Recommended Approach
- **For production/UAT**: Option 1 or 2 (real domain)
- **For development**: Option 1 (subdomain of company domain)

---

## Credential Management

### Enhanced Credential Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. TERRAFORM PROVISIONS RESOURCES                           │
│    - RDS, S3, IAM roles, EKS cluster                        │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. VALIDATE TERRAFORM OUTPUTS (NEW!)                        │
│    Script: validate-terraform-outputs.sh                    │
│    - Checks RDS reachable (pg_isready)                      │
│    - Checks S3 buckets exist                                │
│    - Checks IRSA role configured                            │
│    Exit 0 = Pass, Exit 1 = Fail (stops deployment)         │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. ENHANCED SECRET SEALING                                  │
│    Script: seal-terraform-secrets-enhanced.sh               │
│    - Extracts Terraform outputs                             │
│    - Standardized keys: host, port, database, user, pass   │
│    - Creates 7 sealed secrets                               │
│    - Validates after sealing (dry-run decrypt)              │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. GIT COMMIT WITH METADATA                                 │
│    Commit message includes (no sensitive data):             │
│    - RDS endpoint                                            │
│    - S3 bucket names                                        │
│    - IRSA role ARN                                          │
│    - Timestamp                                               │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. ARGOCD DEPLOYMENT (with Sync Waves)                     │
│    Wave 10: Secrets created                                 │
│    Wave 20: Init jobs run                                   │
│    Wave 30: Applications deploy                             │
│    Result: No CrashLoopBackOff due to missing secrets      │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. RUNTIME VERIFICATION (NEW!)                              │
│    Script: verify-irsa-credentials.sh                       │
│    - Tests IRSA env vars present in pods                    │
│    - Tests database connectivity                            │
│    - Tests S3 access via IRSA                               │
│    - Returns health report                                   │
└─────────────────────────────────────────────────────────────┘
```

### Secret Key Standardization

**Problem**: Past issues with inconsistent keys (`endpoint` vs `host`)

**Solution**: All database secrets now include:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fineract-db-credentials
data:
  host: <base64>        # RDS hostname
  port: <base64>        # 5432
  database: <base64>    # fineract
  username: <base64>    # fineract
  password: <base64>    # from Terraform
  jdbc-url: <base64>    # Full JDBC connection string
```

**Backward compatibility**: Old keys remain, new keys added

---

## Terraform State Security

### Current State (Already Good) ✅
- S3 backend: `fineract-gitops-terraform-state`
- DynamoDB locking: `fineract-gitops-terraform-lock`
- Encryption enabled
- State files gitignored

### Enhancements Implemented

**Script**: `scripts/setup-terraform-backend.sh` (idempotent)

**Enhancements**:
1. ✅ Enable S3 versioning (state history)
2. ✅ Enable S3 encryption (AES256)
3. ✅ Block public access (all 4 settings)
4. ✅ Enable access logging to separate bucket
5. ✅ DynamoDB point-in-time recovery
6. ✅ Lifecycle policies to prevent accidental deletion

**One-Time Setup**:
```bash
make setup-backend
```

This creates/configures:
- `fineract-gitops-terraform-state` (main state)
- `fineract-gitops-terraform-state-logs` (access logs)
- `fineract-gitops-terraform-lock` (DynamoDB)

**Security Best Practices**:
- 🔐 State encryption at rest
- 🔒 MFA delete (optional, requires root account)
- 📝 Access logging for audit trail
- 🔄 Versioning for rollback capability
- 🚫 Public access blocked

---

## IAM Permissions

### Comprehensive IAM Documentation

**New File**: `docs/AWS_IAM_REQUIREMENTS.md`

### Summary of Required Permissions

#### 1. Terraform Operator (Human/CI User)
**Managed Policies**:
- Option A (simpler): `PowerUserAccess` + `IAMFullAccess`
- Option B (least privilege): Custom policy (see full doc)

**AWS Services Accessed**:
- EKS (cluster management)
- EC2 (VPC, subnets, security groups)
- RDS (database provisioning)
- S3 (application buckets + state backend)
- DynamoDB (state locking)
- IAM (role creation, IRSA)
- Route53 (DNS management)
- CloudWatch (monitoring)
- ELB (load balancers)
- AutoScaling (node groups)

**Quick Setup**:
```bash
./scripts/create-iam-user.sh fineract-terraform-operator
```

#### 2. EKS Node Group IAM Role
**Managed Policies** (AWS-managed):
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`
- `AmazonEBSCSIDriverPolicy`

**Created by**: Terraform EKS module automatically

#### 3. Cluster Autoscaler IAM Role (IRSA)
**Custom Policy**:
- `autoscaling:Describe*`
- `autoscaling:SetDesiredCapacity`
- `autoscaling:TerminateInstanceInAutoScalingGroup`

**Created by**: Terraform autoscaling.tf

#### 4. Fineract Application IAM Role (IRSA)
**Custom Policy**:
- RDS: `rds-db:connect`, `rds:DescribeDBInstances`
- S3: `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`
- SES: `ses:SendEmail`, `ses:SendRawEmail`

**Created by**: Terraform IRSA module

### Complete Policy Documents
See `docs/AWS_IAM_REQUIREMENTS.md` for:
- Full JSON policy documents
- Step-by-step setup instructions
- Troubleshooting guide
- Security best practices

---

## Automation Strategy

### Zero Manual Steps Philosophy

**Current Automation**: 90% (requires some manual steps)
**Target Automation**: 100% (fully scripted)

### Makefile Targets

**New/Updated Targets**:
```makefile
# One-time setup
setup-backend:
	@./scripts/setup-terraform-backend.sh

# Full deployment
deploy-dev-eks: setup-backend
	@./scripts/deploy-full-stack.sh dev
	@cat deployment-info.txt

deploy-uat-eks:
	@./scripts/deploy-full-stack.sh uat
	@cat deployment-info.txt

deploy-prod-eks:
	@echo "⚠️  This will deploy to PRODUCTION. Are you sure? [y/N]"
	@read -r REPLY; \
	if [ "$$REPLY" = "y" ]; then \
		./scripts/deploy-full-stack.sh production; \
		cat deployment-info.txt; \
	else \
		echo "Deployment cancelled."; \
	fi

# Utilities
get-endpoints:
	@./scripts/get-endpoints.sh

verify-credentials:
	@./scripts/verify-irsa-credentials.sh dev

smoke-tests:
	@./scripts/smoke-tests.sh dev
```

### Post-Deployment Outputs

**Automatically Generated**: `deployment-info.txt`

Example contents:
```
LOADBALANCER_DNS=a1b2c3d4e5f6g7h8-1234567890.elb.us-east-2.amazonaws.com
APPS_URL=https://apps.dev.yourdomain.com
AUTH_URL=https://auth.dev.yourdomain.com
KUBECONFIG_CMD=aws eks update-kubeconfig --name fineract-dev --region us-east-2
DEPLOYMENT_DATE=2025-01-15 14:30:00 UTC
EKS_CLUSTER_ENDPOINT=https://XXXXX.gr7.us-east-2.eks.amazonaws.com
ROUTE53_ZONE_ID=Z1234567890ABC
```

**Usage**:
- CI/CD pipelines can source this file
- Smoke tests use these URLs
- Documentation auto-updated with endpoints

---

## Files to Create/Modify

### New Files (19 files)

#### Terraform Modules (10 files)
1. `terraform/aws/modules/eks/main.tf`
2. `terraform/aws/modules/eks/node_groups.tf`
3. `terraform/aws/modules/eks/autoscaling.tf`
4. `terraform/aws/modules/eks/irsa.tf`
5. `terraform/aws/modules/eks/addons.tf`
6. `terraform/aws/modules/eks/security.tf`
7. `terraform/aws/modules/eks/variables.tf`
8. `terraform/aws/modules/eks/outputs.tf`
9. `terraform/aws/modules/route53/main.tf`
10. `terraform/aws/modules/route53/outputs.tf`

#### Scripts (12 files)
11. `scripts/setup-terraform-backend.sh`
12. `scripts/validate-terraform-outputs.sh`
13. `scripts/seal-terraform-secrets-enhanced.sh`
14. `scripts/get-endpoints.sh`
15. `scripts/verify-irsa-credentials.sh`
16. `scripts/install-cluster-autoscaler.sh`
17. `scripts/install-ebs-csi-driver.sh`
18. `scripts/setup-letsencrypt.sh`
19. `scripts/wait-for-loadbalancer.sh`
20. `scripts/smoke-tests.sh`
21. `scripts/create-iam-user.sh`

#### Documentation (4 files)
22. `docs/AWS_IAM_REQUIREMENTS.md`
23. `docs/EKS_MIGRATION_GUIDE.md` (this file!)
24. `docs/CLOUDWATCH_MONITORING.md`
25. `docs/TROUBLESHOOTING_EKS.md`

### Modified Files (10 files)

#### Terraform (4 files)
1. `terraform/aws/main.tf` - Add EKS + Route53 modules, remove K3s
2. `terraform/aws/outputs.tf` - Add EKS and Route53 outputs
3. `terraform/aws/variables.tf` - Add domain_name variable
4. `terraform/aws/environments/dev-eks.tfvars` - New EKS configuration

#### Kubernetes Manifests (4 files)
5. `apps/ingress/base/ingress-nginx-values.yaml` - Change to LoadBalancer type
6. `apps/keycloak/base/statefulset.yaml` - Change storage class to gp3
7. `apps/fineract-redis/base/statefulset.yaml` - Change storage class to gp3
8. `environments/dev/kustomization.yaml` - Remove monitoring apps

#### Automation (2 files)
9. `scripts/deploy-full-stack.sh` - Enhanced with new steps
10. `Makefile` - Add new targets

### Deleted Files/Directories (3 directories)

1. `terraform/aws/modules/k3s/` (entire directory - 15+ files)
2. `apps/monitoring/` (Prometheus, Grafana - 10+ files)
3. `apps/logging/` (Loki, Promtail - 5+ files)

**Total**: ~30 files deleted, saving ~2000 lines of YAML

---

## Success Criteria

### Deployment Completion Checklist

After running `make deploy-dev-eks`, verify:

#### Infrastructure
- [ ] EKS cluster created and healthy
- [ ] 2x t3.large nodes running
- [ ] Cluster Autoscaler installed and configured
- [ ] VPC, subnets, security groups created

#### Networking
- [ ] AWS Network Load Balancer provisioned
- [ ] LoadBalancer DNS retrieved and displayed
- [ ] Route53 hosted zone created
- [ ] DNS A records created (apps.dev, auth.dev)
- [ ] DNS propagation complete (dig commands resolve)

#### Storage
- [ ] EBS CSI driver installed
- [ ] gp3 StorageClass created and set as default
- [ ] PVCs using gp3 (not local-path)

#### Security
- [ ] IRSA roles created (Fineract, Cluster Autoscaler)
- [ ] Service accounts have role annotations
- [ ] Sealed secrets controller installed
- [ ] All secrets created and unsealed successfully

#### Applications
- [ ] ArgoCD deployed and accessible
- [ ] All applications synced (green in ArgoCD UI)
- [ ] Fineract pods running (read, write deployments)
- [ ] Keycloak pod running
- [ ] Web app pod running
- [ ] Redis StatefulSet running

#### TLS/Certificates
- [ ] cert-manager installed
- [ ] Let's Encrypt ClusterIssuer created
- [ ] Certificates issued successfully
- [ ] No browser warnings when accessing URLs

#### Monitoring
- [ ] CloudWatch Container Insights enabled
- [ ] CloudWatch Logs configured
- [ ] Metrics visible in CloudWatch console

#### Access
- [ ] kubectl configured (kubeconfig retrieved)
- [ ] Can access ArgoCD UI at https://apps.dev.yourdomain.com
- [ ] Can access Keycloak at https://auth.dev.yourdomain.com
- [ ] Can access Fineract API at https://apps.dev.yourdomain.com/fineract-provider/api/v1

#### Health Checks
- [ ] `verify-irsa-credentials.sh` passes
- [ ] `smoke-tests.sh` passes
- [ ] Database connectivity verified
- [ ] S3 access verified via IRSA
- [ ] All pods in Ready state

#### Documentation
- [ ] `deployment-info.txt` generated with endpoints
- [ ] Logs saved to `logs/` directory
- [ ] Route53 nameservers documented for registrar update

#### Cost
- [ ] Actual cost matches estimate (~$220-240/month)
- [ ] CloudWatch billing alarm set at $300/month
- [ ] No unexpected charges

---

## Future Enhancements

### Not Included in Phase 1 (Can Be Added Later)

#### Security Enhancements
- [ ] AWS WAF on Application Load Balancer
- [ ] AWS GuardDuty for threat detection
- [ ] AWS Security Hub for compliance
- [ ] VPC Flow Logs for network monitoring
- [ ] AWS Config for configuration compliance

#### High Availability
- [ ] Multi-region RDS read replica
- [ ] Cross-region S3 replication
- [ ] Route53 health checks with failover
- [ ] Multi-cluster setup (active-passive)

#### Advanced Monitoring
- [ ] Custom CloudWatch dashboards
- [ ] PagerDuty/Slack integration
- [ ] Advanced alerting rules
- [ ] APM (Application Performance Monitoring)
- [ ] Distributed tracing (AWS X-Ray)

#### Disaster Recovery
- [ ] Automated RDS snapshot testing
- [ ] Disaster recovery runbooks
- [ ] Backup restoration automation
- [ ] RTO/RPO monitoring

#### Cost Optimization
- [ ] Spot instances for non-prod node groups
- [ ] S3 Intelligent Tiering
- [ ] RDS Reserved Instances for production
- [ ] Compute Savings Plans
- [ ] Automatic resource rightsizing

#### Developer Experience
- [ ] Local development environment (Minikube/Kind)
- [ ] Preview environments for PRs
- [ ] Automated testing in CI/CD
- [ ] Developer self-service portal

### Prioritization Framework

**High Priority** (Next 3 months):
- Security enhancements (WAF, GuardDuty)
- CloudWatch dashboards and alerts
- Disaster recovery documentation

**Medium Priority** (3-6 months):
- High availability (multi-AZ, read replicas)
- Cost optimization (Spot instances, Reserved Instances)
- Advanced monitoring (APM, tracing)

**Low Priority** (6+ months):
- Multi-region setup
- Developer preview environments
- Advanced cost optimization

---

## Appendix

### Glossary

- **EKS**: Amazon Elastic Kubernetes Service (managed Kubernetes)
- **IRSA**: IAM Roles for Service Accounts (pod-level permissions)
- **NLB**: Network Load Balancer (AWS Layer 4 load balancer)
- **ALB**: Application Load Balancer (AWS Layer 7 load balancer)
- **Route53**: AWS DNS service
- **Let's Encrypt**: Free automated certificate authority
- **Sealed Secrets**: Encrypted secrets for GitOps
- **Cluster Autoscaler**: Kubernetes component that auto-scales nodes
- **EBS CSI**: AWS Elastic Block Store Container Storage Interface driver
- **VPC CNI**: AWS Virtual Private Cloud Container Network Interface

### Reference Links

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

### Support

For questions or issues during migration:
1. Check `docs/TROUBLESHOOTING_EKS.md`
2. Review deployment logs in `logs/` directory
3. Run health checks: `make verify-credentials`
4. Check AWS CloudWatch logs for application errors

---

**End of Migration Plan**
