# Fineract Platform Observability Guide

This guide provides a comprehensive overview of the observability stack for the Fineract platform, including metrics, logging, tracing, and alerting.

## Table of Contents

1. [Overview](#overview)
2. [Components](#components)
3. [Quick Start](#quick-start)
4. [Accessing Dashboards](#accessing-dashboards)
5. [Common Tasks](#common-tasks)
6. [Architecture](#architecture)

## Overview

The Fineract observability stack provides three pillars of observability:

| Pillar | Tool | Purpose |
|--------|------|---------|
| **Metrics** | Prometheus + Grafana | Quantitative measurements of system behavior |
| **Logs** | Loki + Promtail | Event records from applications |
| **Traces** | Jaeger + OpenTelemetry | Request flow across services |

### Key Benefits

- **Debugging**: Quickly identify root causes of issues
- **Proactive Monitoring**: Get alerted before users notice problems
- **Performance Analysis**: Understand latency and throughput patterns
- **Capacity Planning**: Make data-driven scaling decisions
- **SLO Tracking**: Measure reliability against objectives

## Components

### Metrics Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Prometheus | v2.48.0 | Time-series metrics database |
| Grafana | v10.2.2 | Visualization and dashboards |
| AlertManager | v0.26.0 | Alert routing and notifications |
| ServiceMonitors | - | Auto-discovery of metrics endpoints |
| PodMonitors | - | Pod-level metrics scraping |

### Logging Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Loki | v2.9.3 | Log aggregation and storage |
| Promtail | v2.9.3 | Log collection agent (DaemonSet) |

### Tracing Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Jaeger | v1.53.0 | Trace storage and visualization |
| OpenTelemetry Collector | v0.91.0 | Trace collection and processing |

## Quick Start

### 1. Access Grafana

```bash
# Port forward to Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Open in browser
open http://localhost:3000

# Default credentials: admin / admin (change on first login)
```

### 2. Access Jaeger (Tracing)

```bash
# Port forward to Jaeger UI
kubectl port-forward svc/jaeger-query 16686:16686 -n tracing

# Open in browser
open http://localhost:16686
```

### 3. Query Logs

```bash
# Port forward to Loki
kubectl port-forward svc/loki 3100:3100 -n logging

# Or use Grafana's Explore view with Loki datasource
```

## Accessing Dashboards

### Available Grafana Dashboards

| Dashboard | Purpose | Key Metrics |
|-----------|---------|-------------|
| **Kubernetes Cluster Overview** | Cluster health | CPU, memory, pod count |
| **Fineract Application Metrics** | App performance | Request rate, latency, errors |
| **PostgreSQL Database Metrics** | DB health | Connections, TPS, cache ratio |
| **Business Metrics** | Business KPIs | Loans, transactions, users |
| **Service Level Objectives** | Reliability | Availability, latency SLOs |
| **Distributed Tracing Overview** | Trace stats | Spans, latency by service |

### Dashboard Navigation

1. Open Grafana at `http://localhost:3000`
2. Click "Dashboards" in the left sidebar
3. Select the desired dashboard
4. Use the time picker (top-right) to adjust the time range
5. Use variables (top of dashboard) to filter by namespace/service

## Common Tasks

### Find Errors in Logs

**In Grafana (Explore view):**
```logql
{namespace="fineract-dev", app="fineract"} |= "error" | json
```

**Filter by severity:**
```logql
{namespace="fineract-dev"} | json | level="ERROR"
```

### Investigate Slow Requests

**In Prometheus:**
```promql
# Find p99 latency by endpoint
histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{app="fineract"}[5m])) by (uri, le))
```

**In Jaeger:**
1. Select "fineract" service
2. Set operation to the slow endpoint
3. Set min duration filter (e.g., 1s)
4. Click "Find Traces"

### Check Service Health

**In Prometheus:**
```promql
# Service availability
up{namespace=~"fineract.*"}

# Error rate
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) by (app)
/ sum(rate(http_server_requests_seconds_count[5m])) by (app)
```

### Debug a Specific Request

1. Get the trace ID from logs or headers
2. Open Jaeger UI
3. Enter trace ID in the search box
4. View the full request timeline

### View Active Alerts

**In Prometheus:**
```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/alerts
```

**In AlertManager:**
```bash
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Visit http://localhost:9093
```

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed architecture diagrams.

### Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Fineract   │     │   Keycloak   │     │    Redis     │
│   Pods       │     │   Pods       │     │   Pods       │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       │ /metrics           │ /metrics           │ /metrics
       │                    │                    │
       └────────────────────┼────────────────────┘
                            │
                    ┌───────▼───────┐
                    │  Prometheus   │
                    │  (scrapes)    │
                    └───────┬───────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
      ┌───────▼───────┐     │     ┌───────▼───────┐
      │   Grafana     │     │     │ AlertManager  │
      │  (visualize)  │     │     │  (alerts)     │
      └───────────────┘     │     └───────┬───────┘
                            │             │
                            │     ┌───────▼───────┐
                            │     │    Slack/     │
                            │     │    Email      │
                            │     └───────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
┌─────────────▼─┐   ┌───────▼───────┐   ┌─▼─────────────┐
│ /var/log/pods │   │ OTEL Collector │   │    Loki      │
│  (Promtail)   │   │ (traces)       │   │  (logs)      │
└───────┬───────┘   └───────┬───────┘   └───────────────┘
        │                   │
        │                   ▼
        │           ┌───────────────┐
        └──────────▶│    Jaeger     │
                    │   (traces)    │
                    └───────────────┘
```

## Related Documentation

- [Architecture Diagrams](./ARCHITECTURE.md)
- [Tracing Guide](./TRACING_GUIDE.md)
- [Troubleshooting](./TROUBLESHOOTING.md)
- [Alert Runbook](../operations/ALERT_RUNBOOK.md)
- [Metrics Reference](../operations/METRICS_REFERENCE.md)
