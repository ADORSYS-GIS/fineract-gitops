# OAuth2 Authentication Setup for Fineract Data Operations

This document describes how to configure OAuth2 authentication for Fineract data loading jobs.

## Overview

All data loading jobs authenticate with Fineract using **OAuth2 Client Credentials Flow** via Keycloak. This provides:

- Token-based authentication with expiration
- Centralized authentication management via Keycloak
- Service account pattern for machine-to-machine auth
- Audit trail and security compliance
- Automatic token refresh before expiry

## Architecture

```
┌──────────────────┐          ┌──────────────┐          ┌──────────────┐
│ Data Loading Job │          │  Keycloak    │          │   Fineract   │
│    (Python)      │          │   (OIDC)     │          │   API        │
└────────┬─────────┘          └──────┬───────┘          └──────┬───────┘
         │                           │                         │
         │ 1. POST /token            │                         │
         │    (client_credentials)   │                         │
         ├──────────────────────────>│                         │
         │                           │                         │
         │ 2. access_token           │                         │
         │    (JWT, expires 5min)    │                         │
         │<──────────────────────────┤                         │
         │                           │                         │
         │ 3. GET/POST /api/v1/*     │                         │
         │    Authorization: Bearer {token}                    │
         ├─────────────────────────────────────────────────────>│
         │                           │                         │
         │ 4. Response               │                         │
         │<─────────────────────────────────────────────────────┤
         │                           │                         │
```

## Prerequisites

- Keycloak instance deployed and accessible from Kubernetes cluster
- Fineract configured with OAuth2 enabled (`FINERACT_SECURITY_OAUTH_ENABLED=true`)
- Access to Keycloak admin console

## Step 1: Keycloak Client Configuration

### Pre-configured Client

**Good news!** The `fineract-data-loader` client is **already defined** in the Keycloak realm configuration and will be automatically created when Keycloak is deployed/configured.

**Client Configuration:**
- **Client ID**: `fineract-data-loader`
- **Name**: Fineract Data Loader Service
- **Type**: Confidential Service Account
- **Grant Type**: Client Credentials
- **Service Account Roles**: `admin` (full access)
- **Token Lifespan**: 30 minutes (sufficient for data loading jobs)

### Get Client Secret

After Keycloak is deployed and configured, retrieve the client secret:

```bash
# Port-forward Keycloak service (if running in K8s)
kubectl port-forward -n keycloak svc/keycloak 8080:8080

# Access: http://localhost:8080
# Login with admin credentials
```

