# Version Matrix

**Last Updated:** 2025-11-20
**Purpose:** Authoritative reference for all software versions used in fineract-gitops

> 📋 **Note:** This is the single source of truth for version requirements. All other documentation references this file.

---

## Quick Reference

| Component | Minimum Version | Recommended | Notes |
|-----------|----------------|-------------|-------|
| **Kubernetes** | 1.28 | 1.28+ | EKS, K3s, or other CNCF conformant |
| **kubectl** | 1.28 | 1.28+ | Must match cluster minor version |
| **kustomize** | 5.0.0 | 5.3.0+ | Standalone binary required |
| **Terraform** | 1.5.0 | 1.6.0+ | For infrastructure provisioning |
| **AWS CLI** | 2.0.0 | 2.15.0+ | Required for AWS deployments |
| **eksctl** | 0.150.0 | 0.170.0+ | For EKS cluster management |
| **ArgoCD CLI** | 2.8.0 | 2.10.0+ | For GitOps operations |
| **Helm** | 3.12.0 | 3.14.0+ | For chart-based deployments |
| **kubeseal** | 0.27.0 | 0.27.0 | **Critical:** Must match controller |

---

## Application Versions

### Core Services

| Application | Version | Chart/Image | Status |
|-------------|---------|-------------|--------|
| **Fineract** | 1.9.0 | `apache/fineract:1.9.0` (develop branch) | ✅ Stable |
| **PostgreSQL** | 15.14 | `postgres:15.14-alpine` | ✅ Stable |
| **Keycloak** | 24.0.5 | `quay.io/keycloak/keycloak:24.0.5` | ✅ Stable |
| **ArgoCD** | 2.10.0 | `argoproj/argocd:v2.10.0` | ✅ Stable |

### Infrastructure Components

| Component | Version | Chart Version | Notes |
|-----------|---------|---------------|-------|
| **Sealed Secrets Controller** | 0.27.0 | 2.15.0 | ⚠️ Breaking changes from 0.24.x |
| **cert-manager** | 1.13.3 | 1.13.3 | For TLS certificate management |
| **ingress-nginx** | 1.10.0 | 4.9.0 | Production-ready ingress |
| **CloudNativePG Operator** | 1.21.0 | 0.20.1 | For HA PostgreSQL (optional) |

### Monitoring & Observability

| Component | Version | Chart Version | Notes |
|-----------|---------|---------------|-------|
| **Prometheus** | 2.48.0 | kube-prometheus-stack 55.5.0 | Metrics collection |
| **Grafana** | 10.2.2 | (included in kube-prometheus) | Visualization |
| **Loki** | 2.9.3 | 5.41.0 | Log aggregation |
| **Promtail** | 2.9.3 | 6.15.3 | Log shipping |

### Authentication & Security

| Component | Version | Notes |
|-----------|---------|-------|
| **oauth2-proxy** | 7.5.1 | OIDC authentication proxy |
| **External Secrets Operator** | 0.9.11 | Alternative to Sealed Secrets (optional) |

---

## Language & Runtime Versions

### Python (for operational scripts)
- **Minimum:** 3.8
- **Recommended:** 3.11+
- **Required packages:** `pyyaml`, `requests`, `openpyxl` (see operations/requirements.txt)

### Node.js (for frontend apps)
- **Minimum:** 18.x LTS
- **Recommended:** 20.x LTS
- **Package Manager:** npm 9.x+ or yarn 1.22+

### Java (for Fineract)
- **Version:** OpenJDK 17 (Fineract 1.9.0 requirement)
- **Build Tool:** Gradle 8.x

---

## Cloud Provider Requirements

### AWS

| Service | Minimum Version/Requirements |
|---------|----------------------------|
| **EKS** | 1.28+ |
| **RDS PostgreSQL** | 15.14 (recommended), 15.x minimum |
| **S3** | Any (standard bucket configuration) |
| **VPC** | IPv4 CIDR block, 2+ availability zones |
| **IAM** | IRSA (IAM Roles for Service Accounts) enabled |
| **EC2** | t3.medium or larger for worker nodes |

#### Terraform AWS Provider
- **Version:** ~> 5.0
- **Modules:** VPC, EKS, RDS, S3

### K3s (Cost-Optimized Alternative)

| Requirement | Details |
|-------------|---------|
| **K3s Version** | 1.28.x |
| **Host OS** | Ubuntu 22.04 LTS, Amazon Linux 2023 |
| **Instance Type** | t3.medium minimum (2 vCPU, 4GB RAM) |
| **Storage** | 50GB+ EBS volume |

---

## Environment-Specific Versions

### Development Environment
```yaml
kubernetes: 1.28
fineract: 1.9.0
postgresql: 15.14
keycloak: 24.0.5
sealed-secrets: 0.27.0
```

### UAT Environment
```yaml
kubernetes: 1.28
fineract: 1.9.0
postgresql: 15.14 (RDS)
keycloak: 24.0.5
sealed-secrets: 0.27.0
```

