# Network Policies

Kubernetes NetworkPolicies for securing pod-to-pod communication in the Fineract deployment. These policies implement defense-in-depth by controlling ingress and egress traffic at the network level.

## Overview

Network Policies provide Layer 3/4 network security by restricting which pods can communicate with each other. This deployment implements a **default-deny** approach with explicit allow rules for required communication paths.

**Security Model**:
- ❌ **Default**: Deny all traffic (once policies are applied)
- ✅ **Explicit**: Allow only necessary communication
- 🔒 **Defense-in-depth**: Network policies + RBAC + authentication

## Policies

### 1. Fineract Network Policy

**File**: `fineract-network-policy.yaml`
**Applies to**: All Fineract pods (read, write, batch instances)

#### Ingress (Incoming Traffic)

Allows traffic **to** Fineract pods from:

| Source | Ports | Purpose |
|--------|-------|---------|
| Ingress NGINX | 8080, 8443 | External API requests |
| Other Fineract pods | 8080 | Inter-instance communication |
| Monitoring (Prometheus) | 8080 | Metrics scraping |

#### Egress (Outgoing Traffic)

Allows traffic **from** Fineract pods to:

| Destination | Ports | Purpose |
|-------------|-------|---------|
| External (0.0.0.0/0, excluding RFC1918) | 5432 | AWS RDS PostgreSQL |
| External (0.0.0.0/0, excluding RFC1918) | 443 | AWS S3 (document storage) |
| fineract-redis pods | 6379 | Redis caching |
| Keycloak pods | 8080 | OAuth2 token validation |
| kube-dns | 53 (TCP/UDP) | DNS resolution |

**Security Notes**:
- **RDS**: Protected by AWS Security Groups, database auth, private subnets
- **S3**: Protected by IRSA (IAM Roles for Service Accounts) and bucket policies
- **Private networks excluded**: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16

### 2. Fineract Redis Network Policy

**File**: `fineract-redis-network-policy.yaml`
**Applies to**: Redis StatefulSet pods

#### Ingress (Incoming Traffic)

Allows traffic **to** Redis pods from:

| Source | Ports | Purpose |
|--------|-------|---------|
| Fineract pods | 6379 | Cache access |
| Monitoring (Prometheus) | 9121 | Redis exporter metrics |

#### Egress (Outgoing Traffic)

Allows traffic **from** Redis pods to:

| Destination | Ports | Purpose |
|-------------|-------|---------|
| kube-dns | 53 (TCP/UDP) | DNS resolution |

**Security Notes**:
- Redis has **no external egress** - fully isolated
- Only accessible from Fineract pods within namespace

### 3. Keycloak Network Policy

**File**: `keycloak-network-policy.yaml`
**Applies to**: Keycloak pods

#### Ingress (Incoming Traffic)

Allows traffic **to** Keycloak pods from:

| Source | Ports | Purpose |
|--------|-------|---------|
| OAuth2 Proxy | 8080 | OIDC authentication |
| Fineract pods | 8080 | Token validation |
| Ingress NGINX | 8080 | Admin console access |
| Monitoring (Prometheus) | 8080 | Metrics scraping |

#### Egress (Outgoing Traffic)

Allows traffic **from** Keycloak pods to:

| Destination | Ports | Purpose |
|-------------|-------|---------|
| External (0.0.0.0/0, excluding RFC1918) | 5432 | AWS RDS PostgreSQL (Keycloak DB) |
| External (0.0.0.0/0, excluding RFC1918) | 443 | OIDC federation with external IdPs |
| kube-dns | 53 (TCP/UDP) | DNS resolution |

**Security Notes**:
- Allows HTTPS egress for **external identity provider federation**
- RDS protected by security groups and authentication

### 4. OAuth2 Proxy Network Policy

**File**: `oauth2-proxy-network-policy.yaml`
**Applies to**: OAuth2 Proxy pods

#### Ingress (Incoming Traffic)

Allows traffic **to** OAuth2 Proxy pods from:

| Source | Ports | Purpose |
|--------|-------|---------|
| Ingress NGINX | 4180 | Authentication requests |
| Monitoring (Prometheus) | 4180 | Metrics scraping |

