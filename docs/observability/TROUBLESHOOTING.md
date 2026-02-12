# Observability Troubleshooting Guide

This guide helps diagnose and resolve common issues with the Fineract observability stack.

## Quick Diagnostics

### Check All Observability Components

```bash
# Check monitoring namespace
kubectl get pods -n monitoring

# Check logging namespace
kubectl get pods -n logging

# Check tracing namespace
kubectl get pods -n tracing

# Check all services
kubectl get svc -n monitoring
kubectl get svc -n logging
kubectl get svc -n tracing
```

### Expected Output (Healthy State)

```
# Monitoring
NAME                                  READY   STATUS    RESTARTS   AGE
alertmanager-0                        1/1     Running   0          1d
grafana-xxx                           1/1     Running   0          1d
prometheus-0                          1/1     Running   0          1d
prometheus-operator-xxx               1/1     Running   0          1d

# Logging
NAME                READY   STATUS    RESTARTS   AGE
loki-0              1/1     Running   0          1d
promtail-xxx        1/1     Running   0          1d
promtail-yyy        1/1     Running   0          1d

# Tracing
NAME                              READY   STATUS    RESTARTS   AGE
jaeger-xxx                        1/1     Running   0          1d
otel-collector-xxx                1/1     Running   0          1d
```

## Common Issues

### 1. Prometheus Not Scraping Targets

**Symptoms**:
- Metrics missing in Grafana
- Targets showing "DOWN" in Prometheus UI

**Diagnosis**:
```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/targets

# Check ServiceMonitor exists
kubectl get servicemonitors -n monitoring

# Check ServiceMonitor selectors
kubectl describe servicemonitor fineract -n monitoring
```

**Common Causes**:

1. **Label mismatch**: ServiceMonitor selector doesn't match service labels
   ```bash
   # Check service labels
   kubectl get svc fineract -n fineract-dev --show-labels

   # Check ServiceMonitor selector
   kubectl get servicemonitor fineract -n monitoring -o yaml | grep -A5 selector
   ```

2. **Wrong namespace selector**:
   ```yaml
   # ServiceMonitor should have:
   namespaceSelector:
     any: true
   # OR
   namespaceSelector:
     matchNames:
       - fineract-dev
   ```

3. **Network policy blocking**:
   ```bash
   kubectl get networkpolicies -n fineract-dev
   ```

4. **Service port name mismatch**:
   ```bash
   # ServiceMonitor expects port name "http"
   # Check service port names
   kubectl get svc fineract -n fineract-dev -o yaml | grep -A5 ports
   ```

**Solution**:
```bash
# Verify labels match
kubectl label svc fineract app=fineract -n fineract-dev

# Or update ServiceMonitor selector
kubectl edit servicemonitor fineract -n monitoring
```

### 2. Grafana Dashboards Not Loading

**Symptoms**:
- Dashboards show "No data"
- Panels show errors

**Diagnosis**:
```bash
# Check Grafana logs
kubectl logs -l app=grafana -n monitoring

# Check datasource configuration
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Visit http://localhost:3000/datasources
```

**Common Causes**:

1. **Datasource URL incorrect**:
   ```bash
   # Check Prometheus is reachable from Grafana
   kubectl exec -it deploy/grafana -n monitoring -- wget -qO- http://prometheus:9090/api/v1/query?query=up
   ```

2. **Prometheus not returning data**:
   - Check Prometheus storage
   - Check retention settings
   - Verify query syntax

3. **Time range issue**:
   - Metrics may not exist for selected time range
   - Try "Last 1 hour" instead of "Last 24 hours"

**Solution**:
```bash
# Check datasource ConfigMap
kubectl get configmap grafana-datasources -n monitoring -o yaml

# Verify Prometheus URL
# Should be: http://prometheus:9090
```

### 3. Alerts Not Firing

**Symptoms**:
- Known issues but no alerts
- AlertManager shows no active alerts

**Diagnosis**:
```bash
# Check PrometheusRules exist
kubectl get prometheusrules -n monitoring

# Check rules are loaded in Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/rules

# Check AlertManager is receiving alerts
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Visit http://localhost:9093
```

**Common Causes**:

