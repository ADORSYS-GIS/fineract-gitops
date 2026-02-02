# On-Premise Hetzner Deployment Guide for Fineract GitOps

Deploy the Fineract banking platform on 2 Hetzner machines without cloud services. This guide starts with a **basic single-instance setup** for development/testing, with a clear upgrade path to high availability later.

**Access Method**: IP-based access (no domain required initially)

---

## Hetzner Server Options Comparison

### Option A: Dedicated Servers (Recommended for Long-term)
| Server | Model | Specs | Monthly Cost |
|--------|-------|-------|--------------|
| **Server 1** | AX41-NVMe | 6-core AMD Ryzen, 64GB RAM, 2x512GB NVMe | ~€49/month |
| **Server 2** | AX41-NVMe | 6-core AMD Ryzen, 64GB RAM, 2x512GB NVMe | ~€49/month |

**Pros**: Best price/performance, more RAM, larger storage, better for 24/7 workloads
**Cons**: 1-24 hour setup time, requires manual OS installation, physical hardware (rare failures)

### Option B: Cloud Servers (Easier to Start)
| Server | Type | Specs | Monthly Cost |
|--------|------|-------|--------------|
| **Server 1** | CCX33 | 8 vCPU, 32GB RAM, 240GB NVMe | ~€68/month |
| **Server 2** | CCX33 | 8 vCPU, 32GB RAM, 240GB NVMe | ~€68/month |

**Pros**: Instant provisioning (minutes), easy snapshots/backups, resize easily, API/Terraform support
**Cons**: Higher cost, shared resources, less storage

### Recommendation
**Start with Cloud Servers (Option B)** for faster iteration during setup, then consider migrating to dedicated servers once stable. You can also start with smaller CCX23 (4 vCPU, 16GB) at ~€34/month each to test, then upgrade.

---

## Architecture

```
                    Internet
                        │
                        ▼
              ┌─────────────────┐
              │  Hetzner vSwitch │ (Private Network 10.0.0.0/24)
              └─────────────────┘
                   │         │
        ┌──────────┘         └──────────┐
        ▼                               ▼
┌───────────────────┐         ┌───────────────────┐
│  SERVER 1 (Master)│         │  SERVER 2 (Worker)│
│  10.0.0.1         │         │  10.0.0.2         │
│                   │         │                   │
│  - K3s Master     │         │  - K3s Worker     │
│  - NGINX Ingress  │         │  - PostgreSQL     │
│  - Fineract Write │         │  - Keycloak       │
│  - Fineract Read  │         │  - Redis          │
│  - Fineract Batch │         │  - Monitoring     │
│  - Frontend Apps  │         │  - Logging        │
│  - MetalLB        │         │                   │
│  - cert-manager   │         │                   │
│  - ArgoCD         │         │                   │
└───────────────────┘         └───────────────────┘
```

---

## Cloud Service Replacements

| Cloud Service | On-Premise Alternative |
|---------------|----------------------|
| EKS/GKE | **K3s** (lightweight Kubernetes) |
| RDS PostgreSQL | **Self-hosted PostgreSQL** + Patroni (HA) |
| S3/GCS | **MinIO** (S3-compatible storage) |
| AWS ELB | **MetalLB** (bare-metal load balancer) |
| Route53/Cloud DNS | **Cloudflare** (free DNS) or local DNS |
| AWS SES | **Mailhog** (dev) / **Postfix** or external SMTP |
| IAM/IRSA | **Kubernetes RBAC** + Service Accounts |
| Secrets Manager | **Sealed Secrets** (already used) |

---

## Implementation Steps

### Phase 1: Infrastructure Setup (Hetzner)

#### 1.1 Order Hetzner Servers
- Order 2x AX41-NVMe (or CCX33 cloud servers)
- Request Hetzner vSwitch for private networking
- Request additional IPv4 addresses for load balancing (optional)

#### 1.2 Base OS Installation
- Install **Ubuntu 22.04 LTS** on both servers
- Configure SSH keys (disable password auth)
- Set up firewall (UFW) with minimal open ports
- Configure private networking via vSwitch

#### 1.3 Storage Configuration
- Set up RAID1 on dedicated servers for data protection
- Create partitions: `/` (100GB), `/var/lib/rancher` (200GB), `/data` (remaining)

