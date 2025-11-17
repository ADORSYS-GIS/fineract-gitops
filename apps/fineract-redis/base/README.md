# Redis Cache and Session Store

## Overview

Redis deployment for dual purposes:
1. **OAuth2 Proxy Session Storage**: User authentication sessions
2. **Fineract Application Caching**: Spring Cache for improved performance

This Redis instance is deployed in-cluster to avoid AWS ElastiCache costs (~$11/month savings).

## Purpose

### OAuth2 Proxy Session Storage
- **Session Storage**: OAuth2 Proxy stores user authentication sessions in Redis
- **High Availability**: Shared state across OAuth2 Proxy replicas
- **TTL Management**: Automatic expiration of sessions (4-hour max, 30-min idle)

### Fineract Application Caching
- **Query Results**: Cached database query results to reduce RDS load
- **Entity Cache**: Frequently accessed entities (clients, loans, products)
- **Performance**: Faster response times for read-heavy operations
- **Shared Cache**: Cache shared across all Fineract instances (read/write/batch)

## Architecture

```
┌─────────────────────────┐
│ OAuth2 Proxy (2+ pods)  │
└────────────┬────────────┘
             │ Sessions
             ↓
┌─────────────────────────┐      ┌──────────────────────────┐
│ Fineract Read (1+ pods) │──────│                          │
└─────────────────────────┘      │                          │
                                 │   Redis (in-cluster)     │
┌─────────────────────────┐      │   - Sessions Storage     │
│ Fineract Write (1 pod)  │──────│   - Application Cache    │
└─────────────────────────┘      │   - 512Mi memory         │
             Cache               │   - 450MB max memory     │
             ↓                   │                          │
┌─────────────────────────┐      └──────────────────────────┘
│ Fineract Batch (0-1 pod)│
└─────────────────────────┘
```

## Configuration

### Resource Requirements

- **Memory Requests**: 256Mi
- **Memory Limits**: 512Mi (doubled for Fineract caching)
- **CPU Requests**: 100m
- **CPU Limits**: 200m (increased for caching workload)
- **Storage**: 1Gi persistent volume (for data persistence)

### Memory Allocation

Total maxmemory: 450MB (90% of 512Mi limit)
- **OAuth2 Sessions**: ~50MB (~25,000 sessions @ 2KB each)
- **Fineract Cache**: ~400MB (application data, queries, entities)
- **Eviction Policy**: `allkeys-lru` (Least Recently Used)

## Deployment

```bash
# Deploy Redis for session storage
kubectl apply -k environments/dev

# Verify deployment
kubectl get pods -n fineract-dev -l app=redis-session-store

# Check Redis connectivity
kubectl exec -n fineract-dev redis-session-store-0 -- redis-cli ping
# Expected: PONG
```

## Monitoring

### Check session count

```bash
# Count OAuth2 Proxy sessions
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli KEYS "oauth2*" | wc -l
```

### Monitor memory usage

```bash
# Check Redis memory usage
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli INFO memory

# Check cache statistics
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli INFO stats
```

### View cache keys

```bash
# List all cache keys
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli KEYS "*"

# Count Fineract cache entries
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli KEYS "fineract:cache:*" | wc -l

# Get specific cache entry
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli GET "fineract:cache:<KEY_NAME>"
```

### Performance Metrics

```bash
# Get cache hit/miss ratio
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli INFO stats | grep keyspace

# Check evicted keys
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli INFO stats | grep evicted
```

## Fineract Cache Configuration

Fineract deployments are configured with these Spring Cache environment variables:

```yaml
- name: SPRING_CACHE_TYPE
  value: "redis"
- name: SPRING_REDIS_HOST
  value: "fineract-redis"
- name: SPRING_REDIS_PORT
  value: "6379"
- name: SPRING_CACHE_REDIS_TIME_TO_LIVE
  value: "3600000"  # 1 hour
- name: SPRING_CACHE_REDIS_KEY_PREFIX
  value: "fineract:cache:"
```

## Benefits

### Performance Improvements
- **Reduced Database Load**: Cached queries reduce RDS database queries
- **Faster Response Times**: Cached entities served from memory
- **Scalability**: Shared cache across multiple Fineract instances
- **Cost Savings**: In-cluster Redis saves $11/month vs ElastiCache

### Cache Behavior
- **TTL**: 1 hour for cached entries
- **Eviction**: Automatic LRU eviction when memory limit reached
- **Shared**: All Fineract instances (read/write/batch) share the same cache
- **Invalidation**: Write operations automatically invalidate relevant cache entries

## Troubleshooting

### Clear all cache

```bash
# Flush only Fineract cache (keeps OAuth2 sessions)
kubectl exec -n fineract-dev fineract-redis-0 -- \
  redis-cli KEYS "fineract:cache:*" | \
  xargs kubectl exec -n fineract-dev fineract-redis-0 -- redis-cli DEL

# Flush entire Redis (clears sessions too!)
kubectl exec -n fineract-dev fineract-redis-0 -- redis-cli FLUSHALL
```

### Check cache connectivity

```bash
# Test from Fineract pod
kubectl exec -n fineract-dev deployment/fineract-read -- \
  nc -zv fineract-redis 6379
```

## Notes

- **Persistence**: Data persisted to 1Gi volume, survives pod restarts
- **For Production**: Current configuration suitable for production (with backups)
- **Monitoring**: Redis exporter exposes Prometheus metrics on port 9121
- **Cost**: In-cluster deployment saves ~$11/month vs AWS ElastiCache
