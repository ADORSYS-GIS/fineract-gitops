# Fineract GitOps - Database Strategy

**Last Updated:** 2025-10-30
**Status:** AWS-Managed Services (RDS PostgreSQL + In-Cluster Redis)

---

## Overview

The Fineract GitOps deployment uses **AWS RDS PostgreSQL** for the database and **in-cluster Redis** for caching. This hybrid approach balances operational simplicity with cost efficiency.

## Database Services

### Primary Database: AWS RDS PostgreSQL

**Service:** Amazon RDS for PostgreSQL
**Version:** PostgreSQL 15.x
**Deployment:** Multi-AZ for high availability (production)

**Why PostgreSQL:**
- Modern, robust, open-source RDBMS
- Better JSON support for complex data structures
- Strong ACID compliance
- Excellent performance for OLTP workloads
- AWS RDS provides automated backups, patching, and monitoring

**Configuration:**
```yaml
Driver: org.postgresql.Driver
Port: 5432
Default Database: fineract
Connection Pool: HikariCP
```

### Caching Layer: In-Cluster Redis

**Service:** Redis StatefulSet (fineract-redis)
**Version:** Redis 7.x
**Deployment:** Single instance (dev/uat), HA with replication (production)

**Why In-Cluster Redis:**
- Session management (ephemeral data)
- API response caching
- Significantly lower cost than AWS ElastiCache
- Simple deployment and management via Kubernetes
- No cross-AZ data transfer costs

**Use Cases:**
- Session management (acceptable data loss risk)
- Temporary cache (can be rebuilt)
- Rate limiting
- NOT used for persistent data

**Configuration:**
```yaml
Port: 6379
Persistence: Disabled (cache only)
Deployment: StatefulSet
Service: ClusterIP (fineract-redis)
```

---

## Configuration Details

### Fineract Application Configuration

All Fineract deployments (`deployment-read.yaml`, `deployment-write.yaml`, `deployment-batch.yaml`) use:

```yaml
# Database Driver
FINERACT_HIKARI_DRIVER_SOURCE_CLASS_NAME: "org.postgresql.Driver"

# Database Connection (via secrets)
FINERACT_HIKARI_JDBC_URL: "jdbc:postgresql://$(RDS_ENDPOINT):5432/fineract"
FINERACT_HIKARI_USERNAME: ${from secret: fineract-db-credentials}
FINERACT_HIKARI_PASSWORD: ${from secret: fineract-db-credentials}

# HikariCP Connection Pool Configuration
FINERACT_HIKARI_MINIMUM_IDLE: "3"         # Read: 3, Write: 5, Batch: 2
FINERACT_HIKARI_MAXIMUM_POOL_SIZE: "10"   # Read: 10, Write: 15, Batch: 5
FINERACT_HIKARI_IDLE_TIMEOUT: "60000"     # 60 seconds
FINERACT_HIKARI_CONNECTION_TIMEOUT: "20000"  # 20 seconds
FINERACT_HIKARI_MAX_LIFETIME: "1800000"   # 30 minutes
FINERACT_HIKARI_LEAK_DETECTION_THRESHOLD: "60000"  # 60 seconds
FINERACT_HIKARI_CONNECTION_TEST_QUERY: "SELECT 1"

# Redis Connection (in-cluster)
SPRING_REDIS_HOST: ${from secret: fineract-redis-credentials}
SPRING_REDIS_PORT: "6379"
```

### Secrets Configuration

**Terraform-Managed Secrets:**

1. **aws-rds-credentials** - RDS endpoint
2. **fineract-db-credentials** - Database username/password
3. **fineract-redis-credentials** - Redis connection details

All secrets are created by Terraform in `modules/kubernetes-secret/main.tf`.

---

## Terraform Infrastructure

### RDS PostgreSQL Deployment

**Module:** `terraform/aws/modules/rds/`

**Key Features:**
- Multi-AZ deployment for failover (production)
- Automated backups (7-day retention)
- Encryption at rest
- Parameter group optimizations
- Performance Insights enabled
- Enhanced monitoring

**Instance Types by Environment:**
- **Dev:** db.t3.micro (1 vCPU, 1 GB RAM)
- **UAT:** db.t3.small (2 vCPU, 2 GB RAM)
- **Production:** db.t3.medium or larger (2+ vCPU, 4+ GB RAM)

### Redis StatefulSet Deployment

**ArgoCD Application:** `argocd/applications/operations/fineract-redis.yaml`

**Configuration:**
- Single pod (dev/uat)
- StatefulSet with 1 replica
- PersistentVolumeClaim: 1Gi (for AOF logs, not primary data)
- No authentication (internal cluster network)
- Service: `fineract-redis.fineract-{env}.svc.cluster.local`

---

## Why This Architecture?

### AWS RDS for Database

**Benefits:**
- ✅ Automated backups and point-in-time recovery
- ✅ Multi-AZ high availability
- ✅ Automated patching and upgrades
- ✅ Built-in monitoring and alerting
- ✅ Reduced operational burden
- ✅ Better SLAs for business-critical data

**Cost:** $15-200/month depending on environment

