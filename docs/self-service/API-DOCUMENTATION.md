# Self-Service API Documentation

## Overview

This document describes the APIs exposed by the self-service banking components.

---

## Customer Registration Service

**Base URL**: `/api/registration`

The Customer Registration Service orchestrates user registration across Fineract and Keycloak.

### Endpoints

#### POST /api/registration/register

Register a new self-service customer.

**Request Body**:
```json
{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john.doe@example.com",
  "phone": "+237690123456",
  "nationalId": "CM12345678",
  "dateOfBirth": "1990-01-15",
  "gender": "Male",
  "address": {
    "street": "123 Main Street",
    "city": "Douala",
    "postalCode": "00237"
  }
}
```

**Response (201 Created)**:
```json
{
  "externalId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending_verification",
  "message": "Registration successful. Please check your email to verify your account and set up passwordless authentication.",
  "nextSteps": [
    "VERIFY_EMAIL",
    "REGISTER_WEBAUTHN"
  ]
}
```

**Response (400 Bad Request)**:
```json
{
  "error": "VALIDATION_ERROR",
  "message": "Email already registered",
  "field": "email"
}
```

**Response (500 Internal Server Error)**:
```json
{
  "error": "REGISTRATION_FAILED",
  "message": "Failed to complete registration. Please try again.",
  "correlationId": "abc123-def456"
}
```

---

#### GET /api/registration/status/{externalId}

Check registration status for a customer.

**Path Parameters**:
- `externalId`: The customer's UUID (from registration response)

**Response (200 OK)**:
```json
{
  "externalId": "550e8400-e29b-41d4-a716-446655440000",
  "registrationStatus": "completed",
  "emailVerified": true,
  "webAuthnRegistered": true,
  "kycTier": 1,
  "kycStatus": "pending"
}
```

---

#### POST /api/registration/kyc/upload

Upload KYC documents for verification.

**Headers**:
- `Authorization`: Bearer {access_token}
- `Content-Type`: multipart/form-data

**Request Body (multipart/form-data)**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `documentType` | string | Yes | `ID_FRONT`, `ID_BACK`, `PROOF_OF_ADDRESS`, `SELFIE_WITH_ID` |
| `file` | file | Yes | Document image (JPG, PNG, PDF) |
| `description` | string | No | Optional description |

**Response (201 Created)**:
```json
{
  "documentId": "doc-12345",
  "documentType": "ID_FRONT",
  "status": "uploaded",
  "uploadedAt": "2024-03-15T10:30:00Z"
}
```

---

#### GET /api/registration/kyc/status

Get KYC verification status for the authenticated customer.

**Headers**:
- `Authorization`: Bearer {access_token}

**Response (200 OK)**:
```json
{
  "kycTier": 1,
  "kycStatus": "under_review",
  "documents": [
    {
      "documentType": "ID_FRONT",
      "status": "verified",
      "uploadedAt": "2024-03-15T10:30:00Z"
    },
    {
      "documentType": "ID_BACK",
      "status": "verified",
      "uploadedAt": "2024-03-15T10:31:00Z"
    },
    {
      "documentType": "PROOF_OF_ADDRESS",
      "status": "pending_review",
      "uploadedAt": "2024-03-15T10:32:00Z"
    },
    {
      "documentType": "SELFIE_WITH_ID",
      "status": "pending",
      "uploadedAt": null
    }
  ],
  "requiredDocuments": ["ID_FRONT", "ID_BACK", "PROOF_OF_ADDRESS", "SELFIE_WITH_ID"],
  "missingDocuments": ["SELFIE_WITH_ID"]
}
```

---

## Transaction Limits

Limits are enforced based on the customer's KYC tier.

### Tier 1 (Unverified)

| Limit Type | Value |
|------------|-------|
| Daily Deposit | 50,000 XAF |
| Daily Withdrawal | 25,000 XAF |
| Per Transaction | 25,000 XAF |
| Monthly Total | 200,000 XAF |
| Allowed Methods | MTN Transfer, Orange Transfer |

### Tier 2 (Verified)

| Limit Type | Value |
|------------|-------|
| Daily Deposit | 500,000 XAF |
| Daily Withdrawal | 250,000 XAF |
| Per Transaction | 100,000 XAF |
| Monthly Total | 2,000,000 XAF |
| Allowed Methods | MTN Transfer, Orange Transfer, UBA Bank Transfer, Afriland Bank Transfer |

---

#### GET /api/registration/limits

Get transaction limits for the authenticated customer.

**Headers**:
- `Authorization`: Bearer {access_token}

**Response (200 OK)**:
```json
{
  "kycTier": 1,
  "limits": {
    "dailyDepositLimit": 50000,
    "dailyWithdrawalLimit": 25000,
    "perTransactionLimit": 25000,
    "monthlyTransactionLimit": 200000
  },
  "usage": {
    "dailyDepositUsed": 15000,
    "dailyWithdrawalUsed": 0,
    "monthlyUsed": 45000
  },
  "available": {
    "depositRemaining": 35000,
    "withdrawalRemaining": 25000
  },
  "allowedPaymentMethods": ["MTN_TRANSFER", "ORANGE_TRANSFER"],
  "restrictedFeatures": ["BANK_TRANSFER", "INTERNATIONAL_TRANSFER"],
  "currency": "XAF"
}
```

