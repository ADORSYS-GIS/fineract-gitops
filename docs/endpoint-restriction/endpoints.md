# Fineract Frontend API Endpoints

This document lists all the API endpoints used by the Fineract frontend applications.

## Account Manager App (`account-manager-app`)

| Method | Endpoint |
| --- | --- |
| POST | `/v1/authentication` |
| POST | `/v1/clients` |
| GET | `/v1/runreports/Savings%20Transactions` |
| GET | `/v1/clients/{clientId}` |
| GET | `/v1/clients/{clientId}/accounts` |
| POST | `/v1/savingsaccounts/{accountId}?command=activate` |
| DELETE | `/v1/loans/{loanId}` |
| DELETE | `/v1/savingsaccounts/{accountId}` |
| GET | `/v1/clients/{entityId}/images` |
| POST | `/v1/clients/{entityId}/images` |
| DELETE | `/v1/clients/{entityId}/images` |
| GET | `/v1/clients` |
| POST | `/v2/clients/search` |
| GET | `/v1/offices` |
| GET | `/v1/loans/{loanId}` |
| POST | `/v1/loans` |
| PUT | `/v1/loans/{loanId}` |
| GET | `/v1/loans/template` |
| POST | `/v1/loans?command=calculateLoanSchedule` |
| GET | `/v1/savingsproducts` |
| GET | `/v1/loanproducts` |
| GET | `/v1/products/{type}` |
| GET | `/v1/recurringdepositproducts` |
| GET | `/v1/fixeddepositproducts` |
| POST | `/v1/savingsaccounts` |
| POST | `/v1/accounts/{type}` |
| GET | `/v1/savingsaccounts/{accountId}` |
| POST | `/v1/savingsaccounts/{accountId}?command=unblock` |
| GET | `/v1/codes/{codeId}/codevalues` |
| POST | `/v1/savingsaccounts/{accountId}?command=block` |

## Accounting App (`accounting-app`)

| Method | Endpoint |
| --- | --- |
| GET | `/v1/makercheckers` |
| GET | `/v1/offices` |
| POST | `/v1/glclosures` |
| GET | `/v1/glaccounts` |
| GET | `/v1/currencies` |
| GET | `/v1/paymenttypes` |
| POST | `/v1/journalentries` |
| GET | `/v1/journalentries` |
| DELETE | `/v1/glaccounts/{glAccountId}` |
| GET | `/v1/journalentries/{journalEntryId}` |
| POST | `/v1/journalentries/{transactionId}` |
| POST | `/v1/makercheckers/{auditId}` |

## Admin App (`admin-app`)

| Method | Endpoint |
| --- | --- |
| POST | `/v1/adorsys/employees` |
| GET | `/v1/adorsys/employees` |
| GET | `/v1/adorsys/employees/{userId}` |
| PUT | `/v1/adorsys/employees/{userId}` |
| POST | `/api/user-sync/sync/user` |
| POST | `/api/user-sync/users/{username}/reset-password` |
| PUT | `/api/user-sync/users/{username}/status` |
| POST | `/api/user-sync/users/{username}/force-password-change` |
| GET | `/api/user-sync/users/{username}/keycloak-status` |
| GET | `/v1/roles` |
| GET | `/v1/offices` |
| GET | `/v1/users` |

## Branch Manager App (`branchmanager-app`)

| Method | Endpoint |
| --- | --- |
| GET | `/v1/savingsaccounts` |
| GET | `/v1/savingsaccounts/{accountId}` |
| POST | `/v1/savingsaccounts/{accountId}?command=approve` |
| POST | `/v1/tellers/{tellerId}/cashiers/{cashierId}/allocate` |
| POST | `/v1/tellers/{tellerId}/cashiers/{cashierId}/settle` |
| GET | `/v1/tellers/{tellerId}/cashiers/{cashierId}` |
| GET | `/v1/tellers/{tellerId}/cashiers/{cashierId}/summaryandtransactions` |
| GET | `/v1/tellers` |
| GET | `/v1/tellers/{tellerId}/cashiers` |
| GET | `/v1/loans/{loanId}` |
| POST | `/v1/loans/{loanId}?command=approve` |
| POST | `/v1/loans/{loanId}?command=reject` |
| GET | `/v1/loans` |
| GET | `/v1/staff` |
| GET | `/v1/staff/{staffId}` |
| GET | `/v1/tellers/{tellerId}/cashiers/template` |
| GET | `/v1/tellers/{tellerId}` |
| POST | `/v1/tellers/{tellerId}/cashiers` |
| GET | `/v1/offices` |
| POST | `/v1/tellers` |

## Reporting App (`reporting-app`)

| Method | Endpoint |
| --- | --- |
| GET | `/v1/audits` |
| GET | `/v1/reports` |
| GET | `/v1/loans` |
| GET | `/v1/runreports/{reportName}` |

## Cashier App (`cashier-app`)

| Method | Endpoint |
| --- | --- |
| GET | `/v1/userdetails` |
| GET | `/v1/currencies` |
| GET | `/v1/tellers` |
| GET | `/v1/tellers/{tellerId}/cashiers` |
| GET | `/v1/tellers/{tellerId}/cashiers/{cashierId}/summaryandtransactions` |
| GET | `/v1/savingsaccounts/{accountId}` |
| POST | `/v1/savingsaccounts/{savingsId}/transactions` |
| GET | `/v1/paymenttypes` |
| POST | `/v1/loans/{loanId}/transactions` |
| GET | `/v1/loans` |