1. **Rule not matching any data**:
   ```bash
   # Test the PromQL expression manually
   # In Prometheus UI, run the alert expression
   ```

2. **Rule labels don't match Prometheus selector**:
   ```yaml
   # PrometheusRule needs label:
   labels:
     app.kubernetes.io/part-of: monitoring-stack
   ```

3. **AlertManager not configured**:
   ```bash
   kubectl get secret alertmanager-config -n monitoring -o yaml
   ```

**Solution**:
```bash
# Verify rule is evaluated
kubectl exec -it prometheus-0 -n monitoring -- promtool check rules /etc/prometheus/rules/*.yaml
```

### 4. Alerts Not Sending Notifications

**Symptoms**:
- Alerts firing in Prometheus
- No Slack/Email notifications received

**Diagnosis**:
```bash
# Check AlertManager logs
kubectl logs -l app=alertmanager -n monitoring

# Check AlertManager configuration
kubectl get secret alertmanager-config -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

**Common Causes**:

1. **Slack webhook URL not configured**:
   - Check if `slack_api_url` is set in global config
   - Verify webhook URL is valid

2. **SMTP not configured**:
   - Check `smtp_smarthost`, `smtp_from`, credentials

3. **Route not matching alert**:
   - Alert labels don't match any route
   - Falls through to default receiver

4. **Network policy blocking outbound**:
   ```bash
   kubectl get networkpolicies -n monitoring
   ```

**Solution**:
```bash
# Test webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert"}' \
  https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Update AlertManager config
kubectl edit secret alertmanager-config -n monitoring
```

### 5. Logs Not Appearing in Loki

**Symptoms**:
- LogQL queries return empty results
- Promtail pods running but no logs

**Diagnosis**:
```bash
# Check Promtail logs
kubectl logs -l app=promtail -n logging

# Check Promtail is reading logs
kubectl exec -it ds/promtail -n logging -- cat /var/log/pods/fineract-dev_fineract*/fineract/0.log

# Check Loki ingestion
kubectl port-forward svc/loki 3100:3100 -n logging
curl http://localhost:3100/ready
curl http://localhost:3100/metrics | grep loki_ingester
```

**Common Causes**:

1. **Promtail can't read log files**:
   - Permission issues (must run as root)
   - Log path changed

2. **Log format not recognized**:
   - Promtail expects JSON or logfmt
   - Custom parsing rules needed

3. **Loki rejecting logs**:
   - Rate limits exceeded
   - Label cardinality too high

4. **Storage full**:
   ```bash
   kubectl exec -it loki-0 -n logging -- df -h
   ```

**Solution**:
```bash
# Check Promtail config
kubectl get configmap promtail-config -n logging -o yaml

# Verify log path mounting
kubectl describe daemonset promtail -n logging | grep -A10 "Volumes:"
```

### 6. Traces Not Appearing in Jaeger

**Symptoms**:
- Jaeger shows no services
- Traces missing for some services

**Diagnosis**:
```bash
# Check OTEL Collector logs
kubectl logs -l app=otel-collector -n tracing

# Check Jaeger logs
kubectl logs -l app=jaeger -n tracing

# Check OTEL Collector is receiving traces
kubectl port-forward svc/otel-collector 8888:8888 -n tracing
curl http://localhost:8888/metrics | grep otelcol_receiver
```

**Common Causes**:

1. **Application not sending traces**:
   - Missing OTEL environment variables
   - Tracing disabled in application config

2. **Wrong endpoint**:
   ```bash
   # Application should use:
   # OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.tracing.svc.cluster.local:4317
   ```

3. **OTEL Collector not forwarding to Jaeger**:
   ```bash
   kubectl get configmap otel-collector-config -n tracing -o yaml
   ```

4. **Network connectivity**:
   ```bash
   kubectl exec -it <app-pod> -- nc -zv otel-collector.tracing.svc.cluster.local 4317
   ```

**Solution**:
```bash
# Verify application env vars
kubectl exec -it <fineract-pod> -- env | grep OTEL