### Production Environment
```yaml
kubernetes: 1.28+
fineract: 1.9.0
postgresql: 15.14 (RDS with Multi-AZ)
keycloak: 24.0.5
sealed-secrets: 0.27.0
cert-manager: 1.13.3 (required)
```

---

## Compatibility Matrix

### Kubernetes Version Compatibility

| K8s Version | kubectl | kustomize | ArgoCD | Status |
|-------------|---------|-----------|--------|--------|
| 1.28 | 1.28.x | 5.0+ | 2.8+ | ✅ **Recommended** |
| 1.29 | 1.29.x | 5.0+ | 2.9+ | ✅ Supported |
| 1.30 | 1.30.x | 5.0+ | 2.10+ | ⚠️ Testing |
| 1.31 | 1.31.x | 5.0+ | 2.10+ | 🔄 Future |
| < 1.28 | - | - | - | ❌ Not supported |

### Database Version Compatibility

| PostgreSQL | Fineract 1.9.0 | CloudNativePG | Notes |
|------------|----------------|---------------|-------|
| 15.14 | ✅ Tested | ✅ Supported | **Recommended** |
| 15.x (other) | ✅ Compatible | ✅ Supported | Should work |
| 14.x | ⚠️ May work | ⚠️ Limited | Not tested |
| 16.x | ❌ Not tested | ✅ Supported | Use at own risk |

### Sealed Secrets Version Compatibility

| Controller | kubeseal CLI | Breaking Changes | Status |
|------------|-------------|------------------|--------|
| 0.27.0 | 0.27.0 | None | ✅ **Current** |
| 0.26.x | 0.26.x | None vs 0.27 | ⚠️ Upgrade recommended |
| 0.24.x | 0.24.x | Yes vs 0.27 | ⚠️ Deprecated |
| < 0.24 | - | Yes | ❌ Not supported |

> ⚠️ **Important:** kubeseal CLI version must match the controller version. Mismatch can cause decryption failures.

---

## Version Update Policy

### Immediate Updates (Security)
- Security patches for Kubernetes, PostgreSQL, Keycloak
- CVE fixes in any component
- ArgoCD security updates

### Quarterly Updates (Features)
- Kubernetes minor versions (1.28 → 1.29)
- Application updates (Fineract, Keycloak)
- Monitoring stack updates

### Annual Reviews
- Major version upgrades (PostgreSQL 15 → 16)
- Infrastructure provider updates (Terraform AWS provider)
- Deprecated component replacements

---

## Upgrade Paths

### Kubernetes 1.28 → 1.29
1. Update kubectl to 1.29
2. Test deployments in dev environment
3. Upgrade EKS control plane (in-place)
4. Roll worker nodes with new AMI
5. Verify all workloads

### Sealed Secrets 0.24/0.26 → 0.27
1. **Backup existing keys:** `kubectl get secret -n kube-system sealed-secrets-key -o yaml > backup.yaml`
2. Update controller: `kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/controller.yaml`
3. Update kubeseal CLI: `wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz`
4. Test secret decryption
5. Update all sealed secrets in Git

### PostgreSQL 15.x → 15.14 (Patch Update)
- RDS: Apply during maintenance window (automatic)
- Self-hosted: `kubectl set image statefulset/postgresql postgresql=postgres:15.14-alpine`
- CloudNativePG: Update `postgresql.imageTag` in values

---

## Verification Commands

```bash
# Check installed versions
kubectl version --short
kustomize version
terraform --version
aws --version
argocd version
helm version
kubeseal --version

# Verify cluster version
kubectl get nodes -o wide

# Check deployed application versions
kubectl get deployment -n fineract-dev fineract-write -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment -n keycloak keycloak -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment -n argocd argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}'

# Verify Sealed Secrets version
kubectl get deployment -n kube-system sealed-secrets-controller -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## Related Documentation

- [Prerequisites Guide](PREREQUISITES.md) - Installation instructions for all tools
- [Quick Start (AWS)](guides/QUICKSTART-AWS.md) - Full deployment guide
- [Deployment Guide](../DEPLOYMENT.md) - Interactive deployment steps
- [Operations Guide](operations/OPERATIONS_GUIDE.md) - Day-2 operations

---

## Version History

| Date | Change | Reason |
|------|--------|--------|
| 2025-11-20 | Standardized Sealed Secrets to 0.27.0 | Resolve version inconsistencies |
| 2025-11-20 | Standardized PostgreSQL to 15.14 | Latest stable patch release |
| 2025-11-20 | Created VERSION_MATRIX.md | Central version authority |

---

**Questions or Issues?**
If you find version conflicts or compatibility issues, please:
1. Check this document first
2. Review [GitHub Issues](https://github.com/adorsys-gis/fineract-gitops/issues)
3. Update this document via pull request