1. Navigate to: **Clients** → **fineract-data-loader** → **Credentials** tab
2. Copy the **Secret** value (you'll need this for the Kubernetes secret)

### Manual Creation (If Needed)

If for some reason the client wasn't automatically created:

1. Navigate to: **Clients** → **Create Client**
2. Configure client settings:
   - **Client ID**: `fineract-data-loader`
   - **Name**: Fineract Data Loading Service Account
   - **Description**: Service account for automated data loading operations
   - **Client Protocol**: openid-connect
   - **Access Type**: Confidential
   - **Service Account Enabled**: ON
   - **Standard Flow Enabled**: OFF
   - **Direct Access Grants Enabled**: OFF
   - **Authorization Enabled**: OFF

3. **Credentials Tab**: Copy the client secret
4. **Service Account Roles Tab**: Assign `admin` realm role

## Step 2: Create Kubernetes Secret

### Option A: Manual Secret Creation (Development)

Create the secret with actual credentials from Keycloak:

```bash
# Replace placeholders with actual values from Keycloak
kubectl create secret generic fineract-admin-credentials \
  -n fineract-dev \
  --from-literal=client-id='fineract-data-loader' \
  --from-literal=client-secret='YOUR_CLIENT_SECRET_FROM_KEYCLOAK' \
  --from-literal=token-url='http://keycloak-service:8080/realms/fineract/protocol/openid-connect/token'
```

### Option B: Sealed Secrets (Production)

For production environments, use Sealed Secrets to encrypt credentials before committing to Git.

#### Create and Seal Secret:

```bash
# Create secret locally (not committed)
kubectl create secret generic fineract-admin-credentials \
  --namespace=fineract-prod \
  --from-literal=client-id='YOUR_CLIENT_ID' \
  --from-literal=client-secret='YOUR_CLIENT_SECRET_FROM_KEYCLOAK' \
  --from-literal=token-url='https://keycloak.example.com/realms/fineract/protocol/openid-connect/token' \
  --dry-run=client -o yaml > /tmp/fineract-admin-creds.yaml

# Encrypt with kubeseal
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  < /tmp/fineract-admin-creds.yaml \
  > secrets/production/fineract-admin-credentials-sealed.yaml

# Clean up plaintext
rm /tmp/fineract-admin-creds.yaml

# Commit encrypted secret
git add secrets/production/fineract-admin-credentials-sealed.yaml
git commit -m "feat: add Fineract admin credentials for production"
```

#### SealedSecret Structure:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: fineract-admin-credentials
  namespace: fineract-prod
spec:
  encryptedData:
    client-id: AgA... # encrypted
    client-secret: AgB... # encrypted
    token-url: AgC... # encrypted
  template:
    metadata:
      name: fineract-admin-credentials
      namespace: fineract-prod
    type: Opaque
```

The Sealed Secrets controller automatically unseals this to a regular Kubernetes Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fineract-admin-credentials
  namespace: fineract-prod
type: Opaque
data:
  client-id: <base64-encoded>
  client-secret: <base64-encoded>
  token-url: <base64-encoded>
```

## Step 3: Verify Secret

```bash
# Check secret exists
kubectl get secret fineract-admin-credentials -n fineract-dev

# Decode and verify values (development only!)
kubectl get secret fineract-admin-credentials -n fineract-dev -o jsonpath='{.data.client-id}' | base64 -d && echo
kubectl get secret fineract-admin-credentials -n fineract-dev -o jsonpath='{.data.token-url}' | base64 -d && echo
```

## Step 4: Test Authentication

Test OAuth2 authentication manually before deploying jobs:

```bash
# Get OAuth2 token using client credentials
curl -X POST 'http://keycloak-service:8080/realms/fineract/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials' \
  -d 'client_id=fineract-data-loader' \
  -d 'client_secret=YOUR_CLIENT_SECRET'

# Response should include:
# {
#   "access_token": "eyJhbGc...",
#   "expires_in": 300,
#   "token_type": "Bearer"
# }

# Test Fineract API with token
TOKEN="eyJhbGc..."  # Use access_token from above

curl -X GET 'http://fineract-read-service:8080/fineract-provider/api/v1/offices' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Fineract-Platform-TenantId: default'
```

## Step 5: Deploy Data Loading Jobs

Jobs will automatically use OAuth2 credentials from the secret:

```bash
# Apply jobs
kubectl apply -k operations/fineract-data/jobs/overlays/dev

# Check job logs
kubectl logs -n fineract-dev job/load-code-values

# Expected log output:
# INFO - Using OAuth2 client credentials authentication
# INFO - Successfully obtained OAuth2 access token
# INFO - Loading code values...
```

## Environment Variables Reference

All data loading jobs use these environment variables:

| Variable | Description | Source |
|----------|-------------|--------|
| `FINERACT_CLIENT_ID` | OAuth2 client ID | Secret: `fineract-admin-credentials.client-id` |
| `FINERACT_CLIENT_SECRET` | OAuth2 client secret | Secret: `fineract-admin-credentials.client-secret` |
| `FINERACT_TOKEN_URL` | Keycloak token endpoint | Secret: `fineract-admin-credentials.token-url` |

## Token Lifecycle

1. **Token Acquisition**: Job starts → BaseLoader obtains token from Keycloak
2. **Token Caching**: Token stored in memory with expiry time (default 5 minutes)
3. **Token Refresh**: Before each API call, BaseLoader checks expiry and refreshes if needed
4. **Token Expiry Buffer**: Tokens refreshed 30 seconds before actual expiry

## Troubleshooting

### Job fails with "Failed to obtain OAuth2 token"

**Possible causes:**
- Client ID or secret incorrect
- Token URL incorrect or unreachable
- Keycloak service not available
- Network policy blocking access to Keycloak

**Debug steps:**
```bash
# Check secret values
kubectl get secret fineract-admin-credentials -n fineract-dev -o yaml

# Check Keycloak connectivity from job pod
kubectl run debug-pod --rm -it --image=curlimages/curl -- sh
curl http://keycloak-service:8080/realms/fineract/.well-known/openid-configuration
```

### Job fails with "401 Unauthorized"

**Possible causes:**
- Token expired and not refreshed
- Service account missing required roles
- Fineract not accepting Bearer tokens

**Debug steps:**
```bash
# Check job logs for token refresh
kubectl logs -n fineract-dev job/load-code-values | grep -i token

# Verify service account roles in Keycloak
# Admin Console → Clients → fineract-data-loader → Service Account Roles
```

### Token refresh too frequent

**Solution:** Adjust token expiry in Keycloak:
1. Navigate to: **Realm Settings** → **Tokens** tab
2. Increase **Access Token Lifespan** (default: 5 minutes)
3. Recommended for data loading: 15-30 minutes

## Migration from Basic Auth

If you have existing jobs using Basic Auth:

1. **Backward Compatibility**: BaseLoader supports both OAuth2 and Basic Auth
   - OAuth2 used if `FINERACT_CLIENT_ID`, `FINERACT_CLIENT_SECRET`, `FINERACT_TOKEN_URL` are set
   - Falls back to Basic Auth if only `FINERACT_USERNAME`, `FINERACT_PASSWORD` are set

2. **Migration Steps**:
   - Create OAuth2 secret (Step 2)
   - Update job manifests to use OAuth2 env vars
   - Test in dev environment
   - Deploy to higher environments

3. **Remove Basic Auth** (after OAuth2 verified working):
   - Remove `FINERACT_USERNAME` and `FINERACT_PASSWORD` env vars from jobs
   - Delete old Basic Auth secret
   - Disable Basic Auth in Fineract: `FINERACT_SECURITY_BASICAUTH_ENABLED=false`

## Security Best Practices

1. **Never commit secrets to Git**
   - Use placeholder values in repository
   - Use Sealed Secrets for encrypted credentials

2. **Rotate credentials regularly**
   - Generate new client secret in Keycloak
   - Update Kubernetes secret
   - Jobs will pick up new credentials on next run

3. **Use least privilege**
   - Only assign roles required for data loading
   - Avoid `fineract-admin` if more specific roles available

4. **Monitor token usage**
   - Check Keycloak logs for token requests
   - Alert on authentication failures

5. **Use different service accounts per environment**
   - `fineract-data-loader-dev`
   - `fineract-data-loader-uat`
   - `fineract-data-loader-prod`

## References

- [Keycloak Client Credentials Grant](https://www.keycloak.org/docs/latest/server_admin/#_service_accounts)
- [OAuth2 Client Credentials Flow](https://oauth.net/2/grant-types/client-credentials/)
- [Fineract OAuth2 Configuration](https://fineract.apache.org/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
