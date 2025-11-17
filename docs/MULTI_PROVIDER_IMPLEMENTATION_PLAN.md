# Multi-Provider Implementation Plan: AWS EKS and k3s Support

## Executive Summary

This document outlines the implementation plan for adding support for both AWS EKS and k3s Kubernetes providers to the Fineract GitOps repository. The goal is to enable deployment flexibility while maintaining simplicity and avoiding duplication.

## Overview

### Objectives
- Support both AWS EKS and k3s deployments for each environment (dev, uat, production)
- Terraform provisions complete infrastructure for both providers (including clusters)
- Maintain single codebase with minimal duplication
- Use sealed secrets for both providers
- Keep implementation simple and maintainable

### Branch Strategy
- Implementation in new branch: `feature/multi-provider-support`
- Keep main/develop branches stable during development
- Test thoroughly before merging

## Architecture Design

### Directory Structure

```
environments/
├── base/                    # Common environment configs
│   ├── dev/
│   ├── uat/
│   └── production/
├── providers/               # Provider-specific patches
│   ├── eks/
│   │   ├── kustomization.yaml
│   │   ├── storageclass-patch.yaml
│   │   ├── serviceaccount-patch.yaml
│   │   └── ingress-patch.yaml
│   └── k3s/
│       ├── kustomization.yaml
│       ├── storageclass-patch.yaml
│       └── ingress-patch.yaml
└── overlays/                # Final combinations
    ├── dev-eks/
    ├── dev-k3s/
    ├── uat-eks/
    ├── uat-k3s/
    ├── production-eks/
    └── production-k3s/
```

## Phase 1: Terraform Infrastructure

### 1.1 EKS Module Structure

Create new EKS module at `terraform/aws/modules/eks/`:

```hcl
# modules/eks/main.tf
resource "aws_eks_cluster" "main" {
  name     = "${var.project}-${var.environment}-eks"
  version  = var.kubernetes_version  # e.g., "1.29"

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs    = var.allowed_cidr_blocks
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-${var.environment}-ng"

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  instance_types = var.node_instance_types

  # Use Spot instances for dev/uat
  capacity_type = var.environment == "production" ? "ON_DEMAND" : "SPOT"
}
```

### 1.2 IRSA Configuration

```hcl
# modules/eks/irsa.tf
module "fineract_irsa" {
  source = "./irsa"

  cluster_oidc_issuer_url = aws_eks_cluster.main.identity[0].oidc[0].issuer
  namespace               = "fineract-${var.environment}"
  service_account_name    = "fineract"

  iam_policy_arns = [
    aws_iam_policy.fineract_rds.arn,
    aws_iam_policy.fineract_s3.arn
  ]
}
```

### 1.3 Environment-Specific Configurations

```hcl
# terraform/aws/environments/dev-eks.tfvars
deployment_type = "eks"
kubernetes_version = "1.29"
node_instance_types = ["t3.medium"]
node_desired_size = 2
node_min_size = 1
node_max_size = 4
capacity_type = "SPOT"  # Cost optimization

# terraform/aws/environments/dev-k3s.tfvars
deployment_type = "k3s"
k3s_version = "v1.29.0+k3s1"
instance_type = "t3.large"
server_count = 1
agent_count = 2

# terraform/aws/environments/production-eks.tfvars
deployment_type = "eks"
kubernetes_version = "1.29"
node_instance_types = ["m5.xlarge", "m5.2xlarge"]
node_desired_size = 3
node_min_size = 3
node_max_size = 10
capacity_type = "ON_DEMAND"  # Stability

# terraform/aws/environments/production-k3s.tfvars
deployment_type = "k3s"
k3s_version = "v1.29.0+k3s1"
instance_type = "t3.xlarge"
server_count = 3  # HA setup
agent_count = 3
```

### 1.4 Main Terraform Configuration

```hcl
# terraform/aws/main.tf
locals {
  using_eks = var.deployment_type == "eks"
  using_k3s = var.deployment_type == "k3s"
}

# VPC - Used by both
module "vpc" {
  source = "./modules/vpc"
  # Configuration...
}

# EKS Cluster (full provisioning)
module "eks" {
  count  = local.using_eks ? 1 : 0
  source = "./modules/eks"

  project              = var.project
  environment          = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  kubernetes_version  = var.kubernetes_version
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  capacity_type       = var.capacity_type
}

# K3s Cluster
module "k3s" {
  count  = local.using_k3s ? 1 : 0
  source = "./modules/k3s"

  project         = var.project
  environment     = var.environment
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  instance_type  = var.instance_type
  server_count   = var.server_count
  agent_count    = var.agent_count
  k3s_version    = var.k3s_version
}

# RDS - Shared by both
module "rds" {
  source = "./modules/rds"
  # Configuration...
}

# S3 - Shared by both
module "s3" {
  source = "./modules/s3"
  # Configuration...
}

# Outputs
output "kubeconfig_command" {
  value = local.using_eks ?
    "aws eks update-kubeconfig --name ${module.eks[0].cluster_name}" :
    "scp ubuntu@${module.k3s[0].server_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-${var.environment}-k3s"
}
```

