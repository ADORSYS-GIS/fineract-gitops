# Environments - Kustomize Environment Configurations

This directory contains Kustomize environment configurations that combine deployment profiles with provider choices and environment-specific settings.

---

## Overview

The environments directory supports a flexible deployment model with THREE dimensions:

1. **Environment** (dev, uat, production) - Lifecycle stage
2. **Provider** (self-hosted, AWS, Azure, GCP) - Infrastructure backend
3. **Profile** (minimal, standard, full) - Service deployment level

### Architecture

```
┌─────────────────────────────────────────────────────┐
│         Environment Selection                       │
│  (dev / uat / production) x (provider) x (profile) │
└────────────────┬────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
    ┌───▼───┐        ┌────▼────┐
    │ Base  │        │ Provider│
    │ Apps  │        │Component│
    └───────┘        └─────────┘
```

---

## Directory Structure

```
environments/
├── README.md                      # This file
│
├── # Deployment Profiles (Service Level)
├── minimal/                       # PostgreSQL only
├── standard/                      # PostgreSQL + Redis + MinIO
├── full/                          # All services (+ Kafka, Pentaho)
│
├── # Environment Stages (Lifecycle)
├── dev/                           # Development (original, self-hosted)
├── uat/                           # User Acceptance Testing
├── production/                    # Production
│
└── # Environment + Provider Combinations
    ├── dev-self-hosted/           # Dev with self-hosted databases
    ├── dev-aws/                   # Dev with AWS managed services
    ├── dev-azure/                 # Dev with Azure managed services
    ├── dev-gcp/                   # Dev with GCP managed services
    ├── production-aws/            # Production with AWS managed
    ├── production-azure/          # Production with Azure managed
    └── production-gcp/            # Production with GCP managed
```

---

## Deployment Dimensions Explained

### 1. Deployment Profiles (Service Level)

**What they are**: Different sets of services you can deploy

#### Minimal Profile
**Path**: `environments/minimal/`

**Services included**:
- ✅ Fineract (read/write/batch)
- ✅ PostgreSQL database
- ✅ Apache Gateway
- ✅ Keycloak SSO
- ❌ Redis (no caching)
- ❌ MinIO (no object storage)
- ❌ Kafka (no event streaming)
- ❌ Pentaho (no reporting)

**Best for**:
- Quick testing
- Minimal resource usage
- Learning/experimentation
- CI/CD testing

**Monthly cost**: ~$50-70

#### Standard Profile
**Path**: `environments/standard/`

**Services included**:
- ✅ Fineract (read/write/batch)
- ✅ PostgreSQL database
- ✅ Redis cache
- ✅ MinIO object storage
- ✅ Apache Gateway
- ✅ Keycloak SSO
- ❌ Kafka (no event streaming)
- ❌ Pentaho (no reporting)

**Best for**:
- Development environments
- Standard production deployments
- Most use cases

**Monthly cost**: ~$100-150

#### Full Profile
**Path**: `environments/full/`

**Services included**:
- ✅ Fineract (read/write/batch)
- ✅ PostgreSQL database
- ✅ Redis cache
- ✅ MinIO object storage
- ✅ Apache Gateway
- ✅ Keycloak SSO
- ✅ Kafka event streaming
- ✅ Pentaho reporting

**Best for**:
- Full-featured production
- Event-driven architectures
- Advanced reporting needs

**Monthly cost**: ~$150-250

---

### 2. Environment Stages (Lifecycle)

**What they are**: Different lifecycle stages of your deployment

#### dev
**Path**: `environments/dev/`

**Characteristics**:
- Auto-sync enabled
- Lower resource limits
- Test data allowed
- Relaxed security
- Verbose logging
- Fast iteration

**Target**: Developer testing and debugging

#### uat
**Path**: `environments/uat/`

**Characteristics**:
- Manual sync
- Production-like resources
- Sanitized real data
- Standard security
- Standard logging
- Integration testing

**Target**: User acceptance testing and staging

#### production
**Path**: `environments/production/`

**Characteristics**:
- Manual sync with approval
- Production resources
- Real data
- Strict security
- Audit logging
- HA configuration

**Target**: Live production system

---

### 3. Providers (Infrastructure Backend)

