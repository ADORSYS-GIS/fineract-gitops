# System Architecture Diagrams

This document contains detailed architecture diagrams for the Fineract GitOps platform.

---

## Table of Contents

1. [High-Level System Architecture](#high-level-system-architecture)
2. [Multi-Cloud Provider Architecture](#multi-cloud-provider-architecture)
3. [Multi-Instance Fineract](#multi-instance-fineract)
4. [Authentication Flow](#authentication-flow)
5. [Secrets Management Flow](#secrets-management-flow)
6. [GitOps Workflow](#gitops-workflow)
7. [Network Architecture](#network-architecture)
8. [Data Flow](#data-flow)
9. [Self-Service Data Flow](#self-service-data-flow)

---

## High-Level System Architecture

Complete system architecture showing all components:

```
┌─────────────────────────────────────────────────────────────────────┐
│                          End Users / Clients                        │
│         (Web Browsers, Mobile Apps, API Consumers)                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │ HTTPS
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Ingress Controller / Load Balancer               │
│                      (TLS Termination, Routing)                     │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Apache Gateway (OIDC)                          │
│              Authentication + Authorization Layer                   │
│                    (mod_auth_openidc)                              │
└──────────┬──────────────────┬──────────────────┬────────────────────┘
           │                  │                  │
     ┌─────▼─────┐    ┌───────▼────────┐  ┌─────▼──────┐
     │ Fineract  │    │   Fineract     │  │ Fineract   │
     │   Read    │    │    Write       │  │   Batch    │
     │(2-10 pods)│    │  (2-5 pods)    │  │  (1 pod)   │
     └─────┬─────┘    └───────┬────────┘  └─────┬──────┘
           │                  │                  │
           └──────────┬───────┴──────────────────┘
                      │
      ┌───────────────┼───────────────────────┐
      │               │                       │
  ┌───▼───┐      ┌────▼────┐          ┌──────▼──────┐
  │Postgres│      │  Redis  │          │   MinIO/S3  │
  │  SQL   │      │ (Cache) │          │  (Storage)  │
  └────────┘      └─────────┘          └─────────────┘
   Self-Hosted or Cloud-Managed         Self-Hosted or
   (RDS, Azure DB, Cloud SQL)           Cloud-Managed

┌─────────────────────────────────────────────────────────────────────┐
│                      Self-Service Layer                              │
├─────────────────┬────────────────────┬──────────────────────────────┤
│  Self-Service   │ Customer           │  Payment Gateway             │
│  App (PWA)      │ Registration Svc   │  Service                     │
└─────────────────┴────────────────────┴──────────────────────────────┘
                          │                      │
                          ▼                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    External Payment Providers                        │
├──────────────────────────────┬──────────────────────────────────────┤
│         MTN MoMo API         │        Orange Money API              │
│   (Collection/Disbursement)  │        (Web Payments)                │
└──────────────────────────────┴──────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      Supporting Services                            │
├──────────────┬──────────────┬──────────────┬─────────────┬──────────┤
│   Keycloak   │   Frontend   │   Message    │  Pentaho    │  Kafka   │
│   (SSO/IAM)  │     Apps     │   Gateway    │  Reports    │(Events)  │
└──────────────┴──────────────┴──────────────┴─────────────┴──────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      Observability Stack                            │
├────────────┬──────────────┬───────────────┬──────────────┬──────────┤
│ Prometheus │   Grafana    │     Loki      │  Promtail    │AlertMgr  │
│  (Metrics) │ (Dashboards) │    (Logs)     │(Collection)  │(Alerts)  │
└────────────┴──────────────┴───────────────┴──────────────┴──────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        GitOps Platform                              │
├──────────────────┬──────────────────────┬───────────────────────────┤
│      ArgoCD      │   Sealed Secrets     │     Cert-Manager          │
│   (Deployment)   │   (Encryption)       │    (TLS Certs)            │
└──────────────────┴──────────────────────┴───────────────────────────┘
```

---

## Multi-Cloud Provider Architecture

How provider abstraction enables multi-cloud deployment:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Environment Selection                         │
│   (Kustomize Overlay selects provider component)                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                  ┌────────▼────────┐
                  │  Kustomize      │
                  │  Component      │
                  │  Abstraction    │
                  └────────┬────────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
┌───▼────────┐      ┌──────▼──────┐        ┌─────▼─────┐
│Self-Hosted │      │     AWS     │        │   Azure   │  ...
│ Provider   │      │   Provider  │        │  Provider │
└─────┬──────┘      └──────┬──────┘        └─────┬─────┘
      │                    │                      │
┌─────▼──────┐      ┌──────▼───────┐      ┌──────▼──────┐
│PostgreSQL  │      │   RDS        │      │ Azure DB    │
│StatefulSet │      │   (Managed)  │      │ (Managed)   │
└────────────┘      └──────────────┘      └─────────────┘
┌────────────┐      ┌──────────────┐      ┌─────────────┐
│   Redis    │      │ ElastiCache  │      │ Redis Cache │
│StatefulSet │      │   (Managed)  │      │ (Managed)   │
└────────────┘      └──────────────┘      └─────────────┘
┌────────────┐      ┌──────────────┐      ┌─────────────┐
│   MinIO    │      │      S3      │      │ Blob Storage│
│StatefulSet │      │   (Managed)  │      │ (Managed)   │
└────────────┘      └──────────────┘      └─────────────┘
```

**Key Points**:
- Single application code
- Swappable infrastructure
- Provider selected via Kustomize
- Zero code changes needed

---

## Multi-Instance Fineract

Separate instances for read, write, and batch workloads:

```
┌────────────────────────────────────────────────────┐
│            Apache Gateway                          │
│         (Request Routing Logic)                    │
└──────────┬─────────────┬──────────────┬───────────┘
           │             │              │
    ┌──────▼──────┐ ┌────▼─────┐  ┌────▼──────┐
    │ GET /api/*  │ │POST/PUT  │  │ /jobs/*   │
    │             │ │DELETE    │  │           │
    └──────┬──────┘ └────┬─────┘  └────┬──────┘
           │             │              │
     ┌─────▼──────┐ ┌────▼──────┐ ┌────▼────────┐
     │ Fineract   │ │ Fineract  │ │  Fineract   │
     │   Read     │ │  Write    │ │   Batch     │
     ├────────────┤ ├───────────┤ ├─────────────┤
     │2-10 pods   │ │ 2-5 pods  │ │   1 pod     │
     │            │ │           │ │             │
     │Read-only   │ │Transact-  │ │Scheduled    │
     │queries     │ │ions       │ │jobs         │
     │            │ │           │ │             │
     │Scales      │ │Moderate   │ │Singleton    │
     │horizontally│ │scaling    │ │             │
     └─────┬──────┘ └────┬──────┘ └────┬────────┘
           │             │              │
           └─────────────┴──────────────┘
                         │
                  ┌──────▼──────┐
                  │ PostgreSQL  │
                  │  (Shared)   │
                  └─────────────┘
```

**Benefits**:
- Independent scaling
- Resource isolation
- Better performance
- Batch jobs don't impact users

---

## Authentication Flow

Complete authentication flow with Keycloak SSO:

```
┌─────────┐
│  User   │
└────┬────┘
     │ 1. Access Fineract URL
     ▼
┌─────────────────┐
│ Apache Gateway  │
│(mod_auth_openidc│
└────┬────────────┘
     │ 2. No token, redirect to Keycloak
     ▼
┌─────────────────┐
│   Keycloak      │  ← 3. User enters credentials
│   (OIDC IdP)    │
└────┬────────────┘
     │ 4. Validates credentials
     │ 5. Returns OIDC token (JWT)
     ▼
┌─────────────────┐
│ Apache Gateway  │  ← 6. Validates token
│                 │  ← 7. Extracts user info
└────┬────────────┘
     │ 8. Forwards request with user context
     ▼
┌─────────────────┐
│   Fineract      │  ← 9. Checks permissions
│                 │  ← 10. Processes request
└─────────────────┘
```

**Security Features**:
- OIDC standard (OAuth 2.0 + ID)
- JWT tokens (signed, expiring)
- Single Sign-On (SSO)
- Centralized user management
- Role-based access control (RBAC)

---

## Secrets Management Flow

How Sealed Secrets works in GitOps workflow:

```
Developer Workstation:
┌──────────────────┐
│ 1. Create Secret │
│    (plaintext)   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  2. kubeseal     │ ← Fetches cluster public key
│    (encrypt)     │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│3. SealedSecret   │
│  (encrypted)     │
└────────┬─────────┘
         │ 4. Commit to Git
         ▼
    ┌────────┐
    │  Git   │
    │  Repo  │
    └────┬───┘
         │ 5. ArgoCD detects change
         ▼
    ┌────────────┐
    │   ArgoCD   │
    └────┬───────┘
         │ 6. Syncs SealedSecret
         ▼
┌────────────────────────┐
│   Kubernetes Cluster   │
│  ┌──────────────────┐  │
│  │ SealedSecret     │  │
│  │  (encrypted)     │  │
│  └────────┬─────────┘  │
│           │            │
│           ▼            │
│  ┌──────────────────┐  │
│  │Sealed Secrets    │  │
│  │   Controller     │  │ ← Has private key
│  └────────┬─────────┘  │
│           │ 7. Decrypts
│           ▼            │
│  ┌──────────────────┐  │
│  │  Secret          │  │
│  │  (plaintext)     │  │
│  └────────┬─────────┘  │
│           │            │
│           ▼            │
│  ┌──────────────────┐  │
│  │  Application Pod │  │
│  │  (uses secret)   │  │
│  └──────────────────┘  │
└────────────────────────┘
```

**Security**:
- Private key never leaves cluster
- Encrypted at rest in Git
- Decryption only in cluster
- Audit trail in Git history

---

## GitOps Workflow

Complete GitOps deployment flow with ArgoCD:

```
Developer:
┌──────────────┐
│1. Make change│
│   (YAML)     │
└──────┬───────┘
       │ 2. Commit
       ▼
  ┌────────┐
  │  Git   │ ← Source of Truth
  │  Repo  │
  └────┬───┘
       │ 3. ArgoCD polls (or webhook)
       ▼
┌──────────────────────┐
│      ArgoCD          │
│  ┌────────────────┐  │
│  │  Application   │  │
│  │  Controller    │  │
│  └────────┬───────┘  │
│           │          │
│           ▼          │
│  ┌────────────────┐  │
│  │   Sync Logic   │  │ ← 4. Compare desired vs actual
│  └────────┬───────┘  │
│           │          │
│           ▼          │
│  ┌────────────────┐  │
│  │   Deploy       │  │ ← 5. Apply changes
│  └────────┬───────┘  │
└───────────┼──────────┘
            │ 6. kubectl apply
            ▼
┌────────────────────────┐
│ Kubernetes Cluster     │
│ ┌────────────────────┐ │
│ │  Fineract Pods     │ │
│ └────────────────────┘ │
│ ┌────────────────────┐ │
│ │  Database          │ │
│ └────────────────────┘ │
│ ┌────────────────────┐ │
│ │  Services          │ │
│ └────────────────────┘ │
└────────────────────────┘
            │
            │ 7. Health checks
            ▼
    ┌──────────────┐
    │   ArgoCD     │ ← 8. Updates status
    │   Dashboard  │
    └──────────────┘
```

**Advantages**:
- Git as single source of truth
- Automated deployments
- Rollback capability
- Audit trail
- Declarative configuration

---

## Network Architecture

Network topology and security zones:

```
┌─────────────────────────────────────────────────────┐
│                  Internet / Users                    │
└──────────────────────┬──────────────────────────────┘
                       │ HTTPS (443)
                ┌──────▼──────┐
                │Load Balancer│
                │   (Cloud)   │
                └──────┬──────┘
                       │
┌──────────────────────┴──────────────────────────────┐
│           Kubernetes Cluster (VPC/VNet)             │
│                                                     │
│  ┌─────────────────────────────────────────────┐  │
│  │     Public Subnet (DMZ)                     │  │
│  │  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │   Ingress    │  │Apache Gateway│        │  │
│  │  │  Controller  │  │              │        │  │
│  │  └──────┬───────┘  └──────┬───────┘        │  │
│  └─────────┼──────────────────┼────────────────┘  │
│            │                  │                    │
│  ┌─────────▼──────────────────▼────────────────┐  │
│  │     Private Subnet (Applications)           │  │
│  │  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │  │
│  │  │Fineract  │ │Keycloak  │ │ Frontend    │ │  │
│  │  │  Pods    │ │          │ │    Apps     │ │  │
│  │  └──────┬───┘ └──────────┘ └─────────────┘ │  │
│  └─────────┼──────────────────────────────────┘  │
│            │                                      │
│  ┌─────────▼──────────────────────────────────┐  │
│  │   Private Subnet (Data Tier)               │  │
│  │  ┌──────────┐ ┌──────────┐ ┌────────────┐ │  │
│  │  │PostgreSQL│ │  Redis   │ │   MinIO    │ │  │
│  │  │          │ │          │ │            │ │  │
│  │  └──────────┘ └──────────┘ └────────────┘ │  │
│  │  (or Cloud-Managed Services)              │  │
│  └────────────────────────────────────────────┘  │
│                                                   │
│  NetworkPolicies:                                │
│  - DMZ → Apps: Allow                             │
│  - Apps → Data: Allow                            │
│  - Data → Apps: Deny (stateful allowed)          │
│  - External → Data: Deny                         │
└───────────────────────────────────────────────────┘
```

**Security Zones**:
1. **Public (DMZ)**: Load balancer, ingress
2. **Application**: Fineract, Keycloak, apps
3. **Data**: Databases, cache, storage

---

## Data Flow

How data flows through the system:

```
User Request → Response Journey:

1. User Action
   ┌─────────┐
   │  User   │ "Transfer $100"
   └────┬────┘
        │
        ▼
2. HTTPS Request
   ┌─────────────┐
   │   Browser   │ POST /api/v1/transfers
   └──────┬──────┘
          │
          ▼
3. Authentication
   ┌──────────────┐
   │Apache Gateway│ Validates OIDC token
   └──────┬───────┘
          │
          ▼
4. Route to Write Instance
   ┌──────────────┐
   │Fineract Write│ Processes transaction
   └──────┬───────┘
          │
          ▼
5. Database Transaction
   ┌──────────────┐
   │  PostgreSQL  │ BEGIN; UPDATE ...; COMMIT;
   └──────┬───────┘
          │
          ▼
6. Cache Invalidation
   ┌──────────────┐
   │    Redis     │ DEL user:123:balance
   └──────┬───────┘
          │
          ▼
7. Response
   ┌──────────────┐
   │Apache Gateway│ Returns 200 OK
   └──────┬───────┘
          │
          ▼
   ┌──────────────┐
   │   Browser    │ Shows success message
   └──────────────┘
```

---

## Self-Service Data Flow

How customer self-service requests flow through the system:

### Customer Registration Flow

```
1. Customer Registration
   ┌────────────────┐
   │ Self-Service   │ POST /register
   │    App         │
   └───────┬────────┘
           │
           ▼
2. Registration Service
   ┌────────────────────┐
   │ Customer           │ Create Fineract Client
   │ Registration Svc   │ Create Savings Account
   └───────┬────────────┘
           │
           ├───────────────────┐
           ▼                   ▼
3. Backend Systems
   ┌───────────┐       ┌───────────┐
   │ Fineract  │       │ Keycloak  │
   │  Write    │       │ (Create   │
   └───────────┘       │   User)   │
                       └───────────┘
```

### Mobile Money Deposit Flow

```
1. Deposit Request
   ┌────────────────┐
   │ Self-Service   │ POST /deposits/mtn
   │    App         │
   └───────┬────────┘
           │
           ▼
2. Payment Gateway
   ┌────────────────┐
   │ Payment        │ Initiates collection
   │ Gateway Svc    │
   └───────┬────────┘
           │
           ▼
3. MTN MoMo API
   ┌────────────────┐
   │  MTN MoMo      │ Request to Pay
   │    API         │ Customer approves
   └───────┬────────┘
           │ Callback
           ▼
4. Create Transaction
   ┌────────────────┐       ┌───────────┐
   │ Payment        │──────▶│ Fineract  │
   │ Gateway Svc    │       │  Write    │
   └────────────────┘       └───────────┘
```

### View Transactions Flow (Direct to Fineract)

```
1. View Request
   ┌────────────────┐
   │ Self-Service   │ GET /savingsaccounts/{id}/transactions
   │    App         │
   └───────┬────────┘
           │
           ▼
2. Direct API Call
   ┌────────────────┐
   │  Fineract      │ Read-only query
   │   Read         │
   └───────┬────────┘
           │
           ▼
3. Response
   ┌────────────────┐
   │ Self-Service   │ Display transactions
   │    App         │
   └────────────────┘
```

### KYC Document Upload Flow

```
1. Upload Request
   ┌────────────────┐
   │ Self-Service   │ POST /kyc/documents
   │    App         │ (id_front, id_back, selfie)
   └───────┬────────┘
           │
           ▼
2. Registration Service
   ┌────────────────────┐
   │ Customer           │ Validate & process
   │ Registration Svc   │
   └───────┬────────────┘
           │
           ├───────────────────┐
           ▼                   ▼
3. Backend Systems
   ┌───────────────┐   ┌───────────────┐
   │   Fineract    │   │   Keycloak    │
   │   (Document   │   │  (Update KYC  │
   │    Upload)    │   │    Status)    │
   └───────────────┘   └───────────────┘
```

**API Routing Summary:**

| Operation | Route | Reason |
|-----------|-------|--------|
| Login/Auth | Self-Service → Keycloak | OIDC authentication |
| View account | Self-Service → Fineract (direct) | Read-only, no business logic needed |
| View transactions | Self-Service → Fineract (direct) | Read-only, no business logic needed |
| Registration | Self-Service → CRS → Fineract/KC | Creates accounts in multiple systems |
| KYC upload | Self-Service → CRS → Fineract | Needs validation, status tracking |
| Deposits | Self-Service → PGS → MTN/Orange → Fineract | Payment provider integration |
| Withdrawals | Self-Service → PGS → MTN/Orange → Fineract | Payment provider integration |

---

## References

- [Architecture README](README.md)
- [ADR-001: Multi-Cloud Providers](ADR-001-multi-cloud-providers.md)
- [ADR-002: Multi-Instance Fineract](ADR-002-multi-instance-fineract.md)
- [ADR-003: Sealed Secrets](ADR-003-sealed-secrets.md)

---

**Last Updated:** 2025-10-28
**Diagrams:** ASCII (for version control)
**Future**: Consider Mermaid.js or PlantUML for interactive diagrams