## Phase 2: Kubernetes Manifests

### 2.1 Base Environment Configuration

Move existing environment configs to `environments/base/`:

```yaml
# environments/base/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: fineract-dev

resources:
  - namespace.yaml
  - ../../apps/fineract/base
  - ../../apps/fineract-redis/base
  - ../../apps/keycloak/base
  - ../../apps/oauth2-proxy/base
  - ../../apps/ingress/base
  - ../../apps/sealed-secrets-controller/base

patches:
  - path: scale-down-replicas.yaml
    target:
      kind: Deployment

commonLabels:
  environment: dev
```

### 2.2 Provider-Specific Patches

#### EKS Provider Patches

```yaml
# environments/providers/eks/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

patches:
  - path: storageclass-patch.yaml
    target:
      kind: StatefulSet
  - path: serviceaccount-patch.yaml
    target:
      kind: ServiceAccount
      name: fineract
  - path: ingress-patch.yaml
    target:
      kind: Ingress

commonLabels:
  provider: aws-eks
```

```yaml
# environments/providers/eks/storageclass-patch.yaml
- op: add
  path: /spec/volumeClaimTemplates/0/spec/storageClassName
  value: gp3
```

```yaml
# environments/providers/eks/serviceaccount-patch.yaml
- op: add
  path: /metadata/annotations
  value:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/fineract-${ENVIRONMENT}
```

#### K3s Provider Patches

```yaml
# environments/providers/k3s/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

patches:
  - path: storageclass-patch.yaml
    target:
      kind: StatefulSet

resources:
  - metallb-config.yaml  # For LoadBalancer services

commonLabels:
  provider: k3s
```

```yaml
# environments/providers/k3s/storageclass-patch.yaml
- op: add
  path: /spec/volumeClaimTemplates/0/spec/storageClassName
  value: local-path
```

### 2.3 Environment Overlays

```yaml
# environments/overlays/dev-eks/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base/dev
  - ../../providers/eks
```

```yaml
# environments/overlays/dev-k3s/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base/dev
  - ../../providers/k3s
```

## Phase 3: ArgoCD Configuration

### 3.1 ApplicationSet for Multi-Provider

```yaml
# argocd/applicationsets/fineract-multienv.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: fineract-environments
  namespace: argocd
spec:
  generators:
  - matrix:
      generators:
      - list:
          elements:
          - env: dev
            autoSync: true
            branch: develop
          - env: uat
            autoSync: false
            branch: main
          - env: production
            autoSync: false
            branch: main
      - list:
          elements:
          - provider: eks
          - provider: k3s
  template:
    metadata:
      name: 'fineract-{{env}}-{{provider}}'
      namespace: argocd
    spec:
      project: fineract-{{env}}
      source:
        repoURL: https://github.com/your-org/fineract-gitops
        targetRevision: '{{branch}}'
        path: 'environments/overlays/{{env}}-{{provider}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'fineract-{{env}}'
      syncPolicy:
        automated:
          enabled: '{{autoSync}}'
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

## Phase 4: Scripts and Automation

### 4.1 Unified Deployment Script

```bash
#!/bin/bash
# scripts/deploy-cluster.sh

set -e

ENVIRONMENT=$1
PROVIDER=${2:-eks}

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <environment> [provider]"
    echo "Example: $0 dev eks"
    echo "Example: $0 production k3s"
    exit 1
fi

echo "🚀 Deploying $ENVIRONMENT with $PROVIDER provider"

# 1. Terraform deployment
echo "📦 Provisioning infrastructure..."
cd terraform/aws
terraform init -backend-config="key=fineract-${ENVIRONMENT}-${PROVIDER}.tfstate"
terraform workspace select $ENVIRONMENT-$PROVIDER || terraform workspace new $ENVIRONMENT-$PROVIDER
terraform apply -var-file=environments/${ENVIRONMENT}-${PROVIDER}.tfvars -auto-approve

