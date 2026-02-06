# Self-Service Banking - Deployment Runbook

## Overview

This runbook describes how to deploy and configure the self-service banking components.

---

## Prerequisites

### Infrastructure
- Kubernetes cluster (1.25+)
- ArgoCD installed and configured
- Cert-Manager for TLS certificates
- NGINX Ingress Controller
- Sealed Secrets controller

### Existing Services
- Fineract deployed and healthy
- Keycloak deployed with `fineract` realm
- PostgreSQL database available

### Secrets Required
Before deployment, ensure these secrets exist in the target namespace:

| Secret Name | Keys | Description |
|-------------|------|-------------|
| `keycloak-client-secrets` | `customer-registration-client-id`, `customer-registration-client-secret` | Keycloak service account for user creation |
| `fineract-api-secrets` | `username`, `password` | Fineract API credentials (optional, for direct API calls) |
| `customer-registration-db-secrets` | `username`, `password` | Database credentials for transaction logging |

---

## Deployment Order

The self-service components must be deployed in this order:

1. **Phase 1**: Keycloak configuration (roles, groups, client)
2. **Phase 2**: Fineract configuration (GL accounts, payment types)
3. **Phase 3**: Customer Registration Service
4. **Phase 4**: Self-Service Frontend App
5. **Phase 5**: Ingress rules update

---

## Step-by-Step Deployment

### Step 1: Apply Keycloak Configuration

The Keycloak configuration is applied automatically when `keycloak-config` ArgoCD app syncs.

**Verify Keycloak Configuration**:
```bash
# Port-forward to Keycloak
kubectl port-forward svc/keycloak-service 8080:8080 -n fineract-dev

# Check self-service-app client exists
curl -s http://localhost:8080/realms/fineract/.well-known/openid-configuration | jq .

# Check via admin API (requires admin token)
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://localhost:8080/admin/realms/fineract/clients?clientId=self-service-app
```

**Expected Outcome**:
- Client `self-service-app` exists with PKCE enabled
- Group `/self-service-customers` exists
- Roles `self-service-customer`, `self-service-deposit`, `self-service-withdrawal` exist
- Authentication flow `self-service-browser` is bound to client

---

### Step 2: Apply Fineract Configuration

The Fineract configuration is applied automatically when `fineract-config` ArgoCD app syncs.

**Verify GL Accounts**:
```bash
# Port-forward to Fineract
kubectl port-forward svc/fineract-read-service 8443:8443 -n fineract-dev

# Get GL accounts
curl -sk -H "Authorization: Bearer $TOKEN" \
  -H "Fineract-Platform-TenantId: default" \
  https://localhost:8443/fineract-provider/api/v1/glaccounts | jq '.[] | select(.glCode | IN("43","44","45","46"))'
```

**Expected Outcome**:
- GL 43: MTN Mobile Money (Asset)
- GL 44: Orange Money (Asset)
- GL 45: UBA Bank Account (Asset)
- GL 46: Afriland Bank Account (Asset)

**Verify Payment Types**:
```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  -H "Fineract-Platform-TenantId: default" \
  https://localhost:8443/fineract-provider/api/v1/paymenttypes | jq '.[] | select(.name | contains("Transfer"))'
```

**Expected Outcome**:
- MTN Transfer (position 10)
- Orange Transfer (position 11)
- UBA Bank Transfer (position 12)
- Afriland Bank Transfer (position 13)

---

### Step 3: Create Required Secrets

**Create Keycloak client secret for registration service**:
```bash
# Get or create a Keycloak service account with user management permissions
# Then create the secret:

kubectl create secret generic keycloak-client-secrets \
  --from-literal=customer-registration-client-id=customer-registration-service \
  --from-literal=customer-registration-client-secret=YOUR_SECRET_HERE \
  -n fineract-dev

# Or use Sealed Secrets:
cat <<EOF | kubeseal --format yaml > customer-registration-secrets-sealed.yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-client-secrets
  namespace: fineract-dev
data:
  customer-registration-client-id: $(echo -n "customer-registration-service" | base64)
  customer-registration-client-secret: $(echo -n "YOUR_SECRET_HERE" | base64)
EOF
```

---

### Step 4: Deploy Customer Registration Service

**Sync ArgoCD Application**:
```bash
argocd app sync fineract-dev-customer-registration-service
```

**Verify Deployment**:
```bash
# Check pod is running
kubectl get pods -l app=customer-registration-service -n fineract-dev

# Check service is accessible
kubectl port-forward svc/customer-registration-service 8080:80 -n fineract-dev

# Health check
curl http://localhost:8080/actuator/health
```

**Expected Outcome**:
```json
{
  "status": "UP",
  "components": {
    "keycloak": { "status": "UP" },
    "fineract": { "status": "UP" },
    "db": { "status": "UP" }
  }
}
```

---

### Step 5: Deploy Self-Service Frontend App

