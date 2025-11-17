# Alert Runbook

This runbook provides detailed investigation and resolution procedures for all monitoring alerts in the Fineract platform.

## Table of Contents

- [How to Use This Runbook](#how-to-use-this-runbook)
- [Alert Severity Levels](#alert-severity-levels)
- [Critical Alerts](#critical-alerts)
- [Warning Alerts](#warning-alerts)
- [Escalation Procedures](#escalation-procedures)

---

## How to Use This Runbook

When an alert fires:

1. **Identify the alert** - Check AlertManager or notification
2. **Find the alert in this runbook** - Use the table of contents
3. **Follow investigation steps** - In order, document findings
4. **Apply resolution** - Based on root cause identified
5. **Document** - Update runbook if new resolution found
6. **Escalate if needed** - Follow escalation procedures

**Alert Format:**
```
Alert: [AlertName]
Severity: [critical|warning|info]
Description: Brief description of what triggered
Impact: What business/system impact this has
```

---

## Alert Severity Levels

| Severity | Response Time | Description | Examples |
|----------|---------------|-------------|----------|
| **Critical** | Immediate (15 min) | Service down, data loss risk, security breach | PodCrashLooping, DatabaseDown, HighErrorRate |
| **Warning** | Within 2 hours | Degraded performance, approaching limits | HighMemoryUsage, DiskSpaceLow, CacheMissRateHigh |
| **Info** | Next business day | FYI, no immediate action needed | CertificateExpiringSoon, HighCPUUsage |

---

## Critical Alerts

### PodCrashLooping

**Alert Definition:**
```yaml
alert: PodCrashLooping
expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
severity: critical
```

**Description:** Pod is repeatedly crashing and restarting

**Impact:** Service unavailable or degraded, user requests failing

**Investigation Steps:**

1. **Identify the crashing pod:**
   ```bash
   kubectl get pods -A | grep -E "CrashLoopBackOff|Error"
   ```

2. **Check pod logs:**
   ```bash
   kubectl logs <pod-name> -n <namespace> --previous
   kubectl logs <pod-name> -n <namespace> --tail=100
   ```

3. **Check pod events:**
   ```bash
   kubectl describe pod <pod-name> -n <namespace> | grep -A 20 "Events:"
   ```

4. **Check resource limits:**
   ```bash
   kubectl top pod <pod-name> -n <namespace>
   kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits:"
   ```

**Common Root Causes & Resolutions:**

| Root Cause | Symptoms in Logs | Resolution |
|------------|------------------|------------|
| OOMKilled | "Exit Code: 137", "OutOfMemory" | Increase memory limits |
| Config error | "Failed to load config", "Invalid YAML" | Fix configuration, redeploy |
| Missing secrets | "Secret not found", "Unable to mount" | Create missing secret |
| Database unreachable | "Connection refused", "Timeout" | Check database connectivity |
| Liveness probe failing | "Liveness probe failed" | Fix probe config or app health |
| Image pull error | "ImagePullBackOff", "ErrImagePull" | Fix image name/tag, check registry auth |

**Resolution Examples:**

```bash
# Increase memory limit
kubectl patch deployment <deployment> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"2Gi"}]'

# Restart deployment
kubectl rollout restart deployment <deployment> -n <namespace>

# Delete pod to force recreation
kubectl delete pod <pod-name> -n <namespace>
```

**Escalation:** If unresolved after 30 minutes, escalate to platform team

---

### DatabaseConnectionPoolExhausted

**Alert Definition:**
```yaml
alert: DatabaseConnectionPoolExhausted
expr: hikaricp_connections_active / hikaricp_connections_max > 0.9
severity: critical
```

**Description:** Database connection pool is 90% or more utilized

**Impact:** New database requests will fail, application slowdown

**Investigation Steps:**

1. **Check current connection usage:**
   ```bash
   # Port-forward to Prometheus
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

   # Query connection pool metrics
   hikaricp_connections_active
   hikaricp_connections_max
   hikaricp_connections_pending
   ```

2. **Check for long-running queries:**
   ```sql
   -- Connect to PostgreSQL
   SELECT pid, age(clock_timestamp(), query_start), usename, query
   FROM pg_stat_activity
   WHERE state != 'idle' AND query NOT ILIKE '%pg_stat_activity%'
   ORDER BY query_start DESC;
   ```

3. **Check application logs for connection leaks:**
   ```bash
   kubectl logs deployment/fineract-write -n fineract-dev | grep -i "connection"
   ```

4. **Check database max_connections:**
   ```sql
   SHOW max_connections;
   SELECT count(*) FROM pg_stat_activity;
   ```

**Common Root Causes & Resolutions:**

| Root Cause | Indicators | Resolution |
|------------|------------|------------|
| Connection leak | Connections not released, increasing over time | Restart app, fix code |
| Slow queries | Many long-running queries | Optimize queries, add indexes |
| Traffic spike | Sudden increase in requests | Scale horizontally |
| Small pool size | Pool max < expected concurrency | Increase pool size |

**Resolution Examples:**

```bash
# Increase connection pool size
kubectl set env deployment/fineract-write -n fineract-dev \
  FINERACT_HIKARI_MAXIMUM_POOL_SIZE=20

# Restart to reset connections
kubectl rollout restart deployment/fineract-write -n fineract-dev

# Scale horizontally if traffic spike
kubectl scale deployment fineract-write --replicas=2 -n fineract-dev
```

**Temporary Mitigation:**
```sql
-- Kill idle connections (CAUTION: may affect users)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
  AND state_change < current_timestamp - interval '10 minutes';
```

**Escalation:** If pool exhaustion persists, escalate to database team

---

### HighAPIErrorRate

**Alert Definition:**
```yaml
alert: HighAPIErrorRate
expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.05
severity: critical
```

**Description:** API returning 5xx errors at rate > 5%

**Impact:** Users experiencing errors, potential data inconsistency

**Investigation Steps:**

1. **Identify error types:**
   ```bash
   kubectl logs deployment/fineract-write -n fineract-dev | grep "ERROR" | tail -50
   ```

2. **Check specific error codes:**
   ```promql
   # In Prometheus UI
   sum by (status, uri) (rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
   ```

3. **Check dependent services:**
   ```bash
   kubectl get pods -n fineract-dev
   kubectl logs deployment/fineract-write -n fineract-dev | grep -i "connection refused\|timeout"
   ```

4. **Check recent deployments:**
   ```bash
   kubectl rollout history deployment/fineract-write -n fineract-dev
   ```

**Common Root Causes & Resolutions:**

| Error Code | Common Causes | Resolution |
|------------|---------------|------------|
| 500 | Unhandled exception, bug | Rollback to previous version |
| 502 | Gateway timeout, pod not ready | Check pod health, increase timeout |
| 503 | Service unavailable, overload | Scale up, check resources |
| 504 | Database timeout, slow query | Optimize queries, add connection pool |

**Resolution Examples:**

```bash
# Rollback to previous version
kubectl rollout undo deployment/fineract-write -n fineract-dev

# Scale up to handle load
kubectl scale deployment fineract-write --replicas=2 -n fineract-dev

# Restart unhealthy pods
kubectl delete pod -l app=fineract-write -n fineract-dev
```

**Escalation:** If error rate remains > 5% for 15 minutes, escalate to development team

---

### PodNotReady

**Alert Definition:**
```yaml
alert: PodNotReady
expr: kube_pod_status_ready{condition="false"} == 1
severity: critical
```

**Description:** Pod exists but is not in Ready state

**Impact:** Service degraded, reduced capacity

**Investigation Steps:**

1. **Check pod status:**
   ```bash
   kubectl get pods -n fineract-dev
   kubectl describe pod <pod-name> -n fineract-dev
   ```

2. **Check readiness probe:**
   ```bash
   kubectl describe pod <pod-name> -n fineract-dev | grep -A 10 "Readiness:"
   ```

3. **Check container logs:**
   ```bash
   kubectl logs <pod-name> -n fineract-dev
   ```

4. **Check pod events:**
   ```bash
   kubectl get events -n fineract-dev --field-selector involvedObject.name=<pod-name>
   ```

**Common Root Causes:**
- Readiness probe failing (application not healthy)
- Slow startup (database migrations)
- Missing dependencies (database, cache not available)
- Resource constraints

**Resolution:** See PodCrashLooping section for detailed steps

---

## Warning Alerts

### HighMemoryUsage

**Alert Definition:**
```yaml
alert: HighMemoryUsage
expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
severity: warning
```

**Description:** Container using > 90% of memory limit

**Impact:** Risk of OOMKill, performance degradation

**Investigation Steps:**

1. **Identify high-memory pods:**
   ```bash
   kubectl top pods -A --sort-by=memory
   ```

2. **Check memory trends:**
   ```promql
   # In Prometheus
   container_memory_usage_bytes{pod="<pod-name>"}
   ```

3. **Check for memory leaks:**
   ```bash
   # Get heap dump (Java apps)
   kubectl exec <pod-name> -n <namespace> -- jmap -dump:live,format=b,file=/tmp/heap.bin 1
   ```

4. **Check JVM memory settings (Fineract):**
   ```bash
   kubectl exec <pod-name> -n fineract-dev -- env | grep JAVA_OPTS
   ```

**Resolutions:**

```bash
# Increase memory limit
kubectl patch deployment <deployment> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"4Gi"}]'

# Restart to clear memory (temporary)
kubectl rollout restart deployment <deployment> -n <namespace>

# Adjust JVM heap (Fineract)
kubectl set env deployment/fineract-write -n fineract-dev \
  JAVA_OPTS="-Xms1g -Xmx2g -XX:MaxMetaspaceSize=512m"
```

---

### HighCacheMissRate

**Alert Definition:**
```yaml
alert: HighCacheMissRate
expr: rate(redis_keyspace_misses_total[5m]) / rate(redis_keyspace_hits_total[5m]) > 0.3
severity: warning
```

**Description:** Redis cache miss rate > 30%

**Impact:** Increased database load, slower response times

**Investigation Steps:**

1. **Check cache statistics:**
   ```bash
   kubectl exec -it fineract-redis-0 -n fineract-dev -c redis -- redis-cli INFO stats
   ```

2. **Check cache memory:**
   ```bash
   kubectl exec -it fineract-redis-0 -n fineract-dev -c redis -- redis-cli INFO memory
   ```

3. **Check eviction policy:**
   ```bash
   kubectl exec -it fineract-redis-0 -n fineract-dev -c redis -- redis-cli CONFIG GET maxmemory-policy
   ```

4. **Check for cache clears:**
   ```bash
   kubectl logs fineract-redis-0 -n fineract-dev -c redis | grep FLUSHALL
   ```

**Common Root Causes:**
- Cache recently cleared/restarted
- Cache memory too small (evictions)
- Query pattern changed (different data accessed)
- TTL too short for frequently accessed data

**Resolutions:**

```bash
# Increase Redis memory (if evicting due to memory)
kubectl patch statefulset fineract-redis -n fineract-dev --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"1Gi"}]'

# Check if warming cache helps
kubectl exec <fineract-pod> -n fineract-dev -- curl -X POST http://localhost:8080/fineract-provider/admin/cache/warm
```

**Note:** Cache miss rate typically improves over time as cache warms up. Monitor for 30 minutes before taking action.

---

### DiskSpaceLow

**Alert Definition:**
```yaml
alert: DiskSpaceLow
expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.2
severity: warning
```

**Description:** Node disk space below 20%

**Impact:** Pod scheduling failures, log loss, potential outage

**Investigation Steps:**

1. **Check disk usage by node:**
   ```bash
   kubectl get nodes
   kubectl describe node <node-name> | grep -A 10 "Allocated resources"
   ```

2. **Check persistent volumes:**
   ```bash
   kubectl get pv
   kubectl describe pv <pv-name>
   ```

3. **Identify large consumers:**
   ```bash
   # SSH to node or use DaemonSet
   du -sh /var/lib/docker/* | sort -h
   du -sh /var/log/* | sort -h
   ```

**Resolutions:**

```bash
# Clean up unused images
kubectl exec -it <node-pod> -- docker system prune -a -f

# Clean up old logs
kubectl exec -it <node-pod> -- find /var/log -name "*.log" -mtime +7 -delete

# Increase PV size (if supported by storage class)
kubectl patch pv <pv-name> --type='json' \
  -p='[{"op": "replace", "path": "/spec/capacity/storage", "value":"50Gi"}]'
```

---

### CertificateExpiringSoon

**Alert Definition:**
```yaml
alert: CertificateExpiringSoon
expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
severity: warning
```

**Description:** TLS certificate expires in < 7 days

**Impact:** HTTPS will break when cert expires, service unavailable

**Investigation Steps:**

1. **Check certificate status:**
   ```bash
   kubectl get certificates -A
   kubectl describe certificate <cert-name> -n <namespace>
   ```

2. **Check cert-manager logs:**
   ```bash
   kubectl logs -n cert-manager deployment/cert-manager
   ```

3. **Check issuer status:**
   ```bash
   kubectl get clusterissuer
   kubectl describe clusterissuer letsencrypt-prod
   ```

**Resolutions:**

```bash
# Force certificate renewal
kubectl delete certificate <cert-name> -n <namespace>
kubectl apply -f <certificate-yaml>

# Check cert-manager ACME challenge
kubectl get challenges -A
kubectl describe challenge <challenge-name> -n <namespace>

# Manually renew with certbot (if using Let's Encrypt)
certbot renew --force-renewal
```

---

## Escalation Procedures

### Level 1: On-Call Engineer (You)

**Responsibilities:**
- Acknowledge alert within response time SLA
- Follow runbook procedures
- Document investigation
- Resolve or escalate within 30 minutes

**Actions:**
1. Acknowledge alert in AlertManager
2. Follow runbook steps
3. Document findings in incident tracker
4. Resolve if possible, escalate if not

### Level 2: Platform Team

**When to escalate:**
- Issue not covered in runbook
- Runbook procedures don't resolve issue
- Multiple alerts firing simultaneously
- Data loss risk identified

**How to escalate:**
1. Create incident in tracking system (e.g., Jira)
2. Include all investigation findings
3. Notify on-call platform engineer via Slack/PagerDuty
4. Hand off context

**Escalation Channels:**
- Slack: `#fineract-platform-oncall`
- PagerDuty: Trigger platform team incident
- Email: platform-team@your-domain.com

### Level 3: Development Team

**When to escalate:**
- Application bug identified
- Code change required
- Database schema issue
- Performance optimization needed

**How to escalate:**
1. Create bug ticket with reproduction steps
2. Notify development lead
3. Include relevant logs and metrics
4. Request priority assessment

### Level 4: Leadership

**When to escalate:**
- Customer-facing outage > 1 hour
- Data breach or security incident
- Multiple services down
- Estimated recovery time > 4 hours

**Notification Template:**
```
Subject: [CRITICAL] Fineract Production Incident

Status: ONGOING / RESOLVED
Start Time: YYYY-MM-DD HH:MM UTC
Impact: <Number of affected users/services>
Current Status: <What's happening now>
Next Update: <When>
Incident Commander: <Name>
```

---

## Post-Incident Procedures

After resolving a critical alert:

1. **Update AlertManager** - Resolve or silence the alert
2. **Document Resolution** - Add to runbook if new resolution
3. **Write Post-Mortem** (for critical incidents):
   - Timeline of events
   - Root cause analysis
   - Resolution steps taken
   - Action items to prevent recurrence
4. **Review Alert Threshold** - Was alert useful? Tuning needed?
5. **Update Dashboards** - Add visualization if missing

---

## Related Documentation

- [Monitoring and Alerting Guide](MONITORING_ALERTING.md)
- [Metrics Reference](METRICS_REFERENCE.md)
- [Operations Guide](../OPERATIONS_GUIDE.md)
- [Disaster Recovery Guide](../operations/disaster-recovery/DR_GUIDE.md)

---

## Feedback

If you encounter a scenario not covered in this runbook:
1. Document your investigation and resolution
2. Submit a pull request to update this runbook
3. Share in `#fineract-operations` Slack channel

**Runbook Version:** 1.0
**Last Updated:** 2025-01-02
**Maintained By:** Platform Team
