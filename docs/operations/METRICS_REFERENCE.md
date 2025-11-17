# Metrics Reference

This document provides a complete catalog of metrics available in the Fineract platform, along with PromQL query examples and usage guidance.

## Table of Contents

- [Overview](#overview)
- [Metric Naming Conventions](#metric-naming-conventions)
- [Fineract Metrics](#fineract-metrics)
- [Keycloak Metrics](#keycloak-metrics)
- [Redis Metrics](#redis-metrics)
- [OAuth2 Proxy Metrics](#oauth2-proxy-metrics)
- [Kubernetes Metrics](#kubernetes-metrics)
- [PostgreSQL Metrics](#postgresql-metrics)
- [PromQL Query Examples](#promql-query-examples)
- [Cardinality Considerations](#cardinality-considerations)
- [Retention Policies](#retention-policies)

---

## Overview

The Fineract platform exposes metrics in Prometheus format from multiple components:

| Component | Metrics Endpoint | Scrape Interval | Typical Cardinality |
|-----------|------------------|-----------------|---------------------|
| Fineract (Read/Write/Batch) | `/fineract-provider/actuator/prometheus` | 30s | ~500 series |
| Keycloak | `/metrics` | 30s | ~200 series |
| Redis | Port 9121 (redis-exporter) | 30s | ~100 series |
| OAuth2 Proxy | `/metrics` | 30s | ~50 series |
| Kubernetes | kube-state-metrics | 30s | ~1000 series |

**Total Estimated Cardinality**: ~2,000-3,000 time series for dev environment

---

## Metric Naming Conventions

### Standard Prefixes

- `http_server_requests_*` - HTTP request metrics (Spring Boot Actuator)
- `jvm_*` - JVM runtime metrics (memory, GC, threads)
- `hikaricp_*` - Database connection pool metrics (HikariCP)
- `cache_*` - Cache operation metrics (Spring Cache)
- `redis_*` - Redis server metrics (redis-exporter)
- `keycloak_*` - Keycloak-specific metrics
- `oauth2_proxy_*` - OAuth2 Proxy metrics
- `kube_*` - Kubernetes object state metrics
- `node_*` - Node-level system metrics

### Metric Types

- **Counter** - Monotonically increasing value (e.g., `http_server_requests_seconds_count`)
- **Gauge** - Current value that can go up or down (e.g., `jvm_memory_used_bytes`)
- **Histogram** - Distribution of values (e.g., `http_server_requests_seconds_bucket`)
- **Summary** - Similar to histogram with quantiles (e.g., `http_server_requests_seconds`)

### Common Labels

| Label | Description | Example Values |
|-------|-------------|----------------|
| `namespace` | Kubernetes namespace | `fineract-dev`, `monitoring` |
| `pod` | Pod name | `fineract-write-7d8f9b5c-x7k2m` |
| `app` | Application name | `fineract-write`, `keycloak` |
| `instance` | Target instance | `10.42.0.73:8080` |
| `job` | Scrape job name | `fineract-read` |
| `uri` | HTTP request URI | `/fineract-provider/api/v1/loans` |
| `method` | HTTP method | `GET`, `POST`, `PUT`, `DELETE` |
| `status` | HTTP status code | `200`, `404`, `500` |
| `outcome` | Request outcome | `SUCCESS`, `CLIENT_ERROR`, `SERVER_ERROR` |

---

## Fineract Metrics

Fineract exposes Spring Boot Actuator metrics on all three instances (read, write, batch).

### HTTP Request Metrics

#### `http_server_requests_seconds_count`
**Type**: Counter
**Description**: Total number of HTTP requests
**Labels**: `uri`, `method`, `status`, `outcome`, `exception`

**Example Values**:
```
http_server_requests_seconds_count{uri="/fineract-provider/api/v1/clients",method="GET",status="200",outcome="SUCCESS"} 1234
http_server_requests_seconds_count{uri="/fineract-provider/api/v1/loans",method="POST",status="201",outcome="SUCCESS"} 567
http_server_requests_seconds_count{uri="/fineract-provider/api/v1/loans",method="GET",status="500",outcome="SERVER_ERROR"} 12
```

#### `http_server_requests_seconds_sum`
**Type**: Counter (cumulative duration)
**Description**: Total time spent handling requests
**Labels**: Same as `http_server_requests_seconds_count`

#### `http_server_requests_seconds_max`
**Type**: Gauge
**Description**: Maximum request duration in current time window
**Labels**: Same as `http_server_requests_seconds_count`

#### `http_server_requests_seconds_bucket`
**Type**: Histogram
**Description**: Request duration distribution
**Labels**: Same as above + `le` (less than or equal bucket)

**Bucket Boundaries**: `0.001`, `0.002`, `0.005`, `0.01`, `0.02`, `0.05`, `0.1`, `0.2`, `0.5`, `1.0`, `2.0`, `5.0`, `10.0`, `+Inf`

### JVM Memory Metrics

#### `jvm_memory_used_bytes`
**Type**: Gauge
**Description**: Current memory usage in bytes
**Labels**: `area` (heap/nonheap), `id` (memory pool name)

**Example Values**:
```
jvm_memory_used_bytes{area="heap",id="PS Eden Space"} 134217728
jvm_memory_used_bytes{area="heap",id="PS Old Gen"} 536870912
jvm_memory_used_bytes{area="nonheap",id="Metaspace"} 104857600
```

#### `jvm_memory_max_bytes`
**Type**: Gauge
**Description**: Maximum memory available
**Labels**: Same as `jvm_memory_used_bytes`

#### `jvm_memory_committed_bytes`
**Type**: Gauge
**Description**: Memory guaranteed to be available
**Labels**: Same as `jvm_memory_used_bytes`

### JVM Garbage Collection Metrics

#### `jvm_gc_pause_seconds_count`
**Type**: Counter
**Description**: Number of GC pause events
**Labels**: `action`, `cause`

#### `jvm_gc_pause_seconds_sum`
**Type**: Counter
**Description**: Total time spent in GC pauses
**Labels**: Same as above

#### `jvm_gc_memory_allocated_bytes_total`
**Type**: Counter
**Description**: Total bytes allocated (increases heap pressure)

#### `jvm_gc_memory_promoted_bytes_total`
**Type**: Counter
**Description**: Total bytes promoted from young to old generation

### Database Connection Pool Metrics (HikariCP)

#### `hikaricp_connections_active`
**Type**: Gauge
**Description**: Number of active connections currently in use
**Labels**: `pool` (connection pool name)

**Example**: `hikaricp_connections_active{pool="HikariPool-1"} 5`

#### `hikaricp_connections_idle`
**Type**: Gauge
**Description**: Number of idle connections available
**Labels**: `pool`

#### `hikaricp_connections_pending`
**Type**: Gauge
**Description**: Number of threads waiting for a connection
**Labels**: `pool`

**Alert Threshold**: > 0 indicates connection starvation

#### `hikaricp_connections_max`
**Type**: Gauge
**Description**: Maximum pool size
**Labels**: `pool`

**Default Value**: 10

#### `hikaricp_connections_min`
**Type**: Gauge
**Description**: Minimum pool size
**Labels**: `pool`

#### `hikaricp_connections_timeout_total`
**Type**: Counter
**Description**: Total number of connection timeouts
**Labels**: `pool`

**Alert Threshold**: rate > 0

#### `hikaricp_connections_creation_seconds_count`
**Type**: Counter
**Description**: Number of connections created
**Labels**: `pool`

#### `hikaricp_connections_creation_seconds_sum`
**Type**: Counter
**Description**: Total time spent creating connections
**Labels**: `pool`

#### `hikaricp_connections_acquire_seconds_count`
**Type**: Counter
**Description**: Number of connection acquisitions
**Labels**: `pool`

#### `hikaricp_connections_acquire_seconds_sum`
**Type**: Counter
**Description**: Total time spent acquiring connections
**Labels**: `pool`

#### `hikaricp_connections_usage_seconds_count`
**Type**: Counter
**Description**: Number of times connections were used
**Labels**: `pool`

#### `hikaricp_connections_usage_seconds_sum`
**Type**: Counter
**Description**: Total time connections were in use
**Labels**: `pool`

### Cache Metrics (Spring Cache / Redis)

#### `cache_gets_total`
**Type**: Counter
**Description**: Total number of cache get operations
**Labels**: `cache`, `result` (hit/miss)

**Example Values**:
```
cache_gets_total{cache="clients",result="hit"} 8500
cache_gets_total{cache="clients",result="miss"} 1500
```

#### `cache_puts_total`
**Type**: Counter
**Description**: Total number of cache put operations
**Labels**: `cache`

#### `cache_evictions_total`
**Type**: Counter
**Description**: Total number of cache evictions
**Labels**: `cache`

#### `cache_size`
**Type**: Gauge
**Description**: Number of entries in cache
**Labels**: `cache`

### Custom Fineract Business Metrics

#### `fineract_loans_disbursed_total`
**Type**: Counter
**Description**: Total number of loans disbursed
**Labels**: `product`, `branch`

#### `fineract_loans_disbursed_amount_total`
**Type**: Counter
**Description**: Total amount of loans disbursed
**Labels**: `product`, `branch`, `currency`

#### `fineract_repayments_received_total`
**Type**: Counter
**Description**: Total number of repayments received
**Labels**: `product`, `branch`

#### `fineract_repayments_received_amount_total`
**Type**: Counter
**Description**: Total amount of repayments received
**Labels**: `product`, `branch`, `currency`

#### `fineract_clients_created_total`
**Type**: Counter
**Description**: Total number of clients created
**Labels**: `branch`, `client_type`

#### `fineract_batch_jobs_executed_total`
**Type**: Counter
**Description**: Total number of batch jobs executed
**Labels**: `job_name`, `status` (success/failure)

---

## Keycloak Metrics

Keycloak exposes metrics on `/metrics` endpoint.

### Authentication Metrics

#### `keycloak_logins_total`
**Type**: Counter
**Description**: Total number of successful logins
**Labels**: `realm`, `client_id`, `provider`

**Example Values**:
```
keycloak_logins_total{realm="fineract",client_id="fineract-app",provider="keycloak"} 1234
keycloak_logins_total{realm="fineract",client_id="oauth2-proxy",provider="keycloak"} 567
```

#### `keycloak_login_failures_total`
**Type**: Counter
**Description**: Total number of failed login attempts
**Labels**: `realm`, `client_id`, `error` (invalid_credentials, user_not_found, user_disabled)

**Alert Threshold**: Spike in rate may indicate brute force attack

#### `keycloak_client_login_attempts_total`
**Type**: Counter
**Description**: Total number of client authentication attempts
**Labels**: `realm`, `client_id`, `outcome` (success/failure)

#### `keycloak_user_event_UPDATE_PASSWORD_total`
**Type**: Counter
**Description**: Number of password change events
**Labels**: `realm`

#### `keycloak_user_event_VERIFY_EMAIL_total`
**Type**: Counter
**Description**: Number of email verification events
**Labels**: `realm`

### Session Metrics

#### `keycloak_sessions`
**Type**: Gauge
**Description**: Current number of user sessions
**Labels**: `realm`, `client_id`

#### `keycloak_sessions_duration_seconds_sum`
**Type**: Counter
**Description**: Total duration of all sessions
**Labels**: `realm`

#### `keycloak_sessions_duration_seconds_count`
**Type**: Counter
**Description**: Total number of completed sessions
**Labels**: `realm`

### Token Metrics

#### `keycloak_tokens_issued_total`
**Type**: Counter
**Description**: Total number of tokens issued
**Labels**: `realm`, `client_id`, `token_type` (access/refresh/id)

#### `keycloak_tokens_refreshed_total`
**Type**: Counter
**Description**: Total number of token refresh operations
**Labels**: `realm`, `client_id`

### JVM Metrics

Keycloak also exposes standard JVM metrics similar to Fineract:
- `jvm_memory_used_bytes`
- `jvm_gc_pause_seconds_count`
- `jvm_threads_current`

---

## Redis Metrics

Redis metrics are exposed by redis-exporter on port 9121.

### Connection Metrics

#### `redis_connected_clients`
**Type**: Gauge
**Description**: Number of client connections
**Default Range**: 1-10

#### `redis_blocked_clients`
**Type**: Gauge
**Description**: Number of clients blocked on blocking calls
**Alert Threshold**: > 0 may indicate application issue

#### `redis_rejected_connections_total`
**Type**: Counter
**Description**: Connections rejected due to maxclients limit
**Alert Threshold**: rate > 0

### Memory Metrics

#### `redis_memory_used_bytes`
**Type**: Gauge
**Description**: Total memory used by Redis
**Alert Threshold**: > 80% of max memory

#### `redis_memory_max_bytes`
**Type**: Gauge
**Description**: Maximum memory Redis can use
**Configured Value**: Based on deployment limits

#### `redis_memory_fragmentation_ratio`
**Type**: Gauge
**Description**: Memory fragmentation ratio
**Healthy Range**: 1.0 - 1.5
**Alert Threshold**: > 2.0 indicates fragmentation issue

### Cache Performance Metrics

#### `redis_keyspace_hits_total`
**Type**: Counter
**Description**: Number of successful key lookups

#### `redis_keyspace_misses_total`
**Type**: Counter
**Description**: Number of failed key lookups

**Cache Hit Ratio**:
```promql
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)
```

**Alert Threshold**: < 0.7 (70%) indicates poor cache effectiveness

#### `redis_evicted_keys_total`
**Type**: Counter
**Description**: Number of keys evicted due to memory limit
**Alert Threshold**: Increasing rate may indicate memory too small

#### `redis_expired_keys_total`
**Type**: Counter
**Description**: Number of keys expired naturally

### Persistence Metrics

#### `redis_rdb_last_save_timestamp_seconds`
**Type**: Gauge
**Description**: Timestamp of last successful RDB save

#### `redis_rdb_changes_since_last_save`
**Type**: Gauge
**Description**: Number of changes since last RDB save

### Command Statistics

#### `redis_commands_processed_total`
**Type**: Counter
**Description**: Total number of commands processed

#### `redis_commands_duration_seconds_total`
**Type**: Counter
**Description**: Total time spent executing commands
**Labels**: `cmd` (command name)

**Example Values**:
```
redis_commands_duration_seconds_total{cmd="get"} 45.2
redis_commands_duration_seconds_total{cmd="set"} 12.8
redis_commands_duration_seconds_total{cmd="mget"} 8.5
```

### Keyspace Metrics

#### `redis_db_keys`
**Type**: Gauge
**Description**: Number of keys in database
**Labels**: `db` (database number)

**Example**: `redis_db_keys{db="0"} 12500`

#### `redis_db_keys_expiring`
**Type**: Gauge
**Description**: Number of keys with expiration set
**Labels**: `db`

---

## OAuth2 Proxy Metrics

OAuth2 Proxy exposes metrics on `/metrics` endpoint.

### Request Metrics

#### `oauth2_proxy_requests_total`
**Type**: Counter
**Description**: Total number of requests handled
**Labels**: `method`, `code` (HTTP status)

**Example Values**:
```
oauth2_proxy_requests_total{method="GET",code="200"} 8900
oauth2_proxy_requests_total{method="GET",code="401"} 45
oauth2_proxy_requests_total{method="POST",code="302"} 123
```

#### `oauth2_proxy_request_duration_seconds_bucket`
**Type**: Histogram
**Description**: Request duration distribution
**Labels**: `method`, `code`, `le` (bucket)

### Authentication Metrics

#### `oauth2_proxy_authentication_attempts_total`
**Type**: Counter
**Description**: Total number of authentication attempts
**Labels**: `outcome` (success/failure)

#### `oauth2_proxy_authenticated_requests_total`
**Type**: Counter
**Description**: Total number of authenticated requests

#### `oauth2_proxy_unauthenticated_requests_total`
**Type**: Counter
**Description**: Total number of unauthenticated requests (redirected to login)

---

## Kubernetes Metrics

Kubernetes metrics are exposed by kube-state-metrics and node-exporter.

### Pod Metrics

#### `kube_pod_status_phase`
**Type**: Gauge (StateSet)
**Description**: Current pod phase
**Labels**: `namespace`, `pod`, `phase` (Pending/Running/Succeeded/Failed/Unknown)

**Values**: 1 when pod is in that phase, 0 otherwise

#### `kube_pod_status_ready`
**Type**: Gauge
**Description**: Pod ready condition
**Labels**: `namespace`, `pod`, `condition` (true/false/unknown)

**Alert**: `kube_pod_status_ready{condition="false"} == 1`

#### `kube_pod_container_status_restarts_total`
**Type**: Counter
**Description**: Number of container restarts
**Labels**: `namespace`, `pod`, `container`

**Alert**: `rate(kube_pod_container_status_restarts_total[5m]) > 0`

#### `kube_pod_container_status_waiting_reason`
**Type**: Gauge (StateSet)
**Description**: Reason for container waiting state
**Labels**: `namespace`, `pod`, `container`, `reason` (CrashLoopBackOff, ImagePullBackOff, etc.)

### Resource Metrics

#### `container_memory_usage_bytes`
**Type**: Gauge
**Description**: Current memory usage
**Labels**: `namespace`, `pod`, `container`

#### `container_memory_working_set_bytes`
**Type**: Gauge
**Description**: Working set memory (excludes cache)
**Labels**: Same as above

#### `container_spec_memory_limit_bytes`
**Type**: Gauge
**Description**: Memory limit
**Labels**: Same as above

#### `container_cpu_usage_seconds_total`
**Type**: Counter
**Description**: Cumulative CPU time consumed
**Labels**: Same as above

### Node Metrics

#### `node_memory_MemAvailable_bytes`
**Type**: Gauge
**Description**: Available memory on node

#### `node_memory_MemTotal_bytes`
**Type**: Gauge
**Description**: Total memory on node

#### `node_cpu_seconds_total`
**Type**: Counter
**Description**: CPU time per mode
**Labels**: `cpu`, `mode` (idle/system/user/iowait)

#### `node_filesystem_avail_bytes`
**Type**: Gauge
**Description**: Available filesystem space
**Labels**: `device`, `mountpoint`

#### `node_filesystem_size_bytes`
**Type**: Gauge
**Description**: Total filesystem size
**Labels**: Same as above

---

## PostgreSQL Metrics

PostgreSQL metrics are exposed through postgres-exporter (if deployed).

### Connection Metrics

#### `pg_stat_database_numbackends`
**Type**: Gauge
**Description**: Number of active connections
**Labels**: `datname` (database name)

#### `pg_settings_max_connections`
**Type**: Gauge
**Description**: Maximum connections configured

### Query Performance Metrics

#### `pg_stat_statements_calls_total`
**Type**: Counter
**Description**: Number of times query was executed
**Labels**: `user`, `datname`, `queryid`

#### `pg_stat_statements_total_time_seconds`
**Type**: Counter
**Description**: Total time spent executing query
**Labels**: Same as above

#### `pg_stat_statements_rows_total`
**Type**: Counter
**Description**: Total rows retrieved or affected
**Labels**: Same as above

### Lock Metrics

#### `pg_locks_count`
**Type**: Gauge
**Description**: Number of locks held
**Labels**: `datname`, `mode`, `locktype`

**Alert**: High lock counts may indicate blocking queries

---

## PromQL Query Examples

### Request Rate Calculations

**Total request rate per second (all Fineract instances)**:
```promql
sum(rate(http_server_requests_seconds_count[5m]))
```

**Request rate by endpoint**:
```promql
sum by (uri) (rate(http_server_requests_seconds_count[5m]))
```

**Request rate by instance (read/write/batch)**:
```promql
sum by (pod) (rate(http_server_requests_seconds_count[5m]))
```

### Error Rate Calculations

**5xx error rate**:
```promql
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
```

**Error percentage**:
```promql
100 * sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))
```

**Top 10 endpoints by error rate**:
```promql
topk(10, sum by (uri) (rate(http_server_requests_seconds_count{status=~"5.."}[5m])))
```

### Latency Calculations

**p50 (median) latency**:
```promql
histogram_quantile(0.5, sum by (le) (rate(http_server_requests_seconds_bucket[5m])))
```

**p95 latency**:
```promql
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket[5m])))
```

**p99 latency**:
```promql
histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket[5m])))
```

**p95 latency by endpoint**:
```promql
histogram_quantile(0.95, sum by (uri, le) (rate(http_server_requests_seconds_bucket[5m])))
```

**Average request duration**:
```promql
sum(rate(http_server_requests_seconds_sum[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))
```

### Memory Usage

**JVM heap usage percentage**:
```promql
100 * sum(jvm_memory_used_bytes{area="heap"})
  / sum(jvm_memory_max_bytes{area="heap"})
```

**JVM heap usage by pod**:
```promql
sum by (pod) (jvm_memory_used_bytes{area="heap"}) / 1024 / 1024 / 1024
```

**Container memory usage percentage**:
```promql
100 * container_memory_usage_bytes
  / container_spec_memory_limit_bytes
```

**Top 5 pods by memory usage**:
```promql
topk(5, container_memory_usage_bytes)
```

### Database Connection Pool

**Connection pool utilization percentage**:
```promql
100 * hikaricp_connections_active / hikaricp_connections_max
```

**Average connection acquisition time (ms)**:
```promql
1000 * (rate(hikaricp_connections_acquire_seconds_sum[5m])
  / rate(hikaricp_connections_acquire_seconds_count[5m]))
```

**Connection timeout rate**:
```promql
rate(hikaricp_connections_timeout_total[5m])
```

### Cache Performance

**Redis cache hit ratio**:
```promql
100 * rate(redis_keyspace_hits_total[5m])
  / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
```

**Spring cache hit ratio**:
```promql
100 * sum(rate(cache_gets_total{result="hit"}[5m]))
  / sum(rate(cache_gets_total[5m]))
```

**Cache eviction rate**:
```promql
rate(redis_evicted_keys_total[5m])
```

### Authentication Metrics

**Keycloak login rate**:
```promql
sum(rate(keycloak_logins_total[5m]))
```

**Login success rate**:
```promql
100 * sum(rate(keycloak_logins_total[5m]))
  / (sum(rate(keycloak_logins_total[5m])) + sum(rate(keycloak_login_failures_total[5m])))
```

**OAuth2 Proxy authentication success rate**:
```promql
100 * oauth2_proxy_authentication_attempts_total{outcome="success"}
  / ignoring(outcome) oauth2_proxy_authentication_attempts_total
```

### Resource Utilization

**Node CPU utilization percentage**:
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Node memory utilization percentage**:
```promql
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

**Pod CPU usage (millicores)**:
```promql
1000 * sum by (pod) (rate(container_cpu_usage_seconds_total[5m]))
```

**Disk space usage percentage**:
```promql
100 * (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes)
```

### Business Metrics

**Loan disbursement rate (per hour)**:
```promql
sum(rate(fineract_loans_disbursed_total[1h])) * 3600
```

**Loan disbursement amount rate (per hour)**:
```promql
sum(rate(fineract_loans_disbursed_amount_total[1h])) * 3600
```

**Client creation rate (per day)**:
```promql
sum(rate(fineract_clients_created_total[24h])) * 86400
```

**Batch job success rate**:
```promql
100 * sum(rate(fineract_batch_jobs_executed_total{status="success"}[1h]))
  / sum(rate(fineract_batch_jobs_executed_total[1h]))
```

### Advanced Queries

**Request rate prediction (next 4 hours using linear regression)**:
```promql
predict_linear(sum(rate(http_server_requests_seconds_count[1h]))[4h:], 4*3600)
```

**Anomaly detection (requests > 2 std deviations from mean)**:
```promql
abs(sum(rate(http_server_requests_seconds_count[5m]))
  - avg_over_time(sum(rate(http_server_requests_seconds_count[5m]))[1h:]))
  > 2 * stddev_over_time(sum(rate(http_server_requests_seconds_count[5m]))[1h:])
```

**Service availability (percentage of successful requests)**:
```promql
100 * sum(rate(http_server_requests_seconds_count{status!~"5.."}[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))
```

---

## Cardinality Considerations

High cardinality (many unique time series) can impact Prometheus performance and storage.

### High Cardinality Labels (Use with Caution)

| Label | Typical Cardinality | Impact |
|-------|---------------------|--------|
| `uri` | 100-500 | Medium - OK if grouped by endpoint pattern |
| `client_id` | 10-50 | Low - Safe to use |
| `user_id` | 1000-10000+ | **HIGH - Avoid!** |
| `loan_id` | 10000-1000000+ | **VERY HIGH - Never use!** |
| `transaction_id` | Unlimited | **EXTREME - Never use!** |
| `ip_address` | 1000-10000+ | **HIGH - Avoid!** |

### Best Practices

**DO**:
- Use labels for dimensions with bounded cardinality (< 100 values)
- Group URIs by pattern (e.g., `/api/v1/loans/*` instead of `/api/v1/loans/12345`)
- Aggregate by meaningful business dimensions (product, branch)
- Drop unnecessary labels using metric_relabel_configs

**DON'T**:
- Include IDs (user_id, loan_id, transaction_id) as labels
- Include timestamps or UUIDs as labels
- Include unbounded text fields (descriptions, names) as labels
- Create labels for data that should be logged instead

### Cardinality Reduction Example

**High Cardinality (BAD)**:
```yaml
# Creates 1 time series per loan ID (potentially millions!)
fineract_loan_amount{loan_id="12345",status="active"} 10000
fineract_loan_amount{loan_id="12346",status="active"} 5000
...
```

**Low Cardinality (GOOD)**:
```yaml
# Creates time series per product and branch (dozens)
fineract_loans_total{product="personal",branch="main",status="active"} 1234
fineract_loans_amount_total{product="personal",branch="main",currency="USD"} 5000000
```

### Checking Cardinality

**Query current cardinality**:
```promql
# Total number of time series
count({__name__=~".+"})

# Cardinality per metric
count by (__name__) ({__name__=~".+"})

# Cardinality per label
count by (label_name) ({__name__="metric_name"})
```

**Check via Prometheus UI**:
```
http://localhost:9090/api/v1/status/tsdb
```

**Check via curl**:
```bash
curl http://localhost:9090/api/v1/status/tsdb | jq '.data.seriesCountByMetricName'
```

---

## Retention Policies

### Default Retention

**Prometheus**: 15 days (configurable)

**Storage Calculation**:
- Average sample size: ~2 bytes (timestamp + value compressed)
- Samples per series: `(retention_seconds / scrape_interval_seconds)`
- Total storage: `time_series_count * samples_per_series * 2 bytes`

**Example for dev environment**:
- Time series: 2,000
- Retention: 15 days (1,296,000 seconds)
- Scrape interval: 30 seconds
- Samples per series: 1,296,000 / 30 = 43,200
- Total storage: 2,000 * 43,200 * 2 = ~172 MB (compressed)
- With overhead: ~500 MB - 1 GB actual disk usage

### Recommended Retention by Environment

| Environment | Retention | Storage (per replica) | Use Case |
|-------------|-----------|----------------------|----------|
| Development | 7 days | 5-10 GB | Short-term troubleshooting |
| Staging | 15 days | 10-20 GB | Pre-production testing |
| Production | 30 days | 20-40 GB | Operational monitoring |
| Long-term | 90+ days | 60-120 GB | Capacity planning, trends |

### Configuring Retention

**In Prometheus StatefulSet**:
```yaml
args:
  - --storage.tsdb.retention.time=15d
  - --storage.tsdb.retention.size=50GB  # Optional: size-based limit
```

**Via ArgoCD Application**:
```yaml
# apps/monitoring/base/prometheus-config.yaml
spec:
  retention: 15d
  retentionSize: 50GB
```

### Data Downsampling Strategy

For long-term retention, consider downsampling:

1. **High Resolution (Raw)**: 0-7 days at 30s scrape interval
2. **Medium Resolution**: 7-30 days at 5m aggregation
3. **Low Resolution**: 30-90 days at 1h aggregation
4. **Archive**: 90+ days in object storage (S3)

**Implementation Options**:
- **Thanos**: Multi-cluster, long-term storage, downsampling
- **Cortex**: Multi-tenant, horizontally scalable
- **VictoriaMetrics**: Drop-in replacement with better compression

---

## Related Documentation

- [Monitoring and Alerting Guide](MONITORING_ALERTING.md) - Deployment and configuration
- [Alert Runbook](ALERT_RUNBOOK.md) - Alert investigation procedures
- [Operations Guide](../OPERATIONS_GUIDE.md) - Overall operations procedures

---

## Additional Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/naming/)
- [PromQL for Humans](https://timber.io/blog/promql-for-humans/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/best-practices-for-creating-dashboards/)
- [HikariCP Monitoring Guide](https://github.com/brettwooldridge/HikariCP/wiki/MBean-(JMX)-Monitoring-and-Management)

---

**Document Version**: 1.0
**Last Updated**: 2025-01-02
**Maintained By**: Platform Team