# Expected:
# OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.tracing.svc.cluster.local:4317
# OTEL_SERVICE_NAME=fineract
```

### 7. High Memory Usage in Prometheus

**Symptoms**:
- Prometheus OOMKilled
- Queries timing out

**Diagnosis**:
```bash
# Check Prometheus memory
kubectl top pods -n monitoring

# Check TSDB status
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/tsdb-status

# Check cardinality
curl http://localhost:9090/api/v1/label/__name__/values | jq '. | length'
```

**Common Causes**:

1. **High cardinality metrics**:
   - Too many label values
   - Unbounded labels (request IDs, user IDs in metrics)

2. **Too many scrape targets**:
   - Scraping too frequently
   - Too many pods

3. **Long retention**:
   - Reduce from 30d to 15d

**Solution**:
```bash
# Find high cardinality metrics
curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data.seriesCountByMetricName | to_entries | sort_by(.value) | reverse | .[0:10]'

# Drop high cardinality metrics in ServiceMonitor
# Add metricRelabelings to drop problematic metrics
```

### 8. Grafana Login Issues

**Symptoms**:
- Can't login to Grafana
- Password reset not working

**Diagnosis**:
```bash
# Check Grafana logs
kubectl logs -l app=grafana -n monitoring

# Check Grafana secret
kubectl get secret grafana-admin-credentials -n monitoring -o yaml
```

**Solution**:
```bash
# Reset admin password
kubectl exec -it deploy/grafana -n monitoring -- grafana-cli admin reset-admin-password newpassword

# Or delete the grafana PVC to reset everything (data loss!)
# kubectl delete pvc grafana-storage -n monitoring
```

## Performance Tuning

### Prometheus

```yaml
# Increase memory limits if needed
resources:
  requests:
    memory: 2Gi
  limits:
    memory: 4Gi

# Reduce retention if storage is limited
retention: 15d
retentionSize: 40GB

# Increase scrape interval for non-critical targets
scrapeInterval: 60s  # instead of 30s
```

### Loki

```yaml
# Tune ingestion limits
limits_config:
  ingestion_rate_mb: 20  # increase if logs are being dropped
  ingestion_burst_size_mb: 30
  max_entries_limit_per_query: 10000

# Tune chunk settings
chunk_store_config:
  chunk_cache_config:
    enable_fifocache: true
    fifocache:
      max_size_bytes: 500MB
```

### OTEL Collector

```yaml
# Tune batch processor
processors:
  batch:
    timeout: 5s  # increase for lower throughput
    send_batch_size: 2048
    send_batch_max_size: 4096

# Increase memory limiter
  memory_limiter:
    limit_percentage: 80
    spike_limit_percentage: 30
```

## Recovery Procedures

### Prometheus Data Recovery

If Prometheus data is corrupted:
```bash
# Stop Prometheus
kubectl scale statefulset prometheus --replicas=0 -n monitoring

# Delete corrupted data (will lose all historical data!)
kubectl exec -it prometheus-0 -n monitoring -- rm -rf /prometheus/*

# Restart Prometheus
kubectl scale statefulset prometheus --replicas=1 -n monitoring
```

### Loki Data Recovery

If Loki index is corrupted:
```bash
# Stop Loki
kubectl scale statefulset loki --replicas=0 -n logging

# Delete index (logs still in chunks)
kubectl exec -it loki-0 -n logging -- rm -rf /loki/index/*

# Restart Loki (will rebuild index from chunks)
kubectl scale statefulset loki --replicas=1 -n logging
```

## Getting Help

If you can't resolve an issue:

1. **Collect diagnostics**:
   ```bash
   kubectl logs -l app=prometheus -n monitoring > prometheus.log
   kubectl logs -l app=grafana -n monitoring > grafana.log
   kubectl logs -l app=loki -n logging > loki.log
   kubectl describe pods -n monitoring > monitoring-pods.txt
   ```

2. **Check documentation**:
   - [Prometheus Troubleshooting](https://prometheus.io/docs/prometheus/latest/troubleshooting/)
   - [Grafana Troubleshooting](https://grafana.com/docs/grafana/latest/troubleshooting/)
   - [Loki Troubleshooting](https://grafana.com/docs/loki/latest/operations/troubleshooting/)

3. **Open an issue** with collected logs and environment details
