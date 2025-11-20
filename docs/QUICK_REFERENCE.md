# Fineract GitOps - Quick Reference

> 📋 **Prerequisites:** [PREREQUISITES.md](PREREQUISITES.md) | **Versions:** [VERSION_MATRIX.md](VERSION_MATRIX.md)

## 📁 Repository Layout

```
fineract-gitops/
├── README.md                    # Start here - complete documentation
├── IMPLEMENTATION_GUIDE.md      # Step-by-step extension guide
├── PROJECT_STATUS.md            # What's been created
├── QUICK_REFERENCE.md           # This file - quick commands
│
├── operations/                  # Operational configurations
│   ├── keycloak-config/         # Keycloak SSO configuration
│   └── disaster-recovery/       # Backup and restore procedures
│
├── apps/                        # Core Fineract deployment
│   └── fineract/
│       ├── base/                # Base Kubernetes manifests
│       └── overlays/            # Environment-specific patches
│
└── argocd/                      # ArgoCD GitOps configuration
```

## 🎯 Common Tasks

### 1. Deploy to Development

```bash
# Create namespace
kubectl create namespace fineract-dev

# Deploy ArgoCD app-of-apps
kubectl apply -f argocd/applications/dev/app-of-apps.yaml

# Monitor
argocd app list
argocd app sync fineract-dev
kubectl get pods -n fineract-dev -w
```

### 2. Promote from UAT to Production

```bash
# Run promotion script
./scripts/promote-env.sh uat production v1.2.3

# This creates a PR with:
# - Updated image tags
# - Environment-specific patches
# - Approval checklist

# Review PR, approve, merge
# ArgoCD auto-deploys to production
```

### 3. Rollback Production

```bash
# Rollback to previous version
./scripts/rollback.sh production v1.2.2

# OR use Git revert
git revert HEAD
git push

# ArgoCD will sync the revert
```

## 🎓 Learning Path

1. **Start:** Read `README.md`
2. **Understand:** Review example YAML files
3. **Extend:** Follow `IMPLEMENTATION_GUIDE.md`
4. **Reference:** Use this file for common tasks

## 💡 Tips

1. **Use meaningful commit messages:**
   ```bash
   git commit -m "feat: add new Keycloak client configuration"
   ```

2. **Review diffs before pushing:**
   ```bash
   git diff
   ```

3. **Test in dev first:**
   - Make changes in dev environment
   - Deploy and test
   - Copy to production when ready

4. **Keep production clean:**
   - Only configuration data
   - No demo/test data
   - No client/transaction data

## 🔗 Useful Commands

```bash
# Git
git status
git diff
git log --oneline
git show <commit-hash>

# Kubernetes
kubectl get pods -n fineract-dev
kubectl logs -n fineract-dev <pod-name>
kubectl describe pod -n fineract-dev <pod-name>

# ArgoCD
argocd app list
argocd app get fineract-dev
argocd app sync fineract-dev
argocd app history fineract-dev
```

## 📧 Need Help?

1. Check `README.md` for architecture
2. Check `IMPLEMENTATION_GUIDE.md` for detailed steps
3. Check example YAML files for patterns
4. Check Fineract API docs for field mappings

---

**Quick Reference for Daily Operations**
