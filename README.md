# Fineract GitOps

> **Production-ready GitOps infrastructure for Apache Fineract on Kubernetes with multi-cloud support**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/cd/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-purple.svg)](https://terraform.io/)

---

## 🎯 Overview

Complete, production-ready GitOps infrastructure for deploying Apache Fineract (open-source core banking) on Kubernetes with enterprise features:

- ✅ **Multi-cloud support** - Deploy on AWS, Azure, GCP, or on-premise with easy provider switching
- ✅ **Terraform infrastructure** - Provision RDS PostgreSQL, S3, Azure Database, Cloud SQL, etc.
- ✅ **Cost optimized** - 60-78% savings in dev environments with managed services
- ✅ **Multi-instance architecture** - Read/write/batch separation for scalability
- ✅ **Multi-environment** - Dev, UAT, Production configurations
- ✅ **Keycloak SSO** - Complete identity and access management with OIDC
- ✅ **Frontend applications** - Admin app, account manager, branch manager, cashier
- ✅ **YAML-based configuration** - All Fineract config as code (no more Excel!)
- ✅ **Sealed Secrets** - Secure secrets management for GitOps
- ✅ **Direct messaging** - SMS/email notifications via SMTP/SMS integration
- ✅ **CI/CD pipelines** - Automated testing and deployment
- ✅ **Comprehensive documentation** - Architecture, operations, development guides

---

## 🚀 Quick Start

> 📋 **Prerequisites:** See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for complete tool installation guide
> 🔧 **Versions:** Check [docs/VERSION_MATRIX.md](docs/VERSION_MATRIX.md) for version requirements

### GitOps Deployment (Recommended)

For step-by-step deployment with validation and user confirmation:

```bash
# Set required environment variables
export KUBECONFIG=~/.kube/config-fineract-dev
export GITHUB_TOKEN="ghp_YourPersonalAccessToken"

# Run interactive deployment
make deploy-gitops
```

**See**: [DEPLOYMENT.md](DEPLOYMENT.md) for complete deployment guide with:
- Prerequisites and environment setup
- Interactive full deployment (all steps with confirmations)
- Individual step execution (run steps independently)
- Troubleshooting and verification

### Essential Guides

- **[Prerequisites Guide](docs/PREREQUISITES.md)** - Complete tool installation and setup
- **[Version Matrix](docs/VERSION_MATRIX.md)** - Authoritative version requirements
- **[Getting Started Guide](docs/GETTING_STARTED.md)** - Complete walkthrough
- **[End-to-End Automation Guide](docs/E2E_AUTOMATION_GUIDE.md)** - Full infrastructure provisioning and deployment
- **[Quick Reference](docs/QUICK_REFERENCE.md)** - Common commands and operations

### High-Level Steps

1.  **Provision Infrastructure**: Use Terraform to provision the necessary cloud infrastructure (VPC, Kubernetes cluster, RDS, etc.).
2.  **Deploy Applications**: Use GitOps deployment (`make deploy-gitops`) or ArgoCD to deploy the Fineract platform and its supporting services.
3.  **Promote Changes**: Use the provided scripts to promote changes from one environment to the next.

---

## ☁️ Provider Abstraction (NEW!)

Deploy Fineract on any cloud or on-premise with flexible provider abstraction:

### Self-Hosted Provider
- PostgreSQL, Redis StatefulSets in Kubernetes
- Perfect for: on-premise, air-gapped, multi-cloud portability
- **Cost**: ~$138/month (dev), ~$700/month (production)

### AWS Managed Provider
- RDS PostgreSQL, S3 (Redis runs in-cluster)
- **Cost**: ~$30/month (dev, **78% savings**), ~$675/month (production)
- Features: Multi-AZ, automated backups, Performance Insights

### Azure Managed Provider
- Azure Database for PostgreSQL, Redis Cache, Blob Storage
- **Cost**: ~$55/month (dev, **60% savings**), ~$710/month (production)
- Features: Zone redundancy, geo-replication

### GCP Managed Provider
- Cloud SQL, Memorystore Redis, Google Cloud Storage
- **Cost**: ~$58/month (dev, **58% savings**), ~$720/month (production)
- Features: Regional HA, Cloud SQL Proxy sidecar

**See:** [AWS Cost Analysis](docs/AWS_COST_ANALYSIS.md) for detailed cost comparison

---

## 📦 What's Included

### Core Banking Platform
- **Fineract** - Multi-instance deployment (read/write/batch)
- **PostgreSQL** - Primary database (self-hosted or RDS/Azure Database/Cloud SQL)
- **Redis** - Caching layer (in-cluster Redis StatefulSet or managed Redis service)
- **Object Storage** - Documents and backups (AWS S3, Azure Blob Storage, or Google Cloud Storage)
- **OAuth2 Proxy** - Reverse proxy with OIDC authentication
- **Keycloak** - SSO and identity management

### Supporting Services
- **Frontend Applications** - Web App, Reporting App, Accounting App
- **Logging & Monitoring** - Loki/Promtail for logs, Prometheus/Grafana for metrics

### Infrastructure
- **ArgoCD** - GitOps continuous deployment
- **Argo Rollouts** - Progressive delivery (canary releases)
- **Sealed Secrets** - Encrypted secrets in Git
- **CI/CD Pipelines** - GitHub Actions for automated testing
- **Terraform Modules** - Provision cloud infrastructure (AWS, Azure, GCP)

---

## 🏗️ Repository Structure

```
fineract-gitops/
├── apps/                      # Application manifests
│   ├── fineract/              # Fineract deployments (read/write/batch)
│   ├── keycloak/              # SSO/identity provider
│   ├── oauth2-proxy/          # Reverse proxy with OIDC
│   ├── fineract-redis/        # Redis StatefulSet for caching
│   ├── web-app/               # Main frontend application
│   ├── accounting-app/        # Accounting module frontend
│   ├── reporting-app/         # Reporting module frontend
│   ├── ingress/               # Ingress resources
│   ├── ingress-nginx/         # NGINX ingress controller
│   ├── network-policies/      # Network security policies
│   ├── cert-manager/          # TLS certificate management
│   ├── sealed-secrets-controller/  # Secrets management
│   ├── logging/               # Loki/Promtail log aggregation
│   └── monitoring/            # Prometheus/Grafana observability
│
├── terraform/                 # Infrastructure as Code
│   └── aws/                   # AWS Terraform modules
│       ├── modules/           # RDS, S3, IAM, IRSA, K8s secrets
│       ├── environments/      # Dev, production configs
│       └── README.md          # Comprehensive Terraform guide
│
├── environments/              # Environment-specific Kustomize overlays
│   ├── dev/                   # Development (AWS managed services)
│   ├── uat/                   # User Acceptance Testing (AWS managed services)
│   └── production/            # Production (AWS managed services)
│
│   # Note: All environments currently use AWS managed services:
│   # - RDS PostgreSQL (managed database)
│   # - In-cluster Redis (for OAuth2 Proxy sessions)
│   # - S3 (document storage)
│
├── argocd/                    # ArgoCD configuration
│   ├── applications/          # Application definitions
│   ├── config/                # ArgoCD settings
│   └── projects/              # ArgoCD projects
│
├── secrets/                   # Sealed Secrets (encrypted)
│   ├── base/                  # Secret templates
│   ├── dev/                   # Dev secrets (encrypted)
│   ├── uat/                   # UAT secrets (encrypted)
│   └── production/            # Production secrets (encrypted)
│
├── operations/                # Operational tooling
│   ├── keycloak-config/       # Keycloak configuration
│   └── disaster-recovery/     # Backup/restore procedures
│
├── docs/                      # Documentation
│   ├── AWS_COST_ANALYSIS.md   # Cost analysis and optimization
│   ├── GETTING_STARTED.md     # Quick start guide
│   ├── ARCHITECTURE.md        # System architecture
│   ├── SECRETS_MANAGEMENT.md  # Secrets and security
│   └── ...                    # 30+ additional docs
│
└── scripts/                   # Utility scripts
    ├── validate-data.py       # Validate YAML configs
    └── ...
```

---

## 🚀 Quick Start

### Option 1: Deploy with Self-Hosted Databases (On-Premise)

**Use when**: Deploying on-premise, air-gapped, or want full control

```bash
# 1. Install Sealed Secrets Controller
kubectl apply -f argocd/applications/system/sealed-secrets-controller.yaml

# 2. Create secrets (see docs/SECRETS_MANAGEMENT.md)
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# 3. Deploy with self-hosted provider
kubectl apply -k environments/dev-self-hosted
```

**Cost**: ~$138/month (dev) - You manage databases

### Option 2: Deploy with AWS Managed Services

**Use when**: Running on AWS EKS, want cost savings and zero DB operations

```bash
# 1. Provision AWS infrastructure with Terraform
cd terraform/aws
cp environments/dev.tfvars terraform.tfvars
# Edit with your VPC, subnet, EKS cluster details
terraform init
terraform apply  # Takes 10-15 minutes

# 2. Deploy Fineract with AWS provider
kubectl apply -k environments/dev-aws
```

**Cost**: ~$30/month (dev, **78% savings**) - AWS manages databases

**See:** [Terraform AWS README](terraform/aws/README.md) for complete guide

### Option 3: Deploy with Azure or GCP

Similar to AWS, but use `environments/dev-azure` or `environments/dev-gcp`

**See:** [Multi-Provider Implementation Plan](docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md) for details on Azure and GCP support

---

## 📚 Documentation

### Key Documents
- **[End-to-End Automation Guide](docs/E2E_AUTOMATION_GUIDE.md)** - The primary guide for using this repository.
- **[Operations Guide](docs/OPERATIONS_GUIDE.md)** - How to manage updates and deployments.
- **[Architecture](docs/ARCHITECTURE.md)** - A detailed overview of the system architecture.
- **[Database Strategy](docs/DATABASE_STRATEGY.md)** - Information about the database setup and data migration.
- **[Progressive Delivery with Argo Rollouts](docs/operations/PROGRESSIVE_DELIVERY.md)** - How to perform canary releases.
- **[Cost Optimization](docs/operations/COST_OPTIMIZATION.md)** - How to manage costs with automated shutdowns.

### CI/CD
- **[CI/CD Integration](docs/operations/CI_CD_INTEGRATION.md)** - How the CI/CD pipeline works.
- **[Terraform CI/CD](docs/operations/TERRAFORM_CI_CD.md)** - The CI/CD workflow for Terraform.

### Other
- **[Secrets Management](docs/SECRETS_MANAGEMENT.md)** - How to manage secrets.
- **[Disaster Recovery Guide](docs/operations/disaster-recovery/DR_GUIDE.md)** - Backup and restore procedures.
- **[Deprecations](DEPRECATIONS.md)** - ⚠️ Deprecated features and migration guides.

---

## 🏛️ Architecture

### Multi-Cloud Provider Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Environment Selection                        │
│  dev-self-hosted / dev-aws / dev-azure / dev-gcp             │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │  Provider Component     │
        │  (Kustomize v1alpha1)   │
        └────────────┬────────────┘
                     │
    ┌────────────────┼────────────────┐
    │                │                │
┌───▼────┐     ┌─────▼─────┐    ┌────▼────┐
│ Self-  │     │   AWS     │    │  Azure  │    ...
│Hosted  │     │ Managed   │    │ Managed │
└────────┘     └───────────┘    └─────────┘
PostgreSQL      RDS              Azure DB
Redis           In-cluster Redis Redis Cache
-               S3               Blob Storage
```

### Multi-Instance Fineract Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                     OAuth2 Proxy (OIDC)                         │
│                   (Reverse Proxy + Authentication)              │
└──────────────┬──────────────────┬──────────────────┬───────────┘
               │                  │                  │
       ┌───────▼──────┐  ┌────────▼────────┐  ┌─────▼─────────┐
       │  Fineract    │  │   Fineract      │  │   Fineract    │
       │    Read      │  │    Write        │  │    Batch      │
       │  (2 replicas)│  │  (2 replicas)   │  │  (1 replica)  │
       └───────┬──────┘  └────────┬────────┘  └────┬──────────┘
               │                  │                 │
               └──────────┬───────┴─────────────────┘
                          │
                   ┌──────▼─────────┐
                   │   PostgreSQL   │
                   │ (Self-hosted   │
                   │  or Managed)   │
                   └────────────────┘
```

---

## 💰 Cost Comparison

### Development Environment

| Provider | Monthly Cost | vs Self-Hosted | Best For |
|----------|--------------|----------------|----------|
| Self-Hosted | **$138** | baseline | On-premise, air-gapped |
| AWS Managed | **$30** | -78% 💰 | EKS users, cost optimization |
| Azure Managed | **$55** | -60% 💰 | AKS users, Azure ecosystem |
| GCP Managed | **$58** | -58% 💰 | GKE users, Google Cloud |

### Production Environment

| Provider | Monthly Cost | Features |
|----------|--------------|----------|
| Self-Hosted | **$700** | Full control, manual HA |
| AWS Managed | **$675** | Multi-AZ, automated backups, zero ops |
| Azure Managed | **$710** | Zone redundancy, geo-replication |
| GCP Managed | **$720** | Regional HA, Google security |

**Key Insight**: Managed services eliminate database operations overhead with similar production costs.

**See**: [AWS Cost Analysis](docs/AWS_COST_ANALYSIS.md) for detailed breakdown

---

## 🔐 Security Features

### Secrets Management
- **Sealed Secrets** - Encrypted secrets safe in Git
- **Environment isolation** - Different secrets per environment
- **CI validation** - Prevents plaintext secret commits
- **Rotation procedures** - Documented secret rotation

### Authentication & Authorization
- **Keycloak SSO** - Centralized identity management
- **OIDC integration** - Modern authentication protocol
- **Role-based access** - Granular permissions
- **User sync service** - Automated user management

### Cloud Security (Managed Providers)
- **IRSA/Workload Identity** - No static credentials in pods
- **Encryption at rest** - KMS/customer-managed keys
- **Encryption in transit** - TLS for all connections
- **Private networking** - Databases in private subnets

---

## 🌍 Multi-Environment Strategy

### Environment Profiles

| Environment | Purpose | Provider Options | Auto-Deploy |
|-------------|---------|------------------|-------------|
| **Dev** | Development & testing | self-hosted / AWS / Azure / GCP | ✅ Yes |
| **UAT** | User acceptance testing | self-hosted / AWS / Azure / GCP | 🔶 Manual |
| **Production** | Live system | self-hosted / AWS / Azure / GCP | 🔶 Manual |

### Switching Providers

```bash
# Switch from self-hosted to AWS managed
kubectl apply -k environments/dev-self-hosted  # Before
kubectl apply -k environments/dev-aws          # After

# Or switch to Azure
kubectl apply -k environments/dev-azure

# Or switch to GCP
kubectl apply -k environments/dev-gcp
```

**See**: [Multi-Provider Implementation Plan](docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md) for migration procedures

---

## 📊 Component Status

| Component | Status | Version | Notes |
|-----------|--------|---------|-------|
| Fineract | ✅ Ready | 1.12.1+ | Multi-instance deployment |
| PostgreSQL | ✅ Ready | 15 | RDS or self-hosted (Terraform modules) |
| Redis | ✅ Ready | 7 | In-cluster StatefulSet |
| Object Storage | ✅ Ready | Latest | AWS S3, Azure Blob, GCS (Terraform) |
| Keycloak | ✅ Ready | 24+ | SSO/IAM with WebAuthn 2FA |
| OAuth2 Proxy | ✅ Ready | Latest | OIDC integration |
| Frontend Apps | ✅ Ready | Latest | Web, Accounting, Reporting apps |
| Logging | ✅ Ready | Latest | Loki/Promtail stack |
| Monitoring | ✅ Ready | Latest | Prometheus/Grafana stack |
| Sealed Secrets | ✅ Ready | v0.27.0 | GitOps secrets management |
| ArgoCD | ✅ Ready | 2.9+ | GitOps CD |
| **Providers** | ✅ Ready | - | **Multi-cloud support (AWS/Azure/GCP)** |
| **Terraform** | ✅ Ready | 1.5+ | **AWS modules complete** |
| Kafka | 🔶 Optional | 3.6 | Future: Event streaming (not in /apps/) |
| Pentaho | 🔶 Optional | 9.x | Future: Advanced reporting (not in /apps/) |

---

## 🛠️ Common Operations

### Deploy with Different Providers

```bash
# Self-hosted (on-premise)
kubectl apply -k environments/dev-self-hosted

# AWS managed services
terraform apply -var-file=terraform/aws/environments/dev.tfvars
kubectl apply -k environments/dev-aws

# Azure managed services
kubectl apply -k environments/dev-azure

# GCP managed services
kubectl apply -k environments/dev-gcp
```

### View Logs
```bash
kubectl logs -n fineract-dev -l app=fineract-write -f
```

### Restart Service
```bash
kubectl rollout restart deployment/fineract-write -n fineract-dev
```

### Check Connection to Managed Services
```bash
# Check RDS connection
kubectl get secret rds-connection -n fineract-dev -o yaml

# Check pod environment
kubectl describe pod -n fineract-dev -l app=fineract-read | grep -A20 "Environment:"
```

---

## 🤝 Contributing

This is an internal GitOps repository. For contributions:

1. **Install Git Hooks** (first time only):
   ```bash
   ./scripts/install-git-hooks.sh
   ```
   This enables local validation before commits and pushes.

2. Create feature branch
3. Make changes
4. Test in dev environment (choose your provider)
5. Create pull request
6. Get approval
7. Merge to main

### Git Hooks

Git hooks provide immediate feedback during development:

**Pre-commit** (runs before `git commit`):
- ✅ Secret detection (blocks plain text secrets)
- ✅ Block `:latest` tags in production files
- ✅ Kustomize build validation
- ✅ YAML linting (if yamllint installed)

**Pre-push** (runs before `git push`):
- ✅ ArgoCD application validation

**Installation**:
```bash
./scripts/install-git-hooks.sh
```

**Bypass** (not recommended):
```bash
git commit --no-verify
git push --no-verify
```

**Note**: GitHub Actions will still enforce these checks even if bypassed locally.

---

## 📜 License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

---

## 🆘 Support

### Documentation

**Getting Started:**
- [Getting Started](docs/GETTING_STARTED.md) - Setup guide
- [Quick Reference](docs/QUICK_REFERENCE.md) - Common commands
- [Deployment Guide](DEPLOYMENT.md) - Complete deployment guide

**Secrets & Security:**
- [Secrets Management](docs/SECRETS_MANAGEMENT.md) - Complete secrets strategy
- [Sealed Secrets DR Runbook](docs/SEALED_SECRETS_DR_RUNBOOK.md) - ⚡ Emergency recovery quick reference
- [Sealed Secrets Deployment Guide](docs/SEALED_SECRETS_DEPLOYMENT_GUIDE.md) - Initial deployment

**Disaster Recovery:**
- [Disaster Recovery Guide](docs/DISASTER_RECOVERY.md) - Comprehensive DR procedures
- [Multi-Region DR Strategy](docs/MULTI_REGION_DR_STRATEGY.md) - Cross-region failover

**Multi-Cloud:**
- [Multi-Provider Implementation](docs/MULTI_PROVIDER_IMPLEMENTATION_PLAN.md) - Multi-cloud deployment
- [Operations Runbooks](docs/operations/) - Operational procedures

### Common Issues
1. **Pods not starting** - Check secrets are created (RDS for managed deployments)
2. **Can't connect to RDS** - Check security groups and IRSA configuration
3. **Terraform fails** - Verify VPC, subnet, and EKS OIDC provider configuration
4. **Authentication failing** - Verify Keycloak configuration
5. **High costs** - Review [Cost Optimization Guide](docs/operations/COST_OPTIMIZATION.md) and [AWS Cost Analysis](docs/AWS_COST_ANALYSIS.md)

### Resources
- [Fineract Documentation](https://fineract.apache.org/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## 📈 Roadmap

### Completed ✅
- [x] Multi-cloud provider abstraction
- [x] AWS Terraform modules (RDS, S3, IRSA)
- [x] Cost optimization (60-78% savings in dev)
- [x] Provider selection guide

### In Progress 🚧
- [ ] Azure Terraform modules
- [ ] GCP Terraform modules
- [ ] Monitoring stack (Prometheus/Grafana)
- [ ] Backup automation (Velero)

### Planned 📋
- [ ] Disaster recovery procedures
- [ ] Performance testing
- [ ] Security hardening (Falco, OPA)
- [ ] Multi-region deployment
- [ ] Advanced observability (Loki, Tempo)


To Trust the Certificate in Your Browser

  On macOS:
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/fineract-internal-ca.crt

---

**Made with ❤️ for Production-Ready Core Banking**

**🆕 Now with Multi-Cloud Support!** Deploy on AWS, Azure, GCP, or On-Premise