### Phase 2: Kubernetes Cluster Setup

#### 2.1 Install K3s on Server 1 (Master)
```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --disable servicelb \
  --tls-san <public-ip> \
  --node-taint CriticalAddonsOnly=true:NoExecute
```

#### 2.2 Join Server 2 as Worker
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.1:6443 \
  K3S_TOKEN=<token> sh -s - agent
```

Get the token from Server 1:
```bash
cat /var/lib/rancher/k3s/server/node-token
```

#### 2.3 Install MetalLB for Load Balancing
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

Configure MetalLB with your server's public IP:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - <SERVER_1_PUBLIC_IP>/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

### Phase 3: Core Infrastructure Components

#### 3.1 Storage Classes
K3s includes local-path storage class by default. For production, consider Longhorn:
```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml
```

#### 3.2 Install cert-manager
```bash
kubectl apply -f apps/cert-manager/base/
```

For self-signed certificates (development):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

#### 3.3 Install NGINX Ingress Controller
```bash
kubectl apply -f apps/ingress/base/
```

#### 3.4 Install Sealed Secrets Controller
```bash
kubectl apply -f apps/sealed-secrets-controller/base/
```

### Phase 4: Database & Cache Layer

#### 4.1 Deploy PostgreSQL
Create a self-hosted PostgreSQL StatefulSet (see `apps/postgresql/base/` - to be created).

Key configuration:
- PersistentVolumeClaim: 50GB initial
- Max connections: 100
- Initialize databases: `fineract_tenants`, `fineract_default`, `keycloak`

#### 4.2 Deploy Redis
```bash
kubectl apply -f apps/fineract-redis/base/
```

#### 4.3 Deploy MinIO (S3 replacement)
Create MinIO deployment (see `apps/minio/base/` - to be created).

Create buckets:
- `fineract-documents`
- `fineract-backups`

### Phase 5: Identity & Authentication

#### 5.1 Deploy Keycloak
Modify `apps/keycloak/` to use self-hosted PostgreSQL:
```yaml
env:
  - name: KC_DB
    value: postgres
  - name: KC_DB_URL
    value: jdbc:postgresql://postgresql:5432/keycloak
```

#### 5.2 Deploy OAuth2-Proxy
Update configuration for self-hosted Keycloak URL:
```yaml
env:
  - name: OAUTH2_PROXY_OIDC_ISSUER_URL
    value: https://<SERVER_1_IP>/auth/realms/fineract
```

### Phase 6: Fineract Application

#### 6.1 Deploy Fineract Backend
Modify environment variables in `apps/fineract/`:
```yaml
env:
  - name: FINERACT_DEFAULT_TENANTDB_HOSTNAME
    value: postgresql
  - name: FINERACT_HIKARI_DS_FINERACT_DEFAULT_JDBC_URL
    value: jdbc:postgresql://postgresql:5432/fineract_default
  - name: AWS_S3_ENDPOINT
    value: http://minio:9000