### In-Cluster Redis for Caching

**Benefits:**
- ✅ Significantly lower cost ($0 vs $10-150/month for ElastiCache)
- ✅ Simple deployment via Kubernetes
- ✅ No cross-AZ data transfer costs
- ✅ Fast internal cluster networking
- ✅ Acceptable for cache/session use cases (ephemeral data)

**Trade-offs:**
- ⚠️ Single point of failure (acceptable for cache)
- ⚠️ Manual scaling and management
- ⚠️ Data loss during pod restarts (acceptable for cache)

**Decision:** For session management and caching, the cost savings (100% for dev, 90% for production) justify the operational trade-offs.

---

## Environment-Specific Configuration

### Development Environment

**Purpose:** Testing and development

**RDS Configuration:**
```yaml
instance_class: db.t3.micro
multi_az: false
backup_retention: 1 day
storage: 20 GB gp2
postgres_version: 15
```

**Redis Configuration:**
```yaml
replicas: 1
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
persistence: 1Gi
```

**Cost:** ~$15-20/month (RDS only, Redis is free)

### UAT Environment

**Purpose:** Pre-production testing

**RDS Configuration:**
```yaml
instance_class: db.t3.small
multi_az: false
backup_retention: 3 days
storage: 50 GB gp2
```

**Redis Configuration:**
```yaml
replicas: 1
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
```

**Cost:** ~$40-50/month (RDS only)

### Production Environment

**Purpose:** Live production workloads

**RDS Configuration:**
```yaml
instance_class: db.t3.medium (minimum)
multi_az: true
backup_retention: 7 days
storage: 100 GB gp3
encryption: enabled
performance_insights: enabled
enhanced_monitoring: enabled
```

**Redis Configuration:**
```yaml
replicas: 1  # Can be increased for HA
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
persistence: 5Gi
```

**Cost:** ~$150-200/month (RDS only)

---

### Fineract Version Upgrade Data Migration Strategy

Upgrading Fineract to a new version often involves changes to the underlying database schema and sometimes requires data transformations. A robust data migration strategy is crucial to ensure a smooth and successful upgrade with minimal downtime and data integrity.

#### General Approach

1.  **Pre-Upgrade Backup**:
    *   **Full Database Backup**: Before initiating any upgrade, perform a full, verified backup of the production database. For AWS RDS, this includes a manual snapshot in addition to automated backups.
    *   **Configuration Backup**: Backup all Fineract configuration files, especially those related to database connections and custom settings.
2.  **Review Release Notes and Migration Guides**:
    *   Thoroughly review the official Fineract release notes and any provided migration guides for the target version. Pay close attention to database schema changes, deprecated features, and required data transformations.
3.  **Test Environment Upgrade**:
    *   **Replicate Production**: Create a test environment that is an exact replica of the production environment, including a copy of the production database.
    *   **Perform Dry Run**: Execute the upgrade process in the test environment first. This includes applying schema migrations and running any necessary data transformation scripts.
    *   **Validate Data and Functionality**: After the upgrade, thoroughly validate the data integrity and ensure all Fineract functionalities work as expected.
4.  **Schema Migration**:
    *   **Fineract's Internal Migrations**: Fineract typically includes internal database migration scripts (e.g., using Flyway or Liquibase) that run automatically on application startup. Ensure these are configured correctly.
    *   **Manual Schema Adjustments**: If the release notes indicate any manual schema adjustments are required, prepare and test these scripts in advance.
5.  **Data Transformation and Cleanup**:
    *   **Custom Scripts**: For complex data transformations not handled by Fineract's internal migrations, develop custom SQL scripts. These should be idempotent and thoroughly tested.
    *   **Data Cleanup**: Identify and clean up any obsolete or inconsistent data as recommended by the Fineract upgrade guide.
6.  **Post-Migration Verification**:
    *   **Health Checks**: Run Fineract's built-in health checks and API endpoints to confirm database connectivity and application readiness.
    *   **Data Spot Checks**: Perform targeted queries to verify critical data points (e.g., client counts, loan balances) are correct.
    *   **Application Functionality**: Conduct a smoke test of key application features.
7.  **Rollback Plan**:
    *   **Defined Procedure**: Have a clear, documented rollback procedure in case the upgrade fails or introduces critical issues. This typically involves restoring the database from the pre-upgrade backup.
    *   **Communication**: Ensure all stakeholders are aware of the rollback plan and potential impact.

#### Tools and Technologies

*   **AWS RDS Snapshots**: For quick and reliable database backups and restores.
*   **Fineract Internal Migration Tools**: Leverage Fineract's built-in schema migration capabilities.
*   **Custom SQL Scripts**: For specific data transformations or manual schema adjustments.
*   **Version Control**: All custom migration scripts and configuration changes should be version-controlled in this GitOps repository.

This strategy aims to minimize risks associated with Fineract version upgrades by emphasizing thorough preparation, testing, and a clear rollback path.

## Connection Management

### Connection Pooling

**Library:** HikariCP (built into Fineract)

**Pool Sizing Guidelines:**
```
connections = ((core_count * 2) + effective_spindle_count)
```

