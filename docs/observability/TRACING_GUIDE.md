# Distributed Tracing Guide

This guide explains how to use distributed tracing to debug and analyze request flows in the Fineract platform.

## What is Distributed Tracing?

Distributed tracing tracks requests as they flow through multiple services. Each request gets a unique **Trace ID**, and each operation within that request creates a **Span**.

```
Request: POST /api/v1/loans

Trace ID: abc123
├── Span 1: oauth2-proxy.authenticate (5ms)
├── Span 2: fineract.createLoan (150ms)
│   ├── Span 3: fineract.validateLoan (10ms)
│   ├── Span 4: keycloak.getUser (20ms)
│   ├── Span 5: redis.checkCache (2ms)
│   └── Span 6: postgresql.insertLoan (100ms)
└── Total: 155ms
```

## Accessing Jaeger UI

```bash
# Port forward to Jaeger
kubectl port-forward svc/jaeger-query 16686:16686 -n tracing

# Open browser
open http://localhost:16686
```

## Basic Operations

### Finding Traces by Service

1. Open Jaeger UI
2. Select **Service** dropdown
3. Choose "fineract" (or other service)
4. Click **Find Traces**

### Finding Traces by Operation

1. Select Service: "fineract"
2. Select **Operation**: "/api/v1/loans"
3. Click **Find Traces**

### Finding Slow Requests

1. Select Service: "fineract"
2. Set **Min Duration**: "1s"
3. Click **Find Traces**
4. Results show only requests taking >1 second

### Finding Error Traces

1. Select Service: "fineract"
2. Add **Tags**: `error=true`
3. Click **Find Traces**

### Finding Traces by Trace ID

If you have a trace ID from logs or headers:

1. Click on the search bar
2. Enter the trace ID directly
3. Press Enter to view the full trace

## Understanding Trace Views

### Timeline View

```
┌─────────────────────────────────────────────────────────────────────┐
│ Trace: abc123 (3 Services, 8 Spans, 155ms)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ oauth2-proxy  ████                                          (5ms)   │
│                                                                      │
│ fineract      ██████████████████████████████████████████   (150ms)  │
│                                                                      │
│   ├─validate     ██                                        (10ms)   │
│   ├─keycloak        ████                                   (20ms)   │
│   ├─redis              █                                   (2ms)    │
│   └─postgresql           ████████████████████████████████  (100ms)  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Span Details

Click on any span to see:
- **Operation name**: The method or endpoint
- **Duration**: How long the operation took
- **Tags**: Key-value metadata (http.method, http.status_code, etc.)
- **Logs**: Events that occurred during the span
- **Process**: Service info (hostname, version)

## Common Debugging Scenarios

### 1. Debugging a Slow Loan Application

**Symptom**: Loan creation taking >5 seconds

**Steps**:
1. Open Jaeger UI
2. Service: "fineract"
3. Operation: "/api/v1/loans"
4. Min Duration: "5s"
5. Find Traces

**What to look for**:
- Which child span is taking the longest?
- Is it database (postgresql)?
- Is it an external service (keycloak)?
- Are there multiple sequential calls that could be parallelized?

### 2. Debugging Authentication Failures

**Symptom**: Users getting 401 errors

**Steps**:
1. Service: "oauth2-proxy" or "keycloak"
2. Tags: `http.status_code=401`
3. Find Traces

**What to look for**:
- Is the token validation failing?
- Is Keycloak unreachable?
- Are the credentials expired?

### 3. Finding Database Bottlenecks

**Steps**:
1. Service: "fineract"
2. Tags: `db.type=postgresql`
3. Min Duration: "100ms"
4. Find Traces

**What to look for**:
- Which queries are slow?
- Are there N+1 query patterns?
- Is connection pool exhausted?

### 4. Correlating Errors Across Services

**Steps**:
1. Find an error trace in Fineract
2. Note the Trace ID
3. Search for the same Trace ID
4. View the complete request path

**What to look for**:
- Where did the error originate?
- What was the upstream cause?
- Did error propagate correctly?

## Trace Context Propagation

### How it Works

When Service A calls Service B:
1. Service A adds trace headers to the request
2. Service B reads headers and creates child span
3. All spans share the same Trace ID

### HTTP Headers (W3C Trace Context)

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
tracestate: rojo=00f067aa0ba902b7
```

