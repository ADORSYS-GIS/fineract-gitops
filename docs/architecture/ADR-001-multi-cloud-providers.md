# ADR-001: Multi-Cloud Provider Abstraction

**Status**: Accepted
**Date**: 2025-10-27
**Decision**: Implement provider abstraction layer using Kustomize components

---

## Context

The Fineract GitOps platform needs to support deployment across multiple infrastructure backends:
- On-premise (self-hosted databases)
- AWS (RDS, ElastiCache, S3)
- Azure (Azure Database, Redis Cache, Blob Storage)
- GCP (Cloud SQL, Memorystore, GCS)

Challenges:
- Different connection patterns for each provider
- Different authentication mechanisms (static credentials vs. IRSA/Workload Identity)
- Different service endpoints and configuration
- Need for infrastructure portability without code changes

---

## Decision

Implement provider abstraction using **Kustomize components** (alpha feature) to allow swappable infrastructure backends.

### Architecture

```
environments/<env>-<provider>/
└── kustomization.yaml
    ├── bases: [common apps]
    └── components: [provider-specific config]

providers/
├── self-hosted/     # StatefulSets for PostgreSQL, Redis, MinIO
├── aws-managed/     # Patches for RDS, ElastiCache, S3
├── azure-managed/   # Patches for Azure services
└── gcp-managed/     # Patches for GCP services
```

### Implementation

Each provider directory contains Kustomize patches that:
1. Set appropriate environment variables
2. Configure service endpoints
3. Set up authentication (credentials or workload identity)
4. Adjust resource limits
5. Add sidecars if needed (e.g., Cloud SQL Proxy)

---

## Consequences

### Positive

✅ **True multi-cloud portability** - Switch providers by changing one line
✅ **Cost optimization** - 60-78% savings in dev with managed services
✅ **No vendor lock-in** - Can migrate between clouds easily
✅ **Zero application changes** - Same Fineract code everywhere
✅ **Environment flexibility** - Mix providers (dev=AWS, prod=on-prem)

### Negative

⚠️ **Kustomize alpha feature** - Components are not yet stable API
⚠️ **Terraform required** - Cloud providers need infrastructure provisioning
⚠️ **Testing complexity** - Must test on all providers
⚠️ **Documentation burden** - Each provider needs guides

---

## Alternatives Considered

### 1. Single Provider Only

**Rejected**: No cloud portability, vendor lock-in

### 2. Separate Repositories per Provider

**Rejected**: Code duplication, maintenance nightmare

### 3. Helm with Values Files

**Rejected**: Less composable than Kustomize, harder to customize

### 4. Custom Templating Tool

**Rejected**: Adds complexity, reinvents Kustomize

---

## Implementation Notes

- Terraform modules provision cloud infrastructure
- Secrets created by Terraform (connection strings, endpoints)
- Environment variables patched per provider
- Provider selection at deploy time via Kustomize
- Documented migration procedures between providers

---

## References

- [Providers README](../../providers/README.md)
- [Multi-Provider Implementation Plan](../MULTI_PROVIDER_IMPLEMENTATION_PLAN.md)
- [AWS Cost Analysis](../AWS_COST_ANALYSIS.md)
- [Kustomize Components](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
