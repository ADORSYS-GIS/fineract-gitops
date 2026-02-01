# Add CinetPay Payment Provider for Cameroon

## Overview

Add CinetPay as a payment gateway alongside MTN MoMo and Orange Money for the self-service banking application in Cameroon.

**CinetPay** is a payment aggregator that routes payments to multiple providers (MTN MoMo, Orange Money, bank cards). When a customer pays via CinetPay, they choose the actual payment method (MTN, Orange, etc.) on CinetPay's checkout page. The corresponding GL account (MTN or Orange) should be updated based on the actual method used.

---

## Implementation Status

### Completed ✅

| Task | Status | Commit |
|------|--------|--------|
| Create CinetPayConfig.java | ✅ Done | `d57cd9b` |
| Create CinetPayClient.java | ✅ Done | `d57cd9b` |
| Create CinetPayCallbackRequest.java DTO | ✅ Done | `d57cd9b` |
| Add CINETPAY to PaymentProvider enum | ✅ Done | `d57cd9b` |
| Update PaymentService with CinetPay cases | ✅ Done | `d57cd9b` |
| Update CallbackController with CinetPay endpoints | ✅ Done | `d57cd9b` |
| Update WebClientConfig with cinetpayWebClient | ✅ Done | `d57cd9b` |
| Update application.yml with CinetPay config | ✅ Done | `d57cd9b` |
| Update GitOps configmap.yaml | ✅ Done | `91a582d` |
| Update GitOps deployment.yaml with secrets | ✅ Done | `91a582d` |
| Update secrets template | ✅ Done | `91a582d` |
| Update PAYMENT_GATEWAY_SECRETS.md documentation | ✅ Done | `91a582d` |

### Remaining (Future Phases)

| Task | Status | Priority |
|------|--------|----------|
| Create and seal CinetPay secrets with kubeseal | ⏳ Pending | High |
| Build and deploy updated payment-gateway-service | ⏳ Pending | High |
| Add CinetPay to frontend payment method selection | ⏳ Pending | Medium |
| Unit tests for CinetPayClient | ⏳ Pending | Medium |
| Integration testing with CinetPay sandbox | ⏳ Pending | Medium |

---

### Key Architecture Decision

CinetPay is a **gateway**, not a direct provider:
```
Customer → CinetPay Checkout → [MTN MoMo | Orange Money | Cards]
                                      ↓
                              Callback includes payment_method
                                      ↓
                              Map to corresponding GL account
```

This means:
- **No separate CinetPay GL account** - use existing MTN/Orange GL accounts
- **Dynamic GL mapping** based on `cpm_payment_method` from callback (OM, MOMO, etc.)

---

## CinetPay API Summary

### Payment Collection (Deposits)
- **Endpoint**: `POST https://api-checkout.cinetpay.com/v2/payment`
- **Auth**: API key + site_id in request body
- **Flow**: Returns `payment_url` for customer redirect
- **Callback**: POST to `notify_url` with transaction status

### Money Transfer (Withdrawals)
- **Endpoint**: `POST https://client.cinetpay.com/v1/transfer/money/send/contact`
- **Auth**: Token-based (5 min TTL) via login endpoint
- **Flow**: Direct transfer to mobile wallet

### Key Status Codes
| Code | Meaning |
|------|---------|
| 00 | SUCCESS |
| 201 | CREATED |
| 600 | PAYMENT_FAILED |
| 602 | INSUFFICIENT_BALANCE |

---

## Implementation Plan

### Phase 1: Backend - Payment Gateway Service

**Location**: `/Users/guymoyo/dev/fineract-apps/payment-gateway-service/`

#### 1.1 Create Configuration Class

**File**: `src/main/java/com/adorsys/fineract/payment/config/CinetPayConfig.java`

```java
@Configuration
@ConfigurationProperties(prefix = "payment.cinetpay")
public class CinetPayConfig {
    private String baseUrl = "https://api-checkout.cinetpay.com";
    private String transferUrl = "https://client.cinetpay.com";
    private String apiKey;
    private String siteId;
    private String apiPassword;  // For transfer token auth
    private String currency = "XAF";
    private int timeoutSeconds = 30;
    // Note: No fineractPaymentTypeId or glAccountCode here
    // GL mapping is done dynamically based on payment_method from callback

    // URL construction (uses injected base URLs from infrastructure)
    @Value("${payment.gateway.base-url}")
    private String gatewayBaseUrl;  // ELB URL for payment-gateway-service

    @Value("${self-service.app.base-url}")
    private String selfServiceBaseUrl;  // ELB URL for self-service-app

    public String getCallbackUrl() {
        return gatewayBaseUrl + "/api/callbacks/cinetpay";
    }

    public String getReturnUrl() {
        return selfServiceBaseUrl + "/transactions";
    }

    public String getCancelUrl() {
        return selfServiceBaseUrl + "/transactions";
    }
}
```

