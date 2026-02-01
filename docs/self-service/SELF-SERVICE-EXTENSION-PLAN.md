# Customer Self-Service Extension Plan

## Problem Statement

Customers authenticate via Keycloak but don't have Fineract user accounts. The challenge is: how does Fineract process customer requests when JWT `sub` claim won't match any Fineract user?

## Solution: Service Account Proxy Pattern

**Architecture Decision**: Use an intermediary service (`customer-self-service`) that validates customer JWT tokens, extracts `fineract_client_id` claim, then calls Fineract APIs using service account credentials with ownership verification.

```
Customer (JWT) → Self-Service App → customer-self-service → Fineract (Service Account)
                                           ↓
                                   1. Extract fineract_client_id from JWT
                                   2. Verify account ownership (multi-account)
                                   3. Forward request to Fineract
```

This pattern requires no Fineract modifications.

---

## Implementation Status

### Completed ✅

| Task | Status | Commit |
|------|--------|--------|
| Rename `customer-registration-service` → `customer-self-service` | ✅ Done | `c808c78` |
| Update NGINX proxy for `/api/accounts/` | ✅ Done | `c808c78` |
| Add `fineract_client_id` JWT claim to Keycloak | ✅ Done | `5380b93` |
| Update frontend hooks to use `/api/accounts/` endpoints | ✅ Done | `0eef17e` |
| Create `accountsApi.ts` service in frontend | ✅ Done | `0eef17e` |
| Add account query endpoints to backend | ✅ Done | `4fe8170` |
| Implement `AccountSecurityService` for ownership verification | ✅ Done | `4fe8170` |
| Store `fineract_client_id` in Keycloak during registration | ✅ Done | `4fe8170` |

### Remaining (Future Phases)

| Task | Status | Priority |
|------|--------|----------|
| Add Redis caching for ownership verification | ⏳ Pending | Medium |
| Loan application endpoints | ⏳ Pending | Low |
| Profile management endpoints | ⏳ Pending | Low |
| Additional Keycloak roles for tiered access | ⏳ Pending | Low |

---

## Architecture

### Services Overview

| Operation | Service | Status |
|-----------|---------|--------|
| Registration & KYC | customer-self-service | ✅ Implemented |
| Account Queries | customer-self-service | ✅ Implemented |
| Deposits & Withdrawals | payment-gateway-service | ✅ Existing |
| Loan Applications | customer-self-service | ⏳ Future |
| Profile Updates | customer-self-service | ⏳ Future |

### API Endpoints

#### Account Query Endpoints (Implemented)

| Endpoint | Method | Description | Ownership Check |
|----------|--------|-------------|-----------------|
| `/api/accounts/savings` | GET | List customer's savings accounts | By JWT client ID |
| `/api/accounts/savings/{id}` | GET | Get specific account details | ✅ Required |
| `/api/accounts/savings/{id}/transactions` | GET | Get account transactions | ✅ Required |

---

## Security Implementation

### Customer Identity Flow

```
JWT Token Claims:
├── fineract_client_id: 42      (numeric - primary lookup)
├── fineract_external_id: uuid  (string - fallback lookup)
├── kyc_tier: 1                 (authorization level)
└── kyc_status: pending         (verification status)
```

### Ownership Verification (Implemented)

**File**: `AccountSecurityService.java`

```java
public Long getCustomerClientId(Jwt jwt) {
    // Primary: Try fineract_client_id claim (fast path)
    Object clientIdClaim = jwt.getClaim("fineract_client_id");
    if (clientIdClaim != null) {
        return ((Number) clientIdClaim).longValue();
    }

    // Fallback: Lookup via fineract_external_id
    String externalId = jwt.getClaimAsString("fineract_external_id");
    Map<String, Object> client = fineractService.getClientByExternalId(externalId);
    return ((Number) client.get("id")).longValue();
}

public void verifySavingsAccountOwnership(Long accountId, Jwt jwt) {
    Long customerClientId = getCustomerClientId(jwt);
    Long accountOwnerClientId = fineractService.getSavingsAccountOwner(accountId);

    if (!accountOwnerClientId.equals(customerClientId)) {
        log.warn("SECURITY: Client {} attempted access to account {} owned by {}",
                customerClientId, accountId, accountOwnerClientId);
        throw new ForbiddenException("Access denied");
    }
}
```

