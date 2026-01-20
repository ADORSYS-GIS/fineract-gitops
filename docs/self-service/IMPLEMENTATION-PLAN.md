# Self-Service Banking Application - Implementation Plan

## Overview

Build a customer-facing self-service application enabling user self-registration with passwordless authentication (WebAuthn), and deposit/withdrawal operations via multiple payment methods (MTN Transfer, Orange Transfer, UBA, Afriland).

---

## Implementation Progress

| Phase | Description | Status | Commit |
|-------|-------------|--------|--------|
| **Phase 1** | Keycloak & GL Configuration | ✅ Complete | `64eb9e0` |
| **Phase 2** | Customer Registration Service | ✅ Complete | `b10d99a` |
| **Phase 3** | Self-Service Frontend App | ✅ Complete | `4da00ca` |
| **Phase 4** | Documentation | 🔄 In Progress | - |
| **Phase 5** | Payment Gateway Service | ⏳ Pending | - |
| **Phase 6** | Security & Testing | ⏳ Pending | - |
| **Phase 7** | Staff KYC Review Interface | ⏳ Pending | - |

### Phase 1 Details (Complete)
- ✅ Self-service roles added: `self-service-customer`, `self-service-deposit`, `self-service-withdrawal`
- ✅ Self-service group added: `/self-service-customers`
- ✅ Self-service client added: `self-service-app` (public, PKCE)
- ✅ WebAuthn passwordless flow: `self-service-browser`
- ✅ GL accounts added: UBA (45), Afriland (46)
- ✅ Payment types added: MTN Transfer, Orange Transfer, UBA Bank Transfer, Afriland Bank Transfer

### Phase 2 Details (Complete)
- ✅ `apps/customer-registration-service/base/` created
- ✅ Deployment with Java Spring Boot configuration
- ✅ Transaction limits ConfigMap (Tier 1/Tier 2)
- ✅ ArgoCD application added

### Phase 3 Details (Complete)
- ✅ `apps/self-service-app/base/` created (GitOps manifests)
- ✅ OIDC ConfigMap with Keycloak settings
- ✅ NGINX ConfigMap with API proxies
- ✅ Public Ingress (no OAuth2-Proxy) at `/self-service/*`
- ✅ ArgoCD application added
- ✅ React app scaffolding in `fineract-apps` repo (branch: `self-service`)

---

## Current State Analysis

### Existing Architecture
- **7 frontend apps**: web-app, admin-app, account-manager-app, cashier-app, branch-manager-app, reporting-app, accounting-app
- **No self-service customer app** currently exists
- **Single Keycloak realm** `fineract` with self-registration **disabled**
- **WebAuthn** configured as optional 2FA, not passwordless
- **GL accounts** configured via YAML (fineract-config-cli)
- **OAuth2-Proxy pattern** protects all frontend apps

### Existing GL Accounts (from demo-config-fixed.yml)
- GL 43: MTN Mobile Money (Asset)
- GL 44: Orange Money (Asset)
- GL 41: Banks - Current Accounts (Asset)

---

## Architectural Decisions

### 1. Custom Self-Service Frontend vs Fineract Built-in

**Recommendation: Custom frontend application**

| Option | Pros | Cons |
|--------|------|------|
| Fineract Built-in | Less dev effort | Limited customization, no WebAuthn, tied to releases |
| **Custom Frontend** | Full UX control, WebAuthn native, payment integration | More dev effort |

### 2. Single Realm vs Dual Realm

**Recommendation: Single realm with group-based isolation**

| Option | Pros | Cons |
|--------|------|------|
| **Single Realm** | Simpler management, extend existing config, shared auth flows | Need careful RBAC |
| Dual Realm | Complete isolation | Duplicate config, complex user-sync |

The existing `fineract` realm already has a `client` role and `/clients` group that can be extended.

### 3. Registration Flow

**Recommendation: Orchestrated registration via new service**

Registration creates users in **both** Keycloak and Fineract with proper linking via `fineract_client_id` attribute.

---

## Implementation Plan

### Phase 1: Foundation - Keycloak & GL Configuration

**1.1 Extend Keycloak Realm** (`operations/keycloak-config/base/config/realm-fineract.yaml`)

Add new roles:
```yaml
- name: self-service-customer
- name: self-service-deposit
- name: self-service-withdrawal
```

Add new group:
```yaml
- name: self-service-customers
  path: /self-service-customers
  realmRoles: [self-service-customer, self-service-deposit, self-service-withdrawal]
```

Add new client:
```yaml
- clientId: "self-service-app"
  publicClient: true  # PKCE-enabled
  standardFlowEnabled: true
  attributes:
    pkce.code.challenge.method: "S256"
```

**1.2 Configure WebAuthn Passwordless Flow**

Create custom authentication flow:
```
self-service-browser:
  1. Cookie (ALTERNATIVE)
  2. Username Form (REQUIRED)
  3. WebAuthn Passwordless (REQUIRED)
```

Bind flow to `self-service-app` client.

**1.3 Add/Confirm GL Accounts for Payment Methods**

Existing accounts (already in demo-config-fixed.yml):
```yaml
chartOfAccounts:
  - name: MTN Mobile Money
    glCode: "43"
    accountType: Asset

  - name: Orange Money
    glCode: "44"
    accountType: Asset
```

New accounts to add in `operations/fineract-config/base/config/`:
```yaml
chartOfAccounts:
  - name: UBA Bank Account
    glCode: "45"
    accountType: Asset

  - name: Afriland Bank Account
    glCode: "46"
    accountType: Asset
```

**1.4 Add Payment Types**

```yaml
paymentTypes:
  - name: MTN Transfer
    description: MTN Mobile Money (self-service)
    isCashPayment: false

  - name: Orange Transfer
    description: Orange Money (self-service)
    isCashPayment: false

  - name: UBA Bank Transfer
    description: UBA bank transfer (self-service)
    isCashPayment: false

  - name: Afriland Bank Transfer
    description: Afriland bank transfer (self-service)
    isCashPayment: false
```

---

### Phase 2: Customer Registration Service (Java Spring)

**New service**: `apps/customer-registration-service/`

**Tech Stack**: Java 21 + Spring Boot 3.x

**Purpose**: Orchestrate registration across Fineract and Keycloak

**Registration Flow**:
1. Validate registration data (name, email, phone, national ID)
2. Create Fineract client via API → get `clientId`
3. Create default savings account for client (status: pending activation)
4. Create Keycloak user with attributes:
   - `fineract_client_id`: links to Fineract client
   - `kyc_tier`: "1" (unverified)
   - `kyc_status`: "pending"
5. Assign to `/self-service-customers` group
6. Set required actions: `VERIFY_EMAIL`, `webauthn-register-passwordless`
7. Handle rollback if any step fails

**KYC Document Upload Flow** (in self-service app):
1. Customer uploads documents (ID, proof of address, selfie)
2. Documents stored via Fineract Document API → S3
3. Create KYC verification request in Fineract
4. Notify staff via dashboard/email
5. Staff reviews and approves/rejects
6. On approval: Update Keycloak `kyc_tier` to "2", activate full limits

**Files to create**:
```
apps/customer-registration-service/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/{dev,uat,production}/
```

---

### Phase 3: Self-Service Frontend App (React)

**Source Code Location**: `/Users/guymoyo/dev/fineract-apps/frontend/`
- Create new React app in this directory alongside existing Angular apps
- Build artifacts deployed to: `apps/self-service-app/` (this GitOps repo)

**Tech Stack**: React (for future React Native mobile app conversion)

