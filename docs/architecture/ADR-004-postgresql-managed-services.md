# ADR-004: PostgreSQL - Managed Services vs In-Cluster Deployment

**Status**: ACCEPTED
**Date**: 2025-01-19
**Decision**: Use managed PostgreSQL services (AWS RDS, Azure Database, GCP Cloud SQL) instead of in-cluster PostgreSQL for production environments

---

## Context

Apache Fineract requires a PostgreSQL database for storing all application data. When deploying on Kubernetes, there are two primary approaches:

### Option 1: In-Cluster PostgreSQL
Deploy PostgreSQL as a StatefulSet within the Kubernetes cluster.

**Pros:**
- Complete control over configuration
- No dependency on cloud providers
- Lower cost for small deployments
- All components in same cluster (simpler networking)
- Works in air-gapped environments

**Cons:**
- Team must manage database operations (backups, HA, failover)
- Requires expertise in PostgreSQL administration
- Limited tooling compared to managed services
- Manual scaling and performance tuning
- Higher operational burden
- No built-in point-in-time recovery (PITR)
- Storage management complexity

### Option 2: Managed PostgreSQL Services
Use cloud provider managed database services:
- **AWS RDS PostgreSQL**
- **Azure Database for PostgreSQL**
- **GCP Cloud SQL for PostgreSQL**

**Pros:**
- Automated backups with point-in-time recovery
- Automated failover and high availability
- Performance Insights and monitoring
- Automated patching and upgrades
- Easy vertical and horizontal scaling
- Expert database support from cloud provider
- Reduced operational burden
- Production-grade reliability

**Cons:**
- Higher cost than self-hosted (for large instances)
- Vendor lock-in (to some degree)
- Less control over database internals
- Requires cloud provider account
- Cannot use in air-gapped environments

---

## Decision

**Use managed PostgreSQL services (RDS/Azure Database/Cloud SQL) for production and UAT environments, with optional in-cluster PostgreSQL for development.**

### Rationale

1. **Operational Excellence**
   - Database operations are critical and require specialized expertise
   - Managed services provide automated backups, failover, and patching
   - Reduces operational burden on DevOps team
   - Allows team to focus on application, not database management

2. **Reliability & Availability**
   - Managed services provide production-grade HA (Multi-AZ, read replicas)
   - Automated failover in <60 seconds
   - 99.95% SLA for RDS Multi-AZ
   - Built-in disaster recovery capabilities

3. **Security**
   - Automated security patches
   - Encryption at rest and in transit (by default)
   - Network isolation (VPC, private subnets)
   - Audit logging and compliance features

4. **Performance**
   - Performance Insights for query analysis
   - Easy vertical scaling (instance type changes)
   - Read replicas for scaling read workload
   - Optimized storage (Provisioned IOPS, gp3)

5. **Cost Efficiency (Production)**
   - While RDS costs more than self-hosted for compute, total cost is lower when considering:
     - Reduced operational overhead (no DB admin needed)
     - No backup infrastructure needed
     - No HA implementation costs
   - Development environments can use smaller instances or in-cluster PostgreSQL

6. **Disaster Recovery**
   - Automated continuous backups
   - Point-in-time recovery (PITR)
   - Cross-region replication
   - Easy restoration procedures

---

## Implementation

### Environment Strategy

| Environment | Database Solution | Rationale |
|-------------|------------------|-----------|
| **Production** | AWS RDS Multi-AZ (or equivalent) | Maximum reliability, automated failover |
| **UAT** | AWS RDS Single-AZ (or equivalent) | Production-like, lower cost |
| **Development** | AWS RDS Single-AZ OR in-cluster | Cost-optimized, can use either |
| **Local Dev** | In-cluster PostgreSQL | Developer laptops, no cloud dependency |

### AWS RDS Configuration (Production)

```yaml
# Terraform configuration example
resource "aws_db_instance" "fineract" {
  identifier     = "fineract-prod"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.large"

  # Storage
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true

  # High Availability
  multi_az               = true
  availability_zone      = "us-east-1a"

  # Backup & Recovery
  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Security
  db_subnet_group_name   = aws_db_subnet_group.fineract.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Performance
  performance_insights_enabled = true
  monitoring_interval          = 60

  # Credentials
  username = "fineract"
  password = random_password.db_password.result

  tags = {
    Environment = "production"
    Application = "fineract"
  }
}
```

### Connection from Kubernetes

Fineract pods connect to RDS using:

