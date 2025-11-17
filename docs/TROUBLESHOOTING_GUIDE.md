# Fineract GitOps Troubleshooting Guide

**Last Updated**: 2025-11-10
**Audience**: DevOps Engineers, SREs, Platform Engineers

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
  - [ArgoCD Issues](#argocd-issues)
  - [Application Deployment Issues](#application-deployment-issues)
  - [Database Issues](#database-issues)
  - [Authentication Issues](#authentication-issues)
  - [Networking Issues](#networking-issues)
  - [Resource Issues](#resource-issues)
  - [Storage Issues](#storage-issues)
- [Advanced Diagnostics](#advanced-diagnostics)
- [Emergency Procedures](#emergency-procedures)
- [Getting Help](#getting-help)

---

## Quick Diagnostics

### Health Check Script

Run this comprehensive health check to identify common issues:

```bash
#!/bin/bash
# Quick health check for Fineract platform

NAMESPACE="fineract-dev"  # Change to fineract-uat or fineract-prod as needed

echo "=== Cluster Health ==="
kubectl cluster-info
kubectl get nodes

echo ""
echo "=== ArgoCD Applications ==="
kubectl get applications -n argocd | grep $NAMESPACE

echo ""
echo "=== Pod Status ==="
kubectl get pods -n $NAMESPACE

echo ""
echo "=== Failed Pods ==="
kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded

echo ""
echo "=== Recent Events ==="
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20

echo ""
echo "=== Resource Usage ==="
kubectl top nodes
kubectl top pods -n $NAMESPACE

echo ""
echo "=== PVC Status ==="
kubectl get pvc -n $NAMESPACE

echo ""
echo "=== Service Endpoints ==="
kubectl get endpoints -n $NAMESPACE
```

### Quick Commands

```bash
# Check overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# Check ArgoCD sync status
argocd app list
argocd app get fineract-dev-fineract

# View recent pod failures
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i error | tail -20

# Check application logs
kubectl logs -n fineract-dev -l app=fineract --tail=100

# Check resource constraints
kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

## Common Issues

### ArgoCD Issues

#### Issue: Application Stuck in "Syncing" State

**Symptoms:**
- ArgoCD application shows "Syncing" for extended period
- Resources not being created/updated in cluster

**Diagnosis:**
```bash
# Check application status
argocd app get fineract-dev-fineract

# View sync operation details
kubectl describe application fineract-dev-fineract -n argocd

# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

**Common Causes:**
1. **Invalid Kustomize manifests** - Syntax errors in YAML
2. **Resource quota exceeded** - Not enough cluster resources
3. **Sync waves blocking** - Earlier wave hasn't completed
4. **Network connectivity** - Can't reach Git repository

**Solutions:**

**1. Validate Kustomize locally:**
```bash
kubectl kustomize environments/dev
```

**2. Check sync waves:**
```bash
# List resources by sync wave
kubectl get applications -n argocd -o json | jq '.items[] | {name: .metadata.name, wave: .metadata.annotations["argocd.argoproj.io/sync-wave"]}'
```

**3. Manually terminate stuck sync:**
```bash
argocd app terminate-op fineract-dev-fineract
argocd app sync fineract-dev-fineract --force
```

**4. Check ArgoCD repo access:**
```bash
# Test Git connectivity
argocd repo list
argocd repo get https://github.com/your-org/fineract-gitops
```

---

#### Issue: Application Shows "OutOfSync" but Won't Sync

**Symptoms:**
- Application status is "OutOfSync"
- Manual sync attempts fail or don't resolve drift

**Diagnosis:**
```bash
# View differences
argocd app diff fineract-dev-fineract

# Check sync policy
kubectl get application fineract-dev-fineract -n argocd -o yaml | grep -A 10 syncPolicy
```

**Solutions:**

**1. Force sync with replace:**
```bash
argocd app sync fineract-dev-fineract --force --replace
```

**2. Prune old resources:**
```bash
argocd app sync fineract-dev-fineract --prune
```

**3. Ignore specific differences (if intentional drift):**
Edit the Application manifest:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Ignore replica count drift from HPA
```

---

#### Issue: ArgoCD Can't Access Private Repository

**Symptoms:**
- "Repository not accessible" errors
- Applications can't sync

**Diagnosis:**
```bash
# Check repo credentials
argocd repo list

# Test connectivity
kubectl exec -n argocd deployment/argocd-repo-server -- git ls-remote https://github.com/your-org/fineract-gitops
```

**Solutions:**

**1. Re-add repository with credentials:**
```bash
argocd repo add https://github.com/your-org/fineract-gitops \
  --username <username> \
  --password <token>
```

**2. For SSH access:**
```bash
argocd repo add git@github.com:your-org/fineract-gitops.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

**3. Verify repo secret:**
```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

---

### Application Deployment Issues

#### Issue: Pods Stuck in "CrashLoopBackOff"

**Symptoms:**
- Pods continuously restarting
- Application unavailable

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n fineract-dev

# View pod logs (current container)
kubectl logs -n fineract-dev <pod-name>

# View logs from previous container instance
kubectl logs -n fineract-dev <pod-name> --previous

# Describe pod for events
kubectl describe pod -n fineract-dev <pod-name>
```

**Common Causes:**

**1. Database connection failure:**
```bash
# Check database connectivity from pod
kubectl exec -n fineract-dev <pod-name> -- wget -O- http://postgres:5432 --timeout=5

# Check database credentials secret
kubectl get secret fineract-db-credentials -n fineract-dev -o yaml
```

**Solution:**
- Verify database endpoint is correct
- Check credentials are properly sealed and deployed
- Ensure database is running and accessible

**2. Missing environment variables:**
```bash
# Check pod environment
kubectl exec -n fineract-dev <pod-name> -- env | grep -i fineract
```

**Solution:**
- Review ConfigMap and Secret references in deployment
- Ensure all required environment variables are set

**3. Insufficient resources:**
```bash
# Check resource limits
kubectl describe pod -n fineract-dev <pod-name> | grep -A 5 "Limits"

# Check node resource availability
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Solution:**
- Increase resource requests/limits in deployment
- Scale down other workloads
- Add more cluster nodes

**4. Init container failures:**
```bash
# Check init container logs
kubectl logs -n fineract-dev <pod-name> -c <init-container-name>
```

**Solution:**
- Review init container logic
- Check dependencies (e.g., wait-for-database, copy-assets)

---

#### Issue: Pods Stuck in "Pending" State

**Symptoms:**
- Pods remain in "Pending" status
- No containers running

**Diagnosis:**
```bash
# Check why pod is pending
kubectl describe pod -n fineract-dev <pod-name>

# Check for scheduling issues
kubectl get events -n fineract-dev --field-selector involvedObject.name=<pod-name>
```

**Common Causes:**

**1. Insufficient cluster resources:**
```bash
# Check node capacity
kubectl describe nodes | grep -A 10 "Allocated resources"
```

**Solution:**
```bash
# Scale up cluster or reduce resource requests
# For EKS:
eksctl scale nodegroup --cluster=fineract-dev --name=<nodegroup-name> --nodes=3
```

**2. PVC not bound:**
```bash
# Check PVC status
kubectl get pvc -n fineract-dev
```

**Solution:**
```bash
# Check storage class exists
kubectl get storageclass

# Check PV availability
kubectl get pv

# If using EBS, verify CSI driver is installed
kubectl get pods -n kube-system | grep ebs-csi
```

**3. Node selector/affinity mismatch:**
```bash
# Check pod spec
kubectl get pod -n fineract-dev <pod-name> -o yaml | grep -A 10 nodeSelector
```

**Solution:**
- Remove or update nodeSelector to match available nodes
- Label nodes appropriately

---

#### Issue: Deployment Rollout Stuck

**Symptoms:**
- New deployment not progressing
- Old pods still running alongside new pods

**Diagnosis:**
```bash
# Check rollout status
kubectl rollout status deployment/<deployment-name> -n fineract-dev

# Check deployment events
kubectl describe deployment/<deployment-name> -n fineract-dev
```

**Common Causes:**

**1. Readiness probe failing:**
```bash
# Check pod readiness
kubectl get pods -n fineract-dev -l app=fineract

# Check readiness probe configuration
kubectl get deployment/<deployment-name> -n fineract-dev -o yaml | grep -A 10 readinessProbe
```

**Solution:**
```bash
# Check application health endpoint
kubectl exec -n fineract-dev <pod-name> -- curl http://localhost:8080/fineract-provider/actuator/health

# Adjust readiness probe timing if needed
```

**2. PodDisruptionBudget blocking:**
```bash
# Check PDBs
kubectl get pdb -n fineract-dev
kubectl describe pdb <pdb-name> -n fineract-dev
```

**Solution:**
```bash
# Temporarily reduce PDB constraints or wait for pods to become ready
```

**3. Rollout timeout:**
```bash
# Check deployment progress deadline
kubectl get deployment/<deployment-name> -n fineract-dev -o yaml | grep progressDeadlineSeconds
```

**Solution:**
```bash
# Manually scale down old replica set
kubectl scale rs/<old-replicaset-name> --replicas=0 -n fineract-dev
```

---

### Database Issues

#### Issue: Cannot Connect to PostgreSQL Database

**Symptoms:**
- Application pods failing with database connection errors
- Timeout connecting to database

**Diagnosis:**
```bash
# Check database pod (if using in-cluster DB)
kubectl get pods -n fineract-dev | grep postgres

# For RDS, check connection from cluster
kubectl run -n fineract-dev db-test --rm -it --image=postgres:15 -- \
  psql -h <rds-endpoint> -U fineract -d fineract

# Check database service
kubectl get svc -n fineract-dev | grep postgres

# Check database endpoint
kubectl get endpoints -n fineract-dev | grep postgres
```

**Solutions:**

**1. For RDS connectivity:**
```bash
# Verify security group allows traffic from EKS
aws ec2 describe-security-groups --group-ids <rds-security-group-id>

# Check VPC and subnet configuration
aws rds describe-db-instances --db-instance-identifier <db-instance-id>
```

**2. Check database credentials:**
```bash
# Decode credentials
kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.username}' | base64 -d
kubectl get secret fineract-db-credentials -n fineract-dev -o jsonpath='{.data.password}' | base64 -d
```

**3. Verify database is running:**
```bash
# For RDS
aws rds describe-db-instances --db-instance-identifier <db-instance-id> --query 'DBInstances[0].DBInstanceStatus'
```

**4. Check DNS resolution:**
```bash
kubectl run -n fineract-dev dns-test --rm -it --image=busybox -- nslookup <database-endpoint>
```

---

#### Issue: Database Running Out of Connections

**Symptoms:**
- "Too many connections" errors
- Application intermittently failing

**Diagnosis:**
```bash
# Check current connections
kubectl exec -n fineract-dev <fineract-pod> -- psql -h <db-host> -U fineract -c "SELECT count(*) FROM pg_stat_activity;"

# Check max connections
kubectl exec -n fineract-dev <fineract-pod> -- psql -h <db-host> -U fineract -c "SHOW max_connections;"
```

**Solutions:**

**1. Increase database max_connections:**
```bash
# For RDS, modify parameter group
aws rds modify-db-parameter-group \
  --db-parameter-group-name <parameter-group-name> \
  --parameters "ParameterName=max_connections,ParameterValue=200,ApplyMethod=immediate"
```

**2. Tune application connection pool:**
Edit `apps/fineract/base/deployment-*.yaml`:
```yaml
env:
- name: HIKARICP_MAXIMUM_POOL_SIZE
  value: "20"  # Reduce from default
- name: HIKARICP_MINIMUM_IDLE
  value: "5"
```

**3. Kill idle connections:**
```bash
kubectl exec -n fineract-dev <fineract-pod> -- psql -h <db-host> -U fineract -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND state_change < NOW() - INTERVAL '10 minutes';"
```

---

### Authentication Issues

#### Issue: Keycloak Not Accessible

**Symptoms:**
- Cannot access Keycloak admin console
- Users cannot log in to applications

**Diagnosis:**
```bash
# Check Keycloak pod status
kubectl get pods -n fineract-dev -l app=keycloak

# Check Keycloak logs
kubectl logs -n fineract-dev -l app=keycloak --tail=100

# Test Keycloak health endpoint
kubectl exec -n fineract-dev -l app=keycloak -- curl http://localhost:8080/health
```

**Solutions:**

**1. Keycloak database connection issues:**
```bash
# Check database connectivity
kubectl logs -n fineract-dev -l app=keycloak | grep -i database
```

**2. Keycloak startup timeout:**
```bash
# Increase startup probe timing
# Edit deployment-keycloak.yaml:
startupProbe:
  periodSeconds: 10
  failureThreshold: 60  # Increase from default
```

**3. Import theme/config failures:**
```bash
# Check init containers
kubectl logs -n fineract-dev <keycloak-pod> -c deploy-webank-theme
kubectl logs -n fineract-dev <keycloak-pod> -c keycloak-config-loader
```

---

#### Issue: OAuth2 Proxy Authentication Failures

**Symptoms:**
- Users redirected to error page
- "Error: unable to verify token" messages

**Diagnosis:**
```bash
# Check OAuth2 Proxy logs
kubectl logs -n fineract-dev -l app=oauth2-proxy --tail=100

# Verify OAuth2 Proxy configuration
kubectl get cm oauth2-proxy-config -n fineract-dev -o yaml

# Check client secret
kubectl get secret oauth2-proxy-secret -n fineract-dev -o yaml
```

**Solutions:**

**1. Keycloak client misconfiguration:**
```bash
# Verify client exists in Keycloak
# Access Keycloak admin console → Clients → oauth2-proxy

# Check redirect URIs match
# Should include: https://your-domain.com/oauth2/callback
```

**2. Cookie secret issues:**
```bash
# Regenerate cookie secret
openssl rand -base64 32 | head -c 32

# Update sealed secret
```

**3. Token validation failure:**
```bash
# Check OIDC discovery endpoint
kubectl exec -n fineract-dev <oauth2-proxy-pod> -- \
  curl https://keycloak.your-domain.com/realms/fineract/.well-known/openid-configuration
```

---

### Networking Issues

#### Issue: Service Not Accessible via Ingress

**Symptoms:**
- 404 or 502 errors when accessing application URL
- DNS resolves but connection fails

**Diagnosis:**
```bash
# Check Ingress status
kubectl get ingress -n fineract-dev

# Describe Ingress
kubectl describe ingress <ingress-name> -n fineract-dev

# Check Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100

# Test service directly
kubectl port-forward -n fineract-dev svc/<service-name> 8080:80
```

**Solutions:**

**1. Ingress controller not installed:**
```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml
```

**2. DNS not configured:**
```bash
# Check ALB/NLB endpoint
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Update DNS A record to point to LoadBalancer endpoint
```

**3. TLS certificate issues:**
```bash
# Check certificate status
kubectl get certificate -n fineract-dev
kubectl describe certificate <cert-name> -n fineract-dev

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

---

#### Issue: Pods Cannot Communicate with Each Other

**Symptoms:**
- Service discovery failing
- Connection timeouts between services

**Diagnosis:**
```bash
# Test DNS resolution
kubectl run -n fineract-dev dns-test --rm -it --image=busybox -- \
  nslookup fineract-read.fineract-dev.svc.cluster.local

# Test connectivity
kubectl exec -n fineract-dev <pod-name> -- \
  curl http://fineract-read.fineract-dev.svc.cluster.local:8080

# Check network policies
kubectl get networkpolicies -n fineract-dev
```

**Solutions:**

**1. Network policy blocking traffic:**
```bash
# Temporarily disable network policy for testing
kubectl delete networkpolicy <policy-name> -n fineract-dev

# Review and update network policy rules
```

**2. Service selector mismatch:**
```bash
# Check service selector
kubectl get svc <service-name> -n fineract-dev -o yaml | grep -A 5 selector

# Check pod labels
kubectl get pods -n fineract-dev --show-labels
```

**3. CoreDNS issues:**
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
```

---

### Resource Issues

#### Issue: Node Running Out of Memory (OOMKilled)

**Symptoms:**
- Pods being terminated with OOMKilled status
- Node pressure warnings

**Diagnosis:**
```bash
# Check OOMKilled pods
kubectl get pods -n fineract-dev --field-selector=status.reason=OOMKilled

# Check node memory
kubectl describe node <node-name> | grep -A 10 "Allocated resources"

# Check pod memory usage
kubectl top pods -n fineract-dev
```

**Solutions:**

**1. Increase pod memory limits:**
```yaml
# Edit deployment
resources:
  limits:
    memory: "4Gi"  # Increase as needed
  requests:
    memory: "2Gi"
```

**2. Enable vertical pod autoscaling:**
```bash
# Install VPA
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vpa-0.13.0/vpa-release-0.13.yaml

# Create VPA for deployment
```

**3. Add more nodes:**
```bash
# For EKS
eksctl scale nodegroup --cluster=fineract-dev --nodes=4 --name=<nodegroup-name>
```

---

#### Issue: CPU Throttling

**Symptoms:**
- Slow application response times
- High CPU throttling metrics in monitoring

**Diagnosis:**
```bash
# Check CPU usage
kubectl top pods -n fineract-dev

# Check throttling metrics (if Prometheus installed)
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Query: rate(container_cpu_cfs_throttled_seconds_total[5m])
```

**Solutions:**

**1. Increase CPU limits:**
```yaml
resources:
  limits:
    cpu: "2000m"  # Increase from default
  requests:
    cpu: "1000m"
```

**2. Remove CPU limits (if appropriate):**
```yaml
resources:
  requests:
    cpu: "1000m"
  # limits: {}  # Remove CPU limits to prevent throttling
```

---

### Storage Issues

#### Issue: PersistentVolumeClaim Stuck in "Pending"

**Symptoms:**
- PVC remains in Pending state
- Pod cannot mount volume

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -n fineract-dev
kubectl describe pvc <pvc-name> -n fineract-dev

# Check storage class
kubectl get storageclass

# Check PV availability
kubectl get pv
```

**Solutions:**

**1. StorageClass doesn't exist:**
```bash
# For EBS on EKS, ensure CSI driver is installed
kubectl get pods -n kube-system | grep ebs-csi

# Create default storage class
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**2. No available PVs:**
```bash
# If using static provisioning, create PV manually
# If using dynamic provisioning, check CSI driver logs
kubectl logs -n kube-system -l app=ebs-csi-controller --tail=100
```

**3. Insufficient permissions:**
```bash
# Check IAM role for service account (EKS)
kubectl describe sa ebs-csi-controller-sa -n kube-system

# Verify IAM policy attached
```

---

## Advanced Diagnostics

### Enable Debug Logging

**Fineract:**
```yaml
# Add to deployment environment
- name: LOGGING_LEVEL_ROOT
  value: "DEBUG"
```

**Keycloak:**
```yaml
- name: KEYCLOAK_LOGLEVEL
  value: "DEBUG"
```

**ArgoCD:**
```bash
# Edit argocd-cm ConfigMap
kubectl edit cm argocd-cm -n argocd

# Add:
data:
  application.controller.log.level: "debug"
```

### Capture Network Traffic

```bash
# Install tcpdump in pod
kubectl exec -n fineract-dev <pod-name> -- apt-get update && apt-get install -y tcpdump

# Capture traffic
kubectl exec -n fineract-dev <pod-name> -- tcpdump -i any -w /tmp/capture.pcap

# Copy capture file
kubectl cp fineract-dev/<pod-name>:/tmp/capture.pcap ./capture.pcap
```

### Profile Java Applications

```bash
# Enable JMX in Fineract deployment
env:
- name: JAVA_OPTS
  value: "-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9010 -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false"

# Port-forward JMX port
kubectl port-forward -n fineract-dev <pod-name> 9010:9010

# Connect with VisualVM or JConsole
```

---

## Emergency Procedures

### Complete Platform Restart

```bash
#!/bin/bash
# Emergency restart of entire Fineract platform

NAMESPACE="fineract-dev"

echo "=== Restarting all Fineract deployments ==="
kubectl rollout restart deployment -n $NAMESPACE -l app=fineract

echo "=== Restarting Keycloak ==="
kubectl rollout restart deployment -n $NAMESPACE -l app=keycloak

echo "=== Restarting OAuth2 Proxy ==="
kubectl rollout restart deployment -n $NAMESPACE -l app=oauth2-proxy

echo "=== Restarting Redis ==="
kubectl rollout restart statefulset -n $NAMESPACE -l app=redis

echo "=== Waiting for all pods to be ready ==="
kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=fineract --timeout=600s

echo "=== Restart complete ==="
kubectl get pods -n $NAMESPACE
```

### Rollback to Previous Version

```bash
# For ArgoCD-managed deployments
argocd app rollback fineract-dev-fineract

# For manual deployments
kubectl rollout undo deployment/<deployment-name> -n fineract-dev

# Rollback to specific revision
kubectl rollout undo deployment/<deployment-name> --to-revision=2 -n fineract-dev
```

### Emergency Scale Down

```bash
# Scale down non-critical components to free resources
kubectl scale deployment oauth2-proxy --replicas=0 -n fineract-dev
kubectl scale deployment fineract-batch --replicas=0 -n fineract-dev
kubectl scale deployment web-app --replicas=0 -n fineract-dev

# Scale up critical components
kubectl scale deployment fineract-write --replicas=2 -n fineract-dev
kubectl scale deployment fineract-read --replicas=3 -n fineract-dev
```

---

## Getting Help

### Collect Diagnostics Bundle

Before contacting support, collect comprehensive diagnostics:

```bash
#!/bin/bash
# Collect diagnostic information

NAMESPACE="fineract-dev"
OUTPUT_DIR="diagnostics-$(date +%Y%m%d-%H%M%S)"
mkdir -p $OUTPUT_DIR

# Cluster info
kubectl cluster-info > $OUTPUT_DIR/cluster-info.txt
kubectl get nodes -o wide > $OUTPUT_DIR/nodes.txt
kubectl version > $OUTPUT_DIR/version.txt

# Application status
kubectl get all -n $NAMESPACE > $OUTPUT_DIR/resources.txt
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' > $OUTPUT_DIR/events.txt

# Pod details
for pod in $(kubectl get pods -n $NAMESPACE -o name); do
  kubectl describe $pod -n $NAMESPACE > $OUTPUT_DIR/$(basename $pod)-describe.txt
  kubectl logs $pod -n $NAMESPACE --tail=500 > $OUTPUT_DIR/$(basename $pod)-logs.txt 2>&1
done

# ArgoCD status
argocd app list > $OUTPUT_DIR/argocd-apps.txt
argocd app get fineract-dev-fineract > $OUTPUT_DIR/argocd-app-details.txt

# Configuration
kubectl get cm -n $NAMESPACE -o yaml > $OUTPUT_DIR/configmaps.yaml
kubectl get ingress -n $NAMESPACE -o yaml > $OUTPUT_DIR/ingress.yaml

# Create tarball
tar -czf $OUTPUT_DIR.tar.gz $OUTPUT_DIR
echo "Diagnostics collected in $OUTPUT_DIR.tar.gz"
```

### Support Contacts

- **Platform Team**: platform-team@example.com
- **Security Team**: security-team@example.com
- **On-Call**: sre-team@example.com
- **Slack**: #fineract-support

### Useful Links

- [Operations Guide](OPERATIONS_GUIDE.md)
- [Monitoring & Alerting](operations/MONITORING_ALERTING.md)
- [Alert Runbook](operations/ALERT_RUNBOOK.md)
- [Disaster Recovery Guide](DISASTER_RECOVERY.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)

---

**Document Version**: 1.0
**Last Reviewed**: 2025-11-10