**Features**:
- Registration form (redirects to registration service)
- WebAuthn passwordless login
- Account dashboard (view balances, transactions, KYC status)
- KYC document upload (ID, proof of address, selfie with camera capture)
- KYC status tracking (pending → under review → approved/rejected)
- Deposit flow (select payment method → initiate payment)
- Withdrawal flow (select method → enter details → confirm with WebAuthn)
- Transaction limits display (based on KYC tier)

**Security**: Direct OIDC with PKCE (different from staff apps)
- Self-service app does NOT use OAuth2-Proxy (staff apps do)
- React app handles OIDC directly with Keycloak using `oidc-client-ts`
- Uses the `self-service-app` Keycloak client (public client with PKCE)
- WebAuthn passwordless via Keycloak's custom authentication flow
- JWT tokens stored in browser, passed to backend in Authorization header

**Files to create**:
```
apps/self-service-app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── nginx-configmap.yaml
└── overlays/{dev,uat,production}/
```

**Ingress route**: `/self-service/*` (OAuth2-protected)

---

### Phase 4: Payment Gateway Service (MVP - Mobile Money) - Java Spring

**New service**: `apps/payment-gateway-service/`

**Tech Stack**: Java 21 + Spring Boot 3.x

**MVP Integrations** (APIs available):
| Provider | API | Use Case |
|----------|-----|----------|
| MTN MoMo | MTN Mobile Money API | Deposits/Withdrawals |
| Orange Money | Orange Money API | Deposits/Withdrawals |

**Future Phase** (APIs to be established):
| Provider | API | Use Case |
|----------|-----|----------|
| UBA | Bank transfer API | Withdrawals (Tier 2 only) |
| Afriland | Bank transfer API | Withdrawals (Tier 2 only) |

**Flow for Deposits**:
1. Customer selects payment method + amount
2. Payment gateway generates provider-specific request
3. Customer approves on phone/bank app
4. Callback received → create Fineract transaction
5. Journal entry created automatically (Debit GL 43-46, Credit savings)

**Flow for Withdrawals**:
1. Customer selects method + amount + destination
2. WebAuthn re-authentication (step-up)
3. Create Fineract withdrawal transaction
4. Payment gateway initiates transfer
5. Notify customer of status

---

### Phase 5: Security & Testing

**Security Controls**:
- Client isolation via `fineract_client_id` in JWT
- Transaction limits (daily/per-transaction)
- WebAuthn required for registration
- Step-up auth for withdrawals
- Rate limiting via Ingress
- Network policies for service isolation

**Network Policy** (`apps/network-policies/self-service-network-policy.yaml`):
- Ingress: Only from NGINX Ingress
- Egress: Only to Fineract, Keycloak, DNS

---

### Phase 6: Staff KYC Review Interface (Account Manager App)

**Source Code Location**: `/Users/guymoyo/dev/fineract-apps/frontend/`
- Modify existing Account Manager app in this repository
- Build artifacts deployed via: `apps/account-manager-app/` (this GitOps repo)

**KYC Review Features to Add**:
- List pending KYC verification requests
- View uploaded documents (ID, proof of address, selfie)
- Approve/Reject with comments
- On approval:
  1. Update Fineract client status → Active
  2. Update Keycloak user attribute `kyc_tier` → "2"
  3. Send notification to customer (email/SMS)

---

### Phase 7: Documentation & Branch Strategy

**Branch**: All implementation work on `self-service` branch

**Documentation to create** (committed to repo):
```
docs/self-service/
├── README.md                     # Overview and getting started
├── architecture.md               # System architecture diagrams
├── registration-flow.md          # User registration flow details
├── authentication-flow.md        # WebAuthn passwordless flow
├── payment-integration.md        # MTN/Orange API integration
├── kyc-workflow.md               # KYC document upload and review
├── transaction-limits.md         # Tier-based limits configuration
├── deployment-guide.md           # Kubernetes deployment steps
└── troubleshooting.md            # Common issues and solutions
```

**Git Workflow**:
```bash
# Create branch
git checkout -b self-service

# Work on phases, commit incrementally
git commit -m "feat(keycloak): add self-service roles and client"
git commit -m "feat(fineract): add UBA/Afriland GL accounts"
git commit -m "feat(apps): add customer-registration-service"
...

# Merge to main when complete
git checkout main
git merge self-service
```

---

## Files to Modify

### In fineract-gitops repo (`/Users/guymoyo/dev/fineract-gitops/`)

| File | Changes |
|------|---------|
| `operations/keycloak-config/base/config/realm-fineract.yaml` | Add roles, group, client, auth flow |
| `operations/fineract-config/base/config/demo-config-fixed.yml` | Add GL 45-46, payment types |
| `apps/ingress/base/fineract-web-app-protected.yaml` | Add `/self-service/*` route |

### In fineract-apps repo (`/Users/guymoyo/dev/fineract-apps/frontend/`)

| Directory | Changes |
|-----------|---------|
| `account-manager-app/` | Add KYC review screens for staff |
| (new) `self-service-app/` | Create new React app for customers |

## New Files to Create

| Directory | Purpose |
|-----------|---------|
| `apps/self-service-app/` | Customer frontend |
| `apps/customer-registration-service/` | Registration orchestrator |
| `apps/payment-gateway-service/` | Payment processing |
| `apps/network-policies/self-service-network-policy.yaml` | Security isolation |
| `argocd/applications/dev/self-service-app.yaml` | ArgoCD app |
| `argocd/applications/dev/customer-registration-service.yaml` | ArgoCD app |
| `argocd/applications/dev/payment-gateway-service.yaml` | ArgoCD app |
| `secrets/dev/payment-gateway-secrets-sealed.yaml` | API credentials |

---

## Transaction Flow Diagrams

### Deposit (MTN Transfer)
```
Customer → Self-Service App → Payment Gateway → MTN MoMo API
                                    ↓ (callback)
                              Fineract Transaction API
                                    ↓
                              Journal Entry:
                              DR: GL 43 (MTN MoMo)
                              CR: GL 61 (Savings)
```

### Withdrawal (UBA Bank)
```
Customer → Self-Service App → WebAuthn Re-auth → Fineract Transaction API
                                                        ↓
                                                  Journal Entry:
                                                  DR: GL 61 (Savings)
                                                  CR: GL 45 (UBA)
                                                        ↓
                                                  Payment Gateway → UBA API
```

---

## Verification Plan

1. **Registration**: Register new customer → verify Fineract client + Keycloak user created
2. **WebAuthn Login**: Login with registered device → verify JWT contains `fineract_client_id`
3. **Deposit**: Initiate MTN deposit → verify transaction + journal entry created
4. **Withdrawal**: Initiate UBA withdrawal → verify step-up auth + transaction created
5. **Isolation**: Verify customer cannot access other customers' accounts
6. **Limits**: Test transaction limits are enforced

---

## Confirmed Requirements

| Decision | Choice |
|----------|--------|
| **KYC Model** | Tiered access - immediate low limits, full access after staff KYC approval |
| **KYC Review** | Staff reviews/approves via Account Manager app |
| **Document Upload** | Required for KYC verification |
| **Payment APIs** | MTN & Orange APIs available; UBA & Afriland need to be established |
| **Frontend Stack** | **React** (for easy conversion to React Native mobile app) |
| **Branch** | All changes committed to `self-service` branch |

---

## Tiered Access Model

### Tier 1: Unverified (Immediate after registration)
- Daily deposit limit: 50,000 XAF
- Daily withdrawal limit: 25,000 XAF
- Per-transaction limit: 25,000 XAF
- Features: Basic deposits/withdrawals

### Tier 2: Verified (After KYC approval)
- Daily deposit limit: 500,000 XAF
- Daily withdrawal limit: 250,000 XAF
- Per-transaction limit: 100,000 XAF
- Features: Full access, bank transfers enabled