# 2. Get kubeconfig
echo "🔐 Configuring kubectl..."
if [ "$PROVIDER" = "eks" ]; then
    CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
    aws eks update-kubeconfig --name $CLUSTER_NAME
    export KUBECONFIG=~/.kube/config
else
    K3S_IP=$(terraform output -raw k3s_server_ip)
    scp ubuntu@${K3S_IP}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-${ENVIRONMENT}-k3s
    sed -i "s/127.0.0.1/${K3S_IP}/g" ~/.kube/config-${ENVIRONMENT}-k3s
    export KUBECONFIG=~/.kube/config-${ENVIRONMENT}-k3s
fi

# 3. Install sealed-secrets controller
echo "🔒 Installing sealed-secrets controller..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# 4. Wait for sealed-secrets controller
echo "⏳ Waiting for sealed-secrets controller..."
kubectl wait --for=condition=available --timeout=120s deployment/sealed-secrets-controller -n kube-system

# 5. Seal and apply secrets
echo "🔑 Creating sealed secrets..."
./scripts/seal-terraform-secrets.sh $ENVIRONMENT

# 6. Deploy via ArgoCD
echo "🚢 Installing ArgoCD..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 7. Wait for ArgoCD
echo "⏳ Waiting for ArgoCD..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# 8. Deploy app-of-apps
echo "📱 Deploying applications..."
kubectl apply -f argocd/bootstrap/${ENVIRONMENT}-${PROVIDER}/app-of-apps.yaml

echo "✅ Deployment complete!"
echo ""
echo "📊 Access ArgoCD UI:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "🔑 Get ArgoCD admin password:"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

### 4.2 Provider Switch Script

```bash
#!/bin/bash
# scripts/switch-provider.sh

ENVIRONMENT=$1
FROM_PROVIDER=$2
TO_PROVIDER=$3

echo "🔄 Switching $ENVIRONMENT from $FROM_PROVIDER to $TO_PROVIDER"

# 1. Backup current state
kubectl get all -n fineract-${ENVIRONMENT} -o yaml > backup-${ENVIRONMENT}-${FROM_PROVIDER}.yaml

# 2. Export secrets (sealed secrets remain the same)
kubectl get sealedsecrets -n fineract-${ENVIRONMENT} -o yaml > sealed-secrets-${ENVIRONMENT}.yaml

# 3. Deploy new infrastructure
./scripts/deploy-cluster.sh $ENVIRONMENT $TO_PROVIDER

# 4. Restore sealed secrets
kubectl apply -f sealed-secrets-${ENVIRONMENT}.yaml

echo "✅ Provider switch complete!"
```

## Phase 5: Cost Analysis

### Monthly Cost Comparison

| Component | Dev (EKS) | Dev (k3s) | Prod (EKS) | Prod (k3s) |
|-----------|-----------|-----------|------------|------------|
| Control Plane | $72 | $0 | $72 | $0 |
| Compute (Spot/On-Demand) | $30 | $120 | $450 | $360 |
| RDS PostgreSQL | $12 | $12 | $180 | $180 |
| S3 Storage | $5 | $5 | $50 | $50 |
| NAT Gateway | $45 | $0 | $45 | $0 |
| Load Balancer | $25 | $0 | $25 | $0 |
| **Total Monthly** | **$189** | **$137** | **$822** | **$590** |
| **Annual Total** | **$2,268** | **$1,644** | **$9,864** | **$7,080** |

### Cost Optimization Strategies

#### For EKS:
- Use Spot instances for non-production (70% cost savings)
- Use Graviton (ARM) instances where possible (20% savings)
- Enable cluster autoscaler to scale down during off-hours
- Use Reserved Instances for production nodes (up to 40% savings)

#### For k3s:
- Use single-node setup for dev environments
- Implement auto-shutdown for dev/test environments
- Use local storage instead of EBS where appropriate
- Consider using t3a (AMD) instances for additional savings

## Phase 6: Testing Strategy

### 6.1 Provider Compatibility Testing

```bash
#!/bin/bash
# scripts/test-provider-compatibility.sh

ENVIRONMENT=$1

echo "🧪 Testing provider compatibility for $ENVIRONMENT"

# Test both providers
for PROVIDER in eks k3s; do
    echo "Testing $PROVIDER..."

    # Deploy
    ./scripts/deploy-cluster.sh $ENVIRONMENT $PROVIDER

    # Run tests
    kubectl apply -f tests/smoke-test.yaml
    kubectl wait --for=condition=complete job/smoke-test -n fineract-${ENVIRONMENT}

    # Validate
    if kubectl logs job/smoke-test -n fineract-${ENVIRONMENT} | grep -q "PASSED"; then
        echo "✅ $PROVIDER tests passed"
    else
        echo "❌ $PROVIDER tests failed"
        exit 1
    fi
done

echo "✅ All provider compatibility tests passed!"
```