```yaml
# Sealed Secret with RDS credentials
apiVersion: v1
kind: Secret
metadata:
  name: fineract-db-credentials
stringData:
  host: fineract-prod.cluster-abc.us-east-1.rds.amazonaws.com
  port: "5432"
  database: fineract_default
  username: fineract
  password: <sealed-encrypted>
  jdbc-url: jdbc:postgresql://fineract-prod.cluster-abc.us-east-1.rds.amazonaws.com:5432/fineract_tenants?sslmode=require
```

### In-Cluster PostgreSQL (Development Option)

For development environments or on-premise deployments, in-cluster PostgreSQL is available:

```yaml
# StatefulSet for PostgreSQL
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
spec:
  serviceName: postgresql
  replicas: 1
  template:
    spec:
      containers:
      - name: postgresql
        image: postgres:15-alpine
        env:
        - name: POSTGRES_DB
          value: fineract_default
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 50Gi
```

**Note**: In-cluster PostgreSQL is NOT recommended for production due to operational complexity.

---

## Consequences

### Positive

1. **Reduced Operational Burden**: No database administration required
2. **Improved Reliability**: Production-grade HA and automated failover
3. **Better Disaster Recovery**: Automated backups, PITR, cross-region replication
4. **Enhanced Security**: Automated patching, encryption, audit logs
5. **Easier Scaling**: Vertical and horizontal scaling with minimal downtime
6. **Cost Efficient**: Total cost lower when including operational overhead

### Negative

1. **Cloud Dependency**: Requires cloud provider account (AWS/Azure/GCP)
2. **Vendor Lock-in**: Some degree of lock-in to cloud provider
3. **Higher Direct Costs**: RDS more expensive than self-hosted compute
4. **Less Control**: Cannot modify PostgreSQL internals
5. **Not Air-Gap Compatible**: Cannot deploy in air-gapped environments

### Mitigations

1. **Multi-Cloud Support**: Terraform modules for AWS, Azure, GCP
   - Easy to switch providers if needed
   - Similar features across all providers

2. **Cost Optimization**:
   - Use smaller instances for dev/UAT
   - Reserved Instances for production (up to 60% savings)
   - Automated shutdown for dev environments

3. **In-Cluster Fallback**:
   - Keep in-cluster PostgreSQL manifests for on-premise/air-gapped
   - Document migration path from RDS to self-hosted if needed

4. **Portability**:
   - Use standard PostgreSQL (no proprietary extensions)
   - Terraform modules abstract provider differences
   - Easy to export/import data between providers

---

## Alternatives Considered

### 1. Cloud-Native PostgreSQL Operator (Zalando, CrunchyData, CloudNativePG)

**Pros:**
- Kubernetes-native (CRDs)
- Automated backups, failover
- Works in any cloud or on-premise
- More control than managed services

**Cons:**
- Still requires database expertise
- Team must maintain operator
- Less mature than managed services
- No cloud provider support/SLA

**Verdict**: Good for on-premise, but managed services better for cloud deployments.

### 2. PostgreSQL on VMs (EC2, Azure VMs, Compute Engine)

**Pros:**
- Full control
- Can optimize costs vs RDS
- Works like traditional infrastructure

**Cons:**
- Must manage VMs, OS, PostgreSQL
- No Kubernetes integration
- More operational burden than RDS
- Less reliable than managed services

**Verdict**: Worse than both RDS and in-cluster options.

### 3. Serverless PostgreSQL (Aurora Serverless, Azure Flexible Server)

**Pros:**
- Auto-scaling (pay for what you use)
- Lower cost for intermittent workloads
- Fast scaling up/down

**Cons:**
- Cold start latency (for Aurora Serverless v1)
- More expensive for constant workloads
- Less predictable costs

**Verdict**: Good for dev/staging, but traditional RDS better for production.

---

## Related ADRs

- **ADR-001**: Multi-Cloud Provider Support (provides framework for RDS/Azure/GCP abstraction)
- **ADR-002**: Multi-Instance Fineract (Fineract architecture that connects to PostgreSQL)
- **ADR-003**: Sealed Secrets (how database credentials are managed in Git)

---

## References

- [AWS RDS for PostgreSQL](https://aws.amazon.com/rds/postgresql/)
- [Azure Database for PostgreSQL](https://azure.microsoft.com/en-us/products/postgresql/)
- [GCP Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- [PostgreSQL on Kubernetes Best Practices](https://www.postgresql.org/about/news/postgresql-on-kubernetes-best-practices-2464/)
- [Terraform AWS RDS Module](../../../terraform/aws/modules/rds/)

---

**Last Updated**: 2025-01-19
**Author**: DevOps Team
**Status**: ACCEPTED
