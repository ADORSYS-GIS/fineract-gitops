# Monitoring and Alerting Guide

This guide covers the deployment, configuration, and usage of the monitoring and alerting stack for the Fineract platform.

## Table of Contents

- [Overview](#overview)
- [Stack Components](#stack-components)
- [Deployment](#deployment)
- [Accessing the Monitoring Stack](#accessing-the-monitoring-stack)
- [Pre-configured Dashboards](#pre-configured-dashboards)
- [Service Monitors](#service-monitors)
- [Alert Configuration](#alert-configuration)
- [Resource Requirements](#resource-requirements)
- [Troubleshooting](#troubleshooting)

---

## Overview

The monitoring stack provides comprehensive observability for the Fineract platform using:

- **Prometheus** - Metrics collection and time-series database
- **Grafana** - Visualization and dashboards
- **AlertManager** - Alert routing and notification management
- **ServiceMonitors** - Automatic discovery of metrics endpoints
- **PrometheusRules** - Pre-configured alerting rules

The stack is deployed in the `monitoring` namespace and automatically discovers all services with proper annotations.

---

## Stack Components

### Prometheus Operator

- **Purpose**: Manages Prometheus instances and custom resources
- **Version**: v0.70.0
- **CRDs**: ServiceMonitor, PrometheusRule, AlertmanagerConfig
- **Features**:
  - Automatic target discovery
  - Dynamic configuration reloading
  - Multi-tenancy support

### Prometheus

- **Purpose**: Metrics collection and storage
- **Default Resources**:
  - CPU Request: 300m
  - Memory Request: 1Gi
  - Storage: 10Gi (persistent volume)
- **Retention**: 15 days (configurable)
- **Scrape Interval**: 30s

### Grafana

- **Purpose**: Metrics visualization
- **Default Resources**:
  - CPU Request: 100m
  - Memory Request: 256Mi
- **Default Credentials**:
  - Username: `admin`
  - Password: Retrieved from secret `grafana-admin-credentials`
- **Pre-installed Datasources**: Prometheus

### AlertManager

- **Purpose**: Alert routing and notifications
- **Default Resources**:
  - CPU Request: 50m
  - Memory Request: 128Mi
- **Supported Receivers**:
  - Email (SMTP)
  - Slack
  - PagerDuty
  - AWS SNS
  - Webhook

---

## Deployment

### Prerequisites

1. **ArgoCD installed and configured**
2. **Sufficient cluster resources** (see [Resource Requirements](#resource-requirements))
3. **Storage class available** for persistent volumes

### Deploy Monitoring Stack

```bash
# Apply the monitoring ArgoCD application
kubectl apply -f argocd/applications/dev/monitoring.yaml

# Wait for deployment to complete
kubectl wait --for=condition=Synced application/monitoring-dev -n argocd --timeout=10m

# Verify all components are running
kubectl get pods -n monitoring
```

Expected output:
```
NAME                                   READY   STATUS    RESTARTS   AGE
prometheus-operator-xxx                1/1     Running   0          2m
prometheus-prometheus-0                2/2     Running   0          2m
grafana-xxx                            1/1     Running   0          2m
alertmanager-alertmanager-0            2/2     Running   0          2m
```

### Verify ServiceMonitors

```bash
# List all service monitors
kubectl get servicemonitors -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Then visit http://localhost:9090/targets
```

---

## Accessing the Monitoring Stack

### Prometheus

**Port Forward:**
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
```
Then access: http://localhost:9090

**Via Ingress** (if configured):
```
https://prometheus.your-domain.com
```

### Grafana

**Port Forward:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```
Then access: http://localhost:3000

**Get Admin Password:**
```bash
kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.password}' | base64 -d
```

**Via Ingress** (if configured):
```
https://grafana.your-domain.com
```

### AlertManager

**Port Forward:**
```bash
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
```
Then access: http://localhost:9093

---

## Pre-configured Dashboards

Grafana comes with several pre-configured dashboards:

### 1. Fineract Overview Dashboard

**Metrics Tracked:**
- Request rate (reads/writes/batch)
- Response time (p50, p95, p99)
- Error rate by endpoint
- Active database connections
- Cache hit/miss ratio

**Location:** Grafana → Dashboards → Fineract Overview

### 2. Kubernetes Cluster Dashboard

**Metrics Tracked:**
- Node CPU/memory usage
- Pod resource consumption
- Network I/O
- Persistent volume usage

**Location:** Grafana → Dashboards → Kubernetes Cluster

### 3. Database Performance Dashboard

**Metrics Tracked:**
- PostgreSQL connection pool stats
- Query execution time
- Transaction rate
- Lock wait time
- Replication lag (if using replicas)

**Location:** Grafana → Dashboards → Database Performance

### 4. Redis Cache Dashboard

**Metrics Tracked:**
- Cache hit/miss ratio
- Memory usage
- Eviction rate
- Connected clients
- Commands per second

**Location:** Grafana → Dashboards → Redis Cache

### 5. Authentication & Authorization Dashboard

**Metrics Tracked:**
- Keycloak login rate
- OAuth2 Proxy request rate
- Authentication success/failure rate
- Token refresh rate
- Session count

**Location:** Grafana → Dashboards → Auth & AuthZ

---

## Service Monitors

ServiceMonitors define which services Prometheus should scrape:

### Fineract ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fineract
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: fineract
  endpoints:
  - port: http
    path: /fineract-provider/actuator/prometheus
    interval: 30s
```

**Exposed Metrics:**
- `http_server_requests_seconds` - Request duration
- `jvm_memory_used_bytes` - JVM memory usage
- `jdbc_connections_active` - Database connections
- `cache_gets_total` - Cache operations
- Custom business metrics

### Keycloak ServiceMonitor

**Exposed Metrics:**
- `keycloak_logins` - Login events
- `keycloak_login_failures` - Failed logins
- `keycloak_client_login_attempts` - Client authentication
- `keycloak_user_event_UPDATE_PASSWORD` - Password changes

### Redis ServiceMonitor

**Exposed Metrics:**
- `redis_keyspace_hits_total` - Cache hits
- `redis_keyspace_misses_total` - Cache misses
- `redis_memory_used_bytes` - Memory usage
- `redis_connected_clients` - Client connections

### OAuth2 Proxy ServiceMonitor

**Exposed Metrics:**
- `oauth2_proxy_requests_total` - Total requests
- `oauth2_proxy_authentication_attempts_total` - Auth attempts
- `oauth2_proxy_authenticated_requests` - Authenticated requests

---

## Alert Configuration

### Pre-configured Alert Rules

The monitoring stack includes several critical alerts:

#### High Priority Alerts

**Pod CrashLooping**
```yaml
alert: PodCrashLooping
expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
severity: critical
description: Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping
```

**High Memory Usage**
```yaml
alert: HighMemoryUsage
expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
severity: warning
description: Pod {{ $labels.pod }} memory usage is above 90%
```

**Database Connection Pool Exhausted**
```yaml
alert: DatabaseConnectionPoolExhausted
expr: hikaricp_connections_active / hikaricp_connections_max > 0.9
severity: critical
description: Fineract database connection pool is 90% full
```

**High API Error Rate**
```yaml
alert: HighAPIErrorRate
expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.05
severity: warning
description: API error rate is above 5%
```

**Cache Miss Rate High**
```yaml
alert: HighCacheMissRate
expr: rate(redis_keyspace_misses_total[5m]) / rate(redis_keyspace_hits_total[5m]) > 0.3
severity: warning
description: Redis cache miss rate is above 30%
```

#### Medium Priority Alerts

**Disk Space Low**
```yaml
alert: DiskSpaceLow
expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.2
severity: warning
description: Disk space on {{ $labels.instance }} is below 20%
```

**Certificate Expiring Soon**
```yaml
alert: CertificateExpiringSoon
expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
severity: warning
description: Certificate {{ $labels.name }} expires in less than 7 days
```

### Configuring Alert Receivers

#### Email Notifications (AWS SES)

Edit `apps/monitoring/base/alertmanager-config.yaml`:

```yaml
global:
  smtp_from: 'alerts@your-domain.com'
  smtp_smarthost: 'email-smtp.us-east-2.amazonaws.com:587'
  smtp_auth_username: 'YOUR_SMTP_USERNAME'
  smtp_auth_password: 'YOUR_SMTP_PASSWORD'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: 'devops-team@your-domain.com'
    headers:
      Subject: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
```

#### Slack Notifications

```yaml
receivers:
- name: 'slack-notifications'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#fineract-alerts'
    title: '{{ .CommonLabels.alertname }}'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

#### AWS SNS Notifications

```yaml
receivers:
- name: 'sns-notifications'
  sns_configs:
  - topic_arn: 'arn:aws:sns:us-east-2:123456789:fineract-alerts'
    subject: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
    message: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

### Testing Alerts

**Trigger a test alert:**
```bash
# Scale down a deployment to trigger PodNotReady alert
kubectl scale deployment fineract-read --replicas=0 -n fineract-dev

# Wait for alert to fire (check AlertManager UI)
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093

# Restore deployment
kubectl scale deployment fineract-read --replicas=1 -n fineract-dev
```

### Silencing Alerts

**Via AlertManager UI:**
1. Access AlertManager at http://localhost:9093
2. Click "Silences" → "New Silence"
3. Set matchers (e.g., `alertname="HighMemoryUsage"`)
4. Set duration and comment
5. Click "Create"

**Via CLI:**
```bash
# Create a silence for 2 hours
amtool silence add alertname=HighMemoryUsage --duration=2h --comment="Planned maintenance"
```

---

## Resource Requirements

### Minimum Resources (Development)

| Component | CPU Request | Memory Request | Storage |
|-----------|-------------|----------------|---------|
| Prometheus | 300m | 1Gi | 10Gi |
| Grafana | 100m | 256Mi | 1Gi |
| AlertManager | 50m | 128Mi | 1Gi |
| **Total** | **450m** | **1.4Gi** | **12Gi** |

### Recommended Resources (Production)

| Component | CPU Request | Memory Request | Storage |
|-----------|-------------|----------------|---------|
| Prometheus | 1000m | 4Gi | 100Gi |
| Grafana | 500m | 1Gi | 5Gi |
| AlertManager | 200m | 512Mi | 5Gi |
| **Total** | **1700m** | **5.5Gi** | **110Gi** |

### Metrics Retention Impact

| Retention Period | Estimated Storage (per replica) |
|------------------|--------------------------------|
| 7 days | 5-10Gi |
| 15 days (default) | 10-20Gi |
| 30 days | 20-40Gi |
| 90 days | 60-120Gi |

**Note:** Storage requirements scale with:
- Number of monitored targets
- Scrape frequency
- Cardinality of metrics
- Number of label dimensions

---

## Troubleshooting

### Prometheus Not Scraping Targets

**Symptom:** Targets show as "DOWN" in Prometheus UI

**Check ServiceMonitor:**
```bash
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor fineract -n monitoring
```

**Check service labels match:**
```bash
kubectl get svc -n fineract-dev --show-labels
```

**Check Prometheus logs:**
```bash
kubectl logs -n monitoring prometheus-prometheus-0 -c prometheus
```

**Common issues:**
- Service selector labels don't match
- Metrics endpoint path incorrect
- Network policies blocking scraping
- Service not exposing metrics port

### Grafana Can't Connect to Prometheus

**Symptom:** "Bad Gateway" or "Connection refused" errors

**Verify Prometheus service:**
```bash
kubectl get svc -n monitoring prometheus-operated
```

**Test connection from Grafana pod:**
```bash
kubectl exec -n monitoring deployment/grafana -- wget -O- http://prometheus-operated:9090/-/healthy
```

**Check datasource configuration:**
1. Grafana UI → Configuration → Data Sources
2. Select Prometheus
3. URL should be: `http://prometheus-operated:9090`
4. Click "Save & Test"

### Alerts Not Firing

**Check PrometheusRule is loaded:**
```bash
kubectl get prometheusrules -n monitoring
kubectl describe prometheusrule fineract-alerts -n monitoring
```

**Verify in Prometheus UI:**
1. http://localhost:9090/alerts
2. Check if alert is defined
3. Check alert expression evaluation

**Check AlertManager config:**
```bash
kubectl get secret alertmanager-alertmanager -n monitoring -o yaml
```

### High Memory Usage on Prometheus

**Symptom:** Prometheus pod OOMKilled or high memory usage

**Check metrics cardinality:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Query cardinality
curl http://localhost:9090/api/v1/status/tsdb
```

**Solutions:**
1. Reduce scrape frequency
2. Drop high-cardinality metrics
3. Increase memory limits
4. Enable metrics relabeling to drop unnecessary labels

**Example: Drop high-cardinality labels**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fineract
spec:
  endpoints:
  - port: http
    metricRelabelings:
    - sourceLabels: [__name__]
      regex: 'jvm_gc_.*'
      action: drop
```

### Grafana Dashboard Not Loading Data

**Check time range** - Ensure dashboard time range matches data retention

**Verify metrics exist:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Query metrics
curl 'http://localhost:9090/api/v1/query?query=up'
```

**Check dashboard variables:**
1. Dashboard settings → Variables
2. Ensure variables are populated
3. Check if query returns results

---

## Related Documentation

- [Alert Runbook](ALERT_RUNBOOK.md) - Detailed alert investigation procedures
- [Metrics Reference](METRICS_REFERENCE.md) - Complete metrics catalog
- [Operations Guide](../OPERATIONS_GUIDE.md) - Overall operations procedures
- [Cost Optimization](COST_OPTIMIZATION.md) - Optimizing monitoring costs

---

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Operator Guide](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/user-guides/getting-started.md)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
