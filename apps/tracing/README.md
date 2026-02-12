# Distributed Tracing Stack

This directory contains the distributed tracing infrastructure for the Fineract platform using **OpenTelemetry** and **Jaeger**.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Fineract      │     │   Keycloak      │     │   Frontend      │
│   (Spring Boot) │     │   (Quarkus)     │     │   Apps          │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │ OTLP                  │ OTLP                  │ OTLP
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌────────────────────────┐
                    │   OpenTelemetry        │
                    │   Collector            │
                    │   (otel-collector)     │
                    └───────────┬────────────┘
                                │ OTLP
                                ▼
                    ┌────────────────────────┐
                    │   Jaeger               │
                    │   All-in-One           │
                    │   (jaeger)             │
                    └───────────┬────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
           ┌──────────────┐       ┌──────────────┐
           │   Jaeger UI  │       │  Prometheus  │
           │   (16686)    │       │  (metrics)   │
           └──────────────┘       └──────────────┘
```

## Components

### Jaeger All-in-One (v1.53.0)
- **Purpose**: Trace storage and visualization
- **Ports**:
  - `4317` - OTLP gRPC receiver
  - `4318` - OTLP HTTP receiver
  - `14268` - Jaeger Thrift HTTP
  - `14250` - Jaeger gRPC
  - `16686` - Query UI
  - `14269` - Admin/metrics
- **Storage**: In-memory (50,000 traces max)
- **Resources**: 100m-500m CPU, 256Mi-1Gi memory

### OpenTelemetry Collector (v0.91.0)
- **Purpose**: Receive, process, and export traces
- **Receivers**: OTLP (gRPC/HTTP), Jaeger (Thrift/gRPC)
- **Processors**: Batch, Memory Limiter, Resource enrichment, Health check filtering
- **Exporters**: Jaeger (OTLP), Prometheus (metrics)
- **Ports**:
  - `4317` - OTLP gRPC
  - `4318` - OTLP HTTP
  - `8888` - Internal metrics
  - `8889` - Prometheus exporter
  - `13133` - Health check
- **Resources**: 100m-500m CPU, 256Mi-512Mi memory

## Configuration

### Sending Traces from Applications

#### Spring Boot (Fineract)

Add to `application.yml`:
```yaml
management:
  tracing:
    enabled: true
    sampling:
      probability: 1.0  # 100% sampling for dev, reduce for prod

otel:
  exporter:
    otlp:
      endpoint: http://otel-collector.tracing.svc.cluster.local:4317
  service:
    name: fineract
```

Add dependencies to `pom.xml`:
```xml
<dependency>
  <groupId>io.micrometer</groupId>
  <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
  <groupId>io.opentelemetry</groupId>
  <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

#### Environment Variables

Set these environment variables in your application deployment:
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.tracing.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "fineract"
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # 10% sampling for production
```

## Accessing the UI

### Port Forward (Development)
```bash
# Jaeger UI
kubectl port-forward svc/jaeger-query 16686:16686 -n tracing

# Then visit: http://localhost:16686
```

### Via Ingress (Production)
Configure an Ingress resource to expose Jaeger UI at `/jaeger`.

## Querying Traces

### By Service
1. Open Jaeger UI
2. Select service from dropdown (e.g., "fineract")
3. Click "Find Traces"

### By Trace ID
1. Open Jaeger UI
2. Enter trace ID in search box
3. View full trace timeline

### By Tags
Search with tags like:
- `http.status_code=500` - Find error traces
- `http.method=POST` - Find POST requests
- `user.id=12345` - Find traces for specific user

## Metrics

The tracing stack exposes Prometheus metrics:

### Jaeger Metrics
- `jaeger_collector_traces_received_total` - Total traces received
- `jaeger_collector_spans_received_total` - Total spans received
- `jaeger_collector_traces_rejected_total` - Rejected traces
- `jaeger_query_latency_bucket` - Query latency histogram

### OTEL Collector Metrics
- `otelcol_receiver_accepted_spans` - Accepted spans
- `otelcol_receiver_refused_spans` - Refused spans
- `otelcol_exporter_sent_spans` - Exported spans
- `otelcol_processor_batch_batch_send_size` - Batch sizes

## Troubleshooting

### No Traces Appearing
1. Check OTEL Collector logs:
   ```bash
   kubectl logs -l app=otel-collector -n tracing
   ```
2. Verify endpoint connectivity:
   ```bash
   kubectl exec -it <pod> -- wget -qO- http://otel-collector.tracing.svc.cluster.local:13133
   ```
3. Check application OTEL configuration

### High Memory Usage
1. Reduce trace retention in Jaeger (`--memory.max-traces`)
2. Increase sampling rate to reduce volume
3. Add more filtering in OTEL Collector

### Traces Missing Spans
1. Check if context propagation is enabled
2. Verify all services use same trace context format (W3C Trace Context)
3. Check for clock skew between services

## Production Considerations

For production environments:

1. **Use Persistent Storage**: Replace in-memory with Elasticsearch or Cassandra
2. **Scale Collectors**: Run multiple OTEL Collector replicas
3. **Reduce Sampling**: Use 1-10% sampling rate
4. **Add Ingress**: Expose Jaeger UI securely with authentication
5. **Configure Retention**: Set appropriate trace retention period
6. **Enable TLS**: Secure collector endpoints

## Related Documentation

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Spring Boot Observability](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.observability)
