# Comprehensive RBAC Test Plan

This document outlines the test cases to verify the Role-Based Access Control (RBAC) rules defined in the Ingress Nginx ConfigMap.

**Testing Strategy:**
1.  **Login:** Log in to the application as the specified "Test Role".
2.  **Navigate/Request:** Try to access the "Target Path" (either via the UI browser or using `curl`/Postman for API endpoints).
3.  **Verify:** Check if the access is **Allowed (200 OK / Page Loads)** or **Denied (403 Forbidden)**.

---

## 1. Test Role: `account-manager`

| ID | Target Path | Method | Expected Result | Logic Source |
|----|-------------|--------|-----------------|--------------|
| **Frontend UI** |
| AM-01 | `/account/` | GET | **ALLOWED** | Category `account-manager` allows `account-manager` |
| AM-02 | `/cashier/` | GET | **DENIED (403)** | Category `cashier` requires `cashier` |
| AM-03 | `/branch/` | GET | **DENIED (403)** | Category `branch-manager` requires `branch-manager` |
| AM-04 | `/administration/` | GET | **DENIED (403)** | Category `admin` requires `admin` |
| AM-05 | `/accounting/` | GET | **DENIED (403)** | Category `accountant` requires `accountant` |
| **API Endpoints - Specific** |
| AM-06 | `/fineract-provider/api/v1/clients` | POST | **ALLOWED** | Category `account-manager` |
| AM-07 | `/fineract-provider/api/v1/loans` | POST | **ALLOWED** | Category `account-manager` |
| AM-08 | `/fineract-provider/api/v1/savingsaccounts` | POST | **ALLOWED** | Category `account-manager` |
| **API Endpoints - Shared** |
| AM-09 | `/fineract-provider/api/v1/offices` | GET | **ALLOWED** | `common-offices` allows `account-manager` |
| AM-10 | `/fineract-provider/api/v1/currencies` | GET | **DENIED (403)** | `common-currencies` allows only `accountant|cashier` |
| AM-11 | `/fineract-provider/api/v1/paymenttypes` | GET | **DENIED (403)** | `common-paymenttypes` allows only `accountant|cashier` |
| AM-12 | `/fineract-provider/api/v1/tellers` | GET | **DENIED (403)** | `common-tellers` allows only `branch-manager|cashier` |
| AM-13 | `/fineract-provider/api/v1/savingsaccounts/1` | GET | **ALLOWED** | `common-savingsaccounts-read` allows `account-manager` |
| AM-14 | `/fineract-provider/api/v1/clients/1` | GET | **ALLOWED** | `common-clients-read` allows `account-manager` |
| AM-15 | `/fineract-provider/api/v1/loans/1` | GET | **ALLOWED** | `common-loans-read` allows `account-manager` |

---

## 2. Test Role: `cashier`

| ID | Target Path | Method | Expected Result | Logic Source |
|----|-------------|--------|-----------------|--------------|
| **Frontend UI** |
| CA-01 | `/cashier/` | GET | **ALLOWED** | Category `cashier` allows `cashier` |
| CA-02 | `/account/` | GET | **DENIED (403)** | Category `account-manager` requires `account-manager` |
| CA-03 | `/branch/` | GET | **DENIED (403)** | Category `branch-manager` requires `branch-manager` |
| CA-04 | `/administration/` | GET | **DENIED (403)** | Category `admin` requires `admin` |
| **API Endpoints - Specific** |
| CA-05 | `/fineract-provider/api/v1/userdetails` | GET | **ALLOWED** | Category `cashier` |
| CA-06 | `/fineract-provider/api/v1/savingsaccounts/1/transactions` | POST | **ALLOWED** | Category `cashier` |
| CA-07 | `/fineract-provider/api/v1/loans/1/transactions` | POST | **ALLOWED** | Category `cashier` |
| **API Endpoints - Shared** |
| CA-08 | `/fineract-provider/api/v1/offices` | GET | **DENIED (403)** | `common-offices` excludes `cashier`! |
| CA-09 | `/fineract-provider/api/v1/currencies` | GET | **ALLOWED** | `common-currencies` allows `cashier` |
| CA-10 | `/fineract-provider/api/v1/paymenttypes` | GET | **ALLOWED** | `common-paymenttypes` allows `cashier` |
| CA-11 | `/fineract-provider/api/v1/tellers` | GET | **ALLOWED** | `common-tellers` allows `cashier` |
| CA-12 | `/fineract-provider/api/v1/savingsaccounts/1` | GET | **ALLOWED** | `common-savingsaccounts-read` allows `cashier` |
| CA-13 | `/fineract-provider/api/v1/clients/1` | GET | **DENIED (403)** | `common-clients-read` excludes `cashier` |
| CA-14 | `/fineract-provider/api/v1/loans/1` | GET | **DENIED (403)** | `common-loans-read` excludes `cashier` |

