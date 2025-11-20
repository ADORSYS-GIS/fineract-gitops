# Getting Started with Fineract GitOps

**Quick start guide to initialize and use your Fineract GitOps repository**

---

## 📋 Prerequisites

> 📖 **Complete Setup Guide:** See [PREREQUISITES.md](PREREQUISITES.md) for detailed installation instructions.
> 📋 **Version Requirements:** See [VERSION_MATRIX.md](VERSION_MATRIX.md) for compatibility matrix.

Before you begin, ensure you have:

### Required Tools
- ✅ **Git** (2.30+) - Version control
- ✅ **kubectl** (1.28+) - Kubernetes CLI
- ✅ **kustomize** (5.0+) - Configuration management
- ✅ **kubeseal** (0.27.0) - Sealed Secrets CLI
- ✅ **Python** (3.8+) - Operational scripts

### Optional Tools
- ✅ **ArgoCD CLI** (2.8+) - GitOps management
- ✅ **AWS CLI** (2.0+) - For AWS deployments
- ✅ **Terraform** (1.5+) - Infrastructure provisioning

### Access Requirements
- ✅ Access to a Kubernetes cluster (EKS, K3s, or other CNCF conformant)
- ✅ kubectl configured with cluster credentials

---

## 🚀 Step 1: Clone the Repository

```bash
# Clone the repository
git clone <your-repo-url>
cd fineract-gitops

# Checkout the branch you want to work with
git checkout main  # or dev, deploy-key, etc.
```

---

## 📖 Step 2: Read the Documentation

**Start here** - read these files in order:

1. **Main README** - Project overview and quick start
   ```bash
   cat README.md
   ```

2. **Deployment Guide** - Step-by-step deployment instructions
   ```bash
   cat DEPLOYMENT.md
   ```

3. **Architecture Documentation** - System architecture and design decisions
   ```bash
   cat docs/ARCHITECTURE.md
   cat docs/architecture/README.md
   ```

4. **App-Specific Documentation** - Deep dive into each component
   ```bash
   # Core applications
   cat apps/fineract/README.md      # Fineract banking platform
   cat apps/keycloak/README.md      # Keycloak SSO/IAM

   # Supporting services
   cat apps/oauth2-proxy/base/README.md
   cat apps/fineract-redis/base/README.md
   ```

5. **Operations Documentation**
   ```bash
   cat docs/OPERATIONS_GUIDE.md
   cat docs/SECRETS_MANAGEMENT.md
   cat operations/keycloak-config/README.md
   ```

---

## 🔧 Step 3: Set Up Your Environment

### Verify Cluster Access

```bash
# Test cluster access
kubectl cluster-info

# Check namespaces
kubectl get namespaces
```

---

## 🏗️ Step 4: Understand the Architecture

Your repository is organized as follows:

```
fineract-gitops/
├── apps/                           # Core applications
│   ├── fineract/                   # Fineract deployments (read/write/batch)
│   ├── keycloak/                   # Keycloak SSO
│   └── ...
│
├── operations/                     # Operational configurations
│   ├── keycloak-config/            # Keycloak configuration
│   │   ├── config/                 # Realm and user configurations
│   │   └── jobs/                   # keycloak-config-cli job
│   │
│   └── disaster-recovery/          # Backup and restore procedures
│
├── environments/                   # Environment-specific configs
├── docs/                           # Additional documentation
└── ... (more directories)
```

---

## 📝 Step 5: Deploy the Platform

Deploy Fineract to your environment:

```bash
# Apply the ArgoCD app-of-apps
kubectl apply -f argocd/applications/dev/app-of-apps.yaml

# Monitor deployment
argocd app list
argocd app sync fineract-dev

# Check pods
kubectl get pods -n fineract-dev -w
```

---

## 🎯 Step 6: What to Do Next

### For Deployment

1. **Local Development**
   - Set up local Kubernetes (minikube, kind, or k3d)
   - Deploy to local cluster for testing
   - Iterate on configurations

2. **Cloud Deployment**
   - Create Kubernetes cluster (EKS, GKE, AKS)
   - Set up ArgoCD in the cluster
   - Configure secrets management
   - Deploy applications via GitOps

---

## 🧪 Step 7: Testing Locally

### Test in Dev Kubernetes Cluster

```bash
# Apply dev environment configurations
kubectl apply -k environments/dev/

# Check deployments
kubectl get deployments -n fineract-dev

# Check pods
kubectl get pods -n fineract-dev

# View logs
kubectl logs -n fineract-dev <pod-name>
```

---

## 📚 Important Files Reference

