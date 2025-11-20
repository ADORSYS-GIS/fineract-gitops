# Architecture Documentation

This directory contains architecture decision records (ADRs), system diagrams, and technical design documentation for the Fineract GitOps platform.

---

## Overview

The Fineract GitOps platform is built on several key architectural principles:

1. **Multi-Cloud Provider Abstraction** - Deploy anywhere without code changes
2. **Multi-Instance Fineract** - Separate read, write, and batch workloads
3. **GitOps Workflow** - All configuration as code in Git
4. **Sealed Secrets** - Encrypted secrets safe in version control
5. **Environment Parity** - Consistent deployments across dev/uat/production

---

## Architecture Decision Records (ADRs)

ADRs document significant architectural decisions, their context, and rationale.

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [ADR-001](ADR-001-multi-cloud-providers.md) | Multi-Cloud Provider Abstraction | ✅ Accepted | 2025-10-27 |
| [ADR-002](ADR-002-multi-instance-fineract.md) | Multi-Instance Fineract Deployment | ✅ Accepted | 2025-10-24 |
| [ADR-003](ADR-003-sealed-secrets.md) | Sealed Secrets for GitOps | ✅ Accepted | 2025-10-26 |

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         End Users                               │
│              (Branch Staff, Tellers, Managers)                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Ingress / Load Balancer                      │
│                  (HTTPS, TLS Termination)                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Apache Gateway (OIDC)                          │
│            Authentication & Authorization                       │
└──────────────┬──────────────────┬──────────────────┬───────────┘
               │                  │                  │
       ┌───────▼──────┐  ┌────────▼────────┐  ┌─────▼─────────┐
       │  Fineract    │  │   Fineract      │  │   Fineract    │
       │    Read      │  │    Write        │  │    Batch      │
       │  (2 pods)    │  │  (2 pods)       │  │  (1 pod)      │
       └───────┬──────┘  └────────┬────────┘  └────┬──────────┘
               │                  │                 │
               └──────────┬───────┴─────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼────┐      ┌─────▼─────┐    ┌─────▼────┐
   │PostgreSQL│      │   Redis   │    │  MinIO/  │
   │(Database)│      │  (Cache)  │    │   S3     │
   └──────────┘      └───────────┘    └──────────┘
      Self-Hosted or Cloud-Managed
```

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
Redis           ElastiCache      Redis Cache
MinIO           S3               Blob Storage
```

See [DIAGRAMS.md](DIAGRAMS.md) for detailed architecture diagrams.

---

## Key Architectural Patterns

### 1. GitOps with ArgoCD

**Pattern**: Declarative configuration management with Git as source of truth

**Benefits**:
- Version control for all infrastructure
- Audit trail of changes
- Easy rollback
- Automated deployments

**Implementation**: [Main README](../../README.md)

---

### 2. Provider Abstraction

**Pattern**: Kustomize components for swappable infrastructure backends

**Benefits**:
- Cloud portability
- No vendor lock-in
- Cost optimization
- Environment flexibility

**Implementation**: [ADR-001](ADR-001-multi-cloud-providers.md), [Providers README](../../providers/README.md)

---

### 3. Multi-Instance Deployment

**Pattern**: Separate Fineract instances for read, write, and batch operations

**Benefits**:
- Better scalability
- Resource isolation
- Independent scaling
- Improved performance

**Implementation**: [ADR-002](ADR-002-multi-instance-fineract.md)

---

### 4. Sealed Secrets

**Pattern**: Encrypted secrets stored in Git using Bitnami Sealed Secrets

**Benefits**:
- Secrets in Git safely
- GitOps-compatible
- No external secret store needed
- Cluster-scoped encryption

**Implementation**: [ADR-003](ADR-003-sealed-secrets.md), [Secrets Management](../SECRETS_MANAGEMENT.md)

---

### 5. Environment Parity

**Pattern**: Consistent configurations across environments with targeted overrides

