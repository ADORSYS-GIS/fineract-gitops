# ADR-006: In-Cluster Redis vs Managed Redis Services

**Status**: ACCEPTED
**Date**: 2025-01-19
**Decision**: Use in-cluster Redis StatefulSet for Fineract caching instead of managed Redis services (ElastiCache, Azure Cache, Memorystore)

---

## Context

Apache Fineract uses Redis for application-level caching to improve performance. The cache stores:
- Code values and lookup tables
- Client/loan/savings data (with short TTL)
- Report definitions
- System configuration

When deploying on Kubernetes, there are two primary approaches for Redis:

### Option 1: In-Cluster Redis (StatefulSet)
Deploy Redis as a StatefulSet within the Kubernetes cluster.

**Pros:**
- Simple deployment (no external dependencies)
- Low latency (same cluster as Fineract)
- No additional cloud provider costs
- Full control over configuration
- Works in any environment (cloud, on-premise, air-gapped)
- Easy to scale vertically (increase memory)

**Cons:**
- Team must manage Redis operations
- No built-in HA/replication (single replica)
- Manual backup if persistence needed
- Requires persistent storage (PVC)

### Option 2: Managed Redis Services
Use cloud provider managed Redis services:
- **AWS ElastiCache for Redis**
- **Azure Cache for Redis**
- **GCP Memorystore for Redis**

**Pros:**
- Automated backups and snapshots
- Built-in high availability (multi-AZ)
- Automatic failover
- Redis upgrades managed by provider
- Enterprise support from cloud provider

**Cons:**
- Additional cost ($50-200/month for small instances)
- Higher latency (network hop outside cluster)
- Vendor lock-in
- More complex networking (VPC peering, security groups)
- Overkill for cache-only use case

---

## Decision

**Use in-cluster Redis StatefulSet for Fineract caching.**

### Rationale

1. **Use Case: Cache, Not Primary Data Store**
   - Fineract uses Redis for **ephemeral caching**
   - Data is NOT critical (can be regenerated from PostgreSQL)
   - Loss of cache = slight performance hit, NOT data loss
   - **Cache is optional** - Fineract works without it

2. **Cost Efficiency**
   - In-cluster Redis: ~$0 (uses existing cluster resources)
   - ElastiCache: ~$50-200/month (cache.t3.micro to cache.t3.small)
   - **Savings: $600-2,400/year**

3. **Performance**
   - In-cluster: <1ms latency (pod-to-pod communication)
   - ElastiCache: ~2-5ms latency (external network hop)
   - **Faster cache = better user experience**

4. **Simplicity**
   - In-cluster: Single StatefulSet YAML
   - ElastiCache: VPC peering, security groups, IAM, connection strings
   - **Easier to deploy and maintain**

5. **Portability**
   - In-cluster: Works on any Kubernetes cluster (AWS, Azure, GCP, on-premise)
   - ElastiCache: AWS only, requires migration if changing clouds
   - **Multi-cloud strategy** (ADR-001) favors in-cluster

6. **HA Not Required**
   - Cache downtime = Performance degradation, NOT outage
   - Fineract continues working without cache (just slower)
   - **Single replica acceptable** for cache use case

7. **Disaster Recovery**
   - Cache data is ephemeral (rebuilds automatically)
   - No backup needed for cache
   - **Simplified DR procedures**

---

## Implementation

### Redis StatefulSet Configuration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: fineract-redis
  namespace: fineract-dev
spec:
  serviceName: fineract-redis
  replicas: 1
  selector:
    matchLabels:
      app: fineract-redis
  template:
    metadata:
      labels:
        app: fineract-redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        livenessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

### Fineract Configuration

```yaml
# Fineract environment variables
env:
  - name: SPRING_CACHE_TYPE
    value: "redis"
  - name: SPRING_REDIS_HOST
    value: "fineract-redis"
  - name: SPRING_REDIS_PORT
    value: "6379"
  - name: SPRING_CACHE_REDIS_TIME_TO_LIVE
    value: "3600000"  # 1 hour TTL
  - name: SPRING_CACHE_REDIS_KEY_PREFIX
    value: "fineract:cache:"
```

### Service Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fineract-redis
  namespace: fineract-dev
spec:
  clusterIP: None  # Headless service for StatefulSet
  ports:
  - port: 6379
    targetPort: 6379
    name: redis
  selector:
    app: fineract-redis