**What they are**: Where your databases and storage run

See [Providers README](../providers/README.md) for details on:
- `self-hosted` - Databases run in Kubernetes
- `aws-managed` - AWS RDS, ElastiCache, S3
- `azure-managed` - Azure Database, Cache, Blob Storage
- `gcp-managed` - Cloud SQL, Memorystore, GCS

---

## Understanding the Directory Layout

### Original Environments

```
environments/
├── dev/           # Original dev (self-hosted databases)
├── uat/           # UAT environment (self-hosted)
└── production/    # Production (self-hosted)
```

**These are**: Complete environment configurations using self-hosted databases

**Use when**: Deploying on-premise or want self-hosted databases

---

### Deployment Profiles

```
environments/
├── minimal/       # Minimal service set
├── standard/      # Standard service set
└── full/          # Full service set
```

**These are**: Reusable profiles that can be referenced by environments

**Use when**: Building custom environment configs or choosing service level

---

### Provider-Specific Environments

```
environments/
├── dev-self-hosted/     # Dev + Self-Hosted
├── dev-aws/             # Dev + AWS Managed
├── dev-azure/           # Dev + Azure Managed
├── dev-gcp/             # Dev + GCP Managed
├── production-aws/      # Production + AWS
├── production-azure/    # Production + Azure
└── production-gcp/      # Production + GCP
```

**These are**: Complete environments that combine environment stage + provider

**Use when**: Deploying with cloud-managed services

---

## How to Choose

### Decision Tree

```
1. What lifecycle stage?
   ├─ Development → dev
   ├─ Testing → uat
   └─ Live → production

2. What infrastructure?
   ├─ On-premise/air-gapped → dev/uat/production (self-hosted)
   ├─ AWS EKS → dev-aws/production-aws
   ├─ Azure AKS → dev-azure/production-azure
   └─ Google GKE → dev-gcp/production-gcp

3. What services needed?
   ├─ Core only → Use minimal profile
   ├─ Standard features → Use standard profile (default)
   └─ All features → Use full profile
```

### Example Scenarios

**Scenario 1: Local development with minimal services**
```bash
kubectl apply -k environments/minimal
```

**Scenario 2: On-premise production with all features**
```bash
kubectl apply -k environments/production  # Uses standard profile by default
# Or explicitly use full:
kubectl apply -k environments/full
```

**Scenario 3: AWS EKS development with managed services**
```bash
# 1. Provision AWS infrastructure
cd terraform/aws
terraform apply -var-file=environments/dev.tfvars

# 2. Deploy Fineract
cd ../..
kubectl apply -k environments/dev-aws
```

**Scenario 4: Azure AKS production with managed services**
```bash
# 1. Provision Azure infrastructure
cd terraform/azure
terraform apply -var-file=environments/production.tfvars

# 2. Deploy Fineract
cd ../..
kubectl apply -k environments/production-azure
```

---

## Environment Configuration Files

Each environment directory typically contains:

```
environments/<env-name>/
├── kustomization.yaml          # Main Kustomize config
├── namespace.yaml              # Namespace definition (optional)
├── resource-limits.yaml        # ResourceQuota/LimitRange
├── fineract-image-version.yaml # Fineract image tag
├── patches/                    # Environment-specific patches
│   ├── fineract-env-overrides.yaml
│   ├── replica-counts.yaml
│   └── resource-adjustments.yaml
└── sealed-secrets/             # Environment secrets (if inline)
```

### kustomization.yaml Structure

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Namespace for all resources
namespace: fineract-dev

# Base applications
resources:
  - ../../apps/fineract
  - ../../apps/apache-gateway
  - ../../apps/keycloak
  # ... more apps

# Provider selection
components:
  - ../../providers/aws-managed  # Or self-hosted, azure-managed, gcp-managed

# Environment-specific patches
patchesStrategicMerge:
  - patches/fineract-env-overrides.yaml
  - patches/replica-counts.yaml

# Image versions
images:
  - name: apache/fineract
    newTag: 1.12.1
```

---

## Common Operations

### Deploy Environment

```bash
# Self-hosted development
kubectl apply -k environments/dev

# AWS-managed development
kubectl apply -k environments/dev-aws