**Benefits**:
- Predictable deployments
- Reduced environment drift
- Easier troubleshooting
- Confidence in promotions

**Implementation**: [Environments README](../../environments/README.md)

---

## Technology Stack

### Kubernetes Platform
- **Kubernetes**: 1.28+
- **ArgoCD**: 2.9+ (GitOps continuous deployment)
- **Sealed Secrets**: v0.27.0 (secrets encryption)
- **Cert-Manager**: v1.13+ (TLS certificates)

### Data Tier
- **PostgreSQL**: 15 (primary database)
- **Redis**: 7 (caching layer)
- **MinIO**: Latest (object storage, S3-compatible)
- **Kafka**: 3.6 (optional, event streaming)

### Application Tier
- **Fineract**: 1.12.1+ (core banking)
- **Keycloak**: 23+ (SSO/IAM)
- **Apache Gateway**: 2.4 (reverse proxy, OIDC)
- **Frontend Apps**: Latest (web applications)

### Observability
- **Prometheus**: v2.47+ (metrics collection)
- **Grafana**: v10.2+ (dashboards)
- **Loki**: v2.9+ (log aggregation)
- **AlertManager**: v0.26+ (alerting)

### Infrastructure
- **Terraform**: 1.5+ (cloud infrastructure)
- **Helm**: 3.13+ (package management)
- **Kustomize**: 5.0+ (configuration management)

---

## Security Architecture

### Authentication & Authorization

```
┌─────────┐
│  User   │
└────┬────┘
     │
     ▼
┌─────────────────┐
│   Keycloak      │  ← Identity Provider (OIDC)
│   (SSO/IAM)     │
└────┬────────────┘
     │ OIDC Token
     ▼
┌─────────────────┐
│Apache Gateway   │  ← Authentication Gateway
│  (mod_auth_openidc) │
└────┬────────────┘
     │ Authenticated
     ▼
┌─────────────────┐
│   Fineract      │  ← Application
└─────────────────┘
```

### Secrets Management

```
┌──────────────┐
│  Developer   │
└──────┬───────┘
       │ Creates plaintext secret
       ▼
┌──────────────┐
│  kubeseal    │  ← Encryption tool
└──────┬───────┘
       │ Encrypts with cluster public key
       ▼
┌──────────────┐
│   Git        │  ← Version control
│(sealed secret)│
└──────┬───────┘
       │ ArgoCD deploys
       ▼
┌──────────────┐
│  Cluster     │  ← Sealed Secrets controller decrypts
│(unsealed     │
│ secret)      │
└──────────────┘
```

### Network Security

- **NetworkPolicies**: Isolate services and namespaces
- **TLS**: Encryption in transit for all external traffic
- **Private Subnets**: Databases in private cloud subnets
- **IRSA/Workload Identity**: No static cloud credentials

---

## Scalability

### Horizontal Scaling

| Component | Min Replicas | Max Replicas | Scaling Metric |
|-----------|--------------|--------------|----------------|
| Fineract Read | 2 | 10 | CPU > 70% |
| Fineract Write | 2 | 5 | CPU > 70% |
| Fineract Batch | 1 | 1 | N/A |
| Apache Gateway | 2 | 5 | CPU > 60% |
| Keycloak | 2 | 3 | CPU > 70% |

### Vertical Scaling

Resources adjust per environment:
- **Dev**: 1-2 CPU, 2-4GB RAM per pod
- **UAT**: 2-3 CPU, 4-6GB RAM per pod
- **Production**: 3-4 CPU, 6-8GB RAM per pod

### Data Tier Scaling

**Self-Hosted**:
- PostgreSQL: Vertical (increase resources)
- Redis: Sentinel for HA, sharding for scale
- MinIO: Distributed mode (4+ nodes)

**Cloud-Managed**:
- RDS: Read replicas, instance type changes
- ElastiCache: Redis cluster mode, node types
- S3: Infinite scale, no management

---