---

## 3. Test Role: `branch-manager`

| ID | Target Path | Method | Expected Result | Logic Source |
|----|-------------|--------|-----------------|--------------|
| **Frontend UI** |
| BM-01 | `/branch/` | GET | **ALLOWED** | Category `branch-manager` allows `branch-manager` |
| BM-02 | `/account/` | GET | **DENIED (403)** | Category `account-manager` requires `account-manager` |
| BM-03 | `/cashier/` | GET | **DENIED (403)** | Category `cashier` requires `cashier` |
| **API Endpoints - Specific** |
| BM-04 | `/fineract-provider/api/v1/savingsaccounts` | GET | **ALLOWED** | Category `branch-manager` |
| BM-05 | `/fineract-provider/api/v1/staff` | GET | **ALLOWED** | Category `branch-manager` |
| BM-06 | `/fineract-provider/api/v1/tellers` | POST | **ALLOWED** | Category `branch-manager` |
| **API Endpoints - Shared** |
| BM-07 | `/fineract-provider/api/v1/offices` | GET | **ALLOWED** | `common-offices` allows `branch-manager` |
| BM-08 | `/fineract-provider/api/v1/currencies` | GET | **DENIED (403)** | `common-currencies` excludes `branch-manager` |
| BM-09 | `/fineract-provider/api/v1/tellers` | GET | **ALLOWED** | `common-tellers` allows `branch-manager` |
| BM-10 | `/fineract-provider/api/v1/savingsaccounts/1` | GET | **ALLOWED** | `common-savingsaccounts-read` allows `branch-manager` |
| BM-11 | `/fineract-provider/api/v1/clients/1` | GET | **ALLOWED** | `common-clients-read` allows `branch-manager` |
| BM-12 | `/fineract-provider/api/v1/loans/1` | GET | **ALLOWED** | `common-loans-read` allows `branch-manager` |

---

## 4. Test Role: `admin`

| ID | Target Path | Method | Expected Result | Logic Source |
|----|-------------|--------|-----------------|--------------|
| **Frontend UI** |
| AD-01 | `/administration/` | GET | **ALLOWED** | Category `admin` allows `admin` |
| AD-02 | `/account/` | GET | **DENIED (403)** | Category `account-manager` requires `account-manager` |
| **API Endpoints - Specific** |
| AD-03 | `/fineract-provider/api/v1/users` | GET | **ALLOWED** | Category `admin` |
| AD-04 | `/fineract-provider/api/v1/roles` | GET | **ALLOWED** | Category `admin` |
| AD-05 | `/fineract-provider/api/user-sync/sync/user` | POST | **ALLOWED** | Category `admin` |
| **API Endpoints - Shared** |
| AD-06 | `/fineract-provider/api/v1/offices` | GET | **ALLOWED** | `common-offices` allows `admin` |
| AD-07 | `/fineract-provider/api/v1/tellers` | GET | **DENIED (403)** | `common-tellers` excludes `admin` |

---

## 5. Test Role: `accountant`

| ID | Target Path | Method | Expected Result | Logic Source |
|----|-------------|--------|-----------------|--------------|
| **Frontend UI** |
| AC-01 | `/accounting/` | GET | **ALLOWED** | Category `accountant` allows `accountant` |
| AC-02 | `/account/` | GET | **DENIED (403)** | Category `account-manager` requires `account-manager` |
| **API Endpoints - Specific** |
| AC-03 | `/fineract-provider/api/v1/glaccounts` | GET | **ALLOWED** | Category `accountant` |
| AC-04 | `/fineract-provider/api/v1/journalentries` | POST | **ALLOWED** | Category `accountant` |
| **API Endpoints - Shared** |
| AC-05 | `/fineract-provider/api/v1/offices` | GET | **ALLOWED** | `common-offices` allows `accountant` |
| AC-06 | `/fineract-provider/api/v1/currencies` | GET | **ALLOWED** | `common-currencies` allows `accountant` |
| AC-07 | `/fineract-provider/api/v1/paymenttypes` | GET | **ALLOWED** | `common-paymenttypes` allows `accountant` |
| AC-08 | `/fineract-provider/api/v1/tellers` | GET | **DENIED (403)** | `common-tellers` excludes `accountant` |
