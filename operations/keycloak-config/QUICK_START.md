# Keycloak Quick Start Guide

**⚡ Fast deployment guide for production-ready Keycloak**

---

## 🚀 5-Minute Quick Start (Development)

```bash
# 1. Deploy Keycloak base
kubectl apply -k apps/keycloak/base/

# 2. Wait for Keycloak to be ready
kubectl wait --for=condition=ready pod -l app=keycloak -n fineract --timeout=300s

# 3. Create client secrets (dev)
kubectl create secret generic keycloak-client-secrets -n fineract \
  --from-literal=apache-gateway=dev-secret-apache-123 \
  --from-literal=admin-cli=dev-secret-admin-456 \
  --from-literal=fineract-api=dev-secret-api-789 \
  --from-literal=message-gateway=dev-secret-msg-101 \
  --from-literal=payment-gateway=dev-secret-pay-102

# 4. Deploy Webank theme
kubectl create configmap keycloak-webank-theme -n fineract \
  --from-file=operations/keycloak-config/themes/webank/

# 5. Apply realm configuration
kubectl apply -f operations/keycloak-config/jobs/apply-keycloak-config.yaml

# 6. Check Job status
kubectl logs -n fineract job/apply-keycloak-config -f

# 7. Deploy user sync service
kubectl create secret generic user-sync-keycloak-secret -n fineract \
  --from-literal=admin-cli-secret=dev-secret-admin-456

kubectl apply -f operations/keycloak-config/user-sync-service/k8s/deployment.yaml

# 8. Verify
kubectl get all -n fineract
kubectl port-forward -n fineract svc/keycloak-service 8080:8080
# Open: http://localhost:8080
```

**Done!** Keycloak is running with Webank theme and user sync service.

---

## 🏭 Production Deployment

### Prerequisites

1. **Generate Strong Secrets**
   ```bash
   # For each client
   openssl rand -base64 32
   ```

2. **Set Up Sealed Secrets**
   ```bash
   # Install Sealed Secrets Controller
   kubectl apply -f argocd/applications/system/sealed-secrets-controller.yaml

   # Create secret locally (not committed to Git)
   kubectl create secret generic keycloak-client-secrets \
     --from-literal=apache-gateway=$(openssl rand -base64 32) \
     --from-literal=admin-cli=$(openssl rand -base64 32) \
     --from-literal=fineract-api=$(openssl rand -base64 32) \
     --from-literal=message-gateway=$(openssl rand -base64 32) \
     --from-literal=payment-gateway=$(openssl rand -base64 32) \
     --dry-run=client -o yaml > /tmp/keycloak-client-secrets.yaml

   # Encrypt with kubeseal
   kubeseal --controller-namespace kube-system \
     --controller-name sealed-secrets-controller \
     --format yaml \
     < /tmp/keycloak-client-secrets.yaml \
     > secrets/production/keycloak-client-secrets-sealed.yaml

   # Clean up plaintext
   rm /tmp/keycloak-client-secrets.yaml

   # Commit encrypted secret to Git
   git add secrets/production/keycloak-client-secrets-sealed.yaml
   git commit -m "feat: add Keycloak client secrets for production"
   ```

3. **Configure SMTP**
   ```bash
   # Create SMTP secret locally
   kubectl create secret generic smtp-credentials \
     --from-literal=smtp-user=apikey \
     --from-literal=smtp-password="SG.your-sendgrid-api-key" \
     --dry-run=client -o yaml > /tmp/smtp-credentials.yaml

   # Encrypt with kubeseal
   kubeseal --controller-namespace kube-system \
     --controller-name sealed-secrets-controller \
     --format yaml \
     < /tmp/smtp-credentials.yaml \
     > secrets/production/smtp-credentials-sealed.yaml

   # Clean up plaintext
   rm /tmp/smtp-credentials.yaml

   # Commit encrypted secret
   git add secrets/production/smtp-credentials-sealed.yaml
   git commit -m "feat: add SMTP credentials for production"
   ```

### Deployment Steps