### KYC Document Requirements
- National ID (front + back)
- Proof of address (utility bill, less than 3 months)
- Selfie with ID

### KYC Workflow
```
1. Customer registers → Tier 1 access granted
2. Customer uploads KYC documents via self-service app
3. Documents stored in S3 (existing Fineract document storage)
4. Staff reviews in Admin/Account Manager app
5. Staff approves → Customer upgraded to Tier 2
6. Customer notified via email/SMS
```

---

## Payment Integration Strategy

| Provider | Status | Integration Approach |
|----------|--------|---------------------|
| MTN MoMo | API Available | Integrate in Phase 4 |
| Orange Money | API Available | Integrate in Phase 4 |
| UBA | Need to Establish | Phase 5 or future phase |
| Afriland | Need to Establish | Phase 5 or future phase |

**MVP Scope**: Launch with MTN + Orange (mobile money) first, add bank transfers later.

---

## Technical Clarifications

### Client ID: UUID vs Numeric

**Fineract Limitation**: Fineract uses auto-increment numeric IDs for clients (1, 2, 3...).

**Workaround Options**:

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| **Use `externalId`** (Recommended) | Store UUID in `externalId` field, use for external references | No Fineract modification needed | Two IDs to manage |
| Fineract Fork | Modify Fineract to use UUID primary keys | Clean solution | Maintenance burden, upgrade complexity |
| Mapping Table | Maintain UUID→clientId mapping in registration service | External consistency | Extra DB table |

**Recommendation**: Use Fineract's `externalId` field to store a UUID. The registration service generates a UUID and passes it as `externalId` when creating the client. All external systems (Keycloak, payment gateway) reference clients by this UUID.

```yaml
# Registration creates client with:
{
  "firstname": "John",
  "lastname": "Doe",
  "externalId": "550e8400-e29b-41d4-a716-446655440000",  # UUID
  "officeId": 1,
  ...
}
```

Keycloak user attribute stores `external_id` (UUID), not `client_id` (numeric).

**Who Creates the UUID and When**:

```
Component: customer-registration-service
When: During registration, BEFORE calling Fineract API

Flow:
┌──────────────────────────────────────────────────────────────────────────┐
│ 1. User submits registration form                                        │
│    └── POST /api/register {firstName, lastName, email, phone, ...}       │
│                                                                          │
│ 2. customer-registration-service receives request                        │
│    └── Generates UUID: external_id = uuid.uuid4()                        │
│    └── Example: "550e8400-e29b-41d4-a716-446655440000"                    │
│                                                                          │
│ 3. Create Fineract Client with externalId                                │
│    └── POST /fineract-provider/api/v1/clients                            │
│        {                                                                 │
│          "firstname": "John",                                            │
│          "lastname": "Doe",                                              │
│          "externalId": "550e8400-e29b-41d4-a716-446655440000",           │
│          "officeId": 1,                                                  │
│          "active": false  // Pending KYC                                 │
│        }                                                                 │
│    └── Response: { "clientId": 12345, "resourceId": 12345 }              │
│                                                                          │
│ 4. Create Keycloak User with external_id attribute                       │
│    └── POST /admin/realms/fineract/users                                 │
│        {                                                                 │
│          "username": "john.doe@email.com",                               │
│          "email": "john.doe@email.com",                                  │
│          "attributes": {                                                 │
│            "fineract_external_id": ["550e8400-e29b-41d4-a716-..."],      │
│            "kyc_tier": ["1"],                                            │
│            "kyc_status": ["pending"]                                     │
│          },                                                              │
│          "groups": ["/self-service-customers"],                          │
│          "requiredActions": ["VERIFY_EMAIL", "webauthn-register-..."]    │
│        }                                                                 │
│                                                                          │
│ 5. UUID is now the link between systems                                  │
│    └── Keycloak knows: fineract_external_id = UUID                       │
│    └── Fineract knows: externalId = UUID                                 │
│    └── All APIs use UUID to identify customer                            │
└──────────────────────────────────────────────────────────────────────────┘
```

**Code Example** (customer-registration-service - Java Spring):

```java
// RegistrationService.java
@Service
@Slf4j
public class RegistrationService {

    private final FineractClient fineractClient;
    private final KeycloakAdminClient keycloakClient;

    public RegistrationResponse registerCustomer(RegistrationRequest request) {
        // Generate UUID here - this is the single source of truth
        String externalId = UUID.randomUUID().toString();

        // Step 1: Create Fineract client
        FineractClientRequest fineractRequest = FineractClientRequest.builder()
            .firstname(request.getFirstName())
            .lastname(request.getLastName())
            .externalId(externalId)  // UUID passed here
            .mobileNo(request.getPhone())
            .officeId(defaultOfficeId)
            .active(false)  // Will be activated after KYC
            .legalFormId(1)  // Person
            .build();

        FineractClientResponse fineractResponse = fineractClient.createClient(fineractRequest);
        log.info("Created Fineract client with ID: {}", fineractResponse.getClientId());

        // Step 2: Create Keycloak user
        try {
            KeycloakUserRequest keycloakRequest = KeycloakUserRequest.builder()
                .username(request.getEmail())
                .email(request.getEmail())
                .firstName(request.getFirstName())
                .lastName(request.getLastName())
                .enabled(true)
                .attributes(Map.of(
                    "fineract_external_id", List.of(externalId),  // Same UUID
                    "kyc_tier", List.of("1"),
                    "kyc_status", List.of("pending")
                ))
                .groups(List.of("/self-service-customers"))
                .requiredActions(List.of("VERIFY_EMAIL", "webauthn-register-passwordless"))
                .build();

            keycloakClient.createUser(keycloakRequest);
        } catch (Exception e) {
            // ROLLBACK: Delete Fineract client
            log.error("Failed to create Keycloak user, rolling back Fineract client", e);
            fineractClient.deleteClient(fineractResponse.getClientId());
            throw new RegistrationException("Failed to complete registration", e);
        }

        return new RegistrationResponse(externalId, "pending_verification");
    }
}
```

---

### Passwordless Login Flow (Self-Service vs Staff Apps)

**Key Difference**: Self-service app uses a **custom authentication flow** bound to its Keycloak client, while staff apps use the default browser flow with password.