**Sync ArgoCD Application**:
```bash
argocd app sync fineract-dev-self-service-app
```

**Verify Deployment**:
```bash
# Check pod is running
kubectl get pods -l app=self-service-app -n fineract-dev

# Check service is accessible
kubectl port-forward svc/self-service-app 8080:80 -n fineract-dev

# Load the app
curl -I http://localhost:8080/
```

**Expected Outcome**:
- HTTP 200 response
- HTML content returned
- No 502/503 errors

---

### Step 6: Verify Ingress Configuration

**Check Ingress rules**:
```bash
kubectl get ingress -n fineract-dev

# Describe self-service ingress
kubectl describe ingress self-service-public -n fineract-dev
```

**Test external access**:
```bash
# Replace with your apps hostname
curl -I https://apps.example.com/self-service/
```

**Expected Outcome**:
- HTTP 200 (or 302 redirect to login)
- Path `/self-service/*` routes to `self-service-app` service
- No OAuth2-Proxy authentication required (public)

---

## Post-Deployment Verification

### End-to-End Registration Test

1. **Access the app**:
   ```
   https://apps.example.com/self-service/
   ```

2. **Register a new customer**:
   - Fill in registration form
   - Submit and check for success response

3. **Verify in Fineract**:
   ```bash
   curl -sk -H "Authorization: Bearer $TOKEN" \
     -H "Fineract-Platform-TenantId: default" \
     https://localhost:8443/fineract-provider/api/v1/clients?displayName=John%20Doe
   ```

4. **Verify in Keycloak**:
   ```bash
   curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
     http://localhost:8080/admin/realms/fineract/users?username=john.doe@example.com
   ```

5. **Check email verification**:
   - Customer should receive verification email
   - After verification, WebAuthn registration should be prompted

---

## Troubleshooting

### Common Issues

#### Registration Service Cannot Connect to Keycloak

**Symptoms**:
- Registration fails with "Failed to create user"
- Logs show connection refused to keycloak-service

**Resolution**:
```bash
# Check Keycloak service is running
kubectl get svc keycloak-service -n fineract-dev

# Check network policy allows egress
kubectl describe netpol -n fineract-dev | grep -A5 "customer-registration"

# Verify service account credentials
kubectl get secret keycloak-client-secrets -n fineract-dev -o yaml
```

#### Self-Service App Shows Blank Page

**Symptoms**:
- HTTP 200 but no content
- Browser console shows CORS errors

**Resolution**:
```bash
# Check NGINX config is mounted
kubectl exec -it deploy/self-service-app -n fineract-dev -- cat /etc/nginx/conf.d/default.conf

# Check ConfigMap exists
kubectl get cm self-service-app-nginx-config -n fineract-dev

# Verify OIDC configuration
kubectl get cm self-service-app-config -n fineract-dev -o yaml | grep oidc
```

#### WebAuthn Registration Fails

**Symptoms**:
- "WebAuthn not supported" error
- Authentication flow hangs

**Resolution**:
1. Ensure HTTPS is used (WebAuthn requires secure context)
2. Check Keycloak WebAuthn policy configuration:
   ```bash
   curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
     http://localhost:8080/admin/realms/fineract | jq '.webAuthnPolicyPasswordlessRpEntityName'
   ```
3. Verify `webauthn-register-passwordless` required action is enabled

---

## Rollback Procedure

If deployment fails, rollback using ArgoCD:

```bash
# Rollback customer-registration-service
argocd app rollback fineract-dev-customer-registration-service

# Rollback self-service-app
argocd app rollback fineract-dev-self-service-app

# Rollback to specific revision
argocd app rollback fineract-dev-customer-registration-service <revision>
```

**Manual Cleanup** (if needed):
```bash
# Delete deployments
kubectl delete deploy customer-registration-service -n fineract-dev
kubectl delete deploy self-service-app -n fineract-dev

# Re-sync from GitOps
argocd app sync fineract-dev-customer-registration-service
argocd app sync fineract-dev-self-service-app
```

---

## Monitoring

### Key Metrics to Watch

| Metric | Alert Threshold | Description |
|--------|----------------|-------------|
| `registration_requests_total` | - | Total registration attempts |
| `registration_errors_total` | >10/min | Failed registrations |
| `http_request_duration_seconds` | p99 > 5s | API latency |
| `keycloak_connection_errors` | >0 | Keycloak connectivity issues |
| `fineract_connection_errors` | >0 | Fineract connectivity issues |

### Log Queries (Loki)

```logql
# Registration errors
{app="customer-registration-service"} |= "error" |= "registration"

# WebAuthn failures
{app="keycloak"} |= "webauthn" |= "failed"

# Self-service app errors
{app="self-service-app"} |= "error"
```

---

## Contacts

| Role | Contact |
|------|---------|
| Platform Team | platform@example.com |
| Security Team | security@example.com |
| On-Call | PagerDuty escalation |