#### 1.2 Create Client Class

**File**: `src/main/java/com/adorsys/fineract/payment/client/CinetPayClient.java`

Key methods:
- `initializePayment(transactionId, amount, description, customerPhone)` → Returns payment URL
- `getAuthToken()` → Token for transfer API (cached 4 min)
- `initiateTransfer(transactionId, amount, phone, prefix)` → For withdrawals
- `verifyTransaction(transactionId)` → Check transaction status
- `normalizePhoneNumber(phone)` → Format for Cameroon (+237)

#### 1.3 Create Callback DTO

**File**: `src/main/java/com/adorsys/fineract/payment/dto/CinetPayCallbackRequest.java`

```java
public class CinetPayCallbackRequest {
    private String cpm_site_id;
    private String cpm_trans_id;
    private String cpm_trans_date;
    private String cpm_amount;
    private String cpm_currency;
    private String cpm_payment_method;  // "MOMO", "OM", "FLOOZ", "VISA", etc.
    private String cpm_phone_num;
    private String cpm_error_message;
    private String signature;

    public boolean isSuccessful() { return "00".equals(code); }
    public boolean isFailed() { return "600".equals(code) || "627".equals(code); }

    /**
     * Map CinetPay payment method to our internal provider for GL account lookup.
     * This allows us to use existing MTN/Orange GL accounts.
     */
    public PaymentProvider getActualProvider() {
        return switch (cpm_payment_method) {
            case "MOMO" -> PaymentProvider.MTN_MOMO;      // MTN Mobile Money
            case "OM" -> PaymentProvider.ORANGE_MONEY;   // Orange Money
            // Add more mappings as needed (FLOOZ, VISA, etc.)
            default -> null;  // Unknown - log warning
        };
    }
}
```

#### 1.4 GL Account Mapping Logic

In `PaymentService`, when processing CinetPay callbacks:

```java
// Get the actual payment method from CinetPay callback
PaymentProvider actualProvider = callbackRequest.getActualProvider();

// Use existing GL account mapping
String glAccountCode = switch (actualProvider) {
    case MTN_MOMO -> mtnConfig.getGlAccountCode();
    case ORANGE_MONEY -> orangeConfig.getGlAccountCode();
    default -> throw new PaymentException("Unknown payment method: " + callbackRequest.getCpm_payment_method());
};

int paymentTypeId = switch (actualProvider) {
    case MTN_MOMO -> mtnConfig.getFineractPaymentTypeId();
    case ORANGE_MONEY -> orangeConfig.getFineractPaymentTypeId();
    default -> throw new PaymentException("Unknown payment method");
};

// Create Fineract deposit with correct GL account
fineractClient.createDeposit(accountId, amount, paymentTypeId, glAccountCode, ...);
```

#### 1.5 Update PaymentProvider Enum

**File**: `src/main/java/com/adorsys/fineract/payment/model/PaymentProvider.java`

```java
public enum PaymentProvider {
    MTN_MOMO("mtn_transfer", "MTN Mobile Money"),
    ORANGE_MONEY("orange_transfer", "Orange Money"),
    CINETPAY("cinetpay", "CinetPay (Gateway)"),  // NEW - payment gateway
    // ...
}
```

Note: CINETPAY is a gateway - actual payment flows through MTN/Orange.

#### 1.6 Update PaymentService

**File**: `src/main/java/com/adorsys/fineract/payment/service/PaymentService.java`

Add cases in:
- `initiateDeposit()` switch statement
- `initiateWithdrawal()` switch statement
- Callback handling methods

#### 1.7 Update CallbackController

**File**: `src/main/java/com/adorsys/fineract/payment/controller/CallbackController.java`

Add endpoints:
- `POST /api/callbacks/cinetpay/payment` - Deposit callbacks (PUBLIC - called by CinetPay)
- `POST /api/callbacks/cinetpay/transfer` - Withdrawal callbacks (PUBLIC - called by CinetPay)

#### 1.8 Security Configuration

**Endpoint Security Summary**:

