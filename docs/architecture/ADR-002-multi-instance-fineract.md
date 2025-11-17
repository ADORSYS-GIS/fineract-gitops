# ADR-002: Multi-Instance Fineract Deployment

**Status**: Accepted
**Date**: 2025-10-24
**Decision**: Deploy Fineract as three separate instances: Read, Write, and Batch

---

## Context

Standard Fineract deployments use a single instance handling all operations:
- Read queries (reports, dashboards, searches)
- Write operations (transactions, updates, creates)
- Batch jobs (interest posting, reports, cleanup)

Problems with single-instance:
- **Resource contention**: Batch jobs impact user experience
- **Scaling challenges**: Can't scale reads independently
- **Performance**: Mixed workloads compete for resources
- **Availability**: Batch failures affect user operations

---

## Decision

Deploy **three separate Fineract instances** with specialized workloads:

1. **Fineract Read** (2-10 replicas)
   - Read-only queries
   - Reports and dashboards
   - Search operations
   - Horizontally scalable

2. **Fineract Write** (2-5 replicas)
   - Transactions (deposits, withdrawals, loans)
   - Data modifications
   - Critical operations
   - Moderate scaling

3. **Fineract Batch** (1 replica)
   - Scheduled jobs
   - Interest calculations
   - End-of-day processing
   - Singleton (no replicas)

### Routing

```
                    ┌──────────────┐
                    │Apache Gateway│
                    └──────┬───────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
  ┌──────────┐      ┌──────────┐      ┌──────────┐
  │Fineract  │      │Fineract  │      │Fineract  │
  │  Read    │      │  Write   │      │  Batch   │
  │(2 pods)  │      │(2 pods)  │      │(1 pod)   │
  └────┬─────┘      └────┬─────┘      └────┬─────┘
       │                 │                  │
       └─────────────────┴──────────────────┘
                         │
                  ┌──────▼──────┐
                  │ PostgreSQL  │
                  └─────────────┘
```

---

## Consequences

### Positive

✅ **Independent scaling** - Scale read instances based on user load
✅ **Resource isolation** - Batch jobs don't impact users
✅ **Better performance** - Specialized workloads optimized separately
✅ **Improved availability** - Batch failures don't affect user operations
✅ **Cost efficiency** - Scale only what you need

### Negative

⚠️ **Increased complexity** - Three deployments instead of one
⚠️ **Routing logic** - Need smart routing in Apache Gateway
⚠️ **Configuration overhead** - Manage three sets of configs
⚠️ **More resources** - Minimum 5 pods vs 1

---

## Implementation Details

### Configuration

Each instance configured via environment variable:

```yaml
# Fineract Read
FINERACT_NODE_ID: "1"
FINERACT_MODE_READ_ENABLED: "true"
FINERACT_MODE_WRITE_ENABLED: "false"
FINERACT_MODE_BATCH_ENABLED: "false"

# Fineract Write
FINERACT_NODE_ID: "2"
FINERACT_MODE_READ_ENABLED: "false"
FINERACT_MODE_WRITE_ENABLED: "true"
FINERACT_MODE_BATCH_ENABLED: "false"

# Fineract Batch
FINERACT_NODE_ID: "3"
FINERACT_MODE_READ_ENABLED: "false"
FINERACT_MODE_WRITE_ENABLED: "false"
FINERACT_MODE_BATCH_ENABLED: "true"
```

### Routing Rules (Apache Gateway)

```apache
# Read operations (GET)
<LocationMatch "^/fineract-provider/api/v1/.*">
    RequestHeader set X-Fineract-Instance "read"
    ProxyPass http://fineract-read:8080/
</LocationMatch>

# Write operations (POST, PUT, DELETE)
<LocationMatch "^/fineract-provider/api/v1/.*">
    RequestHeader set X-Fineract-Instance "write"
    ProxyPass http://fineract-write:8080/
</LocationMatch>

# Batch endpoints
<Location "/fineract-provider/api/v1/jobs">
    ProxyPass http://fineract-batch:8080/
</Location>
```

### Resource Allocation

| Instance | Min CPU | Max CPU | Min Memory | Max Memory | Replicas |
|----------|---------|---------|------------|------------|----------|
| Read | 500m | 2000m | 1Gi | 4Gi | 2-10 |
| Write | 1000m | 3000m | 2Gi | 6Gi | 2-5 |
| Batch | 1000m | 4000m | 2Gi | 8Gi | 1 |

---

## Alternatives Considered

### 1. Single Instance

**Rejected**: Resource contention, no independent scaling

### 2. Read-Write Separation Only

**Considered but enhanced**: Added batch instance for better isolation

### 3. Microservices Decomposition

**Rejected**: Too complex, requires Fineract code changes

---

## Migration Path

From single-instance to multi-instance:

1. Deploy read instance alongside existing
2. Route read traffic to new instance
3. Split existing to write + batch
4. Monitor and adjust

---

## Monitoring

Track per-instance metrics:
- Request rate by type (read/write/batch)
- Response times per instance
- Resource utilization per instance
- Error rates per instance

---

## References

- [Main README](../../README.md#multi-instance-fineract-deployment)
- [Apps Fineract Directory](../../apps/fineract/)
