# Documentation Index

> **Comprehensive guide to all documentation in the Fineract GitOps repository**

This index helps you find the right documentation for your needs, whether you're getting started, deploying to production, or developing new features.

---

## 📑 Quick Navigation

| I want to... | Go to... |
|--------------|----------|
| Get started quickly | [Getting Started Guide](#getting-started) |
| Deploy to AWS/Azure/GCP | [Quick-Start Guides](#quick-start-guides) |
| Manage secrets securely | [Secrets Management](#security) |
| Set up databases | [Database Guide](#database) |
| Understand architecture | [Architecture Docs](#architecture) |
| Set up CI/CD pipelines | [CI/CD Integration](#deployment--operations) |
| Develop frontend apps | [Frontend Implementation Guide](#development) |
| Troubleshoot issues | [Operations & Runbooks](#deployment--operations) |

---

## 📚 Documentation by Category

### Getting Started

Essential guides for new users and initial setup.

| Document | Description | Audience |
|----------|-------------|----------|
| **[Getting Started Guide](GETTING_STARTED.md)** | Complete walkthrough from prerequisites to first deployment | 🆕 New users |
| **[Quick Reference](QUICK_REFERENCE.md)** | Common commands and operations cheat sheet | 🔄 All users |
| **[Main README](../README.md)** | Repository overview, architecture, and component status | 📖 Everyone |
| **[Deployment Guide](../DEPLOYMENT.md)** | Interactive full deployment with validation steps | 🎯 Operators |

**Start here:** If this is your first time, read [Getting Started Guide](GETTING_STARTED.md) → [Deployment Guide](../DEPLOYMENT.md) → Deploy!

---

### Quick-Start Guides

Step-by-step deployment guides for different scenarios.

| Document | Description | Audience |
|----------|-------------|----------|
| **[Quick Deploy Guide](guides/QUICK_DEPLOY.md)** | Minimal commands deployment after Terraform | 🚀 Operators |
| **[AWS Quick Start](guides/QUICKSTART-AWS.md)** | Deploy on AWS EKS with managed services | ☁️ AWS users |
| **[AWS K3s Quick Start](guides/QUICKSTART-AWS-K3S.md)** | Cost-optimized K3s deployment on AWS | 💰 Cost-conscious |
| **[Deployment Order](guides/DEPLOYMENT_ORDER.md)** | Correct order for deploying components | 📋 Operators |

**Quick path:** [AWS K3s Guide](guides/QUICKSTART-AWS-K3S.md) for fastest, cheapest AWS deployment.

---

### Database

Complete database setup and management guides.

| Document | Description | Audience |
|----------|-------------|----------|
| **[PostgreSQL Guide](database/POSTGRESQL_GUIDE.md)** | Complete PostgreSQL setup: standard & HA options | 🗄️ DBAs, Operators |

**Database options:**
- **Standard**: Single instance for development
- **HA (CloudNativePG)**: Multi-instance with automatic failover for production

---

### Architecture

System architecture, design decisions, and technical documentation.

| Document | Description | Audience |
|----------|-------------|----------|
| **[Architecture Overview](architecture/README.md)** | Complete system architecture and patterns | 🏗️ Architects, Leads |
| **[System Diagrams](architecture/DIAGRAMS.md)** | Detailed architecture diagrams | 📊 Architects |
| **[ADR-001: Multi-Cloud Providers](architecture/ADR-001-multi-cloud-providers.md)** | Provider abstraction decision | 🏗️ Architects |
| **[ADR-002: Multi-Instance Fineract](architecture/ADR-002-multi-instance-fineract.md)** | Read/Write/Batch separation | 🏗️ Architects |
| **[ADR-003: Sealed Secrets](architecture/ADR-003-sealed-secrets.md)** | Secrets management approach | 🏗️ Architects |

**Architecture highlights:**
- Multi-cloud provider abstraction (AWS, Azure, GCP, on-prem)
- Multi-instance Fineract (separate read/write/batch)
- GitOps with ArgoCD
- Sealed Secrets for security

---

### Security

Comprehensive guides for secrets management, authentication, and security best practices.

| Document | Description | Audience |
|----------|-------------|----------|
| **[Secrets Management](SECRETS_MANAGEMENT.md)** | Complete guide to Sealed Secrets: architecture, workflow, best practices | 🔐 Operators, DevOps |
| **[Migration to Sealed Secrets](MIGRATION_TO_SEALED_SECRETS.md)** | Step-by-step migration from plaintext to encrypted secrets | 🔄 Migration teams |
| **[Secrets Quick Reference](../secrets/README.md)** | Daily operations: creating, rotating, backing up secrets | ⚡ Operators |

**Security workflow:**
1. Read [Secrets Management](SECRETS_MANAGEMENT.md) to understand the system
2. Follow [Migration Guide](MIGRATION_TO_SEALED_SECRETS.md) for migration
3. Use [Secrets Quick Reference](../secrets/README.md) for daily tasks

---

### Deployment & Operations

Guides for deploying, operating, and maintaining the Fineract platform.

| Document | Description | Audience |
|----------|-------------|----------|
| **[CI/CD Integration](operations/CI_CD_INTEGRATION.md)** | Set up automated pipelines for Fineract and frontend apps | 🚀 DevOps, CI/CD engineers |
| **[Excel to YAML Conversion](operations/CONVERT_EXCEL_TO_YAML.md)** | Migrate Fineract configuration from Excel to YAML | 📊 Data migration teams |
| **[Operations Runbooks](operations/)** | Troubleshooting, maintenance, and operational procedures | 🛠️ Operators, SREs |

**Deployment paths:**
- **Development:** [Getting Started](GETTING_STARTED.md) → [Deployment Guide](../DEPLOYMENT.md)
- **Production:** [Secrets Management](SECRETS_MANAGEMENT.md) → [Deployment Guide](../DEPLOYMENT.md) → [CI/CD Integration](operations/CI_CD_INTEGRATION.md)

---

### Development

Guides for developers working on Fineract or frontend applications.

| Document | Description | Audience |
|----------|-------------|----------|
| **[Frontend Apps Implementation Guide](development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md)** | Complete guide to implementing Fineract frontend apps | 🎨 Frontend developers |
| **[Frontend CI/CD Complete Guide](development/FRONTEND_CI_CD_COMPLETE_GUIDE.md)** | Set up automated builds, tests, and deployments for frontend apps | 🚀 Frontend DevOps |
| **[Implementation Guide](development/IMPLEMENTATION_GUIDE.md)** | General implementation patterns and best practices | 💻 All developers |

**Developer workflow:**
1. Read [Frontend Implementation Guide](development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md) for app structure
2. Set up [Frontend CI/CD](development/FRONTEND_CI_CD_COMPLETE_GUIDE.md) for automation
3. Follow [Implementation Guide](development/IMPLEMENTATION_GUIDE.md) for best practices

---

### Applications

Application-specific documentation and configuration guides.

| Application | Documentation | Description |
|-------------|---------------|-------------|
| **Web App** | [apps/web-app/README.md](../apps/web-app/README.md) | Frontend applications (admin, account manager, etc.) |
| **User Sync Service** | [apps/user-sync-service/README.md](../apps/user-sync-service/README.md) | Password reset and Keycloak user synchronization |
| **Fineract Data Management** | [operations/fineract-data/README.md](../operations/fineract-data/README.md) | YAML-based configuration data management |
| **OAuth2 Proxy** | [apps/oauth2-proxy/base/README.md](../apps/oauth2-proxy/base/README.md) | OIDC reverse proxy for authentication |

---

### Architecture

Technical architecture documentation (if you create architecture docs in the future).

| Document | Description | Audience |
|----------|-------------|----------|
| **[Architecture Overview](../README.md#-architecture)** | Multi-instance Fineract deployment architecture | 🏗️ Architects, Tech Leads |
| **architecture/** *(future)* | Detailed architecture decision records (ADRs) | 🏗️ Architects |

**Current architecture docs:** See [README - Architecture section](../README.md#-architecture) for diagrams.

---

### Compliance

Compliance and audit documentation (placeholder for future content).

| Document | Description | Audience |
|----------|-------------|----------|
| **compliance/** *(future)* | SOC2, PCI-DSS, audit logs, compliance reports | 📋 Compliance officers |

---

## 🔍 How to Find Documentation

### By Role

**🆕 New User / Getting Started:**
1. [Getting Started Guide](GETTING_STARTED.md)
2. [Quick Reference](QUICK_REFERENCE.md)
3. [Deployment Guide](../DEPLOYMENT.md)

**🔐 Security / DevOps Engineer:**
1. [Secrets Management](SECRETS_MANAGEMENT.md)
2. [Migration to Sealed Secrets](MIGRATION_TO_SEALED_SECRETS.md)
3. [CI/CD Integration](operations/CI_CD_INTEGRATION.md)

**🎨 Frontend Developer:**
1. [Frontend Apps Implementation Guide](development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md)
2. [Frontend CI/CD Complete Guide](development/FRONTEND_CI_CD_COMPLETE_GUIDE.md)

**🛠️ Operations / SRE:**
1. [Quick Reference](QUICK_REFERENCE.md)
2. [Operations Runbooks](operations/)
3. [Secrets Quick Reference](../secrets/README.md)

**🏗️ Architect / Tech Lead:**
1. [README - Architecture](../README.md#-architecture)
2. [Architecture Overview](architecture/README.md)
3. [Implementation Guide](development/IMPLEMENTATION_GUIDE.md)

### By Task

**Task: Deploy Fineract for the first time**
→ [Getting Started Guide](GETTING_STARTED.md) → [Deployment Guide](../DEPLOYMENT.md)

**Task: Set up secrets management**
→ [Secrets Management](SECRETS_MANAGEMENT.md) → [Sealed Secrets Deployment Guide](SEALED_SECRETS_DEPLOYMENT_GUIDE.md)

**Task: Set up CI/CD pipelines**
→ [CI/CD Integration](operations/CI_CD_INTEGRATION.md) → [Frontend CI/CD Guide](development/FRONTEND_CI_CD_COMPLETE_GUIDE.md)

**Task: Configure frontend applications**
→ [Frontend Implementation Guide](development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md) → [Web App README](../apps/web-app/README.md)

**Task: Migrate configuration from Excel**
→ [Excel to YAML Conversion](operations/CONVERT_EXCEL_TO_YAML.md) → [Fineract Data Management](../operations/fineract-data/README.md)

**Task: Implement new frontend app**
→ [Frontend Implementation Guide](development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md)

**Task: Troubleshoot deployment issues**
→ [Quick Reference](QUICK_REFERENCE.md) → [Operations Runbooks](operations/)

---

## 📂 Documentation Directory Structure

```
docs/
├── INDEX.md                              # This file - documentation index
├── GETTING_STARTED.md                    # Complete setup walkthrough
├── QUICK_REFERENCE.md                    # Common commands cheat sheet
├── SECRETS_MANAGEMENT.md                 # Comprehensive secrets guide
├── SEALED_SECRETS_DEPLOYMENT_GUIDE.md    # Sealed Secrets deployment
├── AWS_COST_ANALYSIS.md                  # Cost analysis and optimization
├── ARCHITECTURE.md                       # System architecture overview
│
├── operations/                           # Operational guides
│   ├── CI_CD_INTEGRATION.md              # Pipeline setup
│   ├── CONVERT_EXCEL_TO_YAML.md          # Data migration
│   ├── COST_OPTIMIZATION.md              # Cost management
│   └── MONITORING_ALERTING.md            # Monitoring setup
│
├── development/                          # Developer guides
│   ├── FRONTEND_APPS_IMPLEMENTATION_GUIDE.md
│   ├── FRONTEND_CI_CD_COMPLETE_GUIDE.md
│   └── IMPLEMENTATION_GUIDE.md
│
├── architecture/                         # Architecture documentation
│   ├── README.md                         # Architecture overview
│   ├── DIAGRAMS.md                       # System diagrams
│   ├── ADR-001-multi-cloud-providers.md  # Multi-cloud decision
│   ├── ADR-002-multi-instance-fineract.md # Multi-instance decision
│   └── ADR-003-sealed-secrets.md         # Secrets management decision
│
└── migrations/                           # Historical migration docs
    └── (ESO to Sealed Secrets migration, etc.)
```

---

## 🆘 Need Help?

### Common Issues

| Issue | Solution |
|-------|----------|
| Pods not starting | Check [Secrets Management - Troubleshooting](SECRETS_MANAGEMENT.md#troubleshooting) |
| Authentication failing | See [Quick Reference - Keycloak](QUICK_REFERENCE.md#keycloak) |
| Database connection errors | Check [Getting Started - PostgreSQL](GETTING_STARTED.md#postgresql) |
| Frontend apps not loading | See [Frontend Implementation Guide](development/FRONTEND_APPS_IMPLEMENTATION_GUIDE.md#troubleshooting) |
| Secrets not decrypting | See [Migration Guide - Troubleshooting](MIGRATION_TO_SEALED_SECRETS.md#troubleshooting) |

### Support Resources

1. **Documentation:** Start with [Getting Started Guide](GETTING_STARTED.md)
2. **Quick Commands:** Use [Quick Reference](QUICK_REFERENCE.md)
3. **Specific Issues:** Check relevant guide from table above
4. **External Resources:**
   - [Fineract Documentation](https://fineract.apache.org/)
   - [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
   - [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
   - [Keycloak Documentation](https://www.keycloak.org/documentation)

---

## 📝 Documentation Standards

When creating new documentation:

1. **Use clear headings** - H2 for major sections, H3 for subsections
2. **Include code examples** - Real commands users can copy-paste
3. **Add troubleshooting** - Common errors and solutions
4. **Link to related docs** - Help users find relevant information
5. **Update this index** - Add your new documentation here

---

## 🔄 Documentation Maintenance

This index is maintained as part of the repository reorganization. When adding new documentation:

1. Place it in the appropriate directory (getting-started, security, operations, development, applications)
2. Update this index with a link and description
3. Add cross-references from related documents
4. Update the [Main README](../README.md) if it's a major guide

---

**Last Updated:** 2025-10-26
**Repository:** [fineract-gitops](https://github.com/yourusername/fineract-gitops)
**Maintainer:** Platform Team