#### Egress (Outgoing Traffic)

Allows traffic **from** OAuth2 Proxy pods to:

| Destination | Ports | Purpose |
|-------------|-------|---------|
| Keycloak pods | 8080 | OIDC provider communication |
| fineract-redis pods | 6379 | Session storage |
| kube-dns | 53 (TCP/UDP) | DNS resolution |

**Security Notes**:
- OAuth2 Proxy has **no external egress** (except DNS)
- All OIDC communication is internal to cluster

## Traffic Flow Diagrams

### Authentication Flow

```
Internet → Ingress NGINX → OAuth2 Proxy → Keycloak
                         ↓               ↓
                    fineract-redis   RDS (Keycloak DB)
```

### API Request Flow (Read)

```
Internet → Ingress NGINX → Fineract Read → RDS PostgreSQL
                                        ↘ fineract-redis
                                        ↘ Keycloak (token validation)
```

### API Request Flow (Write)

```
Internet → Ingress NGINX → Fineract Write → RDS PostgreSQL
                                         ↘ S3 (documents)
                                         ↘ fineract-redis
                                         ↘ Keycloak
```

## Security Benefits

### Defense-in-Depth Layers

1. **Network Policies** (Layer 3/4) - Pod-to-pod firewall rules
2. **RBAC** (Kubernetes) - Who can deploy/modify pods
3. **OAuth2** (Layer 7) - User authentication and authorization
4. **TLS** - Encrypted communication
5. **Cloud Security** - AWS Security Groups, IAM, VPC

### Attack Surface Reduction

**Without Network Policies:**
- Any pod can talk to any pod
- Compromised pod can scan entire cluster
- Lateral movement is easy

**With Network Policies:**
- Only explicitly allowed communication
- Compromised pod is isolated
- Blast radius is limited

### Compliance Benefits

- **PCI-DSS**: Network segmentation requirement
- **SOC 2**: Defense-in-depth security controls
- **GDPR**: Data protection through isolation
- **Audit trails**: Clear documentation of allowed communication

## Deployment

### Prerequisites

Your Kubernetes cluster must support NetworkPolicy:
- **AWS EKS**: Requires Calico or AWS VPC CNI with network policy support
- **GKE**: Network policy support must be enabled
- **AKS**: Azure Network Policies or Calico
- **On-premise**: Calico, Cilium, or Weave Net

Check if your cluster supports NetworkPolicy:
```bash
kubectl api-resources | grep networkpolicy
```

### Deploy Network Policies

```bash
# Deploy all policies
kubectl apply -k apps/network-policies

# Deploy specific policy
kubectl apply -f apps/network-policies/fineract-network-policy.yaml
```

### Verify Deployment

```bash
# List all network policies
kubectl get networkpolicy --all-namespaces

# Describe policy
kubectl describe networkpolicy fineract-network-policy -n fineract-dev

# Check if pods are selected
kubectl get pods -n fineract-dev -l app=fineract
```

## Testing

### Test Allowed Communication

```bash
# From Fineract pod to Redis (should work)
kubectl exec -it -n fineract-dev deploy/fineract-read -- nc -zv fineract-redis 6379

# From Fineract pod to Keycloak (should work)
kubectl exec -it -n fineract-dev deploy/fineract-read -- nc -zv keycloak 8080

# From Fineract pod to RDS (should work if RDS is accessible)
kubectl exec -it -n fineract-dev deploy/fineract-read -- nc -zv <RDS_ENDPOINT> 5432
```

### Test Denied Communication

```bash
# From Redis to external (should fail - no egress except DNS)
kubectl exec -it -n fineract-dev statefulset/fineract-redis -- nc -zv google.com 443
# Expected: Connection timeout or refused

# From unauthorized pod to Fineract (should fail)
kubectl run test-pod --image=busybox -it --rm -- nc -zv fineract-write.fineract-dev 8080
# Expected: Connection timeout
```

