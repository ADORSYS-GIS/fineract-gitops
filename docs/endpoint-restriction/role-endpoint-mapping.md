# Role to Endpoint Mapping

This document maps user roles to the API endpoints they are allowed to access.

## Account Manager (`account-manager-app`)

| Role | Allowed Endpoints |
| --- | --- |
| `account-manager` | <ul><li>`POST /v1/authentication`</li><li>`POST /v1/clients`</li><li>`GET /v1/runreports/Savings%20Transactions`</li><li>`GET /v1/clients/{clientId}`</li><li>`GET /v1/clients/{clientId}/accounts`</li><li>`POST /v1/savingsaccounts/{accountId}?command=activate`</li><li>`DELETE /v1/loans/{loanId}`</li><li>`DELETE /v1/savingsaccounts/{accountId}`</li><li>`GET /v1/clients/{entityId}/images`</li><li>`POST /v1/clients/{entityId}/images`</li><li>`DELETE /v1/clients/{entityId}/images`</li><li>`GET /v1/clients`</li><li>`POST /v2/clients/search`</li><li>`GET /v1/offices`</li><li>`GET /v1/loans/{loanId}`</li><li>`POST /v1/loans`</li><li>`PUT /v1/loans/{loanId}`</li><li>`GET /v1/loans/template`</li><li>`POST /v1/loans?command=calculateLoanSchedule`</li><li>`GET /v1/savingsproducts`</li><li>`GET /v1/loanproducts`</li><li>`GET /v1/products/{type}`</li><li>`GET /v1/recurringdepositproducts`</li><li>`GET /v1/fixeddepositproducts`</li><li>`POST /v1/savingsaccounts`</li><li>`POST /v1/accounts/{type}`</li><li>`GET /v1/savingsaccounts/{accountId}`</li><li>`POST /v1/savingsaccounts/{accountId}?command=unblock`</li><li>`GET /v1/codes/{codeId}/codevalues`</li><li>`POST /v1/savingsaccounts/{accountId}?command=block`</li></ul> |

## Accounting App (`accounting-app`)

| Role | Allowed Endpoints |
| --- | --- |
| `accountant` | <ul><li>`GET /v1/makercheckers`</li><li>`GET /v1/offices`</li><li>`POST /v1/glclosures`</li><li>`GET /v1/glaccounts`</li><li>`GET /v1/currencies`</li><li>`GET /v1/paymenttypes`</li><li>`POST /v1/journalentries`</li><li>`GET /v1/journalentries`</li><li>`DELETE /v1/glaccounts/{glAccountId}`</li><li>`GET /v1/journalentries/{journalEntryId}`</li><li>`POST /v1/journalentries/{transactionId}`</li><li>`POST /v1/makercheckers/{auditId}`</li></ul> |

## Admin App (`admin-app`)

| Role | Allowed Endpoints |
| --- | --- |
| `admin` | <ul><li>`POST /v1/adorsys/employees`</li><li>`GET /v1/adorsys/employees`</li><li>`GET /v1/adorsys/employees/{userId}`</li><li>`PUT /v1/adorsys/employees/{userId}`</li><li>`POST /api/user-sync/sync/user`</li><li>`POST /api/user-sync/users/{username}/reset-password`</li><li>`PUT /api/user-sync/users/{username}/status`</li><li>`POST /api/user-sync/users/{username}/force-password-change`</li><li>`GET /api/user-sync/users/{username}/keycloak-status`</li><li>`GET /v1/roles`</li><li>`GET /v1/offices`</li><li>`GET /v1/users`</li></ul> |

## Branch Manager App (`branchmanager-app`)

| Role | Allowed Endpoints |
| --- | --- |
| `branch-manager` | <ul><li>`GET /v1/savingsaccounts`</li><li>`GET /v1/savingsaccounts/{accountId}`</li><li>`POST /v1/savingsaccounts/{accountId}?command=approve`</li><li>`POST /v1/tellers/{tellerId}/cashiers/{cashierId}/allocate`</li><li>`POST /v1/tellers/{tellerId}/cashiers/{cashierId}/settle`</li><li>`GET /v1/tellers/{tellerId}/cashiers/{cashierId}`</li><li>`GET /v1/tellers/{tellerId}/cashiers/{cashierId}/summaryandtransactions`</li><li>`GET /v1/tellers`</li><li>`GET /v1/tellers/{tellerId}/cashiers`</li><li>`GET /v1/loans/{loanId}`</li><li>`POST /v1/loans/{loanId}?command=approve`</li><li>`POST /v1/loans/{loanId}?command=reject`</li><li>`GET /v1/loans`</li><li>`GET /v1/staff`</li><li>`GET /v1/staff/{staffId}`</li><li>`GET /v1/tellers/{tellerId}/cashiers/template`</li><li>`GET /v1/tellers/{tellerId}`</li><li>`POST /v1/tellers/{tellerId}/cashiers`</li><li>`GET /v1/offices`</li><li>`POST /v1/tellers`</li></ul> |

## Cashier App (`cashier-app`)

| Role | Allowed Endpoints |
| --- | --- |
| `cashier` | <ul><li>`GET /v1/userdetails`</li><li>`GET /v1/currencies`</li><li>`GET /v1/tellers`</li><li>`GET /v1/tellers/{tellerId}/cashiers`</li><li>`GET /v1/tellers/{tellerId}/cashiers/{cashierId}/summaryandtransactions`</li><li>`GET /v1/savingsaccounts/{accountId}`</li><li>`POST /v1/savingsaccounts/{savingsId}/transactions`</li><li>`GET /v1/paymenttypes`</li><li>`POST /v1/loans/{loanId}/transactions`</li><li>`GET /v1/loans`</li></ul> |

## Reporting App (`reporting-app`)

| Role | Allowed Endpoints |
| --- | --- |
| `reporting-user` | <ul><li>`GET /v1/audits`</li><li>`GET /v1/reports`</li><li>`GET /v1/loans`</li><li>`GET /v1/runreports/{reportName}`</li></ul> |
