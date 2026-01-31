# Customer Self-Service Extension Plan

## Problem Statement

Customers authenticate via Keycloak but don't have Fineract user accounts. The challenge is: how does Fineract process customer requests when JWT `sub` claim won't match any Fineract user?

## Solution: Service Account Proxy Pattern

**Architecture Decision**: Use intermediary services that validate customer JWT tokens, extract `fineract_external_id` claim, then call Fineract APIs using service account credentials with the external ID as a filter.

```
Customer (JWT) → Self-Service App → Intermediary Services → Fineract (Service Account)
                                           ↓
                                   Extract fineract_external_id
                                   from JWT for customer isolation
```

This pattern is already established in your codebase and requires no Fineract modifications.

---

## Implementation Overview

### Services Architecture

| Operation | Service | Status |
|-----------|---------|--------|
| Registration & KYC | customer-registration-service | Extend |
| Deposits & Withdrawals | payment-gateway-service | Extend |
| Account Queries | **account-query-service** | **New** |
| Loan Applications | customer-registration-service | Extend |
| Profile Updates | customer-registration-service | Extend |

### Why Create account-query-service (New)

- Separation of read (queries) vs write (transactions) operations
- Independent scaling for high-volume query traffic
- Dedicated caching layer with Redis
- Different authorization granularity

---

## Phase 1: Create account-query-service

### Files to Create

**`apps/account-query-service/base/`**:
- `kustomization.yaml`
- `deployment.yaml`
- `service.yaml`
- `configmap.yaml`
- `serviceaccount.yaml`

**`argocd/applications/dev/account-query-service.yaml`**

### API Endpoints

| Endpoint | Method | Fineract Mapping |
|----------|--------|------------------|
| `/api/accounts/profile` | GET | `GET /self/clients` |
| `/api/accounts/savings` | GET | `GET /self/savingsaccounts` |
| `/api/accounts/savings/{id}` | GET | `GET /self/savingsaccounts/{id}` |
| `/api/accounts/savings/{id}/transactions` | GET | `GET /self/savingsaccounts/{id}/transactions` |
| `/api/accounts/loans` | GET | `GET /self/loanaccounts` |
| `/api/accounts/loans/{id}` | GET | `GET /self/loanaccounts/{id}` |

### Deployment Configuration (based on payment-gateway-service pattern)

```yaml
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: account-query-service
          image: ghcr.io/adorsys-gis/fineract-apps/account-query-service:latest
          ports:
            - containerPort: 8081
          env:
            - name: FINERACT_CLIENT_ID
              valueFrom:
                secretKeyRef:
                  name: fineract-api-secrets
                  key: client-id
            - name: FINERACT_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: fineract-api-secrets
                  key: client-secret
```

---

## Phase 2: Update NGINX Routing

**File**: `apps/self-service-app/base/nginx-configmap.yaml`

Add new proxy locations:

```nginx
# Account Query Service Proxy
location /api/accounts/ {
    proxy_pass http://account-query-service.fineract-dev.svc.cluster.local:8081/api/accounts/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Authorization $http_authorization;
    add_header Cache-Control "no-store, no-cache, must-revalidate";
}

# Payment Gateway Proxy
location /api/payments/ {
    proxy_pass http://payment-gateway-service.fineract-dev.svc.cluster.local:8082/api/payments/;
    proxy_set_header Authorization $http_authorization;
    add_header Cache-Control "no-store, no-cache, must-revalidate";
}

# Loan Application Proxy
location /api/loans/ {
    proxy_pass http://customer-registration-service.fineract-dev.svc.cluster.local:80/api/loans/;
    proxy_set_header Authorization $http_authorization;
    add_header Cache-Control "no-store, no-cache, must-revalidate";
}

# Profile Management Proxy
location /api/profile/ {
    proxy_pass http://customer-registration-service.fineract-dev.svc.cluster.local:80/api/profile/;
    proxy_set_header Authorization $http_authorization;
    client_max_body_size 10m;  # For document uploads
}
```

---

## Phase 3: Extend customer-registration-service

### Add Loan Application Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/loans/products` | GET | List available loan products |
| `/api/loans/products/{id}/calculator` | POST | Calculate repayment schedule |
| `/api/loans/apply` | POST | Submit loan application |
| `/api/loans/applications` | GET | List customer's applications |
| `/api/loans/{id}/repay` | POST | Make loan repayment |