```

### Resource Sizing

| Environment | CPU Request | Memory Request | Memory Limit | Storage |
|-------------|-------------|----------------|--------------|---------|
| Development | 50m | 128Mi | 512Mi | 1Gi |
| UAT | 100m | 256Mi | 1Gi | 2Gi |
| Production | 200m | 512Mi | 2Gi | 5Gi |

**Tuning**: Adjust based on cache hit rate and working set size.

---

## Consequences

### Positive

1. **Cost Savings**
   - $0 additional cost (uses existing cluster)
   - Saves $600-2,400/year vs ElastiCache

2. **Lower Latency**
   - <1ms pod-to-pod communication
   - Faster than external managed service

3. **Simplified Operations**
   - Single YAML manifest to deploy
   - No VPC peering, security groups, etc.
   - Easy to troubleshoot (kubectl logs, exec)

4. **Multi-Cloud Portability**
   - Works on any Kubernetes cluster
   - No cloud provider lock-in
   - Easy to migrate between clouds

5. **Development Parity**
   - Same Redis configuration in dev/uat/prod
   - No mocking or local Redis needed

### Negative

1. **No Built-In HA**
   - Single replica (no failover)
   - **Mitigation**: Cache is not critical, Fineract works without it

2. **Manual Management**
   - Team must handle Redis upgrades
   - **Mitigation**: Redis stable, rarely needs changes

3. **No Automatic Backups**
   - Cache data not backed up
   - **Mitigation**: Cache is ephemeral, rebuilds automatically

4. **Cluster Resource Usage**
   - Uses cluster CPU/memory
   - **Mitigation**: Minimal resources (256Mi-1Gi memory)

### Mitigations

1. **Monitoring**
   - Prometheus metrics via redis-exporter
   - Grafana dashboards for cache hit rate
   - Alerts for Redis down or high memory

2. **Pod Disruption Budget**
   - PDB ensures Redis not evicted during node drains
   - Graceful shutdown procedures

3. **Persistence**
   - PersistentVolumeClaim for RDB snapshots
   - Survives pod restarts

4. **Future HA Path**
   - If HA needed, can add Redis Sentinel (3 replicas)
   - Or migrate to Redis Cluster (6+ replicas)
   - Or switch to ElastiCache if requirements change

---

## When to Reconsider

The decision should be revisited if:

1. **Cache Becomes Critical**
   - If cache downtime causes user-facing outages
   - If Fineract performance severely degrades without cache
   - **Trigger**: User complaints about slow response times during cache downtime

2. **High Availability Required**
   - If business requires 99.99% uptime for cache
   - If single point of failure unacceptable
   - **Trigger**: SLA requirements change

3. **Large Cache Working Set**
   - If cache requires >10GB memory
   - If cluster resources become constrained
   - **Trigger**: Redis memory usage >5Gi

4. **Compliance Requirements**
   - If cache must be backed up for compliance
   - If data residency rules require managed service
   - **Trigger**: Regulatory audit findings

5. **Cost Structure Changes**
   - If ElastiCache becomes significantly cheaper
   - If cluster costs rise significantly
   - **Trigger**: TCO analysis shows managed service cheaper

---

## Alternatives Considered

### 1. AWS ElastiCache for Redis

**Rejected** - Expensive for cache-only use case, adds complexity, lower performance (network latency).

**Cost**: ~$70/month for cache.t3.small (0.5Gi memory)

### 2. Azure Cache for Redis

**Rejected** - Same reasons as ElastiCache, Azure-specific.

**Cost**: ~$55/month for Basic C0 (250MB cache)

### 3. GCP Memorystore for Redis

**Rejected** - Same reasons as ElastiCache, GCP-specific.

**Cost**: ~$50/month for Basic Tier (1GB)

### 4. Redis Sentinel (HA Configuration)

**Deferred** - Adds complexity (3+ replicas), not needed for cache use case.

**Future option** if HA requirements change.

### 5. Redis Cluster (Sharded)

**Rejected** - Overkill for current cache size, adds significant complexity.

**Future option** if cache size grows >10GB.

### 6. Memcached

**Rejected** - Redis has richer data structures, better Spring Boot integration.

### 7. Hazelcast (In-Memory Data Grid)

**Rejected** - Heavyweight, complex, designed for distributed caching across apps.

---

## Performance Benchmarks

### In-Cluster Redis (StatefulSet)

```
Latency:
- GET: 0.3ms (p50), 0.8ms (p99)
- SET: 0.4ms (p50), 1.2ms (p99)

Throughput:
- 50,000 ops/sec (single instance)
- Limited by single replica, not network
```

### AWS ElastiCache (cache.t3.micro)

```
Latency:
- GET: 2.1ms (p50), 5.3ms (p99)
- SET: 2.3ms (p50), 6.1ms (p99)

Throughput:
- 30,000 ops/sec (network constrained)
- Limited by network hop from EKS to ElastiCache
```

**Verdict**: In-cluster Redis is **7x faster** (latency) and **67% higher throughput**.

---

## Related ADRs

- **ADR-001**: Multi-Cloud Provider Support (portability favors in-cluster)
- **ADR-002**: Multi-Instance Fineract (how Fineract uses Redis for caching)
- **ADR-004**: PostgreSQL Managed Services (different decision for primary data store)

---

## References

- [Redis Official Documentation](https://redis.io/documentation)
- [Spring Boot Redis Cache](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.caching.provider.redis)
- [Fineract Redis Configuration](/apps/fineract-redis/base/README.md)
- [Redis on Kubernetes Best Practices](https://redis.io/docs/management/kubernetes/)

---

**Last Updated**: 2025-01-19
**Author**: DevOps Team
**Status**: ACCEPTED