## High Availability

### Application HA
- Multiple replicas (2-3 per service)
- PodDisruptionBudgets (prevent disruption)
- Anti-affinity rules (spread across nodes)
- Health checks (liveness/readiness probes)

### Data HA
- PostgreSQL: Primary + replicas, automatic failover
- Redis: Sentinel (3 nodes minimum)
- MinIO: Distributed mode (4+ nodes)
- Cloud-managed: Multi-AZ, automatic failover

### Infrastructure HA
- Multi-AZ deployment
- Load balancers (cloud or ingress)
- Auto-scaling groups
- Cluster autoscaler

---

## Disaster Recovery

### Backup Strategy

| Component | Frequency | Retention | Method |
|-----------|-----------|-----------|--------|
| PostgreSQL | Daily full, Hourly WAL | 30 days | pg_dump to MinIO/S3 |
| Redis | Daily snapshot | 7 days | RDB snapshot |
| MinIO | Continuous replication | N/A | Cross-region replication |
| Configs | On change | Infinite | Git repository |

### Recovery Procedures

**RTO** (Recovery Time Objective): < 4 hours
**RPO** (Recovery Point Objective): < 1 hour

See [Disaster Recovery README](../../operations/disaster-recovery/README.md) for procedures.

---

## Performance Considerations

### Database Performance
- **Connection Pooling**: PgBouncer (300 connections/instance)
- **Read Replicas**: Separate read traffic from writes
- **Caching**: Redis for frequently accessed data
- **Indexing**: Optimized database indexes

### Application Performance
- **Multi-Instance**: Separate read/write/batch workloads
- **Horizontal Scaling**: Scale read instances independently
- **Resource Limits**: Prevent resource exhaustion
- **CDN**: Static assets via CDN (optional)

### Network Performance
- **Service Mesh**: Envoy/Istio for advanced routing (optional)
- **HTTP/2**: Modern protocol support
- **Compression**: gzip for API responses
- **Private Networking**: Low-latency database connections

---

## Cost Optimization

### Development
- Use K3s instead of EKS (67% savings)
- Use cloud-managed databases (78% savings)
- Scale down to 1 replica
- Use spot/preemptible instances

### Production
- Right-size instances
- Use reserved instances
- Scale based on demand
- Optimize storage classes

See [Cost Optimization Guide](../COST_OPTIMIZATION_APPLIED.md) for details.

---

## Evolution & Roadmap

### Completed ✅
- Multi-cloud provider abstraction
- Sealed Secrets implementation
- Multi-instance Fineract
- AWS Terraform modules
- Cost optimization (60-78%)

### In Progress 🚧
- Azure/GCP Terraform modules
- Monitoring stack integration
- Backup automation

### Planned 📋
- Service mesh (Istio/Linkerd)
- Multi-region deployment
- Advanced observability
- Performance testing framework

---

## Related Documentation

- **[DIAGRAMS.md](DIAGRAMS.md)** - Detailed system diagrams
- **[ADRs](.)** - Architecture decision records
- **[Main README](../../README.md)** - Project overview
- **[Multi-Provider Implementation](../MULTI_PROVIDER_IMPLEMENTATION_PLAN.md)** - Multi-cloud support
- **[AWS Cost Analysis](../AWS_COST_ANALYSIS.md)** - Infrastructure cost comparison
- **[Getting Started](../GETTING_STARTED.md)** - Deployment guide

---

## Contributing to Architecture

When making architectural changes:

1. **Create ADR**: Document decision in new ADR-XXX.md
2. **Update Diagrams**: Modify DIAGRAMS.md if architecture changes
3. **Update Implementation**: Make code changes
4. **Update Documentation**: Update relevant READMEs
5. **Get Review**: Architecture review from team
6. **Mark ADR Status**: Accepted/Rejected/Superseded

---

**Last Updated:** 2025-10-28
**Architecture Version:** 2.0
**Status:** Production-Ready
