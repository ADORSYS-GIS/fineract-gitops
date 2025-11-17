# Fineract GitOps Architecture

This document provides a comprehensive overview of the fineract-gitops architecture, including system components, network flows, multi-cloud deployment options, and Kubernetes resource topology.

## Table of Contents

- [Overview](#overview)
- [High-Level System Architecture](#high-level-system-architecture)
- [Network Flow Diagrams](#network-flow-diagrams)
  - [Authentication Flow](#authentication-flow)
  - [Read Operation Flow](#read-operation-flow)
  - [Write Operation Flow](#write-operation-flow)
  - [Batch Job Flow](#batch-job-flow)
- [Multi-Cloud Provider Comparison](#multi-cloud-provider-comparison)
- [Deployment Architecture](#deployment-architecture)
- [Kubernetes Resource Topology](#kubernetes-resource-topology)
- [Deployment Profiles](#deployment-profiles)
- [Environment Configurations](#environment-configurations)
- [Related Documentation](#related-documentation)

---

## Overview

The fineract-gitops repository implements a **production-ready, multi-cloud GitOps infrastructure** for Apache Fineract with:

- **Multi-instance Fineract deployment** with read/write/batch separation for high availability
- **4 deployment profiles** (minimal, standard, full) per environment
- **4 infrastructure providers** (self-hosted, AWS, Azure, GCP)
- **Complete identity management** with Keycloak, OAuth2 Proxy, and WebAuthn 2FA
- **Full observability** with Prometheus, Grafana, and Loki
- **Disaster recovery** with Velero and automated backups
- **40-55% cost savings** with in-cluster Redis vs managed cache services
- **GitOps automation** with ArgoCD using the app-of-apps pattern

---

## High-Level System Architecture

The following diagram shows the main components of the Fineract system and their relationships:

```mermaid
graph TB
    subgraph "User Interface Layer"
        WebUser[Web Users]
        MobileUser[Mobile Users]
        APIClient[API Clients]
    end

    subgraph "Ingress & Gateway Layer"
        Ingress[Ingress Controller<br/>nginx-ingress]
        OAuth2Proxy[OAuth2 Proxy<br/>OIDC Auth + Routing]
    end

    subgraph "Identity & Authentication"
        Keycloak[Keycloak<br/>SSO/OIDC Provider<br/>WebAuthn 2FA]
        UserSync[User Sync Service<br/>Password Reset]
    end

    subgraph "Fineract Core Banking Platform"
        FineractRead[Fineract Read<br/>1 replica<br/>Query operations]
        FineractWrite[Fineract Write<br/>1 replica HA<br/>Data modifications]
        FineractBatch[Fineract Batch<br/>1 replica<br/>Scheduled jobs]
    end

    subgraph "Data Layer"
        PostgreSQL[(PostgreSQL 15.x<br/>Primary + Replicas<br/>Banking data)]
        Redis[(In-cluster Redis<br/>StatefulSet 768MB LRU<br/>Session + Query cache)]
        S3[(AWS S3<br/>Document storage<br/>Report files)]
    end

    subgraph "Integration Services"
        SMTPSender[Direct SMTP/SMS<br/>Email & SMS<br/>via AWS SES/SNS]
        Pentaho[Pentaho Reports<br/>Financial reporting]
    end

    subgraph "Observability Stack"
        Prometheus[Prometheus<br/>Metrics collection]
        Grafana[Grafana<br/>Dashboards]
        Loki[Loki + Promtail<br/>Log aggregation]
    end

    subgraph "Infrastructure Services"
        SealedSecrets[Sealed Secrets<br/>Encrypted secrets]
        CertManager[Cert Manager<br/>TLS certificates]
        ArgoRollouts[Argo Rollouts<br/>Progressive Delivery]
        NetworkPolicies[Network Policies<br/>Pod security]
    end

    %% User to Ingress
    WebUser --> Ingress
    MobileUser --> Ingress
    APIClient --> Ingress

    %% Ingress to Gateway
    Ingress --> OAuth2Proxy

    %% Gateway routing
    OAuth2Proxy --> Keycloak
    OAuth2Proxy --> FineractRead
    OAuth2Proxy --> FineractWrite

    %% Fineract to data layer
    FineractRead --> PostgreSQL
    FineractRead --> Redis
    FineractWrite --> PostgreSQL
    FineractWrite --> Redis
    FineractBatch --> PostgreSQL
    FineractBatch --> S3
    FineractBatch --> SMTPSender

    %% User sync
    FineractWrite --> UserSync
    UserSync --> Keycloak

    %% Reporting
    FineractRead --> Pentaho
    Pentaho --> S3

    %% Observability
    FineractRead -.-> Prometheus
    FineractWrite -.-> Prometheus
    FineractBatch -.-> Prometheus
    PostgreSQL -.-> Prometheus
    Keycloak -.-> Prometheus
    Prometheus --> Grafana
    FineractRead -.-> Loki
    FineractWrite -.-> Loki

    %% Infrastructure
    SealedSecrets -.-> FineractWrite
    CertManager -.-> Ingress
    NetworkPolicies -.-> FineractRead

    classDef frontend fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef backend fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef data fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef infra fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef obs fill:#fff9c4,stroke:#f57f17,stroke-width:2px

    class WebUser,MobileUser,APIClient frontend
    class OAuth2Proxy,FineractRead,FineractWrite,FineractBatch,Keycloak,UserSync,SMTPSender,Pentaho backend
    class PostgreSQL,Redis,S3 data
    class Ingress,SealedSecrets,CertManager,ArgoRollouts,NetworkPolicies infra
    class Prometheus,Grafana,Loki obs
```

---

## Network Flow Diagrams

### Authentication Flow

This diagram shows how users authenticate through Keycloak with WebAuthn 2FA support:

```mermaid
sequenceDiagram
    participant User as Web User
    participant Browser as Browser
    participant OAuth2 as OAuth2 Proxy
    participant Keycloak as Keycloak
    participant Fineract as Fineract API
    participant DB as PostgreSQL

    User->>Browser: Access Fineract app
    Browser->>OAuth2: GET /app
    OAuth2->>OAuth2: No valid session
    OAuth2->>Keycloak: Redirect to /auth
    Keycloak->>User: Login page
    User->>Keycloak: Username + Password
    Keycloak->>DB: Validate credentials
    DB-->>Keycloak: User valid
    Keycloak->>User: WebAuthn 2FA prompt<br/>(Face ID, Touch ID, Security Key)
    User->>Keycloak: Biometric auth
    Keycloak->>Keycloak: Generate JWT tokens<br/>Access: 15min<br/>Session: 30min
    Keycloak-->>OAuth2: Redirect with tokens
    OAuth2->>OAuth2: Store session
    OAuth2-->>Browser: Redirect to app + cookie
    Browser->>OAuth2: GET /app (with cookie)
    OAuth2->>OAuth2: Validate session
    OAuth2-->>Browser: App page

    Note over Browser,Fineract: Subsequent API calls

    Browser->>OAuth2: GET /api/clients (with JWT)
    OAuth2->>OAuth2: Validate JWT
    OAuth2->>Fineract: Forward request + JWT
    Fineract->>Keycloak: Verify JWT signature
    Keycloak-->>Fineract: Token valid + roles
    Fineract->>DB: Query clients
    DB-->>Fineract: Client data
    Fineract-->>OAuth2: JSON response
    OAuth2-->>Browser: JSON response
```

### Read Operation Flow

This diagram shows how read requests are routed and cached:

```mermaid
sequenceDiagram
    participant Client as Client
    participant OAuth2 as OAuth2 Proxy
    participant FineractR as Fineract Read<br/>(3 replicas)
    participant Redis as In-cluster Redis<br/>StatefulSet
    participant PG as PostgreSQL<br/>(Read Replica)

    Client->>OAuth2: GET /api/v1/clients/123<br/>(with JWT)
    OAuth2->>OAuth2: Validate JWT<br/>Check HTTP method = GET
    OAuth2->>FineractR: Route to Read instance

    FineractR->>Redis: Check cache<br/>Key: clients:123

    alt Cache Hit
        Redis-->>FineractR: Cached data (50ms)
        FineractR-->>OAuth2: JSON response
        OAuth2-->>Client: 200 OK (50-100ms)
    else Cache Miss
        Redis-->>FineractR: Cache miss
        FineractR->>PG: SELECT * FROM clients<br/>WHERE id = 123
        PG-->>FineractR: Client data (200ms)
        FineractR->>Redis: Store in cache<br/>TTL: 5 minutes
        Redis-->>FineractR: Cached
        FineractR-->>OAuth2: JSON response
        OAuth2-->>Client: 200 OK (200-300ms)
    end

    Note over Client,PG: 60-80% faster with in-cluster Redis cache
```

### Write Operation Flow

This diagram shows how write requests are processed and synchronized:

```mermaid
sequenceDiagram
    participant Client as Client
    participant OAuth2 as OAuth2 Proxy
    participant FineractW as Fineract Write<br/>(2 replicas HA)
    participant PG as PostgreSQL<br/>(Primary)
    participant Redis as In-cluster Redis<br/>StatefulSet
    participant Kafka as Kafka<br/>(optional)
    participant UserSync as User Sync Service
    participant Keycloak as Keycloak

    Client->>OAuth2: POST /api/v1/clients<br/>(with JWT + data)
    OAuth2->>OAuth2: Validate JWT<br/>Check HTTP method = POST
    OAuth2->>FineractW: Route to Write instance

    FineractW->>FineractW: Validate request<br/>Check permissions
    FineractW->>PG: BEGIN TRANSACTION
    PG-->>FineractW: Transaction started

    FineractW->>PG: INSERT INTO clients<br/>VALUES (...)
    PG-->>FineractW: Client created (ID: 456)

    FineractW->>PG: INSERT INTO audit_log<br/>VALUES (...)
    PG-->>FineractW: Audit logged

    FineractW->>PG: COMMIT
    PG-->>FineractW: Transaction committed

    par Async operations
        FineractW->>Redis: Invalidate cache<br/>Pattern: clients:*
        Redis-->>FineractW: Cache cleared
    and
        FineractW->>Kafka: Publish event<br/>client.created
        Kafka-->>FineractW: Event published
    end

    FineractW-->>OAuth2: 201 Created<br/>Location: /api/v1/clients/456
    OAuth2-->>Client: 201 Created

    Note over Client,Keycloak: Password reset flow (if applicable)

    opt User password change
        FineractW->>UserSync: Notify user change
        UserSync->>Keycloak: Update user password<br/>via Admin API
        Keycloak-->>UserSync: Password updated
    end
```

### Batch Job Flow

This diagram shows how scheduled batch jobs process transactions:

```mermaid
sequenceDiagram
    participant Cron as Kubernetes CronJob
    participant FineractB as Fineract Batch<br/>(3 replicas)
    participant PG as PostgreSQL
    participant Redis as In-cluster Redis<br/>StatefulSet
    participant S3 as AWS S3
    participant SMTP as Direct SMTP/SMS<br/>(AWS SES/SNS)
    participant Customer as Customer

    Note over Cron,FineractB: Daily batch jobs (02:00 UTC)

    Cron->>FineractB: Trigger job<br/>applyInterest

    FineractB->>PG: SELECT active_savings_accounts<br/>WHERE interest_due = true
    PG-->>FineractB: 1,500 accounts

    loop Process each account
        FineractB->>PG: BEGIN TRANSACTION
        FineractB->>PG: Calculate interest<br/>Update balance
        FineractB->>PG: INSERT transaction
        FineractB->>PG: COMMIT
        PG-->>FineractB: Interest applied
    end

    FineractB->>Redis: Invalidate account caches
    Redis-->>FineractB: Caches cleared

    FineractB->>FineractB: Generate report<br/>InterestAppliedReport.pdf

    FineractB->>S3: Upload report<br/>reports/interest-2025-10-28.pdf<br/>(via IRSA)
    S3-->>FineractB: Report stored

    FineractB->>SMTP: Send notification batch<br/>1,500 customers

    par Parallel notifications
        SMTP->>Customer: SMS via AWS SNS<br/>"Interest credited: $12.50"
    and
        SMTP->>Customer: Email via AWS SES<br/>"Monthly interest statement"
    end

    SMTP-->>FineractB: Notifications sent
    FineractB-->>Cron: Job completed<br/>Status: SUCCESS

    Note over Cron,FineractB: Job metrics sent to Prometheus
```

---

## Multi-Cloud Provider Comparison

This diagram compares the different infrastructure provider options:

```mermaid
graph TB
    subgraph "Self-Hosted (Kubernetes)"
        SH_PG[(PostgreSQL StatefulSet<br/>1 primary + 2 replicas<br/>50GB storage)]
        SH_Redis[(In-cluster Redis<br/>StatefulSet 768MB<br/>AOF persistence)]
        SH_S3[(S3-compatible storage<br/>Local object storage<br/>100GB)]
        SH_Cost[Cost: ~$30-40/month<br/>K3s cluster]
    end

    subgraph "AWS Managed Services"
        AWS_RDS[(RDS PostgreSQL 15.x<br/>db.t3.medium<br/>Multi-AZ)]
        AWS_Cache[(In-cluster Redis<br/>StatefulSet 768MB<br/>Cost: $0)]
        AWS_S3[(S3 Buckets<br/>Standard storage<br/>Lifecycle policies<br/>IRSA access)]
        AWS_Cost[Cost: ~$90-110/month<br/>EKS cluster<br/><br/>$40-50/month with K3s<br/>55% savings vs ElastiCache]
    end

    subgraph "Azure Managed Services"
        Azure_DB[(Azure Database<br/>PostgreSQL 15.x Flexible<br/>Multi-zone HA)]
        Azure_Cache[(In-cluster Redis<br/>StatefulSet 768MB<br/>Cost: $0)]
        Azure_Blob[(Azure Blob Storage<br/>Hot tier<br/>Geo-redundant)]
        Azure_Cost[Cost: ~$90-120/month<br/>AKS cluster<br/>36% savings vs managed cache]
    end

    subgraph "GCP Managed Services"
        GCP_SQL[(Cloud SQL<br/>PostgreSQL 15.x HA<br/>Regional instances)]
        GCP_Redis[(In-cluster Redis<br/>StatefulSet 768MB<br/>Cost: $0)]
        GCP_GCS[(Cloud Storage<br/>Standard class<br/>Multi-region)]
        GCP_Cost[Cost: ~$85-110/month<br/>GKE cluster<br/>34% savings vs Memorystore]
    end

    subgraph "Fineract Application Layer"
        Fineract[Fineract Instances<br/>Read + Write + Batch]
    end

    %% Connections
    Fineract -.->|Self-hosted| SH_PG
    Fineract -.->|Self-hosted| SH_Redis
    Fineract -.->|Self-hosted| SH_S3

    Fineract -.->|AWS| AWS_RDS
    Fineract -.->|AWS| AWS_Cache
    Fineract -.->|AWS| AWS_S3

    Fineract -.->|Azure| Azure_DB
    Fineract -.->|Azure| Azure_Cache
    Fineract -.->|Azure| Azure_Blob

    Fineract -.->|GCP| GCP_SQL
    Fineract -.->|GCP| GCP_Redis
    Fineract -.->|GCP| GCP_GCS

    classDef selfhosted fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef aws fill:#ff9800,stroke:#e65100,stroke-width:2px
    classDef azure fill:#2196f3,stroke:#0d47a1,stroke-width:2px
    classDef gcp fill:#f44336,stroke:#b71c1c,stroke-width:2px
    classDef app fill:#9c27b0,stroke:#4a148c,stroke-width:2px

    class SH_PG,SH_Redis,SH_S3,SH_Cost selfhosted
    class AWS_RDS,AWS_Cache,AWS_S3,AWS_Cost aws
    class Azure_DB,Azure_Cache,Azure_Blob,Azure_Cost azure
    class GCP_SQL,GCP_Redis,GCP_GCS,GCP_Cost gcp
    class Fineract app
```

### Provider Feature Comparison

| Feature | Self-Hosted | AWS | Azure | GCP |
|---------|-------------|-----|-------|-----|
| **Database** | PostgreSQL 15.x StatefulSet | RDS PostgreSQL 15.x Multi-AZ | Azure PostgreSQL 15.x Flexible | Cloud SQL PostgreSQL 15.x HA |
| **Automatic Backups** | Manual (Velero) | Automated (7-30 days) | Automated (7-35 days) | Automated (7-365 days) |
| **Cache** | In-cluster Redis StatefulSet | In-cluster Redis StatefulSet | In-cluster Redis StatefulSet | In-cluster Redis StatefulSet |
| **Object Storage** | S3-compatible | AWS S3 (IRSA) | Blob Storage | Cloud Storage |
| **HA Setup** | Manual replicas | Built-in Multi-AZ | Zone-redundant | Regional HA |
| **Monitoring** | Prometheus/Grafana | CloudWatch + Prometheus | Azure Monitor + Prometheus | Cloud Monitoring + Prometheus |
| **Secrets** | Sealed Secrets | Sealed Secrets + AWS Secrets Manager | Sealed Secrets + Key Vault | Sealed Secrets + Secret Manager |
| **Auth Integration** | None | IRSA (IAM Roles for Service Accounts) | Workload Identity | Workload Identity |
| **Cost (Dev)** | $30-40/month | $40-50 (K3s)<br/>$90-110 (EKS) | $90-120/month | $85-110/month |
| **Cost (Prod)** | $100-150/month | $400-500/month | $380-470/month | $370-460/month |
| **Setup Complexity** | Low (Kustomize) | Medium (Terraform + IRSA) | Medium (Terraform) | Medium (Terraform) |
| **Operational Overhead** | High | Low | Low | Low |

---

## Deployment Architecture

This diagram shows the GitOps workflow and Kustomize layering:

```mermaid
graph TB
    subgraph "Git Repository (Source of Truth)"
        GitMain[main branch<br/>Production-ready]
        GitDev[develop branch<br/>Development]
    end

    subgraph "ArgoCD (GitOps Orchestration)"
        ArgoApp[ArgoCD Application<br/>App-of-Apps pattern]
        ArgoDev[Dev Environment<br/>Auto-sync: ON]
        ArgoUAT[UAT Environment<br/>Auto-sync: OFF]
        ArgoProd[Production Environment<br/>Auto-sync: OFF<br/>Sync window: Tue-Thu 10AM-4PM]
    end

    subgraph "Kustomize Structure"
        Base[apps/*/base/<br/>Common configs]
        Overlays[apps/*/overlays/<br/>Environment-specific]
        Components[components/providers/<br/>Cloud providers]
        Environments[environments/<br/>dev, uat, production]
    end

    subgraph "Kubernetes Clusters"
        DevCluster[Dev Cluster<br/>K3s or EKS<br/>Namespace: fineract-dev]
        UATCluster[UAT Cluster<br/>Namespace: fineract-uat]
        ProdCluster[Production Cluster<br/>Namespace: fineract-production]
    end

    %% Git to ArgoCD
    GitDev -->|Watch| ArgoDev
    GitMain -->|Watch| ArgoUAT
    GitMain -->|Watch| ArgoProd

    %% ArgoCD to Kustomize
    ArgoDev -->|Read| Environments
    ArgoUAT -->|Read| Environments
    ArgoProd -->|Read| Environments

    %% Kustomize layers
    Environments -->|Include| Base
    Environments -->|Include| Overlays
    Environments -->|Include| Components

    %% ArgoCD deploys to clusters
    ArgoDev -->|Auto-deploy| DevCluster
    ArgoUAT -->|Manual approval| UATCluster
    ArgoProd -->|Manual approval<br/>+ Sync window| ProdCluster

    subgraph "Deployment Profiles"
        Minimal[Minimal Profile<br/>PostgreSQL only<br/>5 CPUs, 13Gi RAM]
        Standard[Standard Profile<br/>PostgreSQL + Redis<br/>5.5 CPUs, 14Gi RAM]
        Full[Full Profile<br/>All services<br/>14.5 CPUs, 40Gi RAM]
    end

    Environments -.->|Profile selection| Minimal
    Environments -.->|Profile selection| Standard
    Environments -.->|Profile selection| Full

    classDef git fill:#f4511e,stroke:#bf360c,stroke-width:2px
    classDef argo fill:#ff6f00,stroke:#e65100,stroke-width:2px
    classDef kustomize fill:#0288d1,stroke:#01579b,stroke-width:2px
    classDef cluster fill:#388e3c,stroke:#1b5e20,stroke-width:2px
    classDef profile fill:#7b1fa2,stroke:#4a148c,stroke-width:2px

    class GitMain,GitDev git
    class ArgoApp,ArgoDev,ArgoUAT,ArgoProd argo
    class Base,Overlays,Components,Environments kustomize
    class DevCluster,UATCluster,ProdCluster cluster
    class Minimal,Standard,Full profile
```

### Kustomize Layering Example

```
environments/dev-aws/
├── kustomization.yaml              # Environment root
│   ├── resources:
│   │   ├── apps/fineract/base      # Base Fineract config
│   │   ├── apps/postgresql/base    # PostgreSQL (scaled to 0)
│   │   ├── apps/redis/base         # In-cluster Redis StatefulSet
│   │   └── apps/keycloak/base      # Keycloak config
│   └── components:
│       └── providers/aws-managed   # AWS provider patches
│           ├── Patch PostgreSQL → use RDS PostgreSQL 15.x
│           ├── Patch S3 access → add IRSA annotations
│           └── Enable in-cluster Redis (no ElastiCache)
└── Output: Fully configured AWS deployment with in-cluster Redis
```

---

## Kubernetes Resource Topology

This diagram shows how resources are organized in Kubernetes:

```mermaid
graph TB
    subgraph "Cluster"
        subgraph "Namespace: fineract-production"
            subgraph "Fineract Read Pods"
                ReadPod1[fineract-read-0<br/>Zone: us-east-2a]
                ReadPod2[fineract-read-1<br/>Zone: us-east-2b]
                ReadPod3[fineract-read-2<br/>Zone: us-east-2c]
            end

            subgraph "Fineract Write Pods"
                WritePod1[fineract-write-0<br/>Zone: us-east-2a<br/>Active]
                WritePod2[fineract-write-1<br/>Zone: us-east-2b<br/>Standby]
            end

            subgraph "Fineract Batch Pods"
                BatchPod1[fineract-batch-0]
                BatchPod2[fineract-batch-1]
                BatchPod3[fineract-batch-2]
            end

            subgraph "Data Services"
                PGPrimary[(PostgreSQL Primary<br/>StatefulSet<br/>100GB PVC)]
                PGReplica1[(PostgreSQL Replica 1<br/>StatefulSet<br/>100GB PVC)]
                PGReplica2[(PostgreSQL Replica 2<br/>StatefulSet<br/>100GB PVC)]
                RedisMain[(Redis<br/>StatefulSet<br/>10GB PVC)]
                S3Storage[(S3 Storage<br/>AWS S3 or compatible<br/>100GB)]
            end

            subgraph "Services (ClusterIP)"
                SvcReadLB[fineract-read-service<br/>LoadBalancer to 3 pods]
                SvcWriteLB[fineract-write-service<br/>LoadBalancer to 2 pods]
                SvcBatch[fineract-batch-service]
                SvcPG[postgresql-service]
                SvcRedis[redis-service]
                SvcS3[s3-service]
            end

            subgraph "Ingress"
                IngressRule[Ingress: fineract.example.com<br/>TLS cert from cert-manager<br/>→ oauth2-proxy-service]
            end

            subgraph "ConfigMaps & Secrets"
                CM1[ConfigMap: fineract-config<br/>application.properties]
                CM2[ConfigMap: keycloak-realm<br/>realm-fineract.yaml]
                Secret1[SealedSecret: db-credentials]
                Secret2[SealedSecret: redis-password]
            end

            subgraph "Jobs & CronJobs"
                DataLoader[Job: fineract-data-loader<br/>Run once]
                InterestJob[CronJob: apply-interest<br/>Schedule: 0 2 * * *]
                BackupJob[CronJob: pg-backup<br/>Schedule: 0 3 * * *]
            end

            subgraph "Persistent Volumes"
                PV1[PV: postgresql-primary-pv<br/>100GB gp3]
                PV2[PV: postgresql-replica1-pv<br/>100GB gp3]
                PV3[PV: s3-cache-pv<br/>10GB gp3]
            end
        end

        subgraph "Namespace: monitoring"
            Prometheus[Prometheus<br/>StatefulSet<br/>50GB PVC]
            Grafana[Grafana<br/>Deployment]
            Loki[Loki<br/>StatefulSet<br/>30GB PVC]
            Promtail[Promtail<br/>DaemonSet]
        end

        subgraph "Namespace: cert-manager"
            CertMgr[cert-manager<br/>Deployment]
            CertIssuer[ClusterIssuer: letsencrypt]
        end

        subgraph "Namespace: sealed-secrets"
            SealedCtrl[sealed-secrets-controller<br/>Deployment]
        end

        subgraph "Namespace: velero"
            VeleroCtrl[velero<br/>Deployment]
        end
    end

    %% Service connections
    ReadPod1 --> SvcReadLB
    ReadPod2 --> SvcReadLB
    ReadPod3 --> SvcReadLB
    WritePod1 --> SvcWriteLB
    WritePod2 --> SvcWriteLB
    BatchPod1 --> SvcBatch
    BatchPod2 --> SvcBatch
    BatchPod3 --> SvcBatch

    %% Data connections
    ReadPod1 --> SvcPG
    ReadPod1 --> SvcRedis
    WritePod1 --> SvcPG
    WritePod1 --> SvcRedis
    BatchPod1 --> SvcPG
    BatchPod1 --> SvcS3

    SvcPG --> PGPrimary
    SvcPG --> PGReplica1
    SvcPG --> PGReplica2
    SvcRedis --> RedisMain
    SvcS3 --> S3Storage

    %% Ingress connections
    IngressRule --> SvcReadLB
    IngressRule --> SvcWriteLB

    %% Config connections
    ReadPod1 -.-> CM1
    WritePod1 -.-> CM1
    ReadPod1 -.-> Secret1
    WritePod1 -.-> Secret1

    %% PV connections
    PGPrimary -.-> PV1
    PGReplica1 -.-> PV2
    S3Storage -.-> PV3

    %% Cross-namespace
    SvcReadLB -.-> Prometheus
    SvcWriteLB -.-> Prometheus
    IngressRule -.-> CertMgr
    Secret1 -.-> SealedCtrl
    PGPrimary -.-> VeleroCtrl

    classDef pod fill:#4caf50,stroke:#1b5e20,stroke-width:2px
    classDef data fill:#9c27b0,stroke:#4a148c,stroke-width:2px
    classDef service fill:#2196f3,stroke:#0d47a1,stroke-width:2px
    classDef config fill:#ff9800,stroke:#e65100,stroke-width:2px
    classDef storage fill:#f44336,stroke:#b71c1c,stroke-width:2px
    classDef monitoring fill:#ffeb3b,stroke:#f57f17,stroke-width:2px

    class ReadPod1,ReadPod2,ReadPod3,WritePod1,WritePod2,BatchPod1,BatchPod2,BatchPod3 pod
    class PGPrimary,PGReplica1,PGReplica2,RedisMain,S3Storage data
    class SvcReadLB,SvcWriteLB,SvcBatch,SvcPG,SvcRedis,SvcS3,IngressRule service
    class CM1,CM2,Secret1,Secret2,DataLoader,InterestJob,BackupJob config
    class PV1,PV2,PV3 storage
    class Prometheus,Grafana,Loki,Promtail monitoring
```

### Resource Allocation by Profile

| Resource Type | Minimal | Standard (Recommended) | Full |
|--------------|---------|------------------------|------|
| **Total CPUs** | 5 CPUs | 5.5 CPUs | 14.5 CPUs |
| **Total Memory** | 13Gi | 14Gi | 40Gi |
| **Deployment Time** | ~5 min | ~6 min | ~15 min |
| **Concurrent Users** | 50-200 | 200-1000 | 1000-5000+ |
| **Services** | PostgreSQL only | PostgreSQL + Redis | All services |
| **Performance** | Baseline | 60-80% faster | Enterprise-grade |
| **Use Case** | Testing, CI/CD | Production (most cases) | High-volume production |

---

## Deployment Profiles

### Minimal Profile
- **Services**: PostgreSQL only
- **Resources**: 5 CPUs, 13Gi RAM
- **Storage**: 100GB (PostgreSQL)
- **Use case**: Development, testing, CI/CD pipelines
- **Limitations**: No caching, no event streaming, slower response times

### Standard Profile (Recommended)
- **Services**: PostgreSQL + In-cluster Redis
- **Resources**: 5.5 CPUs, 14Gi RAM
- **Storage**: 110GB (PostgreSQL + Redis)
- **Use case**: Most production deployments
- **Performance**: 60-80% faster than minimal due to in-cluster Redis caching
- **Cost**: $60-80/month (self-hosted) or $110-140/month (managed with in-cluster Redis)

### Full Profile
- **Services**: PostgreSQL + Redis + Kafka + S3 (via IRSA) + OAuth2 Proxy
- **Resources**: 14.5 CPUs, 40Gi RAM
- **Storage**: 310GB (all services)
- **Use case**: Enterprise with event streaming needs
- **Features**: Event-driven architecture, S3 document storage, OAuth2 authentication
- **Cost**: $150-200/month (self-hosted) or $400-500/month (managed with in-cluster Redis)

---

## Environment Configurations

| Environment | Namespace | Auto-Sync | Source Branch | Approval Required | Retry Limit | Sync Window |
|-------------|-----------|-----------|---------------|-------------------|-------------|-------------|
| **dev** | fineract-dev | ✅ Enabled | develop | ❌ No | 5 | Always |
| **dev-aws** | fineract-dev | ✅ Enabled | develop | ❌ No | 5 | Always |
| **dev-azure** | fineract-dev | ✅ Enabled | develop | ❌ No | 5 | Always |
| **dev-gcp** | fineract-dev | ✅ Enabled | develop | ❌ No | 5 | Always |
| **uat** | fineract-uat | ❌ Disabled | main | ✅ Yes | 5 | Always |
| **production** | fineract-production | ❌ Disabled | main (tagged) | ✅ Yes | 3 | Tue-Thu 10AM-4PM |
| **production-aws** | fineract-production | ❌ Disabled | main (tagged) | ✅ Yes | 3 | Tue-Thu 10AM-4PM |
| **production-azure** | fineract-production | ❌ Disabled | main (tagged) | ✅ Yes | 3 | Tue-Thu 10AM-4PM |
| **production-gcp** | fineract-production | ❌ Disabled | main (tagged) | ✅ Yes | 3 | Tue-Thu 10AM-4PM |

### Environment Selection Guide

**Use Dev environments when:**
- Testing new features
- Experimenting with configurations
- Learning the system
- Running CI/CD tests

**Use UAT environments when:**
- User acceptance testing
- Pre-production validation
- Stakeholder demos
- Performance testing

**Use Production environments when:**
- Serving real customers
- Processing actual transactions
- Requiring SLAs and support
- Need for audit trails and compliance

---

## Related Documentation

- [AWS Quick-Start Guide](./AWS_QUICK_START.md) - Deploy to AWS in 30 minutes
- [Mifos Web App Setup](./MIFOS_WEB_APP_SETUP.md) - Configure the Angular web interface
- [Mifos Web App Implementation](./MIFOS_WEB_APP_IMPLEMENTATION_SUMMARY.md) - Technical implementation details
- [PostgreSQL HA Deployment](./POSTGRESQL_HA_DEPLOYMENT.md) - High-availability database setup
- [AWS IAM Setup Guide](./AWS_IAM_SETUP_GUIDE.md) - Configure IAM roles for AWS integration
- [Keycloak Configuration](../operations/keycloak-config/README.md) - Identity provider setup

---

## Architecture Principles

The fineract-gitops architecture follows these key principles:

1. **GitOps-First**: All configuration is versioned in Git and deployed via ArgoCD
2. **Multi-Cloud**: Abstract infrastructure providers for portability
3. **High Availability**: Multi-instance deployments with pod anti-affinity
4. **Observability**: Built-in monitoring, logging, and alerting
5. **Security**: Sealed secrets, network policies, RBAC, WebAuthn 2FA
6. **Cost Optimization**: Multiple deployment profiles and K3s option
7. **Developer Experience**: Simple Kustomize overlays, clear documentation
8. **Production-Ready**: Backup/restore, disaster recovery, sync windows

---

## Contributing

To modify the architecture:

1. Update base configurations in `apps/*/base/`
2. Add environment-specific overlays in `apps/*/overlays/`
3. Create provider patches in `components/providers/`
4. Update environment kustomizations in `environments/`
5. Test in dev environment before promoting to UAT/production
6. Update this documentation with any architectural changes

For questions or discussions about the architecture, please open an issue or discussion in the repository.
