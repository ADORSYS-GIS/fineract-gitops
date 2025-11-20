# Legacy Scripts

This directory contains deprecated scripts that are no longer recommended for use but are kept for reference or backward compatibility.

## ⚠️ WARNING

**These scripts are deprecated and may be removed in future releases.**

Do not use these scripts for new deployments. Use the recommended alternatives instead.

---

## Scripts in This Directory

### `deploy-with-loadbalancer-dns.sh`

**Status**: ⚠️ **DEPRECATED** as of 2025-11-20
**Removal planned**: 2026-05-20

**Why deprecated**:
- Requires manual kubeconfig setup
- Monolithic design makes debugging difficult
- No automatic configuration features
- Replaced by more modular deployment approaches

**Recommended alternatives**:

1. **Two-phase deployment** (for fresh infrastructure):
   ```bash
   make deploy-infrastructure-dev
   make deploy-k8s-with-loadbalancer-dns-dev
   ```

2. **Interactive GitOps deployment**:
   ```bash
   make deploy-gitops
   ```

**Migration guide**: See [DEPLOYMENT.md](../../DEPLOYMENT.md) and [DEPRECATIONS.md](../../DEPRECATIONS.md)

---

## Need Help?

If you were using a deprecated script and need help migrating:

1. Check [DEPRECATIONS.md](../../DEPRECATIONS.md) for migration guides
2. Refer to [DEPLOYMENT.md](../../DEPLOYMENT.md) for current deployment methods
3. Open a GitHub issue if you need specific guidance

---

**Note**: Scripts in this directory may be removed after their planned removal date. Update your processes to use the recommended alternatives.