| Endpoint | Auth Required | Notes |
|----------|---------------|-------|
| `POST /api/payments/deposit` | ✅ JWT | Customer initiates deposit |
| `POST /api/payments/withdraw` | ✅ JWT | Customer initiates withdrawal |
| `POST /api/callbacks/cinetpay/*` | ❌ Public | CinetPay server callbacks |

**File**: `src/main/java/com/adorsys/fineract/payment/config/SecurityConfig.java`

Add to security filter chain:
```java
// CinetPay callbacks - public (validated by signature)
.requestMatchers("/api/callbacks/cinetpay/**").permitAll()
```

**Callback Signature Validation** (in CinetPayClient):
```java
public boolean validateCallbackSignature(CinetPayCallbackRequest callback) {
    // CinetPay signs callbacks - verify signature using API key
    String expectedSignature = generateHmacSha256(
        callback.getCpm_trans_id() + callback.getCpm_amount(),
        apiKey
    );
    return expectedSignature.equals(callback.getSignature());
}
```

**Important**: Even though callback endpoints are public, they must:
1. Validate signature from CinetPay
2. Verify site_id matches our configured site_id
3. Check transaction exists in our database before processing

#### 1.9 Update WebClientConfig

**File**: `src/main/java/com/adorsys/fineract/payment/config/WebClientConfig.java`

Add:
```java
@Bean("cinetpayWebClient")
public WebClient cinetpayWebClient() {
    return WebClient.builder()
        .baseUrl(cinetPayConfig.getBaseUrl())
        .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
        .build();
}
```

#### 1.10 Update application.yml

**File**: `src/main/resources/application.yml`

```yaml
payment:
  cinetpay:
    base-url: ${CINETPAY_BASE_URL:https://api-checkout.cinetpay.com}
    transfer-url: ${CINETPAY_TRANSFER_URL:https://client.cinetpay.com}
    api-key: ${CINETPAY_API_KEY}
    site-id: ${CINETPAY_SITE_ID}
    api-password: ${CINETPAY_API_PASSWORD}
    currency: XAF
    timeout-seconds: 30
    # URLs constructed dynamically using ELB base URL (same pattern as MTN/Orange)
    # callback-url: ${PAYMENT_GATEWAY_BASE_URL}/api/callbacks/cinetpay
    # return-url: ${SELF_SERVICE_APP_BASE_URL}/transactions
    # cancel-url: ${SELF_SERVICE_APP_BASE_URL}/transactions
    # Note: No fineract-payment-type-id or gl-account-code
    # GL mapping is dynamic based on cpm_payment_method from callback
```

---

### Phase 2: GitOps Configuration

**Location**: `/Users/guymoyo/dev/fineract-gitops/`

#### 2.1 Update ConfigMap

**File**: `apps/payment-gateway-service/base/configmap.yaml`

Add:
```yaml
# CinetPay Configuration (Gateway - GL mapping is dynamic)
CINETPAY_BASE_URL: "https://api-checkout.cinetpay.com"
CINETPAY_TRANSFER_URL: "https://client.cinetpay.com"
# Note: Callback/Return/Cancel URLs use dynamic base from infrastructure
# No CINETPAY_FINERACT_PAYMENT_TYPE_ID - uses MTN/Orange payment types based on actual method
```

**Note**: Callback, return, and cancel URLs are constructed dynamically using the ELB base URL (same pattern as MTN/Orange).

#### 2.2 Update Secrets Template (Sealed Secrets)

**File**: `secrets/dev/payment-gateway-secrets.yaml.template`

Add:
```yaml
# CinetPay Credentials (will be sealed with kubeseal)
# Obtain from: https://my.cinetpay.com (merchant dashboard)
cinetpay-api-key: "CHANGE_ME"
cinetpay-site-id: "CHANGE_ME"
cinetpay-api-password: "CHANGE_ME"
```

**Note**: No separate GL account for CinetPay - uses existing MTN/Orange GL accounts based on actual payment method.

**Seal the secret** (same pattern as MTN/Orange):
```bash
kubeseal --format=yaml --cert=sealed-secrets-cert.pem \
  < payment-gateway-secrets.yaml \
  > payment-gateway-secrets-sealed.yaml
```

#### 2.3 Update Deployment

**File**: `apps/payment-gateway-service/base/deployment.yaml`