**Staff Apps Flow** (current - web-app, admin-app, etc.):
```
┌─────────────────────────────────────────────────────────────────────────┐
│ STAFF LOGIN FLOW (Standard OAuth2-Proxy + Password)                      │
│                                                                          │
│ 1. User visits https://apps.domain.com/administration                    │
│                                                                          │
│ 2. NGINX checks auth via OAuth2-Proxy                                    │
│    └── auth_request /oauth2/auth                                         │
│    └── No valid session → redirect to OAuth2-Proxy                       │
│                                                                          │
│ 3. OAuth2-Proxy redirects to Keycloak                                    │
│    └── /realms/fineract/protocol/openid-connect/auth                     │
│    └── client_id=oauth2-proxy (uses DEFAULT browser flow)                │
│                                                                          │
│ 4. Keycloak shows LOGIN PAGE (password-based)                            │
│    ┌────────────────────────────────────────┐                            │
│    │ Username: [_______________]            │                            │
│    │ Password: [_______________]            │                            │
│    │ [Sign In]                              │                            │
│    └────────────────────────────────────────┘                            │
│                                                                          │
│ 5. User enters username + password → Keycloak validates                  │
│                                                                          │
│ 6. Keycloak issues tokens → OAuth2-Proxy sets session cookie             │
│                                                                          │
│ 7. User redirected to /administration with valid session                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**Self-Service App Flow** (new - passwordless with WebAuthn):
```
┌─────────────────────────────────────────────────────────────────────────┐
│ SELF-SERVICE LOGIN FLOW (OAuth2-Proxy + WebAuthn Passwordless)           │
│                                                                          │
│ 1. User visits https://apps.domain.com/self-service                      │
│                                                                          │
│ 2. NGINX checks auth via OAuth2-Proxy                                    │
│    └── auth_request /oauth2/auth                                         │
│    └── No valid session → redirect to OAuth2-Proxy                       │
│                                                                          │
│ 3. OAuth2-Proxy redirects to Keycloak                                    │
│    └── /realms/fineract/protocol/openid-connect/auth                     │
│    └── client_id=self-service-app (uses CUSTOM browser flow)             │
│                                                                          │
│ 4. Keycloak detects client_id=self-service-app                           │
│    └── Client has authenticationFlowBindingOverrides:                    │
│        browser: "self-service-browser" (custom flow)                     │
│                                                                          │
│ 5. Keycloak executes CUSTOM flow "self-service-browser":                 │
│                                                                          │
│    Step 5a: Username Form (no password field)                            │
│    ┌────────────────────────────────────────┐                            │
│    │ Email: [john.doe@email.com____]        │                            │
│    │ [Continue]                             │                            │
│    └────────────────────────────────────────┘                            │
│                                                                          │
│    Step 5b: WebAuthn Passwordless Challenge                              │
│    ┌────────────────────────────────────────┐                            │
│    │ 🔐 Use Face ID / Touch ID to sign in   │                            │
│    │                                        │                            │
│    │ [Touch sensor or look at camera...]    │                            │
│    └────────────────────────────────────────┘                            │
│    └── Browser calls navigator.credentials.get()                         │
│    └── User authenticates with biometric/security key                    │
│    └── Authenticator returns signed assertion                            │
│    └── Keycloak validates WebAuthn response                              │
│                                                                          │
│ 6. Keycloak issues tokens → OAuth2-Proxy sets session cookie             │
│    └── JWT contains: fineract_external_id, kyc_tier, roles               │
│                                                                          │
│ 7. User redirected to /self-service with valid session                   │
└─────────────────────────────────────────────────────────────────────────┘
```

**Keycloak Configuration for Custom Flow**:

```yaml
# In realm-fineract.yaml

# Define custom authentication flow
authenticationFlows:
  - alias: self-service-browser
    description: Passwordless browser flow for self-service customers
    providerId: basic-flow
    topLevel: true
    builtIn: false
    authenticationExecutions:
      # Check if user has existing session
      - authenticator: auth-cookie
        requirement: ALTERNATIVE
        priority: 10
      # Username + WebAuthn sub-flow
      - flowAlias: self-service-passwordless-forms
        requirement: ALTERNATIVE
        priority: 20
        autheticatorFlow: true

  - alias: self-service-passwordless-forms
    description: Username + WebAuthn passwordless
    providerId: basic-flow
    topLevel: false
    builtIn: false
    authenticationExecutions:
      # Username input (no password)
      - authenticator: auth-username-form
        requirement: REQUIRED
        priority: 10
      # WebAuthn passwordless (instead of password)
      - authenticator: webauthn-authenticator-passwordless
        requirement: REQUIRED
        priority: 20

# Bind custom flow to self-service-app client
clients:
  - clientId: self-service-app
    # ... other config ...
    authenticationFlowBindingOverrides:
      browser: self-service-browser  # <-- This is the key!
```

**Architecture Options for Different Auth Flows**:

The current OAuth2-Proxy is configured with a SINGLE client_id (`oauth2-proxy`). To use a different client with passwordless, we have two options:

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| **Option A: Separate OAuth2-Proxy** | Deploy second OAuth2-Proxy for self-service | Isolated config | More resources |
| **Option B: Direct OIDC in React** | React app handles OIDC directly with PKCE | No extra proxy, native WebAuthn | More frontend logic |

**Recommendation: Option B - Direct OIDC in React App**

Since self-service is a React SPA, it can handle OIDC authentication directly using:
- `react-oidc-context` or `oidc-client-ts` library
- PKCE flow (public client, no client secret)
- Native WebAuthn integration

```
┌─────────────────────────────────────────────────────────────────────────┐
│ SELF-SERVICE ARCHITECTURE (Direct OIDC - No OAuth2-Proxy)               │
│                                                                          │
│                     ┌───────────────────┐                                │
│                     │   NGINX Ingress   │                                │
│                     └───────────────────┘                                │
│                              │                                           │
│              ┌───────────────┼───────────────┐                           │
│              │               │               │                           │
│              ▼               ▼               ▼                           │
│     ┌────────────────┐ ┌──────────┐ ┌──────────────────┐                │
│     │ Staff Apps     │ │ Keycloak │ │ Self-Service App │                │
│     │ (web-app, etc) │ │          │ │ (React SPA)      │                │
│     └────────────────┘ └──────────┘ └──────────────────┘                │
│              │               ▲               │                           │
│              │               │               │                           │
│              ▼               │               │                           │
│     ┌────────────────┐       │               │                           │
│     │ OAuth2-Proxy   │───────┘               │                           │
│     │ (oauth2-proxy  │                       │                           │
│     │  client)       │                       │                           │
│     └────────────────┘                       │                           │
│                                              │                           │
│              Direct OIDC with PKCE ──────────┘                           │
│              (self-service-app client)                                   │
│                                                                          │
│ Staff Apps: NGINX → OAuth2-Proxy → Keycloak (password flow)             │
│ Self-Service: React App → Keycloak directly (WebAuthn passwordless)     │
└─────────────────────────────────────────────────────────────────────────┘
```

**React App OIDC Configuration**:

```typescript
// src/config/auth.ts
import { AuthProvider } from 'react-oidc-context';

const oidcConfig = {
  authority: 'https://auth.domain.com/realms/fineract',
  client_id: 'self-service-app',  // Separate client with WebAuthn flow
  redirect_uri: 'https://apps.domain.com/self-service/callback',
  post_logout_redirect_uri: 'https://apps.domain.com/self-service',
  scope: 'openid profile email offline_access',
  // PKCE is automatic with oidc-client-ts
};

// App.tsx
<AuthProvider {...oidcConfig}>
  <App />