### Configuration in Spring Boot (Fineract)

```yaml
management:
  tracing:
    enabled: true
    propagation:
      type: W3C  # or B3 for Zipkin compatibility
    sampling:
      probability: 1.0  # 100% in dev, reduce in prod
```

### Configuration in Application Deployment

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.tracing.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "fineract"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=fineract-dev,deployment.environment=dev"
```

## Custom Spans

### Adding Custom Spans in Code

```java
// Spring Boot with Micrometer Tracing
@Autowired
private Tracer tracer;

public void processLoan(Loan loan) {
    Span span = tracer.nextSpan().name("processLoan").start();
    try (Tracer.SpanInScope ws = tracer.withSpan(span)) {
        span.tag("loan.id", loan.getId().toString());
        span.tag("loan.amount", loan.getAmount().toString());

        // Business logic here

    } catch (Exception e) {
        span.error(e);
        throw e;
    } finally {
        span.end();
    }
}
```

### Adding Events to Spans

```java
span.event("validation.started");
// ... validation logic ...
span.event("validation.completed");
```

## Best Practices

### 1. Naming Conventions

- **Good**: `POST /api/v1/loans`, `database.query`, `cache.get`
- **Bad**: `span1`, `doSomething`, `method123`

### 2. Meaningful Tags

Always include:
- `http.method`, `http.url`, `http.status_code` (for HTTP)
- `db.type`, `db.statement` (for database)
- `error=true` and error message (for failures)
- Business context: `loan.id`, `user.id`, `tenant.id`

### 3. Sampling Strategy

| Environment | Sampling Rate | Reason |
|-------------|---------------|--------|
| Development | 100% | See all traces for debugging |
| UAT | 10-50% | Balance visibility and cost |
| Production | 1-5% | Minimize overhead |

### 4. Error Handling

Always mark spans as errors when exceptions occur:
```java
span.error(exception);
span.tag("error", "true");
span.tag("error.message", exception.getMessage());
```

## Jaeger Query Language

### Basic Queries

```
# Find traces by service
service = "fineract"

# Find traces with errors
error = true

# Find slow traces
minDuration = 1s

# Find by HTTP status
http.status_code = 500

# Combine conditions
service = "fineract" AND error = true AND minDuration = 500ms
```

### Tag Searches

```
# By user ID
user.id = "12345"

# By loan ID
loan.id = "67890"

# By tenant
tenant.id = "default"
```

## Integration with Grafana

Traces are accessible in Grafana through the Jaeger datasource:

1. Go to Grafana > Explore
2. Select "Jaeger" datasource
3. Query traces using the same search criteria

### Linking Metrics to Traces

In dashboards, you can add links from metric panels to Jaeger:
- Click on a data point
- See "View traces" option
- Opens Jaeger with time-correlated traces

### Linking Logs to Traces

If logs include trace IDs:
```json
{"message": "Processing loan", "trace_id": "abc123", "span_id": "def456"}
```

Grafana can link directly to the trace view.

## Troubleshooting Tracing

### No Traces Appearing

1. **Check OTEL Collector is running**:
   ```bash
   kubectl get pods -n tracing
   kubectl logs -l app=otel-collector -n tracing
   ```

2. **Check application is sending traces**:
   ```bash
   kubectl logs -l app=fineract | grep -i trace
   ```

3. **Verify endpoint configuration**:
   ```bash
   kubectl exec -it <fineract-pod> -- env | grep OTEL
   ```

### Traces Missing Spans

1. **Context propagation issue**: Ensure all services use same propagation format (W3C)
2. **Service not instrumented**: Add tracing dependencies
3. **Sampling**: Increase sampling rate temporarily

### High Latency in Tracing

1. Reduce batch size in OTEL Collector
2. Check OTEL Collector resource limits
3. Check Jaeger storage performance