```bash
# 1. Deploy Keycloak base
kubectl apply -k apps/keycloak/base/

# 2. Wait for Keycloak to be ready
kubectl wait --for=condition=ready pod -l app=keycloak -n fineract --timeout=300s

# 3. Sealed Secrets unsealed automatically by controller

# 4. Deploy Webank theme
kubectl create configmap keycloak-webank-theme -n fineract \
  --from-file=operations/keycloak-config/themes/webank/ \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap keycloak-webank-theme -n fineract \
  app.kubernetes.io/part-of=keycloak

# 5. Apply realm configuration
kubectl apply -f operations/keycloak-config/jobs/apply-keycloak-config.yaml

# 6. Deploy user sync service
kubectl apply -f operations/keycloak-config/user-sync-service/k8s/deployment.yaml

# 7. Apply production security policies
kubectl apply -f operations/keycloak-config/security-policies/network-policy-production.yaml
kubectl apply -f operations/keycloak-config/security-policies/keycloak-production-config.yaml

# 8. Deploy monitoring
kubectl apply -f operations/keycloak-config/monitoring/prometheus-rules.yaml

# 9. Verify installation
kubectl get all -n fineract -l app.kubernetes.io/part-of=keycloak
```

---

## 🧪 Testing

### Test Login Flow

```bash
# Port forward Keycloak
kubectl port-forward -n fineract svc/keycloak-service 8080:8080

# Open browser
open http://localhost:8080/realms/fineract/account

# Login with test user
# Username: loan.officer
# Password: Password123! (temporary - will be forced to change)
```

### Test User Sync

```bash
# Port forward user sync service
kubectl port-forward -n fineract svc/user-sync-service 5000:5000

# Sync a user
curl -X POST http://localhost:5000/sync/user \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 123,
    "username": "john.doe",
    "email": "john.doe@webank.com",
    "firstName": "John",
    "lastName": "Doe",
    "role": "Loan Officer",
    "officeId": 1,
    "officeName": "Head Office",
    "employeeId": "EMP001",
    "mobileNumber": "+254712345678"
  }'
```

### Test Admin Console is Blocked

```bash
# Try to access admin console (should fail in production)
kubectl port-forward -n fineract svc/keycloak-service 8080:8080
open http://localhost:8080/admin

# Expected: 403 Forbidden or Connection Refused
```

---

## 📝 Common Operations

### Update Realm Configuration

```bash
# Edit realm config
vim operations/keycloak-config/config/realm-fineract.yaml

# Commit and push
git add operations/keycloak-config/config/realm-fineract.yaml
git commit -m "keycloak: update realm configuration"
git push

# ArgoCD will auto-apply within 3 minutes
# Or manually trigger:
kubectl apply -f operations/keycloak-config/jobs/apply-keycloak-config.yaml
```

### Update Webank Theme

```bash
# Edit theme files
vim operations/keycloak-config/themes/webank/login/resources/css/webank.css

# Update ConfigMap
kubectl create configmap keycloak-webank-theme -n fineract \
  --from-file=operations/keycloak-config/themes/webank/ \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Keycloak to reload theme
kubectl rollout restart deployment/keycloak -n fineract

# Commit and push
git add operations/keycloak-config/themes/
git commit -m "keycloak: update theme"
git push
```

### Add New Role

```bash
# 1. Edit realm config
vim operations/keycloak-config/config/realm-fineract.yaml

# Add to roles.realm section:
# - name: auditor
#   description: Audit role
#   composite: false

# 2. Update user sync service (if mapping from Fineract)
vim operations/keycloak-config/user-sync-service/app/sync_service.py

# Add to ROLE_MAPPING:
# "Auditor": "auditor",
# "auditor": "auditor",

# 3. Commit and push
git add operations/keycloak-config/
git commit -m "keycloak: add auditor role"
git push

# 4. Apply changes
kubectl apply -f operations/keycloak-config/jobs/apply-keycloak-config.yaml
kubectl rollout restart deployment/fineract-user-sync -n fineract
```

### Add New Client

```bash
# 1. Edit realm config
vim operations/keycloak-config/config/realm-fineract.yaml

# Add to clients section:
# - clientId: reporting-service
#   name: Reporting Microservice
#   enabled: true
#   publicClient: false
#   clientAuthenticatorType: client-secret
#   secret: "${REPORTING_SERVICE_SECRET}"
#   serviceAccountsEnabled: true
#   standardFlowEnabled: false

# 2. Create secret (production: use External Secrets)
# Development:
kubectl create secret generic keycloak-client-secrets -n fineract \
  --from-literal=reporting-service=dev-secret-reporting-789 \
  --dry-run=client -o yaml | kubectl apply -f -

# Production: update SealedSecret
# (add reporting-service key, reseal, and commit to Git)

# 3. Commit and push
git add operations/keycloak-config/config/realm-fineract.yaml
git commit -m "keycloak: add reporting-service client"
git push

# 4. Apply changes
kubectl apply -f operations/keycloak-config/jobs/apply-keycloak-config.yaml
```