</AuthProvider>
```

**Ingress Configuration** (self-service NOT through OAuth2-Proxy):

```yaml
# apps/ingress/base/self-service-public.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: self-service-public
  annotations:
    # NO auth_request annotation - React handles auth
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
  - host: apps.domain.com
    http:
      paths:
      - path: /self-service(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: self-service-app
            port:
              number: 80

# Static assets bypass (no auth needed)
# API calls to backend include JWT from React app
```

**Self-Service Backend API Protection** (Java Spring):

The React app passes JWT in Authorization header. Spring validates it:

```yaml
# self-service-backend configmap
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth.domain.com/realms/fineract
          jwk-set-uri: https://auth.domain.com/realms/fineract/protocol/openid-connect/certs
```

This way:
- Staff apps continue using OAuth2-Proxy (unchanged)
- Self-service React app talks directly to Keycloak
- Self-service backend validates JWT from React app
- Each uses its own Keycloak client with appropriate auth flow

---

### Transaction Limits Configuration

**Where limits are configured**:

1. **Savings Product Level** (Fineract):
   - `minRequiredOpeningBalance`
   - `withdrawalFeeForTransfers`
   - `minBalanceForInterestCalculation`

2. **Account Level** (Fineract):
   - Per-account withdrawal limits via savings account rules

3. **Self-Service Backend** (New - customer-registration-service):
   - Tier-based limits stored in ConfigMap
   - Enforced at API layer before calling Fineract

```yaml
# configmap.yaml for customer-registration-service
data:
  transaction-limits.yaml: |
    tiers:
      tier1:  # Unverified
        dailyDepositLimit: 50000
        dailyWithdrawalLimit: 25000
        perTransactionLimit: 25000
        allowedPaymentMethods:
          - MTN_TRANSFER
          - ORANGE_TRANSFER
      tier2:  # Verified (KYC approved)
        dailyDepositLimit: 500000
        dailyWithdrawalLimit: 250000
        perTransactionLimit: 100000
        allowedPaymentMethods:
          - MTN_TRANSFER
          - ORANGE_TRANSFER
          - UBA_BANK_TRANSFER
          - AFRILAND_BANK_TRANSFER
```

**How Limits Are Enforced - Detailed Flow**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ TRANSACTION LIMIT ENFORCEMENT FLOW                                       │
│                                                                          │
│ Component: self-service-backend (or customer-registration-service)       │
│ Location: API middleware layer BEFORE calling Fineract                   │
│                                                                          │
│ Example: Customer requests withdrawal of 30,000 XAF                      │
│                                                                          │
│ 1. Request arrives at self-service-backend                               │
│    POST /api/transactions/withdraw                                       │
│    {                                                                     │
│      "amount": 30000,                                                    │
│      "paymentMethod": "MTN_TRANSFER",                                    │
│      "destinationPhone": "+237612345678"                                 │
│    }                                                                     │
│    Headers: Authorization: Bearer <JWT>                                  │
│                                                                          │
│ 2. Extract user info from JWT token                                      │
│    {                                                                     │
│      "sub": "john.doe@email.com",                                        │
│      "fineract_external_id": "550e8400-e29b-41d4-...",                   │
│      "kyc_tier": "1",  // <-- Key attribute                              │
│      "kyc_status": "pending",                                            │
│      "realm_access": { "roles": ["self-service-customer", ...] }         │
│    }                                                                     │
│                                                                          │
│ 3. Load tier limits from ConfigMap                                       │
│    tier1_limits = {                                                      │
│      "dailyDepositLimit": 50000,                                         │
│      "dailyWithdrawalLimit": 25000,                                      │
│      "perTransactionLimit": 25000,                                       │
│      "allowedPaymentMethods": ["MTN_TRANSFER", "ORANGE_TRANSFER"]        │
│    }                                                                     │
│                                                                          │
│ 4. Check #1: Per-transaction limit                                       │
│    if amount (30000) > perTransactionLimit (25000):                      │
│        return 400 Bad Request:                                           │
│        {                                                                 │
│          "error": "LIMIT_EXCEEDED",                                      │
│          "message": "Amount 30,000 XAF exceeds your per-transaction      │
│                      limit of 25,000 XAF. Complete KYC to increase."     │
│        }                                                                 │
│    ❌ REJECTED - Does not proceed to Fineract                            │
│                                                                          │
│ 5. Check #2: Daily limit (requires DB query)                             │
│    today_withdrawals = db.query(                                         │
│      "SELECT SUM(amount) FROM transactions                               │
│       WHERE external_id = ? AND type = 'WITHDRAWAL'                      │
│       AND date = CURRENT_DATE"                                           │
│    )                                                                     │
│    if (today_withdrawals + amount) > dailyWithdrawalLimit:               │
│        return 400: "Daily withdrawal limit exceeded"                     │
│                                                                          │
│ 6. Check #3: Payment method allowed for tier                             │
│    if paymentMethod not in allowedPaymentMethods:                        │
│        return 400: "UBA_BANK_TRANSFER requires Tier 2 (KYC verified)"    │
│                                                                          │
│ 7. All checks passed → Proceed to Fineract                               │
│    POST /fineract-provider/api/v1/savingsaccounts/{id}/transactions      │
│    └── Create withdrawal transaction in Fineract                         │
│    └── Fineract creates journal entry                                    │
│                                                                          │
│ 8. Record transaction in self-service-backend DB                         │
│    (for daily limit tracking in step 5)                                  │
│                                                                          │
│ 9. Initiate payment via Payment Gateway                                  │
│    POST /payment-gateway/transfer/mtn                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

**Implementation Code** (self-service-backend - Java Spring):

```java
// service/TransactionLimitService.java
@Service
@Slf4j
public class TransactionLimitService {

    private final LimitsConfig limitsConfig;
    private final TransactionLogRepository transactionLogRepository;

    /**
     * Validates transaction against tier-based limits.
     * Called BEFORE processing transaction.
     * @throws LimitExceededException if any limit is violated
     */
    public void checkLimits(
        AuthenticatedUser user,
        TransactionType transactionType,
        BigDecimal amount,
        PaymentMethod paymentMethod
    ) {
        // Get limits for user's tier (from JWT claim)
        String tier = user.getKycTier();  // "1" or "2"
        TierLimits limits = limitsConfig.getTierLimits(tier);

        // Check 1: Per-transaction limit
        if (amount.compareTo(limits.getPerTransactionLimit()) > 0) {
            throw new LimitExceededException(String.format(
                "Amount %s XAF exceeds per-transaction limit of %s XAF for Tier %s. " +
                "Complete KYC verification to increase your limits.",
                amount, limits.getPerTransactionLimit(), tier
            ));
        }

        // Check 2: Daily limit
        BigDecimal todayTotal = transactionLogRepository.getDailyTotal(
            user.getFineractExternalId(),
            transactionType,
            LocalDate.now()
        );
        BigDecimal dailyLimit = transactionType == TransactionType.DEPOSIT
            ? limits.getDailyDepositLimit()
            : limits.getDailyWithdrawalLimit();

        if (todayTotal.add(amount).compareTo(dailyLimit) > 0) {
            BigDecimal remaining = dailyLimit.subtract(todayTotal);
            throw new LimitExceededException(String.format(
                "This transaction would exceed your daily %s limit of %s XAF. " +
                "Remaining today: %s XAF.",
                transactionType.name().toLowerCase(), dailyLimit, remaining
            ));
        }

        // Check 3: Payment method allowed for tier
        if (!limits.getAllowedPaymentMethods().contains(paymentMethod)) {
            throw new PaymentMethodNotAllowedException(String.format(
                "%s is only available for Tier 2 users. " +
                "Complete KYC verification to unlock bank transfers.",
                paymentMethod.name()
            ));
        }
    }
}

// controller/TransactionController.java
@RestController
@RequestMapping("/api/transactions")
@Slf4j
public class TransactionController {

    private final TransactionLimitService limitService;
    private final TransactionService transactionService;

    @PostMapping("/withdraw")
    public ResponseEntity<TransactionResponse> withdraw(
        @Valid @RequestBody WithdrawRequest request,
        @AuthenticationPrincipal Jwt jwt  // JWT from Keycloak
    ) {
        // Extract user info from JWT
        AuthenticatedUser user = AuthenticatedUser.fromJwt(jwt);

        // Step 1: Check limits BEFORE calling Fineract
        limitService.checkLimits(
            user,
            TransactionType.WITHDRAWAL,
            request.getAmount(),
            request.getPaymentMethod()
        );

        // Step 2: Limits OK - proceed with transaction
        TransactionResponse response = transactionService.processWithdrawal(user, request);

        return ResponseEntity.ok(response);
    }
}

// model/AuthenticatedUser.java
@Data
public class AuthenticatedUser {
    private String email;
    private String fineractExternalId;
    private String kycTier;
    private String kycStatus;

    public static AuthenticatedUser fromJwt(Jwt jwt) {
        AuthenticatedUser user = new AuthenticatedUser();
        user.setEmail(jwt.getSubject());
        user.setFineractExternalId(jwt.getClaimAsString("fineract_external_id"));
        user.setKycTier(jwt.getClaimAsString("kyc_tier"));
        user.setKycStatus(jwt.getClaimAsString("kyc_status"));
        return user;
    }
}
```

**Database Table for Daily Tracking**:

```sql
-- In self-service-backend database (not Fineract)
CREATE TABLE transaction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id VARCHAR(36) NOT NULL,  -- Customer's Fineract externalId
    transaction_type VARCHAR(20) NOT NULL,  -- 'DEPOSIT' or 'WITHDRAWAL'
    amount DECIMAL(15, 2) NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    fineract_transaction_id BIGINT,  -- Reference to Fineract transaction
    status VARCHAR(20) NOT NULL,  -- 'PENDING', 'COMPLETED', 'FAILED'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_daily_totals (external_id, transaction_type, created_at)
);
```

**Why Not Use Fineract for Limit Enforcement?**

| Option | Pros | Cons |
|--------|------|------|
| Fineract product-level limits | Built-in | Not tier-based, no payment method restrictions |
| **Self-service middleware** | Full control, tier-aware, payment method restrictions | Requires additional DB |

Fineract savings products have basic limits but don't support:
- Tier-based limits (different limits for KYC vs non-KYC)
- Payment method restrictions per tier
- Custom error messages for limit violations

The self-service-backend acts as a **policy enforcement layer** between the customer and Fineract.

---

### Rollback Mechanism for Registration

**Problem**: Registration touches two systems (Fineract + Keycloak). If one fails, we need to undo the other.

**Saga Pattern Implementation**:

```
Registration Saga:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Step 1: Create Fineract Client                                     │
│    ├── Success → Continue to Step 2                                 │
│    └── Failure → Return error (nothing to rollback)                 │
│                                                                     │
│  Step 2: Create Keycloak User                                       │
│    ├── Success → Registration complete                              │
│    └── Failure → COMPENSATE: Delete Fineract client                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation in customer-registration-service** (Java Spring):

