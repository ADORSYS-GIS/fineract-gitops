# GCP Migration Guide for Fineract GitOps

This guide covers deploying Fineract on Google Cloud Platform (GCP) using GKE, Cloud SQL, and GCS.

## Prerequisites

1. **Google Cloud SDK** installed and authenticated
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **GCP Project** created with billing enabled

3. **Terraform** >= 1.0.0 installed

4. **kubectl** installed

5. **kubeseal** installed (for Sealed Secrets)
   ```bash
   brew install kubeseal
   ```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    GCP Project                               │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    VPC Network                        │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │              GKE Cluster                      │    │   │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐      │    │   │
│  │  │  │Fineract │  │Fineract │  │Fineract │      │    │   │
│  │  │  │  Read   │  │  Write  │  │  Batch  │      │    │   │
│  │  │  └────┬────┘  └────┬────┘  └────┬────┘      │    │   │
│  │  │       │            │            │            │    │   │
│  │  │       └──────┬─────┴────────────┘            │    │   │
│  │  │              │                               │    │   │
│  │  │         Cloud SQL Proxy (sidecar)            │    │   │
│  │  └──────────────┼───────────────────────────────┘    │   │
│  │                 │                                     │   │
│  │                 │ Private IP                          │   │
│  │                 ▼                                     │   │
│  │  ┌─────────────────────────┐                         │   │
│  │  │    Cloud SQL (PostgreSQL) │                        │   │
│  │  │    - fineract_tenants    │                        │   │
│  │  │    - fineract_default    │                        │   │
│  │  │    - keycloak            │                        │   │
│  │  └─────────────────────────┘                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │  GCS (Documents) │    │  GCS (Backups)  │               │
│  └─────────────────┘    └─────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Deploy Infrastructure

```bash
# Deploy dev environment
./scripts/deploy-gcp-cluster.sh dev

# Or deploy production
./scripts/deploy-gcp-cluster.sh production
```

### 2. Configure kubectl

```bash
# Dev (zonal cluster)
gcloud container clusters get-credentials apache-fineract-dev \
  --zone us-central1-a \
  --project fineract-dev-project

# Production (regional cluster)
gcloud container clusters get-credentials apache-fineract-production \
  --region us-central1 \
  --project fineract-prod-project
```

### 3. Create Sealed Secrets

```bash
./scripts/seal-terraform-secrets-gcp.sh dev
```

### 4. Deploy Applications

```bash
# Apply Kubernetes manifests
kubectl apply -k environments/dev-gcp/
```

## Terraform Modules

### Module Structure

```
terraform/gcp/
├── main.tf              # Main orchestration
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── modules/
│   ├── vpc/             # VPC, subnets, Cloud NAT
│   ├── gke/             # GKE cluster and node pools
│   ├── cloud-sql/       # Cloud SQL PostgreSQL
│   ├── gcs/             # Cloud Storage buckets
│   ├── iam/             # Service accounts, Workload Identity
│   ├── cloud-dns/       # DNS (optional)
│   └── secret-manager/  # Secret Manager
└── environments/
    ├── dev.tfvars
    ├── uat.tfvars
    └── production.tfvars
```

### Key Configuration Options

| Variable | Dev | Production | Description |
|----------|-----|------------|-------------|
| `machine_type` | e2-standard-2 | n2d-standard-4 | Node machine type |
| `use_preemptible` | true | false | Use spot/preemptible VMs |
| `sql_availability_type` | ZONAL | REGIONAL | Database HA |
| `sql_instance_tier` | db-custom-2-4096 | db-custom-4-16384 | Database size |

## Workload Identity

Workload Identity allows pods to authenticate as GCP service accounts without static credentials.

### How It Works

1. **GCP Service Account** created by Terraform
2. **IAM Binding** allows K8s ServiceAccount to impersonate GCP SA
3. **K8s ServiceAccount** annotated with GCP SA email
4. **Pods** using the K8s SA can access GCP services

### Configuration

```yaml
# Kubernetes ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fineract-gcp
  annotations:
    iam.gke.io/gcp-service-account: fineract-dev@PROJECT_ID.iam.gserviceaccount.com
```

### Testing Workload Identity

```bash
kubectl run test-wi \
  --image=google/cloud-sdk:slim \
  --serviceaccount=fineract-gcp \
  --rm -it -- \
  gcloud auth list
```

## Cloud SQL Connectivity

### Cloud SQL Auth Proxy

Pods connect to Cloud SQL via the Cloud SQL Auth Proxy sidecar:

```yaml
containers:
  - name: cloud-sql-proxy
    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
    args:
      - "--structured-logs"
      - "--port=5432"
      - "PROJECT_ID:REGION:INSTANCE_NAME"
```

### Connection String

```
jdbc:postgresql://localhost:5432/fineract_tenants
```

(The proxy runs as a sidecar on localhost)

## Cost Optimization

### Implemented Strategies

| Strategy | Savings | Notes |
|----------|---------|-------|
| Preemptible VMs (dev) | 60-80% | Can be interrupted |
| e2 machine types | 20-30% | vs n1 |
| Zonal cluster (dev) | 67% | vs regional |
| Private Google Access | Free | No NAT for GCP services |
| Nearline storage | 50% | For backups |
| Lifecycle policies | Variable | Auto-archive old data |

### Estimated Monthly Costs

| Environment | Cost | Notes |
|-------------|------|-------|
| Dev | ~$180 | Preemptible, zonal |
| UAT | ~$250 | Preemptible, zonal |
| Production | ~$750 | On-demand, regional HA |
| Prod + CUD | ~$525 | With 1-year commitment |

## Troubleshooting

### GKE Issues

```bash
# Check cluster status
gcloud container clusters describe apache-fineract-dev --zone us-central1-a

# Check node pool
kubectl get nodes -o wide

# Check pods
kubectl get pods -n fineract-dev
```

### Cloud SQL Issues

```bash
# Check Cloud SQL instance
gcloud sql instances describe INSTANCE_NAME

# Check private IP connectivity
kubectl run test-pg --rm -it --image=postgres:15 -- \
  psql -h PRIVATE_IP -U fineract -d fineract_tenants

# Check Cloud SQL Proxy logs
kubectl logs POD_NAME -c cloud-sql-proxy
```

### Workload Identity Issues

```bash
# Verify annotation
kubectl get sa fineract-gcp -o yaml

# Test authentication
kubectl run test --rm -it --serviceaccount=fineract-gcp \
  --image=google/cloud-sdk:slim -- gcloud auth list

# Check IAM binding
gcloud iam service-accounts get-iam-policy \
  fineract-dev@PROJECT_ID.iam.gserviceaccount.com
```

## AWS to GCP Migration Checklist

- [ ] Create GCP project with billing
- [ ] Enable required APIs
- [ ] Update `project_id` in tfvars files
- [ ] Run `./scripts/deploy-gcp-cluster.sh dev`
- [ ] Verify GKE cluster is running
- [ ] Create sealed secrets
- [ ] Deploy Fineract applications
- [ ] Test database connectivity
- [ ] Test GCS access
- [ ] Configure DNS (if needed)
- [ ] Set up monitoring/alerting

## Reference

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
- [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine)