## Troubleshooting

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Pods can't communicate** | Connection timeout | Check podSelector labels match exactly |
| **RDS connection fails** | Database unreachable | Verify ipBlock allows egress to RDS IP |
| **S3 access fails** | S3 operations timeout | Check egress port 443 is allowed |
| **DNS resolution fails** | Can't resolve service names | Ensure kube-dns egress is allowed |
| **Monitoring broken** | No metrics in Prometheus | Add monitoring namespace selector |

### Debug Steps

1. **Check policy is applied**:
   ```bash
   kubectl get networkpolicy -n fineract-dev
   kubectl describe networkpolicy fineract-network-policy -n fineract-dev
   ```

2. **Verify pod labels**:
   ```bash
   # Check Fineract pods have correct labels
   kubectl get pods -n fineract-dev -l app=fineract --show-labels

   # Check Redis pods have correct labels
   kubectl get pods -n fineract-dev -l app=fineract-redis --show-labels
   ```

3. **Test connectivity**:
   ```bash
   # From Fineract pod
   kubectl exec -it -n fineract-dev deploy/fineract-read -- sh
   nc -zv fineract-redis 6379
   nc -zv keycloak 8080
   ```

4. **Check namespace labels** (for namespaceSelector):
   ```bash
   kubectl get namespace ingress-nginx --show-labels
   kubectl get namespace monitoring --show-labels
   ```

5. **View CNI logs** (if using Calico):
   ```bash
   kubectl logs -n kube-system -l k8s-app=calico-node
   ```

### Enable/Disable Policies

To temporarily disable a policy for testing:
```bash
# Delete policy
kubectl delete networkpolicy fineract-network-policy -n fineract-dev

# Re-apply later
kubectl apply -f apps/network-policies/fineract-network-policy.yaml
```

## Customization

### Allow Additional Ingress

Example: Allow from custom monitoring system:

```yaml
ingress:
  # ... existing rules ...
  - from:
    - namespaceSelector:
        matchLabels:
          name: custom-monitoring
    ports:
    - protocol: TCP
      port: 8080
```

### Allow Additional Egress

Example: Allow Fineract to call external webhook:

```yaml
egress:
  # ... existing rules ...
  - to:
    - ipBlock:
        cidr: 1.2.3.4/32  # Specific external IP
    ports:
    - protocol: TCP
      port: 443
```

### Restrict by Pod Label

Example: Only allow from specific Fineract instance:

```yaml
ingress:
  - from:
    - podSelector:
        matchLabels:
          app: fineract
          instance: write  # Only write instance
    ports:
    - protocol: TCP
      port: 8080
```

## Best Practices

1. **Start with monitoring disabled** - Add monitoring ingress after policies work
2. **Test in dev first** - Don't apply to production without testing
3. **Use specific labels** - Don't use wildcard or empty podSelectors
4. **Document exceptions** - Explain why each rule exists
5. **Regular audits** - Review policies quarterly
6. **Version control** - All policies should be in Git
7. **Monitor logs** - Watch for unexpected denials

## Performance Considerations

Network Policies have minimal performance impact:
- **Latency**: < 1ms additional latency
- **CPU**: Negligible CPU overhead
- **Memory**: ~100KB per policy

However, too many policies can impact CNI performance. Keep policies simple and consolidated.

## Migration Guide

### From No Policies to Network Policies

1. **Audit current traffic**:
   ```bash
   # Enable flow logs (if using Calico)
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calicoctl.yaml
   calicoctl get felixconfiguration default -o yaml
   ```

2. **Deploy in permissive mode** first (document traffic patterns)

3. **Apply policies to dev environment**

4. **Monitor for denials**:
   ```bash
   kubectl logs -n kube-system -l k8s-app=calico-node | grep denied
   ```

5. **Adjust policies** based on findings

6. **Deploy to production** after testing

## References

- **[Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)**
- **[Calico Documentation](https://docs.projectcalico.org/security/calico-network-policy)**
- **[Network Policy Editor](https://editor.cilium.io/)**
- **[Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)**

---

**Namespace**: Per environment (fineract-dev, fineract-uat, fineract-production)
**Component**: Network Security
**Managed by**: ArgoCD
**CNI**: Calico / AWS VPC CNI / Azure CNI (cluster-dependent)