```java
// service/RegistrationService.java
@Service
@Slf4j
public class RegistrationService {

    private final FineractClient fineractClient;
    private final KeycloakAdminClient keycloakClient;
    private final AlertService alertService;

    @Transactional
    public RegistrationResponse registerCustomer(RegistrationRequest data) {
        String externalId = UUID.randomUUID().toString();
        Long fineractClientId = null;

        // Step 1: Create Fineract client
        try {
            FineractClientResponse response = fineractClient.createClient(
                FineractClientRequest.builder()
                    .firstname(data.getFirstName())
                    .lastname(data.getLastName())
                    .externalId(externalId)
                    .mobileNo(data.getPhone())
                    .officeId(defaultOfficeId)
                    .active(false)
                    .build()
            );
            fineractClientId = response.getClientId();
            log.info("Created Fineract client: {}", fineractClientId);
        } catch (Exception e) {
            log.error("Failed to create Fineract client", e);
            throw new RegistrationException("Failed to create Fineract client", e);
        }

        // Step 2: Create Keycloak user
        try {
            keycloakClient.createUser(
                KeycloakUserRequest.builder()
                    .username(data.getEmail())
                    .email(data.getEmail())
                    .attributes(Map.of(
                        "fineract_external_id", List.of(externalId),
                        "kyc_tier", List.of("1"),
                        "kyc_status", List.of("pending")
                    ))
                    .groups(List.of("/self-service-customers"))
                    .requiredActions(List.of("VERIFY_EMAIL", "webauthn-register-passwordless"))
                    .build()
            );
            log.info("Created Keycloak user: {}", data.getEmail());
        } catch (Exception e) {
            // COMPENSATE: Rollback Fineract client
            log.error("Failed to create Keycloak user, initiating rollback", e);
            rollbackFineractClient(fineractClientId);
            throw new RegistrationException("Failed to create Keycloak user", e);
        }

        return new RegistrationResponse(externalId, "pending_verification");
    }

    private void rollbackFineractClient(Long clientId) {
        try {
            fineractClient.deleteClient(clientId);
            log.info("Successfully rolled back Fineract client: {}", clientId);
        } catch (Exception rollbackError) {
            // CRITICAL: Orphaned Fineract client - needs manual intervention
            log.error("CRITICAL: Failed to rollback Fineract client {}. Manual cleanup required.",
                clientId, rollbackError);
            alertService.sendCriticalAlert(
                "ORPHANED_FINERACT_CLIENT",
                String.format("Client ID %d could not be deleted. Manual cleanup required.", clientId),
                rollbackError
            );
        }
    }
}
```

**Edge Cases**:
- If rollback itself fails → Log critical error, alert ops team for manual cleanup
- Idempotency: Use `externalId` to check if client already exists before creating

---

## Implementation Checklist

Use this checklist to track implementation progress across sessions. Each step includes the specific files to modify or create.

### Setup (Do First)
- [ ] Create `self-service` branch: `git checkout -b self-service`
- [ ] Create documentation folder: `mkdir -p docs/self-service`

---

### Phase 1: Keycloak & GL Configuration

#### Step 1.1: Add Self-Service Roles to Keycloak
**File**: `operations/keycloak-config/base/config/realm-fineract.yaml`
**Section**: `roles.realm` (around line 364)
**Add**:
```yaml
- name: self-service-customer
  description: Self-service banking customer - limited to own accounts
  composite: false

- name: self-service-deposit
  description: Can perform deposits to own accounts
  composite: false

- name: self-service-withdrawal
  description: Can perform withdrawals from own accounts
  composite: false
```
- [ ] Added roles

#### Step 1.2: Add Self-Service Group
**File**: `operations/keycloak-config/base/config/realm-fineract.yaml`
**Section**: `groups` (around line 449)
**Add**:
```yaml
- name: self-service-customers
  path: /self-service-customers
  realmRoles:
    - self-service-customer
    - self-service-deposit
    - self-service-withdrawal
  attributes:
    registration_allowed: ["true"]
```
- [ ] Added group

#### Step 1.3: Add Self-Service Client
**File**: `operations/keycloak-config/base/config/realm-fineract.yaml`
**Section**: `clients` (around line 61)
**Add**:
```yaml
- clientId: "self-service-app"
  name: Self-Service Banking Portal
  description: Customer self-service portal with passwordless authentication
  enabled: true
  publicClient: true
  clientAuthenticatorType: client-secret
  protocol: openid-connect
  standardFlowEnabled: true
  implicitFlowEnabled: false
  directAccessGrantsEnabled: false
  serviceAccountsEnabled: false
  rootUrl: "https://${APPS_HOSTNAME}/self-service"
  redirectUris:
    - "https://${APPS_HOSTNAME}/self-service/callback"
    - "https://${APPS_HOSTNAME}/self-service/*"
  webOrigins:
    - "https://${APPS_HOSTNAME}"
  defaultClientScopes:
    - profile
    - email
    - offline_access
  optionalClientScopes:
    - address
    - phone
  attributes:
    post.logout.redirect.uris: "https://${APPS_HOSTNAME}/self-service/##https://${APPS_HOSTNAME}/self-service/*"
    pkce.code.challenge.method: "S256"
  authenticationFlowBindingOverrides:
    browser: self-service-browser
  protocolMappers:
    - name: fineract-external-id-mapper
      protocol: openid-connect
      protocolMapper: oidc-usermodel-attribute-mapper
      config:
        userinfo.token.claim: "true"
        user.attribute: "fineract_external_id"
        id.token.claim: "true"
        access.token.claim: "true"
        claim.name: "fineract_external_id"
        jsonType.label: "String"
    - name: kyc-tier-mapper
      protocol: openid-connect
      protocolMapper: oidc-usermodel-attribute-mapper
      config:
        userinfo.token.claim: "true"
        user.attribute: "kyc_tier"
        id.token.claim: "true"
        access.token.claim: "true"
        claim.name: "kyc_tier"
        jsonType.label: "String"
```
- [ ] Added client