Add environment variables (secrets from sealed secret):
```yaml
- name: CINETPAY_API_KEY
  valueFrom:
    secretKeyRef:
      name: payment-gateway-secrets
      key: cinetpay-api-key
- name: CINETPAY_SITE_ID
  valueFrom:
    secretKeyRef:
      name: payment-gateway-secrets
      key: cinetpay-site-id
- name: CINETPAY_API_PASSWORD
  valueFrom:
    secretKeyRef:
      name: payment-gateway-secrets
      key: cinetpay-api-password
```

**Note**: GL accounts are mapped dynamically from existing MTN/Orange configs based on callback `payment_method`.

#### 2.4 Update Secrets Documentation

**File**: `docs/PAYMENT_GATEWAY_SECRETS.md`

Add CinetPay section with:
- How to obtain credentials from CinetPay merchant dashboard
- Required credentials list
- Sealed secret creation commands

---

### Phase 3: Frontend Integration

**Location**: `/Users/guymoyo/dev/fineract-apps/frontend/self-service-app/`

#### 3.1 Update Payment Provider Types

**File**: `src/types/payment.ts` (or similar)

Add CinetPay to provider enum/types.

#### 3.2 Update Payment Method Selection UI

Add CinetPay option to deposit/withdrawal forms with appropriate icon and label.

---

### Phase 4: Fineract Configuration

**No separate CinetPay payment type needed.**

Since CinetPay is a gateway that routes to MTN MoMo or Orange Money:
- Use existing **MTN MoMo payment type** for MOMO payments
- Use existing **Orange Money payment type** for OM payments

This ensures:
- GL accounts correctly reflect the actual payment method
- Fineract reports accurately show MTN vs Orange transactions
- Accounting reconciliation matches mobile money provider statements

---

## Files to Create/Modify Summary

### Backend (payment-gateway-service) ✅ Complete

| File | Action | Status |
|------|--------|--------|
| `config/CinetPayConfig.java` | CREATE | ✅ Done |
| `client/CinetPayClient.java` | CREATE | ✅ Done |
| `dto/CinetPayCallbackRequest.java` | CREATE | ✅ Done |
| `dto/PaymentProvider.java` | MODIFY - add CINETPAY | ✅ Done |
| `service/PaymentService.java` | MODIFY - add cases | ✅ Done |
| `controller/CallbackController.java` | MODIFY - add endpoints | ✅ Done |
| `config/WebClientConfig.java` | MODIFY - add bean | ✅ Done |
| `application.yml` | MODIFY - add config | ✅ Done |

### GitOps (fineract-gitops) ✅ Complete

| File | Action | Status |
|------|--------|--------|
| `apps/payment-gateway-service/base/configmap.yaml` | MODIFY | ✅ Done |
| `apps/payment-gateway-service/base/deployment.yaml` | MODIFY | ✅ Done |
| `secrets/dev/payment-gateway-secrets.yaml.template` | MODIFY | ✅ Done |
| `docs/PAYMENT_GATEWAY_SECRETS.md` | MODIFY | ✅ Done |

### Frontend (self-service-app) ⏳ Pending

| File | Action | Status |
|------|--------|--------|
| Payment types/constants | MODIFY | ⏳ Pending |
| Payment method selection UI | MODIFY | ⏳ Pending |

---

## Verification Plan

1. **Unit Tests**
   - Test CinetPayClient with mock responses
   - Test callback DTO parsing
   - Test phone number normalization

2. **Integration Testing**
   - Use CinetPay sandbox environment
   - Test deposit flow end-to-end
   - Test withdrawal flow end-to-end
   - Verify Fineract transaction creation

3. **Callback Testing**
   - Use ngrok or similar to test callbacks locally
   - Verify status transitions (PENDING → SUCCESS/FAILED)

4. **Security Testing**
   - Verify callback signature validation
   - Test with invalid credentials
   - Test rate limiting

---

## Git Workflow

```bash
# Before starting
git fetch origin
git pull origin self-service

# Commit strategy
feat(payment): add CinetPay configuration classes
feat(payment): implement CinetPay client for deposits
feat(payment): implement CinetPay transfer for withdrawals
feat(payment): add CinetPay callback handling
feat(gitops): add CinetPay configuration and secrets
feat(frontend): add CinetPay payment method option
```

---

## References

- [CinetPay Documentation](https://docs.cinetpay.com/)
- [Payment Initialization](https://docs.cinetpay.com/api/1.0-en/checkout/initialisation)
- [Transfer API](https://docs.cinetpay.com/api/1.0-en/transfert/utilisation)
- [Status Codes](https://docs.cinetpay.com/api/1.0-en/checkout/tableau)