### 6.2 Sealed Secrets Validation

```yaml
# tests/sealed-secret-test.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sealed-secret-test
spec:
  template:
    spec:
      serviceAccountName: fineract
      containers:
      - name: test
        image: amazon/aws-cli:latest
        command:
        - sh
        - -c
        - |
          # Test database connection
          if psql "$DATABASE_URL" -c "SELECT 1"; then
            echo "✅ Database connection successful"
          else
            echo "❌ Database connection failed"
            exit 1
          fi

          # Test S3 access
          if aws s3 ls s3://$DOCUMENTS_BUCKET; then
            echo "✅ S3 access successful"
          else
            echo "❌ S3 access failed"
            exit 1
          fi

          echo "PASSED"
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: fineract-db-credentials
              key: jdbc-url
        - name: DOCUMENTS_BUCKET
          valueFrom:
            secretKeyRef:
              name: s3-connection
              key: documents-bucket
      restartPolicy: Never
```

## Phase 7: Documentation

### 7.1 README Updates

Add to main README.md:

```markdown
## Provider Support

This repository supports deployment to both AWS EKS and k3s clusters:

- **AWS EKS**: Managed Kubernetes with full AWS integration
- **k3s**: Lightweight Kubernetes for cost-effective deployments

### Quick Start

Deploy to AWS EKS:
```bash
./scripts/deploy-cluster.sh dev eks
```

Deploy to k3s:
```bash
./scripts/deploy-cluster.sh dev k3s
```

### Provider Selection Guide

| Use Case | Recommended Provider | Reason |
|----------|---------------------|---------|
| Production | AWS EKS | Managed control plane, auto-scaling, AWS integration |
| Development | k3s | Lower cost, faster provisioning |
| Testing/CI | k3s | Ephemeral environments, cost optimization |
| High Availability | AWS EKS | Multi-AZ support, managed updates |
| Edge/On-Premise | k3s | Lightweight, runs anywhere |
```

### 7.2 Migration Guide

```markdown
# Migrating Between Providers

## From k3s to EKS

1. Backup your data:
   ```bash
   ./scripts/backup-environment.sh production k3s
   ```

2. Deploy EKS infrastructure:
   ```bash
   ./scripts/deploy-cluster.sh production eks
   ```

3. Restore data:
   ```bash
   ./scripts/restore-environment.sh production eks
   ```

## From EKS to k3s

Follow the same process in reverse, ensuring you have adequate resources for k3s.
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Create feature branch
- [ ] Implement EKS Terraform module
- [ ] Update main Terraform configuration
- [ ] Test infrastructure provisioning

### Week 2: Kubernetes Manifests
- [ ] Restructure environments directory
- [ ] Create provider-specific patches
- [ ] Implement overlay structure
- [ ] Test manifest generation

### Week 3: Integration
- [ ] Update ArgoCD configurations
- [ ] Implement deployment scripts
- [ ] Create testing framework
- [ ] Document changes

### Week 4: Testing & Refinement
- [ ] Full end-to-end testing
- [ ] Performance comparison
- [ ] Cost validation
- [ ] Documentation completion

## Success Criteria

- [ ] Both EKS and k3s can be provisioned via Terraform
- [ ] All applications deploy successfully on both providers
- [ ] Sealed secrets work on both platforms
- [ ] Provider switching is documented and tested
- [ ] Cost savings demonstrated for appropriate use cases
- [ ] No duplication of application configurations
- [ ] Clear documentation for operations team

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Storage incompatibility | High | Test StorageClass patches thoroughly |
| IRSA vs Instance Profile | Medium | Clear documentation, automated detection |
| Network policy differences | Low | Test on both CNI implementations |
| Cost overrun during testing | Medium | Use dev environment, implement auto-shutdown |
| Sealed secrets compatibility | High | Validated that both providers support it |

## Notes

- Both providers will use sealed secrets (confirmed by user)
- Implementation will be in a separate branch
- Testing will start with dev environment
- Production deployment only after full validation

---

**Document Version**: 1.0
**Last Updated**: 2025-11-11
**Author**: Claude (with user collaboration)
**Status**: Ready for Implementation