### Add Profile Management Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/profile` | GET | Get full customer profile |
| `/api/profile` | PATCH | Update profile fields |
| `/api/profile/documents` | GET/POST | List/upload documents |
| `/api/profile/kyc/status` | GET | Get KYC status |
| `/api/profile/kyc/submit` | POST | Submit for KYC review |

### ConfigMap Extension

**File**: `apps/customer-registration-service/base/configmap.yaml`

Add:
```yaml
# Loan Application Configuration
LOAN_APPLICATION_REQUIRES_KYC_TIER: "2"
MAX_ACTIVE_LOAN_APPLICATIONS: "3"

# Profile Configuration
PROFILE_UPDATE_ALLOWED_FIELDS: "email,phone,address"

# Document Upload Configuration
DOCUMENT_MAX_SIZE_MB: "10"
DOCUMENT_ALLOWED_TYPES: "image/jpeg,image/png,application/pdf"
KYC_REQUIRED_DOCUMENTS: "ID_FRONT,ID_BACK,PROOF_OF_ADDRESS,SELFIE_WITH_ID"
```

---

## Phase 4: Extend Keycloak Roles

**File**: `operations/keycloak-config/base/config/realm-fineract.yaml`

Add new roles:

```yaml
# Loan application capability (Tier 2 only)
- name: self-service-loan-applicant
  description: Can apply for loans

# Document management capability
- name: self-service-document-manager
  description: Can upload and manage documents
```

Update group assignments:
- `/self-service-customers/tier1`: base roles only
- `/self-service-customers/tier2`: add `self-service-loan-applicant`, `self-service-document-manager`

---

## Phase 5: Extend payment-gateway-service

### Add Withdrawal Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/payments/deposit/initiate` | POST | Initiate mobile money deposit |
| `/api/payments/deposit/{id}/status` | GET | Check deposit status |
| `/api/payments/withdraw/initiate` | POST | Initiate withdrawal |
| `/api/payments/withdraw/{id}/status` | GET | Check withdrawal status |
| `/api/payments/methods` | GET | List available payment methods |
| `/api/payments/limits` | GET | Get customer's limits |

---

## Security Implementation

### Customer Isolation - Prevent Account Usurpation (CRITICAL)

**Problem**: A malicious customer could attempt to access or manipulate accounts belonging to other customers by guessing/brute-forcing account IDs in API requests.

**Solution**: Every API endpoint that accepts an account ID must verify ownership before processing.

#### Performance-Optimized Ownership Verification

**Problem**: Naive implementation requires 2 Fineract API calls per request (slow).

**Solution**: Two complementary optimizations:

---

**Optimization 1: Add `fineract_client_id` to JWT Claims**

During customer registration, store the Fineract client ID in Keycloak user attributes and include it in JWT. This eliminates the need to look up clientId on every request.

**File to modify**: `operations/keycloak-config/base/config/realm-fineract.yaml`

Add protocol mapper:
```yaml
protocolMappers:
  - name: fineract-client-id-mapper
    protocol: openid-connect
    protocolMapper: oidc-usermodel-attribute-mapper
    config:
      user.attribute: "fineract_client_id"
      claim.name: "fineract_client_id"
      claim.type: "long"
      access.token.claim: "true"
      id.token.claim: "true"
```

**Update registration service**: When creating Fineract client, store the returned `clientId` in Keycloak user attributes:
```java
// After creating Fineract client
Long fineractClientId = fineractApi.createClient(clientData).getClientId();

// Store in Keycloak user
keycloakAdmin.setUserAttribute(userId, "fineract_client_id", String.valueOf(fineractClientId));
```

---

**Optimization 2: Cache Account Ownership in Redis**

Cache the mapping `accountId → clientId` with reasonable TTL.

```java
@Service
public class AccountOwnershipCache {
    private final RedisTemplate<String, Long> redis;
    private final FineractApi fineractApi;

    private static final Duration CACHE_TTL = Duration.ofMinutes(10);

    public Long getOwningClientId(String accountId) {
        String cacheKey = "account:owner:" + accountId;

        // Try cache first
        Long clientId = redis.opsForValue().get(cacheKey);
        if (clientId != null) {
            return clientId;  // Cache hit - no Fineract call
        }

        // Cache miss - fetch and cache
        SavingsAccount account = fineractApi.getSavingsAccount(accountId);
        clientId = account.getClientId();
        redis.opsForValue().set(cacheKey, clientId, CACHE_TTL);

        return clientId;
    }
}
```