```

#### 6.2 Deploy Frontend Applications
```bash
kubectl apply -f apps/web-app/base/
kubectl apply -f apps/accounting-app/base/
kubectl apply -f apps/reporting-app/base/
```

### Phase 7: Monitoring & Observability

#### 7.1 Deploy Prometheus Stack
```bash
kubectl apply -f apps/monitoring/base/
```

Reduce retention for 2-node setup:
```yaml
retention: 15d
retentionSize: 20GB
```

#### 7.2 Deploy Loki & Promtail
```bash
kubectl apply -f apps/logging/base/
```

### Phase 8: GitOps Setup

#### 8.1 Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### 8.2 Create On-Premise Environment
Create `environments/onprem/` directory with Kustomize overlays.

---

## Files to Create/Modify

### New Files
| Path | Purpose |
|------|---------|
| `environments/onprem/kustomization.yaml` | On-premise environment base |
| `apps/postgresql/base/` | Self-hosted PostgreSQL manifests |
| `apps/minio/base/` | MinIO S3-compatible storage |
| `terraform/onprem/` | Hetzner infrastructure scripts (optional) |

### Files to Modify
| Path | Change |
|------|--------|
| `apps/fineract/overlays/onprem/` | Database/storage configuration |
| `apps/keycloak/overlays/onprem/` | Self-hosted PostgreSQL connection |
| `argocd/environments/onprem/` | ArgoCD applications for on-premise |

---

## DNS & Networking (IP-Based for Development)

### Initial Setup (No Domain)
- Access services directly via Server 1 public IP
- Use **self-signed certificates** for HTTPS (browser warning, but encrypted)
- Configure `/etc/hosts` on your local machine for friendly names:
  ```
  <SERVER_1_IP>  fineract.local keycloak.local grafana.local
  ```

### Future Upgrade (When Ready for Production)
- Register a domain (Cloudflare free tier recommended)
- Point domain to Hetzner server public IP
- Switch to Let's Encrypt certificates (automatic renewal)
- Enable Cloudflare proxy for DDoS protection

---

## Backup Strategy

1. **PostgreSQL**: Daily pg_dump to MinIO with 7-day retention
   ```bash
   pg_dump -U fineract fineract_default | gzip > /backup/fineract_$(date +%Y%m%d).sql.gz
   ```

2. **MinIO**: Replicate to off-site storage (optional second location)

3. **Kubernetes**: Velero for cluster state backup
   ```bash
   velero install --provider aws --bucket velero-backup --use-node-agent
   ```

4. **etcd**: Automated K3s etcd snapshots (enabled by default)

---

## Security Considerations

1. **Firewall**: Only expose ports 80, 443, 6443 (K8s API)
   ```bash
   ufw allow 22/tcp    # SSH
   ufw allow 80/tcp    # HTTP
   ufw allow 443/tcp   # HTTPS
   ufw allow 6443/tcp  # K8s API
   ufw enable
   ```

2. **SSH**: Key-only authentication, fail2ban
   ```bash
   apt install fail2ban
   systemctl enable fail2ban
   ```

3. **Private Network**: All inter-service communication via vSwitch

4. **TLS**: Self-signed or Let's Encrypt certificates for all endpoints

5. **Network Policies**: Kubernetes network policies for pod isolation

---

## Verification Checklist

- [ ] Access Fineract web UI via HTTPS
- [ ] Login via Keycloak SSO
- [ ] Verify database connectivity
- [ ] Test document upload to MinIO
- [ ] Check Prometheus/Grafana dashboards
- [ ] Verify ArgoCD sync status
- [ ] Test pod restart recovery

---

## Cost Summary

### Basic Setup (Cloud Servers - Recommended to Start)
| Item | Monthly Cost |
|------|--------------|
| 2x Hetzner CCX23 (starter) | ~€68 |
| Hetzner vSwitch | Free |
| **Total** | **~€68/month** |

### Full Setup (Cloud Servers)
| Item | Monthly Cost |
|------|--------------|
| 2x Hetzner CCX33 | ~€136 |
| Hetzner vSwitch | Free |
| **Total** | **~€136/month** |

### Full Setup (Dedicated Servers - Best Value)
| Item | Monthly Cost |
|------|--------------|
| 2x Hetzner AX41-NVMe | ~€98 |
| Additional IPv4 (optional) | ~€4 |
| Hetzner vSwitch | Free |
| **Total** | **~€102/month** |

Compared to cloud deployment (~$600-700/month), this represents **80-90% cost savings**.

---

## Future HA Upgrade Path

When ready to move to production, these upgrades can be added:

| Component | Basic (Now) | HA Upgrade |
|-----------|-------------|------------|
| PostgreSQL | Single instance | Patroni cluster (3 nodes) |
| Redis | Single instance | Redis Sentinel (3 nodes) |
| Fineract | 1 write, 1 read | 2 write, 3 read with HPA |
| K3s | 1 master | 3 masters (HA control plane) |
| Storage | Local disk | Longhorn distributed storage |

This would require adding a 3rd server to the cluster.

---

## Related Documentation

- [QUICKSTART-AWS.md](./QUICKSTART-AWS.md) - AWS deployment guide
- [QUICKSTART-AWS-K3S.md](./QUICKSTART-AWS-K3S.md) - AWS K3s deployment
- [../ARCHITECTURE.md](../ARCHITECTURE.md) - System architecture overview
- [../DATABASE_STRATEGY.md](../DATABASE_STRATEGY.md) - Database configuration
- [../SECRETS_MANAGEMENT.md](../SECRETS_MANAGEMENT.md) - Sealed Secrets guide