# Production with Azure
kubectl apply -k environments/production-azure
```

### View Generated Manifests

```bash
# Preview what will be deployed
kubectl kustomize environments/dev

# Save to file
kubectl kustomize environments/dev > preview.yaml
```

### Update Environment

```bash
# Update image version
cd environments/dev
vi fineract-image-version.yaml  # Change tag
kubectl apply -k .

# Or use ArgoCD
kubectl apply -f ../../argocd/applications/dev/fineract.yaml
```

### Switch Providers

```bash
# Edit kustomization.yaml
cd environments/dev
vi kustomization.yaml

# Change:
#  components:
#    - ../../providers/self-hosted
# To:
#  components:
#    - ../../providers/aws-managed

kubectl apply -k .
```

---

## Environment Variables

Each environment sets different variables:

### Development
```yaml
FINERACT_NODE_ID: "1"
FINERACT_LOG_LEVEL: "DEBUG"
SPRING_PROFILES_ACTIVE: "dev"
```

### UAT
```yaml
FINERACT_NODE_ID: "1"
FINERACT_LOG_LEVEL: "INFO"
SPRING_PROFILES_ACTIVE: "uat"
```

### Production
```yaml
FINERACT_NODE_ID: "1"
FINERACT_LOG_LEVEL: "WARN"
SPRING_PROFILES_ACTIVE: "production"
```

---

## Resource Allocation

### Development
```yaml
CPU: 500m-1000m per pod
Memory: 1Gi-2Gi per pod
Replicas: 1 per service
```

### UAT
```yaml
CPU: 1000m-2000m per pod
Memory: 2Gi-4Gi per pod
Replicas: 2 per service
```

### Production
```yaml
CPU: 2000m-4000m per pod
Memory: 4Gi-8Gi per pod
Replicas: 2-3 per service
```

---

## Best Practices

### 1. Environment Isolation
- Use separate namespaces for each environment
- Isolate with NetworkPolicies
- Use separate sealed secrets
- Different resource quotas

### 2. Naming Conventions
- Namespace: `fineract-{env}` (e.g., `fineract-dev`)
- Resources: `{service}-{instance}` (e.g., `fineract-read`)
- Secrets: `{service}-{type}` (e.g., `postgresql-credentials`)

### 3. Version Control
- Pin image versions in production
- Use `latest` only in dev
- Track version changes in Git
- Document version compatibility

### 4. Configuration Management
- Use patches for environment differences
- Keep base configs DRY
- Document all overrides
- Validate with `kubectl kustomize`

---

## Troubleshooting

### Issue: Wrong provider deployed

**Solution**:
```bash
# Check kustomization.yaml components section
cat environments/dev-aws/kustomization.yaml | grep -A5 components

# Should show:
components:
  - ../../providers/aws-managed
```

### Issue: Resources not found

**Solution**:
```bash
# Validate kustomization
kubectl kustomize environments/dev

# Check for errors
kubectl apply -k environments/dev --dry-run=client
```

### Issue: Namespace conflicts

**Solution**:
```bash
# Ensure namespace in kustomization.yaml
cat environments/dev/kustomization.yaml | grep namespace

# Create namespace first if needed
kubectl create namespace fineract-dev
```

---

## Related Documentation

- **[Providers README](../providers/README.md)** - Provider abstraction details
- **[Multi-Provider Implementation](../docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md)** - Multi-cloud deployment
- **[AWS Cost Analysis](../docs/AWS_COST_ANALYSIS.md)** - Cost comparison and optimization
- **[Getting Started](../docs/GETTING_STARTED.md)** - Deployment walkthrough
- **[Deployment Guide](../DEPLOYMENT.md)** - Interactive full deployment

---

## Migration Guide

### From self-hosted to AWS managed

```bash
# 1. Deploy new environment alongside existing
kubectl apply -k environments/dev-aws

# 2. Migrate data
# ... (see provider migration docs)

# 3. Switch traffic
# ... (update ingress/service)

# 4. Decommission old environment
kubectl delete -k environments/dev
```

---

**Last Updated:** 2025-10-28
**Total Environments:** 14 (3 stages × 4 providers + 3 profiles)
**Default Profile:** Standard
**Recommended**: Use provider-specific environments (e.g., dev-aws) for clarity