#### Step 1.4: Add WebAuthn Passwordless Authentication Flow
**File**: `operations/keycloak-config/base/config/realm-fineract.yaml`
**Section**: `authenticationFlows` (create new section if needed)
**Add**:
```yaml
authenticationFlows:
  - alias: self-service-browser
    description: Passwordless browser flow for self-service customers
    providerId: basic-flow
    topLevel: true
    builtIn: false
    authenticationExecutions:
      - authenticator: auth-cookie
        requirement: ALTERNATIVE
        priority: 10
      - flowAlias: self-service-passwordless-forms
        requirement: ALTERNATIVE
        priority: 20
        autheticatorFlow: true

  - alias: self-service-passwordless-forms
    description: Username + WebAuthn passwordless
    providerId: basic-flow
    topLevel: false
    builtIn: false
    authenticationExecutions:
      - authenticator: auth-username-form
        requirement: REQUIRED
        priority: 10
      - authenticator: webauthn-authenticator-passwordless
        requirement: REQUIRED
        priority: 20
```
- [ ] Added authentication flows

#### Step 1.5: Add GL Accounts for UBA and Afriland
**File**: `operations/fineract-config/base/config/demo-config-fixed.yml` OR create new file
**Section**: `chartOfAccounts`
**Add**:
```yaml
  - name: UBA Bank Account
    glCode: "45"
    accountType: Asset
    accountUsage: Detail
    manualEntriesAllowed: true
    description: UBA bank transfer settlement account

  - name: Afriland Bank Account
    glCode: "46"
    accountType: Asset
    accountUsage: Detail
    manualEntriesAllowed: true
    description: Afriland bank transfer settlement account
```
- [ ] Added GL accounts

#### Step 1.6: Add Payment Types for Self-Service
**File**: `operations/fineract-config/base/config/demo-config-fixed.yml` OR create new file
**Section**: `paymentTypes`
**Add**:
```yaml
  - name: MTN Transfer
    description: MTN Mobile Money transfer (self-service)
    isCashPayment: false
    position: 10

  - name: Orange Transfer
    description: Orange Money transfer (self-service)
    isCashPayment: false
    position: 11

  - name: UBA Bank Transfer
    description: UBA bank transfer (self-service)
    isCashPayment: false
    position: 12

  - name: Afriland Bank Transfer
    description: Afriland bank transfer (self-service)
    isCashPayment: false
    position: 13
```
- [ ] Added payment types

#### Step 1.7: Commit Phase 1 Changes
```bash
git add operations/keycloak-config/ operations/fineract-config/
git commit -m "feat(config): add self-service roles, client, and GL accounts

- Add self-service-customer, deposit, withdrawal roles
- Add self-service-customers group
- Add self-service-app Keycloak client with PKCE
- Add WebAuthn passwordless authentication flow
- Add UBA and Afriland GL accounts
- Add self-service payment types

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 1

---

### Phase 2: Customer Registration Service (Java Spring)

#### Step 2.1: Create Service Directory Structure
**Create files**:
```
apps/customer-registration-service/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    └── dev/
        └── kustomization.yaml
```
- [ ] Created directory structure

#### Step 2.2: Create kustomization.yaml
**File**: `apps/customer-registration-service/base/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app: customer-registration-service
  app.kubernetes.io/name: customer-registration-service
  app.kubernetes.io/component: backend
```
- [ ] Created kustomization.yaml

#### Step 2.3: Create deployment.yaml
**File**: `apps/customer-registration-service/base/deployment.yaml`
(Copy pattern from existing Java services like user-sync-service)
- [ ] Created deployment.yaml

#### Step 2.4: Create service.yaml
**File**: `apps/customer-registration-service/base/service.yaml`
- [ ] Created service.yaml

#### Step 2.5: Create configmap.yaml with transaction limits
**File**: `apps/customer-registration-service/base/configmap.yaml`
Include transaction limits configuration:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: customer-registration-config
data:
  transaction-limits.yaml: |
    tiers:
      tier1:
        dailyDepositLimit: 50000
        dailyWithdrawalLimit: 25000
        perTransactionLimit: 25000
        allowedPaymentMethods:
          - MTN_TRANSFER
          - ORANGE_TRANSFER
      tier2:
        dailyDepositLimit: 500000
        dailyWithdrawalLimit: 250000
        perTransactionLimit: 100000
        allowedPaymentMethods:
          - MTN_TRANSFER
          - ORANGE_TRANSFER
          - UBA_BANK_TRANSFER
          - AFRILAND_BANK_TRANSFER
```
- [ ] Created configmap.yaml

#### Step 2.6: Create ArgoCD Application
**File**: `argocd/applications/dev/customer-registration-service.yaml`
- [ ] Created ArgoCD app

#### Step 2.7: Commit Phase 2 Changes
```bash
git add apps/customer-registration-service/ argocd/applications/
git commit -m "feat(apps): add customer-registration-service scaffolding

- Add Kubernetes deployment manifests
- Add transaction limits ConfigMap
- Add ArgoCD application

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 2

---

### Phase 3: Self-Service Frontend App (React)

#### Step 3.1: Create GitOps Directory Structure
**Create files**:
```
apps/self-service-app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── nginx-configmap.yaml
└── overlays/
    └── dev/
        └── kustomization.yaml