**Implemented Configuration (Base):**

| Deployment | Min Idle | Max Pool Size | Timeout (ms) | Max Lifetime (ms) | Leak Detection (ms) |
|------------|----------|---------------|--------------|-------------------|---------------------|
| **Read**   | 3        | 10            | 20000        | 1800000           | 60000               |
| **Write**  | 5        | 15            | 20000        | 1800000           | 60000               |
| **Batch**  | 2        | 5             | 20000        | 1800000           | 60000               |

**Environment-Specific Overlays:**

**Development** (`apps/fineract/overlays/dev/`):
- Read: 2-5 connections
- Write: 3-8 connections
- Batch: 1-3 connections
- **Total Max:** ~16 connections

**Production** (`apps/fineract/overlays/production/`):
- Read: 5-15 connections (up to 5 replicas via HPA = 75 connections max)
- Write: 8-25 connections (up to 3 replicas = 75 connections max)
- Batch: 3-10 connections (1 replica = 10 connections)
- **Total Max:** ~160 connections (well under RDS 500 limit)

**RDS Max Connections:**
- db.t3.micro: 60 connections
- db.t3.small: 150 connections
- db.t3.medium: 300 connections
- db.r6g.large (production): ~500 connections (configured in `terraform/aws/environments/production.tfvars`)

### Read/Write Splitting

**Architecture:**
- Write operations → RDS Primary
- Read operations → RDS Read Replicas (optional, not currently implemented)

**Fineract Deployments:**
- `deployment-write.yaml` → Primary endpoint
- `deployment-read.yaml` → Primary endpoint (read replicas can be added later)
- `deployment-batch.yaml` → Primary endpoint

---

## Backup and Recovery

### RDS Automated Backups

**Backup Window:** 03:00-04:00 UTC (configurable)
**Retention:** 7 days (production), 1-3 days (dev/uat)
**Snapshots:** Manual snapshots for major releases

**Point-in-Time Recovery:**
- Recovery to any point within retention period
- Granularity: 5 minutes

### Redis Data Loss

**Impact:** Session and cache data lost during pod restart
**Mitigation:**
- Users will need to re-login
- Cache will be rebuilt automatically
- No permanent data loss (cache only)

**Acceptable:** Cache and session data is ephemeral by nature

---

## Monitoring and Alerts

### RDS CloudWatch Metrics

**Key Metrics:**
- `CPUUtilization` → Alert if > 80%
- `DatabaseConnections` → Alert if > 80% of max
- `FreeStorageSpace` → Alert if < 10 GB
- `ReadLatency` / `WriteLatency` → Alert if > 100ms
- `ReplicationLag` → Alert if > 10 seconds (if using read replicas)

### Redis Kubernetes Metrics

**Key Metrics:**
- Pod CPU/Memory usage via Prometheus
- Service availability
- Connection count
- Cache hit rate (application-level metrics)

---

## Cost Optimization

### Current Architecture Savings

| Component | AWS ElastiCache | In-Cluster Redis | Savings |
|-----------|----------------|------------------|---------|
| Dev | $10-15/month | $0 | 100% |
| UAT | $20-30/month | $0 | 100% |
| Production | $100-150/month | $0 | 100% |

**Total Monthly Savings:** $130-195/month (~$1,560-2,340/year)

### Additional Strategies

1. **Right-Size Instances:**
   - Start small, scale based on metrics
   - Use CloudWatch to identify under-utilized resources

2. **Reserved Instances:**
   - Purchase 1-year or 3-year RIs for production
   - Save 30-60% vs on-demand

3. **Automated Shutdown:**
   - Stop dev/uat databases outside business hours
   - Use Lambda or EventBridge rules

4. **Storage Optimization:**
   - Use gp3 instead of gp2 (better price/performance)
   - Regular cleanup of old backups

---

## Security Best Practices

### Network Security
- ✅ RDS in private subnets only
- ✅ Security groups restrict access to Fineract pods
- ✅ No public accessibility
- ✅ Redis accessible only within cluster network

### Authentication
- ✅ Strong passwords (32+ characters, generated)
- ✅ Rotate credentials regularly
- ✅ Secrets stored in Kubernetes secrets (created by Terraform)
- ✅ IRSA (IAM Roles for Service Accounts) for AWS service access

### Encryption
- ✅ RDS encryption at rest (KMS)
- ✅ RDS encryption in transit (SSL/TLS)
- ✅ Encrypted backups
- ✅ Redis runs in trusted internal network

### Auditing
- ✅ Enable audit logging
- ✅ CloudTrail for API calls
- ✅ VPC Flow Logs for network traffic
- ✅ Regular security assessments

---

## References

- [AWS RDS PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [Redis Documentation](https://redis.io/documentation)
- [Fineract Database Schema](https://github.com/apache/fineract)
- [HikariCP Configuration](https://github.com/brettwooldridge/HikariCP)

---

## Changelog

**2025-10-30:** Updated to reflect PostgreSQL + in-cluster Redis architecture
**2025-10-29:** Initial documentation (outdated MySQL + ElastiCache references)