### Documentation
- `.claude.md` - **Start here!** Complete project context
- `.clinerules` - Project rules and patterns
- `FINAL_SUMMARY.md` - Executive summary of what's been created
- `README.md` - Main documentation
- `IMPLEMENTATION_GUIDE.md` - How to extend the foundation
- `PROJECT_STATUS.md` - Current status and updates
- `QUICK_REFERENCE.md` - Quick command reference
- `CONVERT_EXCEL_TO_YAML.md` - Excel to YAML conversion guide

### Keycloak Configuration
- `operations/keycloak-config/config/realm-fineract.yaml` - Complete realm config
- `operations/keycloak-config/config/users-default.yaml` - Default users (dev/uat only)
- `operations/keycloak-config/README.md` - Keycloak configuration guide

---

## 🔐 Security Considerations

### Secrets Management

**Never commit secrets to Git!**

For development:
```bash
# Create Kubernetes secrets
kubectl create secret generic fineract-admin-credentials \
  --from-literal=username=mifos \
  --from-literal=password=password \
  -n fineract-dev
```

For production:
- Use Sealed Secrets for GitOps-friendly encrypted secrets
- Secrets are encrypted with cluster's public key and stored in Git
- Only the Sealed Secrets controller can decrypt them
- See: `docs/SEALED_SECRETS_DEPLOYMENT_GUIDE.md`

### Keycloak Secrets

```bash
# Development
kubectl create secret generic keycloak-client-secrets \
  --from-literal=OAUTH2_PROXY_CLIENT_SECRET=dev-secret-123 \
  --from-literal=MOBILE_APP_CLIENT_SECRET=dev-secret-456 \
  -n fineract-dev

# Production: Use Sealed Secrets
# See: scripts/create-complete-sealed-secrets.sh
```

---

## 🆘 Troubleshooting

### Validation Errors

```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('path/to/file.yaml'))"

# Run full validation
python3 scripts/validate-data.py
```

### Job Failures

```bash
# Check job status
kubectl get jobs -n fineract-dev

# View logs
kubectl logs -n fineract-dev job/load-loan-products

# Describe job for events
kubectl describe job load-loan-products -n fineract-dev
```

### Fineract Connection Issues

```bash
# Check Fineract pods
kubectl get pods -n fineract-dev -l app=fineract

# Check Fineract logs
kubectl logs -n fineract-dev -l app=fineract-write

# Test Fineract health
kubectl exec -n fineract-dev -it deployment/fineract-write -- \
  wget -q -O- http://localhost:8080/fineract-provider/actuator/health
```

---

## 💡 Tips for Success

### Git Workflow Best Practices

```bash
# Always work in feature branches
git checkout -b feature/add-new-product

# Make small, focused commits
git commit -m "ops: add SME loan product"

# Push and create PR
git push origin feature/add-new-product
```

### Environment Promotion

```bash
# Test in dev first
git checkout -b feature/new-config
# Make changes
git commit -m "feat: add new configuration"

# After testing in dev, promote to UAT
git push origin feature/new-config
# Create PR for UAT

# After UAT validation, promote to production
# Merge to main branch
```

---

## 🎓 Learning Resources

### Fineract
- [Fineract Official Docs](https://fineract.apache.org/)
- [Fineract API Docs](https://demo.fineract.dev/fineract-provider/api-docs/apiLive.htm)

### GitOps
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://www.gitops.tech/)

### Kubernetes
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kustomize Guide](https://kustomize.io/)

### Keycloak
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli)

---

## ✅ Checklist: Are You Ready?

Before deploying to production, ensure:

- [ ] Tested in dev environment
- [ ] Tested in UAT environment
- [ ] Secrets properly configured (Sealed Secrets for production)
- [ ] Keycloak realm configured with production settings
- [ ] Monitoring and alerting configured
- [ ] Backup and disaster recovery procedures in place
- [ ] Team trained on GitOps workflow
- [ ] Documentation reviewed and updated
- [ ] Change management process established

---

## 🎉 You're Ready to Begin!

**Next Steps:**

1. ✅ Initialize Git repository (see Step 1)
2. ✅ Read `.claude.md` for context
3. ✅ Try the example in Step 5
4. ✅ Follow `IMPLEMENTATION_GUIDE.md` to extend
5. ✅ Deploy to dev environment
6. ✅ Iterate and improve

**Remember:**

- 🔍 This is a **production-ready foundation**
- 📖 All patterns and templates are provided
- ✅ Test in dev first
- 📝 Everything is GitOps - all changes via Git

---

**Welcome to Fineract GitOps!** 🚀

You now have everything you need to build and operate a production-ready Apache Fineract platform using modern GitOps practices.

For questions or issues, refer to the comprehensive documentation in this repository.

---

**Created:** 2024-10-24
**Status:** Foundation Complete ✅
**Next:** Initialize Git and start extending!