---

**Optimized Flow (Fast Path)**

```
1. JWT contains: fineract_client_id = 42 (from token - no API call)
2. Request: GET /api/accounts/savings/5001
3. Redis lookup: account:owner:5001 → 99 (cache hit - no API call)
4. 42 != 99 → REJECT with 403 Forbidden
```

**Total Fineract API calls**: 0 (after initial cache warm-up)

---

#### Implementation Pattern (Optimized)

```java
@Service
public class AccountSecurityService {
    private final AccountOwnershipCache ownershipCache;

    public void verifyAccountOwnership(String accountId, Jwt jwt) {
        // 1. Get customer's Fineract client ID from JWT (no API call)
        Long customerClientId = jwt.getClaimAsLong("fineract_client_id");
        if (customerClientId == null) {
            // Fallback for legacy tokens without this claim
            String externalId = jwt.getClaimAsString("fineract_external_id");
            customerClientId = lookupClientIdByExternalId(externalId);
        }

        // 2. Get account owner from cache (usually no API call)
        Long accountOwnerClientId = ownershipCache.getOwningClientId(accountId);

        // 3. Verify ownership
        if (!accountOwnerClientId.equals(customerClientId)) {
            log.warn("SECURITY: Client {} attempted access to account {} owned by {}",
                     customerClientId, accountId, accountOwnerClientId);
            throw new ForbiddenException("Access denied");
        }
    }
}
```

#### Endpoints Requiring Ownership Verification

| Service | Endpoint | Resource |
|---------|----------|----------|
| account-query-service | `/api/accounts/savings/{id}` | Savings account |
| account-query-service | `/api/accounts/savings/{id}/transactions` | Savings account |
| account-query-service | `/api/accounts/loans/{id}` | Loan account |
| payment-gateway-service | `/api/payments/deposit/initiate` | Target savings account |
| payment-gateway-service | `/api/payments/withdraw/initiate` | Source savings account |
| customer-registration-service | `/api/loans/{id}/repay` | Loan account |
| customer-registration-service | `/api/profile/documents/{id}` | Document (via client) |

#### Additional Safeguards

1. **List endpoints return ONLY customer's resources**
   - `/api/accounts/savings` → Filter by customer's clientId
   - Never return all accounts and filter client-side

2. **Audit logging for security events**
   - Log all ownership verification failures
   - Monitor for brute-force patterns

3. **Rate limiting on account endpoints**
   - Limit requests per customer to prevent enumeration attacks

### KYC-Based Authorization

Check `kyc_tier` claim for restricted operations:
- Loan applications require `kyc_tier: 2`
- Bank transfers require `kyc_tier: 2`

### Idempotency for Financial Operations

Use idempotency keys with Redis storage (24-hour TTL) to prevent duplicate transactions.

---

## Critical Files to Modify

1. **`apps/self-service-app/base/nginx-configmap.yaml`**
   - Add proxy locations for new API routes

2. **`apps/customer-registration-service/base/configmap.yaml`**
   - Add loan and profile configuration

3. **`operations/keycloak-config/base/config/realm-fineract.yaml`**
   - Add new roles for loan and document management
   - Add fineract_client_id protocol mapper

4. **New: `apps/account-query-service/base/`**
   - Create entire service manifests

5. **`argocd/applications/dev/`**
   - Add account-query-service.yaml ArgoCD application

---

## Verification Plan

1. **Account Query Testing**
   - Deploy account-query-service
   - Login to self-service app
   - Verify balance queries return only customer's accounts
   - Verify transaction history displays correctly

2. **Deposit/Withdrawal Testing**
   - Initiate MTN mobile money deposit
   - Verify payment flow completes
   - Check Fineract transaction created
   - Test withdrawal with limit enforcement

3. **Loan Application Testing**
   - Verify Tier 1 users blocked from loan applications
   - Complete KYC to upgrade to Tier 2
   - Submit loan application
   - Verify loan appears in Fineract pending approval

4. **Security Testing**
   - Attempt to access another customer's account (should fail with 403)
   - Attempt Tier 2 operation as Tier 1 user (should fail)
   - Test idempotency by replaying same request
   - Test rate limiting by sending rapid requests
