# Logging Stack (Loki + Promtail)

Centralized log aggregation and querying infrastructure for the Fineract platform using Grafana Loki and Promtail. This stack provides scalable, cost-effective log management for all Kubernetes workloads.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
  - [Loki](#loki)
  - [Promtail](#promtail)
- [Configuration](#configuration)
  - [Loki Configuration](#loki-configuration)
  - [Promtail Configuration](#promtail-configuration)
  - [Log Retention](#log-retention)
- [Deployment](#deployment)
- [Usage](#usage)
  - [Querying Logs](#querying-logs)
  - [LogQL Examples](#logql-examples)
  - [Grafana Integration](#grafana-integration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Related Documentation](#related-documentation)

## Overview

The logging stack provides centralized log aggregation for all Fineract platform components.

**Key Features:**
- **Loki** - Log aggregation system inspired by Prometheus
- **Promtail** - Log collector agent running on every node
- 30-day log retention
- LogQL query language (similar to PromQL)
- Grafana integration for log visualization
- Efficient storage (indexes only metadata, not log content)
- Low resource footprint

**Loki Version**: 2.9.3
**Promtail Version**: 2.9.3

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Pod (App) │  │  Pod (App) │  │  Pod (App) │            │
│  │   Logs     │  │   Logs     │  │   Logs     │            │
│  └──────┬─────┘  └──────┬─────┘  └──────┬─────┘            │
│         │                │                │                  │
│         └────────────────┴────────────────┘                  │
│                          │                                   │
│              /var/log/pods/* (hostPath)                      │
│                          │                                   │
│                ┌─────────▼─────────┐                         │
│                │    Promtail       │ (DaemonSet)             │
│                │  (Log Collector)  │ (1 pod per node)        │
│                └─────────┬─────────┘                         │
│                          │                                   │
│                          │ HTTP Push (port 3100)             │
│                          │                                   │
│                ┌─────────▼─────────┐                         │
│                │       Loki        │ (StatefulSet)           │
│                │  (Log Storage)    │ (1 replica)             │
│                └─────────┬─────────┘                         │
│                          │                                   │
│                    PVC: 100Gi Storage                        │
│                    Retention: 30 days                        │
│                          │                                   │
│                ┌─────────▼─────────┐                         │
│                │      Grafana      │ (Visualization)         │
│                │  (Log Queries)    │                         │
│                └───────────────────┘                         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Log Flow

1. **Application Pods** → Write logs to stdout/stderr
2. **Kubernetes** → Captures logs in `/var/log/pods/`
3. **Promtail DaemonSet** → Tails log files from hostPath volume
4. **Promtail** → Enriches logs with Kubernetes metadata (pod, namespace, labels)
5. **Promtail** → Pushes logs to Loki via HTTP (port 3100)
6. **Loki** → Indexes metadata (labels), stores log content
7. **Loki** → Serves queries via HTTP API
8. **Grafana** → Queries Loki and visualizes logs

## Components

### Loki

**Loki** is a horizontally-scalable, highly-available log aggregation system inspired by Prometheus.

**Key Characteristics:**
- **Label-based indexing**: Indexes only metadata (labels), not full log text
- **Cost-effective**: Stores raw logs without full-text indexing
- **LogQL**: Prometheus-inspired query language for logs
- **Multi-tenancy**: Supports multiple tenants (disabled in this deployment)
- **Grafana native**: First-class integration with Grafana

**Deployment:**
- **Type**: StatefulSet (1 replica)
- **Storage**: 100Gi PersistentVolumeClaim
- **Retention**: 30 days
- **Resources**:
  - Requests: 200m CPU, 512Mi memory
  - Limits: 1000m CPU, 2Gi memory

**Endpoints:**
- HTTP: `http://loki-headless.logging.svc.cluster.local:3100`
- gRPC: Port 9096
- Metrics: `http://loki-headless.logging.svc.cluster.local:3100/metrics`
- Ready: `http://loki-headless.logging.svc.cluster.local:3100/ready`

**Storage Backend**: Filesystem (local PVC)
- Chunks: `/loki/chunks`
- Index: `/loki/index` (BoltDB)
- Rules: `/loki/rules`

**Configuration File**: `/apps/logging/base/loki-configmap.yaml`

### Promtail

**Promtail** is an agent that ships logs to Loki, similar to how Prometheus exporters push metrics.

**Key Characteristics:**
- **DaemonSet**: Runs on every Kubernetes node
- **Automatic discovery**: Discovers pods via Kubernetes API
- **Label enrichment**: Adds Kubernetes metadata (namespace, pod, container)
- **Filtering**: Can drop/keep logs based on patterns
- **Efficient**: Minimal CPU/memory footprint

**Deployment:**
- **Type**: DaemonSet (1 pod per node)
- **Tolerations**: Runs on all nodes (including control plane)
- **Resources**:
  - Requests: 100m CPU, 128Mi memory
  - Limits: 200m CPU, 256Mi memory

**Security Context:**
- **Runs as root** (UID 0) - Required to read log files from `/var/log`
- **RBAC**: Minimal permissions (list pods, get pods, watch pods)
- **Mitigation**: Read-only volume mounts, RBAC restrictions

**Volume Mounts:**
- `/var/log` (hostPath, read-only) - System logs
- `/var/lib/docker/containers` (hostPath, read-only) - Container logs
- `/etc/promtail` (ConfigMap) - Promtail configuration

**Configuration File**: `/apps/logging/base/promtail-configmap.yaml`

## Configuration

### Loki Configuration

**Key Settings** (`loki-configmap.yaml`):

#### Storage Configuration
```yaml
common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
```

**Storage Type**: Filesystem (local PVC)
- **Chunks**: Raw log data
- **Index**: BoltDB-based index for fast queries
- **Replication**: Single replica (no replication)

**Future Scaling**: For production with HA, consider:
- AWS S3 / Azure Blob / GCS for object storage
- Multiple Loki replicas with object storage backend
- Separate read/write/backend components

#### Schema Configuration
```yaml
schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
```

**Schema**: v11 (current recommended schema)
- **Index**: BoltDB Shipper (stores index in object storage)
- **Period**: 24-hour index chunks

#### Retention Configuration
```yaml
limits_config:
  retention_period: 720h  # 30 days

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h  # 30 days

compactor:
  retention_enabled: true
  retention_delete_delay: 2h
  compaction_interval: 10m
```

**Retention**: 30 days (720 hours)
- Logs older than 30 days are automatically deleted
- Compactor runs every 10 minutes to enforce retention
- 2-hour delay before deleting expired logs

**Adjusting Retention**:
```yaml
# For shorter retention (7 days)
retention_period: 168h

# For longer retention (90 days)
retention_period: 2160h
```

**Storage Calculation**:
- 30 days retention ≈ 50-100Gi (depends on log volume)
- Adjust PVC size based on log ingestion rate

#### Rate Limiting
```yaml
limits_config:
  ingestion_rate_mb: 10           # 10 MB/s per stream
  ingestion_burst_size_mb: 20     # 20 MB burst
  max_query_series: 500           # Max series per query
```

**Rate Limits** protect Loki from overload:
- **Ingestion Rate**: 10 MB/s sustained per stream
- **Burst Size**: 20 MB temporary spikes
- **Query Limit**: 500 series per query

**Increase for high-volume environments**:
```yaml
ingestion_rate_mb: 50
ingestion_burst_size_mb: 100
max_query_series: 1000
```

#### Query Configuration
```yaml
query_range:
  align_queries_with_step: true
  max_retries: 5
  parallelise_shardable_queries: true
  cache_results: true
```

**Query Optimization**:
- **Parallelization**: Shards queries across time ranges
- **Caching**: Caches query results
- **Retries**: Automatically retries failed queries

### Promtail Configuration

**Key Settings** (`promtail-configmap.yaml`):

#### Kubernetes Service Discovery
Promtail automatically discovers pods via Kubernetes API:

```yaml
scrape_configs:
- job_name: kubernetes-pods
  kubernetes_sd_configs:
  - role: pod
```

**Discovery**: Promtail watches Kubernetes API for pod events

#### Label Relabeling

Promtail enriches logs with Kubernetes metadata:

**Standard Labels Added**:
- `job`: Job name (e.g., `kubernetes-pods`)
- `namespace`: Pod namespace (e.g., `fineract-dev`)
- `pod`: Pod name (e.g., `fineract-write-abc123`)
- `container`: Container name (e.g., `fineract`)
- `node_name`: Node where pod runs
- `app`: App label from pod (if present)

**Custom Labels**:
Add custom labels via pod annotations:
```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    loki.io/log_level: "debug"
    loki.io/component: "api"
```

#### Log Filtering

**Drop Logs** (reduce noise):
```yaml
- action: drop
  regex: ".*healthcheck.*"
```

**Keep Only Specific Logs**:
```yaml
- action: keep
  source_labels: ['__meta_kubernetes_pod_label_app']
  regex: 'fineract.*'
```

### Log Retention

**Current Retention**: 30 days

**Storage Calculation**:
```
Daily Log Volume: ~3-5 GB/day (estimated for Fineract platform)
30 days: ~90-150 GB

Actual usage varies based on:
- Log verbosity (INFO vs DEBUG)
- Request volume
- Number of pods
```

**Monitoring Disk Usage**:
```bash
# Check PVC usage
kubectl exec -it loki-0 -n logging -- df -h /loki

# Check index and chunk sizes
kubectl exec -it loki-0 -n logging -- du -sh /loki/chunks /loki/index
```

**Adjusting Retention**:

1. Edit Loki ConfigMap:
```bash
kubectl edit configmap loki-config -n logging
```

2. Update retention settings:
```yaml
limits_config:
  retention_period: 168h  # 7 days
table_manager:
  retention_period: 168h  # 7 days
```

3. Restart Loki:
```bash
kubectl rollout restart statefulset/loki -n logging
```

4. Adjust PVC size if needed:
```bash
# Expand PVC (if storage class supports expansion)
kubectl patch pvc storage-loki-0 -n logging -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

## Deployment

### Prerequisites

1. **Kubernetes Cluster**: 1.28+ with persistent storage
2. **StorageClass**: Default StorageClass with `ReadWriteOnce` support
3. **ArgoCD**: (Optional) For GitOps deployment
4. **Grafana**: (Optional) For log visualization

### ArgoCD Deployment

**ArgoCD Application**: `argocd/applications/{dev,uat,prod}/logging.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: logging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fineract-gitops.git
    targetRevision: main
    path: apps/logging/base
  destination:
    server: https://kubernetes.default.svc
    namespace: logging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Deploy**:
```bash
# Apply ArgoCD application
kubectl apply -f argocd/applications/dev/logging.yaml

# Monitor deployment
argocd app get logging --watch

# Check sync status
argocd app sync logging
```

### Manual Deployment

```bash
# Apply logging stack
kubectl apply -k apps/logging/base/

# Verify deployment
kubectl get all -n logging

# Check Loki status
kubectl get statefulset loki -n logging
kubectl get pods -n logging -l app.kubernetes.io/name=loki

# Check Promtail status
kubectl get daemonset promtail -n logging
kubectl get pods -n logging -l app.kubernetes.io/name=promtail

# View logs
kubectl logs -f statefulset/loki -n logging
kubectl logs daemonset/promtail -n logging --tail=50
```

### Post-Deployment Verification

```bash
# Check Loki is ready
kubectl exec -it loki-0 -n logging -- wget -qO- http://localhost:3100/ready

# Check Promtail is sending logs
kubectl logs -n logging daemonset/promtail | grep "Successfully sent"

# Query Loki directly
kubectl exec -it loki-0 -n logging -- wget -qO- \
  'http://localhost:3100/loki/api/v1/query?query={namespace="fineract-dev"}&limit=10'
```

## Usage

### Querying Logs

#### Via kubectl Port-Forward

```bash
# Forward Loki port
kubectl port-forward -n logging svc/loki-headless 3100:3100

# Query logs (from another terminal)
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="fineract-dev"}' \
  --data-urlencode 'limit=10' | jq
```

#### Via Grafana

1. Add Loki data source in Grafana:
   - URL: `http://loki-headless.logging.svc.cluster.local:3100`
   - Access: Server (proxy)

2. Create log query in Explore:
   - Select Loki data source
   - Enter LogQL query
   - View logs

### LogQL Examples

LogQL is Loki's query language, inspired by PromQL.

#### Basic Log Queries

**View logs from a namespace:**
```logql
{namespace="fineract-dev"}
```

**View logs from a specific pod:**
```logql
{namespace="fineract-dev", pod="fineract-write-abc123"}
```

**View logs from a specific container:**
```logql
{namespace="fineract-dev", container="fineract"}
```

**View logs from all Fineract pods:**
```logql
{namespace="fineract-dev", app=~"fineract.*"}
```

#### Log Filtering

**Filter logs by content (regex):**
```logql
{namespace="fineract-dev"} |= "error"
```

**Exclude logs by content:**
```logql
{namespace="fineract-dev"} != "healthcheck"
```

**Case-insensitive search:**
```logql
{namespace="fineract-dev"} |~ "(?i)error|exception"
```

**Multiple filters (AND):**
```logql
{namespace="fineract-dev"} |= "error" != "healthcheck"
```

#### Log Parsing

**Parse JSON logs:**
```logql
{namespace="fineract-dev"} | json | level="ERROR"
```

**Parse logfmt logs:**
```logql
{namespace="fineract-dev"} | logfmt | method="POST"
```

**Extract fields with regex:**
```logql
{namespace="fineract-dev"} | regexp "user=(?P<user>\\w+)"
```

#### Aggregations

**Count log lines per pod:**
```logql
sum by (pod) (count_over_time({namespace="fineract-dev"}[1h]))
```

**Rate of error logs:**
```logql
rate({namespace="fineract-dev"} |= "error" [5m])
```

**Bytes processed per second:**
```logql
sum(rate({namespace="fineract-dev"} | unwrap bytes [1m]))
```

#### Time Ranges

**Last hour:**
```logql
{namespace="fineract-dev"} [1h]
```

**Specific time range:**
```
# In Grafana UI: Use time picker
# In API: &start=<timestamp>&end=<timestamp>
```

### Grafana Integration

#### Add Loki Data Source

1. Navigate to **Configuration** → **Data Sources** → **Add data source**
2. Select **Loki**
3. Configure:
   - **Name**: Loki
   - **URL**: `http://loki-headless.logging.svc.cluster.local:3100`
   - **Access**: Server (proxy)
4. Click **Save & Test**

#### Create Log Dashboard

**Example Dashboard Panels:**

1. **Real-time Logs**:
   - Query: `{namespace="fineract-dev"}`
   - Visualization: Logs
   - Options: Show time, wrap lines

2. **Error Rate**:
   - Query: `rate({namespace="fineract-dev"} |= "error" [5m])`
   - Visualization: Graph
   - Y-axis: Errors/second

3. **Log Volume by Pod**:
   - Query: `sum by (pod) (count_over_time({namespace="fineract-dev"}[1m]))`
   - Visualization: Bar gauge

4. **Top Error Messages**:
   - Query: `topk(10, sum by (msg) (count_over_time({namespace="fineract-dev"} |= "error" | json [1h])))`
   - Visualization: Table

#### Explore Logs

1. Navigate to **Explore** in Grafana
2. Select **Loki** data source
3. Enter LogQL query
4. Click **Run query**
5. Features:
   - **Live tailing**: Real-time log streaming
   - **Context**: View surrounding log lines
   - **Log details**: Expand log entries for full content
   - **Field filtering**: Click labels to filter

## Monitoring

### Loki Metrics

Loki exposes Prometheus metrics at `/metrics` endpoint.

**Key Metrics:**
- `loki_ingester_chunks_created_total`: Chunks created
- `loki_ingester_bytes_received_total`: Bytes ingested
- `loki_distributor_lines_received_total`: Log lines received
- `loki_request_duration_seconds`: Query latency

**ServiceMonitor** (if using Prometheus Operator):
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: loki
  namespace: logging
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: loki
  endpoints:
  - port: http-metrics
    path: /metrics
```

### Promtail Metrics

**Key Metrics:**
- `promtail_sent_bytes_total`: Bytes sent to Loki
- `promtail_dropped_bytes_total`: Bytes dropped (errors)
- `promtail_read_lines_total`: Lines read from logs

**Access Metrics:**
```bash
# Port-forward Promtail
kubectl port-forward -n logging daemonset/promtail 9080:9080

# View metrics
curl http://localhost:9080/metrics
```

### Health Checks

**Loki Health:**
```bash
# Ready endpoint
kubectl exec -it loki-0 -n logging -- wget -qO- http://localhost:3100/ready

# Metrics endpoint
kubectl exec -it loki-0 -n logging -- wget -qO- http://localhost:3100/metrics
```

**Promtail Health:**
```bash
# Check Promtail logs
kubectl logs -n logging daemonset/promtail --tail=50

# Metrics endpoint
kubectl exec -it $(kubectl get pods -n logging -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}') -n logging -- wget -qO- http://localhost:9080/metrics
```

## Troubleshooting

### Common Issues

#### 1. Loki Pod Stuck in Pending

**Symptom**: Loki StatefulSet pod in `Pending` state.

**Cause**: PVC not provisioned or no available storage.

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -n logging

# Describe PVC
kubectl describe pvc storage-loki-0 -n logging

# Check StorageClass
kubectl get storageclass
```

**Solution:**
```bash
# If no default StorageClass, create one or specify in PVC
# If PVC size too large, reduce in loki-statefulset.yaml:
#   storage: 50Gi  # instead of 100Gi

# Delete StatefulSet and recreate with new storage size
kubectl delete statefulset loki -n logging
kubectl apply -k apps/logging/base/
```

#### 2. No Logs Appearing in Loki

**Symptom**: Loki is running, but queries return no logs.

**Cause**: Promtail not sending logs or misconfigured.

**Diagnosis:**
```bash
# Check Promtail pods are running
kubectl get pods -n logging -l app.kubernetes.io/name=promtail

# Check Promtail logs for errors
kubectl logs -n logging daemonset/promtail | grep -i error

# Check Promtail is discovering targets
kubectl logs -n logging daemonset/promtail | grep "target"

# Check Promtail metrics for sent bytes
kubectl exec -it $(kubectl get pods -n logging -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}') -n logging -- wget -qO- http://localhost:9080/metrics | grep promtail_sent_bytes_total
```

**Solution:**
```bash
# Restart Promtail
kubectl rollout restart daemonset/promtail -n logging

# Check RBAC permissions
kubectl get clusterrole promtail -o yaml
kubectl get clusterrolebinding promtail -o yaml

# Verify Promtail can reach Loki
kubectl exec -it $(kubectl get pods -n logging -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}') -n logging -- wget -qO- http://loki-headless.logging.svc.cluster.local:3100/ready
```

#### 3. Loki High Memory Usage

**Symptom**: Loki pod OOMKilled or high memory usage.

**Cause**: High ingestion rate, large queries, or insufficient memory limits.

**Diagnosis:**
```bash
# Check pod resource usage
kubectl top pod -n logging -l app.kubernetes.io/name=loki

# Check memory limits
kubectl get statefulset loki -n logging -o yaml | grep -A 5 resources

# Check ingestion rate
kubectl exec -it loki-0 -n logging -- wget -qO- http://localhost:3100/metrics | grep loki_distributor_bytes_received_total
```

**Solution:**
```bash
# Increase memory limits
# Edit loki-statefulset.yaml:
resources:
  limits:
    memory: "4Gi"  # Increase from 2Gi

# Apply changes
kubectl apply -k apps/logging/base/

# Reduce retention period
# Edit loki-configmap.yaml:
retention_period: 168h  # 7 days instead of 30

# Restart Loki
kubectl rollout restart statefulset/loki -n logging
```

#### 4. "429 Too Many Requests" Errors

**Symptom**: Promtail logs show "429 Too Many Requests" from Loki.

**Cause**: Ingestion rate limit exceeded.

**Diagnosis:**
```bash
# Check Promtail logs
kubectl logs -n logging daemonset/promtail | grep "429"

# Check Loki rate limit settings
kubectl get configmap loki-config -n logging -o yaml | grep ingestion_rate
```

**Solution:**
```bash
# Increase rate limits in loki-configmap.yaml:
limits_config:
  ingestion_rate_mb: 50          # Increase from 10
  ingestion_burst_size_mb: 100   # Increase from 20

# Apply changes
kubectl apply -k apps/logging/base/

# Restart Loki
kubectl rollout restart statefulset/loki -n logging
```

#### 5. Disk Full (PVC at 100%)

**Symptom**: Loki pod crashes or stops ingesting logs, PVC full.

**Cause**: Log retention too long or high log volume.

**Diagnosis:**
```bash
# Check PVC usage
kubectl exec -it loki-0 -n logging -- df -h /loki

# Check chunk and index sizes
kubectl exec -it loki-0 -n logging -- du -sh /loki/*
```

**Solution:**
```bash
# Option 1: Reduce retention period
# Edit loki-configmap.yaml: retention_period: 168h (7 days)

# Option 2: Expand PVC (if storage class supports)
kubectl patch pvc storage-loki-0 -n logging -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'

# Option 3: Clean up old data manually (emergency)
kubectl exec -it loki-0 -n logging -- rm -rf /loki/chunks/fake/*
kubectl rollout restart statefulset/loki -n logging
```

## Performance Tuning

### Loki Performance

**High Log Volume (>10GB/day)**:
```yaml
# Increase resources
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# Increase rate limits
limits_config:
  ingestion_rate_mb: 50
  ingestion_burst_size_mb: 100

# Enable query caching
query_range:
  cache_results: true
  max_retries: 10
```

**Slow Queries**:
```yaml
# Limit query range
limits_config:
  max_query_length: 721h  # 30 days max

# Reduce query series
limits_config:
  max_query_series: 500
```

### Promtail Performance

**High CPU Usage**:
```yaml
# Increase Promtail resources
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Reduce Log Noise** (drop unnecessary logs):
```yaml
# In promtail-configmap.yaml:
- action: drop
  regex: ".*healthcheck.*|.*readiness.*"
```

## Related Documentation

### Core Documentation
- [Architecture Overview](/docs/architecture/README.md)
- [Operations Guide](/docs/OPERATIONS_GUIDE.md)

### Component Documentation
- [Monitoring (Prometheus/Grafana)](/apps/monitoring/README.md)
- [Fineract](/apps/fineract/README.md)
- [Keycloak](/apps/keycloak/README.md)

### External Resources
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Promtail Configuration](https://grafana.com/docs/loki/latest/send-data/promtail/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/query/)

---

**Last Updated**: 2025-01-19
**Maintainer**: DevOps Team
**Loki Version**: 2.9.3
**Promtail Version**: 2.9.3