### Rotate Client Secret

```bash
# 1. Generate new secret
NEW_SECRET=$(openssl rand -base64 32)

# 2. Update secret store (production)
aws secretsmanager update-secret \
  --secret-id /fineract/production/keycloak/apache-gateway-secret \
  --secret-string "$NEW_SECRET"

# Or update Kubernetes Secret (development)
kubectl create secret generic keycloak-client-secrets -n fineract \
  --from-literal=apache-gateway="$NEW_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart Keycloak to reload secret
kubectl rollout restart statefulset/keycloak -n fineract

# 4. Update clients using this secret (Apache gateway, etc.)
# Update client configuration to use new secret
```

---

## 🔍 Troubleshooting

### Check Logs

```bash
# Keycloak logs
kubectl logs -n fineract statefulset/keycloak -f

# User sync service logs
kubectl logs -n fineract -l app=fineract-user-sync -f

# Config apply job logs
kubectl logs -n fineract job/apply-keycloak-config
```

### Verify Services

```bash
# Check all Keycloak components
kubectl get all -n fineract -l app.kubernetes.io/part-of=keycloak

# Check secrets
kubectl get secrets -n fineract | grep keycloak

# Check ConfigMaps
kubectl get configmaps -n fineract | grep keycloak
```

### Test Endpoints

```bash
# Test Keycloak health
kubectl port-forward -n fineract svc/keycloak-service 8080:8080
curl http://localhost:8080/health

# Test realm endpoint
curl http://localhost:8080/realms/fineract/.well-known/openid-configuration

# Test user sync health
kubectl port-forward -n fineract svc/user-sync-service 5000:5000
curl http://localhost:5000/health
```

### Reset User Password (Admin)

```bash
# Port forward Keycloak
kubectl port-forward -n fineract svc/keycloak-service 8080:8080

# Get admin token
ADMIN_TOKEN=$(curl -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

# Get user ID
USER_ID=$(curl -X GET "http://localhost:8080/admin/realms/fineract/users?username=john.doe" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

# Reset password
curl -X PUT "http://localhost:8080/admin/realms/fineract/users/$USER_ID/reset-password" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "password",
    "value": "NewPassword123!",
    "temporary": true
  }'
```

### Unlock Locked User

```bash
# Check user lockout status
curl -X GET "http://localhost:8080/admin/realms/fineract/attack-detection/brute-force/users/$USER_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Unlock user
curl -X DELETE "http://localhost:8080/admin/realms/fineract/attack-detection/brute-force/users/$USER_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

---

## 📊 Monitoring

### View Metrics

```bash
# Port forward Keycloak
kubectl port-forward -n fineract svc/keycloak-service 8080:8080

# View Prometheus metrics
curl http://localhost:8080/metrics
```

### Check Prometheus Alerts

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open browser
open http://localhost:9090/alerts
```

### View Grafana Dashboard

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser (default credentials: admin/admin)
open http://localhost:3000

# Import dashboard from:
# operations/keycloak-config/monitoring/grafana-dashboard.json
```

---

## 🔐 Emergency Admin Access

**⚠️ Use only in emergencies with proper approval**

```bash
# 1. Get approval from security team
# 2. Document the reason in incident ticket
# 3. Port forward Keycloak
kubectl port-forward -n fineract svc/keycloak-service 8080:8080

# 4. Access admin console
open http://localhost:8080/admin

# 5. Login with admin credentials (stored in secret)
kubectl get secret keycloak-admin-secret -n fineract -o jsonpath='{.data.admin-password}' | base64 -d

# 6. Perform emergency action
# 7. Document all changes made
# 8. Close port-forward
```

---

## 📚 Documentation

- **Complete Guide**: [README.md](README.md)
- **Implementation Summary**: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)
- **Security Architecture**: [docs/SECURITY.md](docs/SECURITY.md)
- **User Onboarding**: [docs/USER_ONBOARDING.md](docs/USER_ONBOARDING.md)
- **Role Mapping**: [ROLE_MAPPING.md](ROLE_MAPPING.md)
- **Validation Complete**: [VALIDATION_COMPLETE.md](VALIDATION_COMPLETE.md)

---

## 🆘 Support

**Emergency**: PagerDuty
**Security**: security@webank.com
**User Support**: support@webank.com
**Documentation**: operations/keycloak-config/docs/

---

**🎉 Keycloak is production-ready!** 🚀🏦🔒