### Registration Flow (Updated)

**File**: `RegistrationService.java`

```java
// Step 1: Create Fineract client
fineractClientId = fineractService.createClient(request, externalId);

// Step 2: Create Keycloak user
keycloakUserId = keycloakService.createUser(request, externalId);

// Step 3: Store fineract_client_id in Keycloak (NEW)
keycloakService.updateUserAttributes(keycloakUserId, Map.of(
    "fineract_client_id", List.of(String.valueOf(fineractClientId))
));
```

---

## Files Modified/Created

### GitOps Repository (fineract-gitops)

| File | Change |
|------|--------|
| `apps/customer-self-service/base/*` | Renamed from customer-registration-service |
| `apps/self-service-app/base/nginx-configmap.yaml` | Added `/api/accounts/` proxy |
| `argocd/applications/dev/customer-self-service.yaml` | Renamed ArgoCD application |
| `operations/keycloak-config/base/config/realm-fineract.yaml` | Added `fineract_client_id` mapper |

### Backend Repository (fineract-apps)

| File | Change |
|------|--------|
| `backend/customer-registration-service/` | |
| ├── `controller/AccountController.java` | **NEW** - Account query endpoints |
| ├── `service/AccountSecurityService.java` | **NEW** - Ownership verification |
| ├── `service/FineractService.java` | Added account query methods |
| ├── `service/RegistrationService.java` | Stores fineract_client_id |
| ├── `config/SecurityConfig.java` | Added /api/accounts/** authorization |
| ├── `dto/SavingsAccountResponse.java` | **NEW** - Response DTO |
| └── `dto/TransactionResponse.java` | **NEW** - Response DTO |

### Frontend Repository (fineract-apps)

| File | Change |
|------|--------|
| `frontend/self-service-app/src/` | |
| ├── `services/api.ts` | Added accounts config |
| ├── `services/accountsApi.ts` | **NEW** - Accounts API client |
| ├── `hooks/useSavingsAccount.ts` | Uses `/api/accounts/savings` |
| ├── `hooks/useTransactions.ts` | Uses `/api/accounts/savings/{id}/transactions` |
| ├── `routes/dashboard.tsx` | Updated hook usage |
| ├── `routes/transactions.tsx` | Updated hook usage |
| └── `routes/account.tsx` | Updated hook usage |

---

## Future Enhancements

### Phase 2: Redis Caching (Recommended)

Add Redis caching for ownership verification to eliminate Fineract API calls after initial warm-up.

```java
@Service
public class AccountOwnershipCache {
    private final RedisTemplate<String, Set<Long>> redis;
    private static final Duration CACHE_TTL = Duration.ofMinutes(10);

    public Set<Long> getCustomerAccountIds(Long clientId, String accountType) {
        String cacheKey = "customer:" + clientId + ":accounts:" + accountType;
        Set<Long> accountIds = redis.opsForSet().members(cacheKey);
        if (accountIds != null && !accountIds.isEmpty()) {
            return accountIds;  // Cache hit
        }
        // Cache miss - fetch from Fineract and cache
        // ...
    }
}
```

### Phase 3: Loan Application Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/loans/products` | GET | List available loan products |
| `/api/loans/apply` | POST | Submit loan application |
| `/api/loans/applications` | GET | List customer's applications |

### Phase 4: Profile Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/profile` | GET | Get full customer profile |
| `/api/profile` | PATCH | Update profile fields |
| `/api/profile/documents` | GET/POST | Manage documents |

### Phase 5: Additional Keycloak Roles

```yaml
- name: self-service-loan-applicant
  description: Can apply for loans (Tier 2 only)

- name: self-service-document-manager
  description: Can upload and manage documents
```

---

## Verification Plan

### Account Query Testing ✅

- [x] Deploy customer-self-service
- [x] Login to self-service app
- [x] Verify balance queries return only customer's accounts
- [x] Verify transaction history displays correctly

### Security Testing

- [ ] Attempt to access another customer's account (should fail with 403)
- [ ] Attempt Tier 2 operation as Tier 1 user (should fail)
- [ ] Test cache invalidation when new account is opened

---

## Git Workflow

**Before committing**:
```bash
git fetch origin
git pull origin self-service
```

**Commit message convention**:
```
feat(scope): short description

- Detailed bullet points
- What changed and why

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```
