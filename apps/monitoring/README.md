# Monitoring Stack (Prometheus + Grafana + AlertManager)

Comprehensive monitoring and alerting infrastructure for the Fineract platform using Prometheus Operator, Grafana, and AlertManager. This stack provides metrics collection, visualization, and intelligent alerting for all platform components.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
  - [Prometheus](#prometheus)
  - [Grafana](#grafana)
  - [AlertManager](#alertmanager)
  - [Prometheus Operator](#prometheus-operator)
- [Configuration](#configuration)
  - [Prometheus Configuration](#prometheus-configuration)
  - [Service Monitors](#service-monitors)
  - [Alert Rules](#alert-rules)
  - [Grafana Configuration](#grafana-configuration)
- [Deployment](#deployment)
- [Usage](#usage)
  - [Accessing Grafana](#accessing-grafana)
  - [Querying Prometheus](#querying-prometheus)
  - [PromQL Examples](#promql-examples)
  - [Creating Dashboards](#creating-dashboards)
- [Monitoring Targets](#monitoring-targets)
- [Alert Rules](#alert-rules-1)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Related Documentation](#related-documentation)

## Overview

The monitoring stack provides comprehensive observability for the entire Fineract platform with metrics, dashboards, and intelligent alerting.

**Key Features:**
- **Prometheus** - Metrics collection and time-series database
- **Grafana** - Visualization and dashboards
- **AlertManager** - Alert routing and notification
- **Prometheus Operator** - Kubernetes-native monitoring configuration
- **ServiceMonitors** - Automatic service discovery
- **30-day metrics retention**
- **Pre-configured alert rules** for Fineract components
- **Custom dashboards** for Fineract, Keycloak, Redis, etc.

**Versions:**
- Prometheus: v2.48.0
- Grafana: 10.2.2
- Prometheus Operator: v0.70.0

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                │
│  │  Fineract  │  │  Keycloak  │  │   Redis    │  (Apps)        │
│  │  :8443     │  │  :8080     │  │  :6379     │                │
│  │  /metrics  │  │  /metrics  │  │  /metrics  │                │
│  └──────┬─────┘  └──────┬─────┘  └──────┬─────┘                │
│         │                │                │                      │
│         └────────────────┴────────────────┘                      │
│                          │                                       │
│              ServiceMonitors (CRDs)                              │
│                          │                                       │
│                ┌─────────▼─────────┐                             │
│                │    Prometheus     │ (StatefulSet)               │
│                │ (Metrics Storage) │ (1 replica)                 │
│                └─────────┬─────────┘                             │
│                          │                                       │
│         PVC: 50Gi Storage, 30-day retention                      │
│                          │                                       │
│         ┌────────────────┼────────────────┐                      │
│         │                │                │                      │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌─────▼──────┐              │
│  │   Grafana   │  │ AlertManager │  │ Prometheus │              │
│  │(Dashboards) │  │ (Alerting)   │  │    API     │              │
│  └─────────────┘  └──────┬───────┘  └────────────┘              │
│                           │                                       │
│                    ┌──────▼───────┐                              │
│                    │ Notifications │                             │
│                    │ (Email/Slack) │                             │
│                    └──────────────┘                              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Monitoring Flow

1. **Applications** → Expose `/metrics` endpoint (Prometheus format)
2. **ServiceMonitors** → Define scrape configuration (CRD)
3. **Prometheus Operator** → Watches ServiceMonitors, generates scrape configs
4. **Prometheus** → Scrapes metrics from targets (every 30s)
5. **Prometheus** → Stores metrics in time-series database
6. **Prometheus** → Evaluates alert rules
7. **AlertManager** → Receives alerts, groups, routes, notifies
8. **Grafana** → Queries Prometheus for visualization
9. **Users** → Access Grafana dashboards

### Prometheus Operator Pattern

The **Prometheus Operator** provides Kubernetes-native configuration:

```
ServiceMonitor CRD → Prometheus Operator → Prometheus Scrape Config
PrometheusRule CRD → Prometheus Operator → Alert Rules
```

**Benefits:**
- Declarative monitoring configuration
- Automatic service discovery
- Dynamic configuration updates (no restarts)
- Kubernetes-native CRDs

## Components

### Prometheus

**Prometheus** is a time-series database and monitoring system for collecting and storing metrics.

**Key Characteristics:**
- **Pull-based**: Scrapes metrics from targets
- **Time-series DB**: Stores metrics with labels and timestamps
- **PromQL**: Powerful query language
- **Service discovery**: Automatic target discovery via Kubernetes API
- **Alerting**: Evaluates rules and sends alerts to AlertManager

**Deployment:**
- **Type**: StatefulSet (managed by Prometheus Operator)
- **Replicas**: 1
- **Storage**: 50Gi PersistentVolumeClaim
- **Retention**: 30 days or 45GB (whichever comes first)
- **Resources**:
  - Requests: 500m CPU, 2Gi memory
  - Limits: 1000m CPU, 4Gi memory

**Endpoints:**
- Web UI: `http://prometheus.monitoring.svc.cluster.local:9090`
- API: `http://prometheus.monitoring.svc.cluster.local:9090/api/v1`
- Metrics: `http://prometheus.monitoring.svc.cluster.local:9090/metrics`

**Storage:**
- **TSDB**: Time-Series Database (local PVC)
- **Blocks**: 2-hour blocks, compacted over time
- **Retention**: 30 days (`retention: 30d`)
- **Size Limit**: 45GB (`retentionSize: 45GB`)

**Configuration File**: `/apps/monitoring/base/prometheus.yaml`

### Grafana

**Grafana** is a visualization platform for creating dashboards and exploring metrics.

**Key Characteristics:**
- **Multi-datasource**: Prometheus, Loki, CloudWatch, etc.
- **Dashboards**: Pre-built and custom dashboards
- **Templating**: Variables and dynamic dashboards
- **Alerts**: Visual alerts based on queries
- **Plugins**: Extensible with community plugins

**Deployment:**
- **Type**: Deployment (1 replica)
- **Storage**: PersistentVolumeClaim for dashboards
- **Resources**:
  - Requests: 100m CPU, 256Mi memory
  - Limits: 500m CPU, 512Mi memory

**Endpoints:**
- Web UI: `http://grafana.monitoring.svc.cluster.local:3000`
- API: `http://grafana.monitoring.svc.cluster.local:3000/api`
- Health: `http://grafana.monitoring.svc.cluster.local:3000/api/health`

**Pre-configured Data Sources:**
- Prometheus: `http://prometheus.monitoring.svc.cluster.local:9090`
- Loki: `http://loki-headless.logging.svc.cluster.local:3100`

**Plugins Installed:**
- `grafana-piechart-panel` - Pie chart visualizations
- `grafana-clock-panel` - Clock panel

**Configuration File**: `/apps/monitoring/base/grafana-deployment.yaml`

### AlertManager

**AlertManager** handles alerts from Prometheus, deduplicates, groups, and routes to notification channels.

**Key Characteristics:**
- **Grouping**: Groups similar alerts together
- **Deduplication**: Prevents duplicate notifications
- **Silencing**: Temporarily mute alerts
- **Routing**: Routes alerts based on labels
- **Inhibition**: Suppresses alerts based on other alerts

**Deployment:**
- **Type**: StatefulSet (managed by Prometheus Operator)
- **Replicas**: 1

**Endpoints:**
- Web UI: `http://alertmanager.monitoring.svc.cluster.local:9093`
- API: `http://alertmanager.monitoring.svc.cluster.local:9093/api/v2`

**Configuration File**: `/apps/monitoring/base/alertmanager-config.yaml`

### Prometheus Operator

**Prometheus Operator** manages Prometheus, AlertManager, and related monitoring components using Kubernetes CRDs.

**CRDs (Custom Resource Definitions):**
- `Prometheus` - Prometheus instance configuration
- `ServiceMonitor` - Defines how to scrape a service
- `PodMonitor` - Defines how to scrape pods directly
- `PrometheusRule` - Alert and recording rules
- `Alertmanager` - AlertManager instance configuration

**Deployment:**
- **Type**: Deployment
- **Version**: v0.70.0

**Configuration File**: `/apps/monitoring/base/prometheus-operator.yaml`

## Configuration

### Prometheus Configuration

**Key Settings** (`prometheus.yaml`):

#### Retention Settings
```yaml
retention: 30d           # Keep metrics for 30 days
retentionSize: 45GB      # Or until storage reaches 45GB
```

**Adjusting Retention:**
```yaml
# Shorter retention (7 days)
retention: 7d
retentionSize: 10GB

# Longer retention (90 days)
retention: 90d
retentionSize: 100GB
```

**Storage Calculation:**
```
Metrics per second: ~1000-2000 (depends on services)
Daily data: ~5-10 GB/day
30 days: ~150-300 GB (compressed)

With 50Gi PVC and 45GB retention limit:
- Effective retention: ~7-10 days (before hitting size limit)
- Adjust PVC size or retention period accordingly
```

#### Service Monitor Selection
```yaml
serviceMonitorSelector:
  matchLabels:
    app.kubernetes.io/part-of: monitoring-stack
```

**Prometheus scrapes all ServiceMonitors with this label.**

#### Alert Configuration
```yaml
alerting:
  alertmanagers:
  - name: alertmanager
    namespace: monitoring
    port: web
```

**Prometheus sends alerts to AlertManager.**

### Service Monitors

**ServiceMonitors** define how Prometheus scrapes metrics from Kubernetes services.

#### Fineract ServiceMonitor

**File**: `servicemonitor-fineract.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fineract
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: fineract
  endpoints:
  - port: https
    path: /fineract-provider/actuator/prometheus
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
    interval: 30s
```

**Scrape Configuration:**
- **Selector**: Matches services with label `app.kubernetes.io/name: fineract`
- **Port**: HTTPS (8443)
- **Path**: `/fineract-provider/actuator/prometheus`
- **Interval**: 30 seconds
- **TLS**: Skip verification (self-signed cert)

#### Other ServiceMonitors

**Keycloak** (`servicemonitor-keycloak.yaml`):
- Path: `/metrics`
- Port: 8080
- Interval: 30s

**Redis** (`servicemonitor-redis.yaml`):
- Port: 6379
- Exporter: Redis exporter sidecar

**OAuth2-Proxy** (`servicemonitor-oauth2-proxy.yaml`):
- Path: `/metrics`
- Port: metrics port

**Kubernetes Components** (`servicemonitor-kubernetes.yaml`):
- Kubelet, API server, controller-manager, scheduler

### Alert Rules

**PrometheusRule** defines alert conditions.

**File**: `alert-rules.yaml`

#### Resource Alerts

**High CPU Usage**:
```yaml
- alert: HighCPUUsage
  expr: |
    (sum(rate(container_cpu_usage_seconds_total{namespace=~"fineract.*"}[5m])) by (pod, namespace) /
    sum(container_spec_cpu_quota{namespace=~"fineract.*"}/container_spec_cpu_period{namespace=~"fineract.*"}) by (pod, namespace)) > 0.8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High CPU usage detected"
    description: "Pod {{ $labels.pod }} is using {{ $value | humanizePercentage }} of CPU"
```

**Triggers when**: Pod uses >80% CPU for 5 minutes

**High Memory Usage**:
```yaml
- alert: HighMemoryUsage
  expr: |
    (sum(container_memory_working_set_bytes{namespace=~"fineract.*"}) by (pod, namespace) /
    sum(container_spec_memory_limit_bytes{namespace=~"fineract.*"}) by (pod, namespace)) > 0.8
  for: 5m
  labels:
    severity: warning
```

**Triggers when**: Pod uses >80% memory for 5 minutes

#### Pod Alerts

**Pod Restarting**:
```yaml
- alert: PodRestarting
  expr: rate(kube_pod_container_status_restarts_total{namespace=~"fineract.*"}[15m]) > 0
  for: 5m
  labels:
    severity: warning
```

**Pod Crash Looping**:
```yaml
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total{namespace=~"fineract.*"}[5m]) > 0.1
  for: 2m
  labels:
    severity: critical
```

**Pod Not Ready**:
```yaml
- alert: PodNotReady
  expr: kube_pod_status_phase{namespace=~"fineract.*", phase!~"Running|Succeeded"} > 0
  for: 5m
  labels:
    severity: warning
```

#### Application-Specific Alerts

**Fineract Alerts**:
- High response time (>5s)
- High error rate (>5%)
- Database connection pool exhausted

**Keycloak Alerts**:
- High failed login rate
- High session count
- Certificate expiration

**Database Alerts**:
- PostgreSQL down
- High connection count
- Slow queries

### Grafana Configuration

**Admin Credentials** (secret):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
stringData:
  username: admin
  password: <strong-password>
```

**Data Sources** (auto-provisioned):
```yaml
datasources:
- name: Prometheus
  type: prometheus
  url: http://prometheus.monitoring.svc.cluster.local:9090
  isDefault: true

- name: Loki
  type: loki
  url: http://loki-headless.logging.svc.cluster.local:3100
```

**Dashboard Provisioning**:
- Dashboards stored in ConfigMaps
- Auto-loaded on Grafana startup
- Located in `/var/lib/grafana/dashboards`

## Deployment

### Prerequisites

1. **Kubernetes Cluster**: 1.28+ with persistent storage
2. **StorageClass**: Default StorageClass with `ReadWriteOnce` support
3. **ArgoCD**: (Optional) For GitOps deployment
4. **Sealed Secrets**: For Grafana admin credentials

### ArgoCD Deployment

**ArgoCD Application**: `argocd/applications/{dev,uat,prod}/monitoring.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fineract-gitops.git
    targetRevision: main
    path: apps/monitoring/base
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
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
kubectl apply -f argocd/applications/dev/monitoring.yaml

# Monitor deployment
argocd app get monitoring --watch

# Check sync status
argocd app sync monitoring
```

### Manual Deployment

```bash
# Create Grafana admin secret
kubectl create secret generic grafana-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=<strong-password> \
  -n monitoring

# Apply monitoring stack
kubectl apply -k apps/monitoring/base/

# Verify deployment
kubectl get all -n monitoring

# Check Prometheus
kubectl get prometheus -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Check Grafana
kubectl get deployment grafana -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check AlertManager
kubectl get alertmanager -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager
```

### Post-Deployment Verification

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Check Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000 (login: admin / <password>)

# Check AlertManager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Open http://localhost:9093
```

## Usage

### Accessing Grafana

#### Via Port-Forward

```bash
# Forward Grafana port
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Access in browser
# URL: http://localhost:3000
# Username: admin
# Password: <from secret>
```

#### Via Ingress (Production)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
spec:
  rules:
  - host: grafana.fineract.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
  tls:
  - hosts:
    - grafana.fineract.example.com
    secretName: grafana-tls
```

### Querying Prometheus

#### Via Prometheus UI

```bash
# Forward Prometheus port
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open http://localhost:9090
# Navigate to Graph tab
# Enter PromQL query
```

#### Via API

```bash
# Query current CPU usage
curl -G http://localhost:9090/api/v1/query \
  --data-urlencode 'query=rate(container_cpu_usage_seconds_total{namespace="fineract-dev"}[5m])'

# Query range (last hour)
curl -G http://localhost:9090/api/v1/query_range \
  --data-urlencode 'query=up' \
  --data-urlencode 'start=2025-01-19T10:00:00Z' \
  --data-urlencode 'end=2025-01-19T11:00:00Z' \
  --data-urlencode 'step=60s'
```

### PromQL Examples

**PromQL** is Prometheus Query Language for querying metrics.

#### Basic Queries

**Check if services are up:**
```promql
up{job="fineract"}
```

**CPU usage by pod:**
```promql
rate(container_cpu_usage_seconds_total{namespace="fineract-dev"}[5m])
```

**Memory usage by pod:**
```promql
container_memory_working_set_bytes{namespace="fineract-dev"}
```

**HTTP requests per second:**
```promql
rate(http_server_requests_seconds_count{namespace="fineract-dev"}[5m])
```

#### Aggregations

**Total CPU usage per namespace:**
```promql
sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))
```

**Average response time:**
```promql
avg(http_server_requests_seconds_sum / http_server_requests_seconds_count)
```

**95th percentile latency:**
```promql
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))
```

#### Fineract-Specific Queries

**Active database connections:**
```promql
hikari_connections_active{namespace="fineract-dev"}
```

**JVM memory usage:**
```promql
jvm_memory_used_bytes{namespace="fineract-dev"}
```

**HTTP error rate:**
```promql
rate(http_server_requests_seconds_count{status=~"5.."}[5m])
```

**Request rate by endpoint:**
```promql
sum by (uri) (rate(http_server_requests_seconds_count{namespace="fineract-dev"}[5m]))
```

#### Keycloak-Specific Queries

**Active sessions:**
```promql
keycloak_sessions_active{namespace="fineract-dev"}
```

**Login rate:**
```promql
rate(keycloak_logins_total{namespace="fineract-dev"}[5m])
```

**Failed logins:**
```promql
rate(keycloak_login_errors_total{namespace="fineract-dev"}[5m])
```

### Creating Dashboards

#### Create Dashboard in Grafana

1. Navigate to **Dashboards** → **New Dashboard**
2. Click **Add visualization**
3. Select **Prometheus** data source
4. Enter PromQL query
5. Choose visualization type (Graph, Stat, Gauge, etc.)
6. Configure panel options (title, thresholds, units)
7. Click **Apply**
8. **Save dashboard**

#### Example Dashboard Panels

**Panel 1: CPU Usage by Pod**
- Query: `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="fineract-dev"}[5m]))`
- Visualization: Time series
- Unit: Percent (0-100)

**Panel 2: Memory Usage by Pod**
- Query: `sum by (pod) (container_memory_working_set_bytes{namespace="fineract-dev"})`
- Visualization: Time series
- Unit: Bytes (IEC)

**Panel 3: HTTP Request Rate**
- Query: `sum(rate(http_server_requests_seconds_count{namespace="fineract-dev"}[5m]))`
- Visualization: Stat
- Unit: req/s

**Panel 4: Error Rate**
- Query: `sum(rate(http_server_requests_seconds_count{namespace="fineract-dev",status=~"5.."}[5m]))`
- Visualization: Stat
- Unit: err/s
- Thresholds: Green <1, Yellow <10, Red >=10

## Monitoring Targets

The monitoring stack automatically discovers and scrapes metrics from:

**Fineract Components:**
- Fineract Read instances (`/fineract-provider/actuator/prometheus`)
- Fineract Write instance (`/fineract-provider/actuator/prometheus`)
- Fineract Batch workers (`/fineract-provider/actuator/prometheus`)

**Authentication & Routing:**
- Keycloak (`/metrics`)
- OAuth2-Proxy (`/metrics`)

**Data Layer:**
- Redis (`/metrics` via redis-exporter)
- PostgreSQL (via postgres-exporter if deployed)

**Infrastructure:**
- Kubernetes API Server
- Kubelet (node metrics)
- kube-state-metrics (cluster state)

**Frontend Applications:**
- Web App
- Accounting App
- Reporting App

## Alert Rules (1)

### Configured Alerts

The monitoring stack includes pre-configured alert rules organized into groups:

#### Resource Alerts
- **HighCPUUsage**: CPU >80% for 5min (warning)
- **CriticalCPUUsage**: CPU >95% for 2min (critical)
- **HighMemoryUsage**: Memory >80% for 5min (warning)
- **CriticalMemoryUsage**: Memory >95% for 2min (critical)

#### Pod Alerts
- **PodRestarting**: Restart rate >0 for 5min (warning)
- **PodCrashLooping**: Restart rate >0.1 for 2min (critical)
- **PodNotReady**: Pod not Running/Succeeded for 5min (warning)

#### Database Alerts
- **PostgreSQLDown**: PostgreSQL unreachable (critical)
- **HighDatabaseConnections**: Connection pool >80% (warning)
- **SlowQueries**: Queries >5s (warning)

#### Application Alerts
- **HighResponseTime**: Latency >5s (warning)
- **HighErrorRate**: Error rate >5% (warning)
- **FineractDown**: Fineract unreachable (critical)
- **KeycloakDown**: Keycloak unreachable (critical)

### Viewing Alerts

**Prometheus UI:**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/alerts
```

**AlertManager UI:**
```bash
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Open http://localhost:9093
```

**Grafana:**
- Navigate to **Alerting** → **Alert rules**
- View active alerts, silences, and notification history

## Troubleshooting

### Common Issues

#### 1. Prometheus Not Scraping Targets

**Symptom**: Targets shown as "Down" in Prometheus UI.

**Diagnosis:**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor fineract -n monitoring

# Check if service has correct labels
kubectl get svc -n fineract-dev --show-labels
```

**Solution:**
```bash
# Verify ServiceMonitor selector matches service labels
# Edit ServiceMonitor if needed
kubectl edit servicemonitor fineract -n monitoring

# Check network policies allow Prometheus → Target
kubectl get networkpolicy -n fineract-dev

# Restart Prometheus
kubectl delete pod -n monitoring -l app.kubernetes.io/name=prometheus
```

#### 2. Grafana Cannot Connect to Prometheus

**Symptom**: Grafana shows "Bad Gateway" or "Connection Refused" for Prometheus data source.

**Diagnosis:**
```bash
# Test connectivity from Grafana pod
kubectl exec -it -n monitoring deployment/grafana -- \
  wget -qO- http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up

# Check Prometheus is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
```

**Solution:**
```bash
# Verify Prometheus service
kubectl get svc prometheus -n monitoring

# Check data source configuration in Grafana
# Settings → Data Sources → Prometheus
# URL should be: http://prometheus.monitoring.svc.cluster.local:9090

# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring
```

#### 3. High Prometheus Memory Usage

**Symptom**: Prometheus pod OOMKilled or high memory usage.

**Cause**: High cardinality metrics or retention too long.

**Diagnosis:**
```bash
# Check memory usage
kubectl top pod -n monitoring -l app.kubernetes.io/name=prometheus

# Check storage size
kubectl exec -it prometheus-prometheus-0 -n monitoring -- df -h /prometheus

# Check cardinality
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Navigate to http://localhost:9090/tsdb-status
```

**Solution:**
```bash
# Increase memory limits
# Edit prometheus.yaml:
resources:
  limits:
    memory: "8Gi"  # Increase from 4Gi

# Reduce retention
retention: 15d      # Reduce from 30d
retentionSize: 30GB # Reduce from 45GB

# Apply changes
kubectl apply -k apps/monitoring/base/

# Reduce metric cardinality (drop high-cardinality labels)
```

#### 4. No Alerts Firing Despite Issues

**Symptom**: Expected alerts not firing despite metric thresholds exceeded.

**Diagnosis:**
```bash
# Check PrometheusRule exists
kubectl get prometheusrule -n monitoring

# Check alert rule syntax
kubectl get prometheusrule fineract-alert-rules -n monitoring -o yaml

# Check Prometheus alerts status
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/alerts
```

**Solution:**
```bash
# Verify PrometheusRule has correct label
labels:
  app.kubernetes.io/part-of: monitoring-stack

# Test alert expression manually in Prometheus
# Verify expression returns results

# Check Prometheus logs for rule errors
kubectl logs -n monitoring prometheus-prometheus-0
```

#### 5. Disk Full (Prometheus PVC)

**Symptom**: Prometheus crashes, PVC at 100%.

**Diagnosis:**
```bash
# Check PVC usage
kubectl exec -it prometheus-prometheus-0 -n monitoring -- df -h /prometheus

# Check retention settings
kubectl get prometheus prometheus -n monitoring -o yaml | grep retention
```

**Solution:**
```bash
# Option 1: Reduce retention
# Edit prometheus.yaml: retention: 7d, retentionSize: 10GB

# Option 2: Expand PVC (if storage class supports)
kubectl patch pvc prometheus-prometheus-db-prometheus-prometheus-0 -n monitoring \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# Option 3: Clean up old data (emergency)
kubectl exec -it prometheus-prometheus-0 -n monitoring -- rm -rf /prometheus/wal/*
kubectl delete pod prometheus-prometheus-0 -n monitoring
```

## Performance Tuning

### Prometheus Performance

**High Metrics Volume (>100k series)**:
```yaml
# Increase resources
resources:
  requests:
    cpu: 1000m
    memory: 4Gi
  limits:
    cpu: 2000m
    memory: 8Gi

# Adjust scrape interval
interval: 60s  # Reduce from 30s
```

**Slow Queries**:
```yaml
# Limit query time range
- --query.max-samples=50000000
- --query.timeout=2m
```

### Grafana Performance

**Slow Dashboards**:
- Reduce query time range
- Use recording rules for complex queries
- Increase refresh interval (e.g., 5m instead of 30s)
- Limit number of panels per dashboard (<20)

**High Memory Usage**:
```yaml
resources:
  limits:
    memory: "1Gi"  # Increase from 512Mi
```

## Related Documentation

### Core Documentation
- [Architecture Overview](/docs/architecture/README.md)
- [Operations Guide](/docs/OPERATIONS_GUIDE.md)
- [Metrics Reference](/docs/METRICS_REFERENCE.md)

### Component Documentation
- [Logging (Loki/Promtail)](/apps/logging/README.md)
- [Fineract](/apps/fineract/README.md)
- [Keycloak](/apps/keycloak/README.md)
- [Redis](/apps/fineract-redis/base/README.md)

### External Resources
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Prometheus Operator](https://prometheus-operator.dev/)

---

**Last Updated**: 2025-01-19
**Maintainer**: DevOps Team
**Prometheus Version**: v2.48.0
**Grafana Version**: 10.2.2
**Prometheus Operator Version**: v0.70.0