---

## Self-Service App API Calls

The React frontend calls these Fineract APIs (proxied through NGINX):

### Account Dashboard

#### GET /fineract-provider/api/v1/self/clients

Get the authenticated customer's profile.

**Headers**:
- `Authorization`: Bearer {access_token}
- `Fineract-Platform-TenantId`: default

**Response (200 OK)**:
```json
{
  "id": 12345,
  "accountNo": "000000012345",
  "externalId": "550e8400-e29b-41d4-a716-446655440000",
  "status": {
    "id": 300,
    "code": "clientStatusType.active",
    "value": "Active"
  },
  "firstname": "John",
  "lastname": "Doe",
  "displayName": "John Doe",
  "mobileNo": "+237690123456",
  "emailAddress": "john.doe@example.com",
  "dateOfBirth": [1990, 1, 15],
  "gender": {
    "id": 1,
    "name": "Male"
  },
  "officeId": 1,
  "officeName": "Head Office"
}
```

---

#### GET /fineract-provider/api/v1/self/savingsaccounts

Get the customer's savings accounts.

**Headers**:
- `Authorization`: Bearer {access_token}
- `Fineract-Platform-TenantId`: default

**Response (200 OK)**:
```json
{
  "savingsAccounts": [
    {
      "id": 1001,
      "accountNo": "000000001001",
      "productId": 1,
      "productName": "Voluntary Savings Account",
      "shortProductName": "VSAV",
      "status": {
        "id": 300,
        "code": "savingsAccountStatusType.active",
        "value": "Active"
      },
      "currency": {
        "code": "XAF",
        "name": "Central African CFA Franc",
        "decimalPlaces": 0,
        "displaySymbol": "FCFA"
      },
      "accountBalance": 125000,
      "availableBalance": 125000
    }
  ]
}
```

---

#### GET /fineract-provider/api/v1/self/savingsaccounts/{accountId}/transactions

Get transactions for a savings account.

**Headers**:
- `Authorization`: Bearer {access_token}
- `Fineract-Platform-TenantId`: default

**Query Parameters**:
- `offset`: Pagination offset (default: 0)
- `limit`: Number of results (default: 20)

**Response (200 OK)**:
```json
{
  "totalFilteredRecords": 15,
  "pageItems": [
    {
      "id": 5001,
      "transactionType": {
        "id": 1,
        "code": "savingsAccountTransactionType.deposit",
        "value": "Deposit"
      },
      "accountId": 1001,
      "accountNo": "000000001001",
      "date": [2024, 3, 15],
      "currency": {
        "code": "XAF",
        "decimalPlaces": 0
      },
      "amount": 25000,
      "runningBalance": 125000,
      "reversed": false,
      "paymentDetailData": {
        "paymentType": {
          "id": 10,
          "name": "MTN Transfer"
        }
      }
    }
  ]
}
```

---

#### POST /fineract-provider/api/v1/self/savingsaccounts/{accountId}/transactions

Create a deposit or withdrawal transaction.

**Headers**:
- `Authorization`: Bearer {access_token}
- `Fineract-Platform-TenantId`: default

**Query Parameters**:
- `command`: `deposit` or `withdrawal`

**Request Body (Deposit)**:
```json
{
  "transactionDate": "15 March 2024",
  "transactionAmount": 25000,
  "paymentTypeId": 10,
  "locale": "en",
  "dateFormat": "dd MMMM yyyy",
  "note": "MTN Transfer deposit"
}
```

**Response (200 OK)**:
```json
{
  "officeId": 1,
  "clientId": 12345,
  "savingsId": 1001,
  "resourceId": 5002,
  "changes": {
    "accountNumber": "000000001001",
    "transactionDate": "15 March 2024",
    "transactionAmount": 25000,
    "paymentTypeId": 10
  }
}
```

---

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Request validation failed |
| `EMAIL_ALREADY_EXISTS` | 400 | Email is already registered |
| `PHONE_ALREADY_EXISTS` | 400 | Phone number is already registered |
| `INVALID_DOCUMENT_TYPE` | 400 | Invalid document type for KYC |
| `DOCUMENT_TOO_LARGE` | 400 | Document exceeds 10MB limit |
| `DAILY_LIMIT_EXCEEDED` | 400 | Daily transaction limit exceeded |
| `TRANSACTION_LIMIT_EXCEEDED` | 400 | Per-transaction limit exceeded |
| `PAYMENT_METHOD_NOT_ALLOWED` | 403 | Payment method not available for KYC tier |
| `UNAUTHORIZED` | 401 | Invalid or expired access token |
| `FORBIDDEN` | 403 | Access denied to resource |
| `NOT_FOUND` | 404 | Resource not found |
| `REGISTRATION_FAILED` | 500 | Registration process failed |
| `SERVICE_UNAVAILABLE` | 503 | Downstream service unavailable |

---

## Authentication

All protected endpoints require a valid JWT access token from Keycloak.

**Token Claims**:
```json
{
  "sub": "john.doe@example.com",
  "fineract_external_id": "550e8400-e29b-41d4-a716-446655440000",
  "kyc_tier": "1",
  "kyc_status": "pending",
  "tenant": "default",
  "realm_access": {
    "roles": ["self-service-customer", "self-service-deposit", "self-service-withdrawal"]
  }
}
```

**Request Format**:
```
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```