```
- [ ] Created GitOps directory structure

#### Step 3.2: Create Ingress for Self-Service (Public - no OAuth2-Proxy)
**File**: `apps/ingress/base/self-service-public.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: self-service-public
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${APPS_HOSTNAME}
      secretName: apps-tls
  rules:
    - host: ${APPS_HOSTNAME}
      http:
        paths:
          - path: /self-service(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: self-service-app
                port:
                  number: 80
```
- [ ] Created Ingress

#### Step 3.3: Update ingress kustomization.yaml
**File**: `apps/ingress/base/kustomization.yaml`
Add `self-service-public.yaml` to resources
- [ ] Updated kustomization

#### Step 3.4: Create ArgoCD Application
**File**: `argocd/applications/dev/self-service-app.yaml`
- [ ] Created ArgoCD app

#### Step 3.5: Document React App Requirements
**Note**: The React app source code will be created in `/Users/guymoyo/dev/fineract-apps/frontend/self-service-app/`
Key dependencies:
- `react-oidc-context` or `oidc-client-ts` for OIDC auth
- `@simplewebauthn/browser` for WebAuthn
- React Router for navigation
- Axios or fetch for API calls

- [ ] Documented React app requirements

#### Step 3.6: Commit Phase 3 Changes
```bash
git add apps/self-service-app/ apps/ingress/ argocd/applications/
git commit -m "feat(apps): add self-service-app GitOps scaffolding

- Add Kubernetes deployment manifests
- Add public Ingress (no OAuth2-Proxy)
- Add ArgoCD application

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 3

---

### Phase 4: Payment Gateway Service (Java Spring)

#### Step 4.1: Create Service Directory Structure
**Create files**:
```
apps/payment-gateway-service/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    └── dev/
        └── kustomization.yaml
```
- [ ] Created directory structure

#### Step 4.2: Create Sealed Secret for Payment API Credentials
**File**: `secrets/dev/payment-gateway-secrets-sealed.yaml`
(Create placeholder, seal with kubeseal later)
- [ ] Created secrets placeholder

#### Step 4.3: Create ArgoCD Application
**File**: `argocd/applications/dev/payment-gateway-service.yaml`
- [ ] Created ArgoCD app

#### Step 4.4: Commit Phase 4 Changes
```bash
git add apps/payment-gateway-service/ argocd/applications/ secrets/
git commit -m "feat(apps): add payment-gateway-service scaffolding

- Add Kubernetes deployment manifests
- Add secrets placeholder for payment API credentials
- Add ArgoCD application

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 4

---

### Phase 5: Network Policies & Security

#### Step 5.1: Create Network Policy for Self-Service
**File**: `apps/network-policies/self-service-network-policy.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: self-service-network-policy
  namespace: fineract-dev
spec:
  podSelector:
    matchLabels:
      app: self-service-app
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 80
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: fineract
      ports:
        - protocol: TCP
          port: 8443
    - to:
        - podSelector:
            matchLabels:
              app: keycloak
      ports:
        - protocol: TCP
          port: 8080
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
```
- [ ] Created network policy

#### Step 5.2: Update network-policies kustomization.yaml
**File**: `apps/network-policies/kustomization.yaml`
Add `self-service-network-policy.yaml` to resources
- [ ] Updated kustomization

#### Step 5.3: Commit Phase 5 Changes
```bash
git add apps/network-policies/
git commit -m "feat(security): add network policy for self-service

- Restrict ingress to NGINX Ingress only
- Restrict egress to Fineract, Keycloak, and DNS

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 5

---

### Phase 6: Document Account Manager KYC Requirements

#### Step 6.1: Create KYC Requirements Document
**File**: `docs/self-service/kyc-account-manager-requirements.md`
Document the features needed in Account Manager app:
- List pending KYC verification requests
- View uploaded documents
- Approve/Reject workflow
- Update Keycloak kyc_tier on approval

- [ ] Created KYC requirements doc

#### Step 6.2: Commit Phase 6 Changes
```bash
git add docs/
git commit -m "docs: add KYC review requirements for Account Manager app

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 6

---

### Phase 7: Create Documentation

#### Step 7.1: Create README.md
**File**: `docs/self-service/README.md`
- [ ] Created README

#### Step 7.2: Create architecture.md
**File**: `docs/self-service/architecture.md`
- [ ] Created architecture doc

#### Step 7.3: Create registration-flow.md
**File**: `docs/self-service/registration-flow.md`
- [ ] Created registration flow doc

#### Step 7.4: Create authentication-flow.md
**File**: `docs/self-service/authentication-flow.md`
- [ ] Created auth flow doc

#### Step 7.5: Create payment-integration.md
**File**: `docs/self-service/payment-integration.md`
- [ ] Created payment integration doc

#### Step 7.6: Create transaction-limits.md
**File**: `docs/self-service/transaction-limits.md`
- [ ] Created transaction limits doc

#### Step 7.7: Create deployment-guide.md
**File**: `docs/self-service/deployment-guide.md`
- [ ] Created deployment guide

#### Step 7.8: Commit Phase 7 Changes
```bash
git add docs/
git commit -m "docs: add self-service documentation

- Add architecture overview
- Add registration and authentication flow docs
- Add payment integration guide
- Add transaction limits configuration
- Add deployment guide

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
- [ ] Committed Phase 7

---

### Final Steps

#### Push to Remote
```bash
git push -u origin self-service
```
- [ ] Pushed to remote

#### Create Pull Request
```bash
gh pr create --title "feat: add self-service banking application" \
  --body "## Summary
- Add self-service customer portal with WebAuthn passwordless login
- Add customer registration service (Java Spring)
- Add payment gateway service for MTN/Orange integration
- Add GL accounts and payment types for mobile money
- Add network policies for security isolation
- Add comprehensive documentation

## Test Plan
- [ ] Deploy to dev environment
- [ ] Test customer registration flow
- [ ] Test WebAuthn login
- [ ] Test deposit/withdrawal transactions
- [ ] Verify transaction limits enforcement
"
```
- [ ] Created PR

---

## Branching & Testing Strategy

### Branch Structure
```
main (or deploy-key)     ← Production/EKS deployment branch
    │
    └── self-service     ← Feature branch for self-service implementation
```

### How to Test Before Merging

**Option A: Deploy self-service branch to dev environment (Recommended)**

1. **Update ArgoCD to track self-service branch for dev**:
   ```yaml
   # In argocd/applications/dev/*.yaml, temporarily change:
   spec:
     source:
       targetRevision: self-service  # Instead of main/deploy-key
   ```

2. **Or create a separate ArgoCD Application Set for testing**:
   ```yaml
   # argocd/applications/dev/self-service-test.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: self-service-test
   spec:
     source:
       repoURL: https://github.com/ADORSYS-GIS/fineract-gitops.git
       targetRevision: self-service
       path: apps/self-service-app/overlays/dev
   ```

3. **Sync and test**:
   ```bash
   # ArgoCD will deploy from self-service branch
   argocd app sync self-service-test
   ```

**Option B: Use Kustomize overlays for feature testing**

Create a dedicated overlay for testing the self-service feature:
```
apps/self-service-app/
└── overlays/
    ├── dev/           # Regular dev
    ├── self-service-test/  # Feature testing
    └── production/
```

### Testing Workflow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ FEATURE TESTING WORKFLOW                                                 │
│                                                                          │
│ 1. Implement on self-service branch                                      │
│    └── All commits go to self-service branch                             │
│                                                                          │
│ 2. Push changes                                                          │
│    └── git push origin self-service                                      │
│                                                                          │
│ 3. Deploy to dev for testing                                             │
│    └── ArgoCD syncs from self-service branch                             │
│    └── Access at: https://apps.dev.domain.com/self-service               │
│                                                                          │
│ 4. Run test checklist:                                                   │
│    □ Customer registration works                                         │
│    □ WebAuthn passwordless login works                                   │
│    □ Keycloak user created with correct attributes                       │
│    □ Fineract client created with externalId                             │
│    □ Deposit via MTN/Orange works                                        │
│    □ Withdrawal with limits enforced                                     │
│    □ KYC document upload works                                           │
│    □ Staff can review KYC in Account Manager                             │
│                                                                          │
│ 5. Fix issues, repeat steps 1-4                                          │
│                                                                          │
│ 6. When ready, create PR:                                                │
│    └── gh pr create --base deploy-key --head self-service                │
│                                                                          │
│ 7. Code review + approval                                                │
│                                                                          │
│ 8. Merge to deploy-key                                                   │
│    └── Feature goes to production                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Commands for Testing

```bash
# 1. Ensure you're on self-service branch
git checkout self-service

# 2. Make changes and commit
git add .
git commit -m "feat: implement X"

# 3. Push to remote
git push origin self-service

# 4. Check ArgoCD sync status (if configured)
argocd app list | grep self-service

# 5. When testing complete, create PR
gh pr create \
  --base deploy-key \
  --head self-service \
  --title "feat: add self-service banking application" \
  --body "## Summary
- Self-service customer portal with WebAuthn passwordless
- Customer registration service
- Payment gateway for MTN/Orange
- Tiered KYC with transaction limits

## Testing Done
- [x] Registration flow tested
- [x] Login flow tested
- [x] Deposit/withdrawal tested
- [x] KYC workflow tested"

# 6. After PR approved and merged
git checkout deploy-key
git pull origin deploy-key
```

### Keeping Branches in Sync

If `deploy-key` gets updates while you're working on `self-service`:

```bash
# On self-service branch
git checkout self-service
git fetch origin
git rebase origin/deploy-key  # Or merge: git merge origin/deploy-key
git push origin self-service --force-with-lease  # If rebased
```

---

## Session Resume Instructions

When resuming implementation in a new session:

1. **Check current state**:
   ```bash
   git status
   git branch
   ```

2. **Switch to self-service branch** (if not already):
   ```bash
   git checkout self-service
   ```

3. **Find the last completed step** in this checklist

4. **Continue from the next uncompleted step**

5. **Use this plan file** as reference: `/Users/guymoyo/.claude/plans/hazy-cuddling-hummingbird.md`
