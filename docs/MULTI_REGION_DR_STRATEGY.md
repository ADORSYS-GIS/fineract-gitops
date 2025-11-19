# Multi-Region Disaster Recovery Strategy

**Status**: PROPOSED
**Date**: 2025-01-19
**Version**: 1.0

---

## Executive Summary

This document outlines the strategy for implementing multi-region disaster recovery for the Fineract GitOps platform, with specific focus on Sealed Secrets key management and cross-region failover procedures.

### Current State

- **Single Region Deployment**: All environments currently run in a single AWS region (us-east-1)
- **Sealed Secrets Backup**: Keys backed up to AWS Secrets Manager in same region
- **RPO**: ~24 hours (daily database backups)
- **RTO**: ~2-4 hours (manual recovery)

### Target State

- **Multi-Region Active-Passive**: Primary region (us-east-1) with passive DR region (us-west-2)
- **Cross-Region Replication**: Sealed secrets keys replicated across regions
- **RPO**: ~15 minutes (continuous replication)
- **RTO**: ~30 minutes (automated failover)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Components Requiring Multi-Region Support](#components-requiring-multi-region-support)
3. [Sealed Secrets Multi-Region Strategy](#sealed-secrets-multi-region-strategy)
4. [Database Replication](#database-replication)
5. [Storage Replication](#storage-replication)
6. [Infrastructure as Code](#infrastructure-as-code)
7. [Failover Procedures](#failover-procedures)
8. [Failback Procedures](#failback-procedures)
9. [Testing and Validation](#testing-and-validation)
10. [Cost Analysis](#cost-analysis)
11. [Implementation Roadmap](#implementation-roadmap)

---

## Architecture Overview

### Current Architecture (Single Region)

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS us-east-1                          │
│                                                             │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   EKS       │───▶│  RDS         │    │  S3 Bucket   │  │
│  │  Cluster    │    │  PostgreSQL  │    │  (Reports)   │  │
│  └─────────────┘    └──────────────┘    └──────────────┘  │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │          AWS Secrets Manager                        │  │
│  │  /fineract/*/sealed-secrets/master-key              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Target Architecture (Multi-Region Active-Passive)

```
┌────────────────────────────────────────┐    ┌────────────────────────────────────────┐
│       PRIMARY REGION (us-east-1)       │    │       DR REGION (us-west-2)            │
│                                        │    │                                        │
│  ┌─────────────┐    ┌──────────────┐  │    │  ┌─────────────┐    ┌──────────────┐  │
│  │   EKS       │───▶│  RDS         │  │    │  │   EKS       │───▶│  RDS         │  │
│  │  (Active)   │    │  (Primary)   │  │    │  │  (Standby)  │    │  (Replica)   │  │
│  └─────────────┘    └──────────────┘  │    │  └─────────────┘    └──────────────┘  │
│         │                   │          │    │         │                   │          │
│         │                   │          │    │         │                   │          │
│         ▼                   │          │    │         ▼                   │          │
│  ┌──────────────────────┐   │          │    │  ┌──────────────────────┐   │          │
│  │  Secrets Manager     │   │          │    │  │  Secrets Manager     │   │          │
│  │  (Primary)           │───┼──────────┼────┼─▶│  (Replica)           │   │          │
│  └──────────────────────┘   │          │    │  └──────────────────────┘   │          │
│                              │          │    │                              │          │
│  ┌──────────────┐            │          │    │  ┌──────────────┐            │          │
│  │  S3 Bucket   │────────────┼──────────┼────┼─▶│  S3 Bucket   │            │          │
│  │  (Primary)   │ Replication│          │    │  │  (Replica)   │            │          │
│  └──────────────┘            │          │    │  └──────────────┘            │          │
│                              │          │    │                              │          │
│         Route 53 Failover ───┼──────────┼────┼───────────────────────▶      │          │
│                              │          │    │                              │          │
└────────────────────────────────────────┘    └────────────────────────────────────────┘
```

---

## Components Requiring Multi-Region Support

### Critical Components

| Component | Current State | Multi-Region Strategy | Priority |
|-----------|---------------|----------------------|----------|
| **Sealed Secrets Keys** | Single region backup | Cross-region replication | **HIGH** |
| **RDS PostgreSQL** | Single region | Read replica in DR region | **HIGH** |
| **S3 Storage** | Single region | Cross-region replication | **MEDIUM** |
| **EKS Cluster** | Single region | Pre-provisioned standby cluster | **HIGH** |
| **Keycloak Data** | In RDS | Covered by RDS replication | **HIGH** |
| **ArgoCD State** | In cluster | Git-backed (inherently multi-region) | **LOW** |

### Non-Critical Components

| Component | Strategy | Notes |
|-----------|----------|-------|
| **Monitoring Data** | No replication | Historical data loss acceptable |
| **Logs** | No replication | Historical data loss acceptable |
| **Redis Cache** | No replication | Cache rebuilt automatically |

---

## Sealed Secrets Multi-Region Strategy

### Strategy 1: Automated Cross-Region Replication (Recommended)

**Approach**: Use AWS Secrets Manager replication feature to automatically sync sealed secrets keys across regions.

#### Implementation

```hcl
# terraform/aws/modules/secrets-manager/main.tf

resource "aws_secretsmanager_secret" "sealed_secrets_key" {
  name        = "/fineract/${var.environment}/sealed-secrets/master-key"
  description = "Sealed Secrets controller master key for ${var.environment}"

  # Enable cross-region replication
  replica {
    region = "us-west-2"
  }

  tags = {
    Environment = var.environment
    Component   = "sealed-secrets"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "sealed_secrets_key" {
  secret_id     = aws_secretsmanager_secret.sealed_secrets_key.id
  secret_string = jsonencode({
    keys     = var.sealed_secrets_keys_base64
    metadata = {
      timestamp   = timestamp()
      environment = var.environment
      region      = data.aws_region.current.name
    }
  })
}

# Outputs for both regions
output "secret_arn_primary" {
  value = aws_secretsmanager_secret.sealed_secrets_key.arn
}

output "secret_arn_replica" {
  value = aws_secretsmanager_secret.sealed_secrets_key.replica[0].arn
}
```

#### Backup Script Updates

Update `scripts/backup-sealed-secrets-keys.sh` to support multi-region:

```bash
# Add after existing backup logic

# Optional: Verify replication to DR region
if [ "$ENABLE_MULTI_REGION" = "true" ]; then
  DR_REGION="us-west-2"

  echo "🔍 Verifying replication to DR region: $DR_REGION"

  aws secretsmanager describe-secret \
    --secret-id "$SECRET_PATH" \
    --region "$DR_REGION" \
    > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "✅ Replication to $DR_REGION confirmed"
  else
    echo "⚠️ WARNING: Replication to $DR_REGION not found"
    exit 1
  fi
fi
```

#### Restore Script Updates

Update `scripts/restore-sealed-secrets-keys.sh` to support multi-region:

```bash
# Add region parameter
REGION="${2:-us-east-1}"  # Default to primary region

# Allow override via environment variable
if [ -n "$DR_REGION" ]; then
  REGION="$DR_REGION"
  echo "🌍 Using DR region: $REGION"
fi

# Update AWS CLI calls to use specified region
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_PATH" \
  --region "$REGION" \
  --query 'SecretString' \
  --output text
```

### Strategy 2: Dual-Write Backup (Alternative)

**Approach**: Backup script explicitly writes to both regions.

```bash
# In backup-sealed-secrets-keys.sh

REGIONS=("us-east-1" "us-west-2")

for REGION in "${REGIONS[@]}"; do
  echo "📦 Backing up to region: $REGION"

  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_PATH" \
    --secret-string "$SECRET_JSON" \
    --region "$REGION"

  if [ $? -eq 0 ]; then
    echo "✅ Backup to $REGION successful"
  else
    echo "❌ Backup to $REGION failed"
    exit 1
  fi
done
```

### Strategy Comparison

| Aspect | Strategy 1 (Replication) | Strategy 2 (Dual-Write) |
|--------|-------------------------|------------------------|
| **Complexity** | Low (AWS managed) | Medium (custom logic) |
| **Latency** | Automatic (~1 min) | Immediate |
| **Cost** | Lower (replication free) | Same |
| **Failure Mode** | AWS handles consistency | Must handle errors |
| **Recommendation** | ✅ **RECOMMENDED** | Use only if replication unavailable |

---

## Database Replication

### RDS Cross-Region Read Replica

```hcl
# terraform/aws/modules/rds/main.tf

# Primary database
resource "aws_db_instance" "fineract_primary" {
  identifier              = "fineract-${var.environment}-primary"
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = "db.t3.large"

  # Enable automated backups (required for read replicas)
  backup_retention_period = 30
  backup_window          = "03:00-04:00"

  # Multi-AZ for high availability in primary region
  multi_az = true

  tags = {
    Role = "primary"
  }
}

# Cross-region read replica
resource "aws_db_instance" "fineract_replica" {
  provider = aws.dr_region  # Define in providers.tf

  identifier                = "fineract-${var.environment}-replica"
  replicate_source_db       = aws_db_instance.fineract_primary.arn

  # Can be different class for cost optimization
  instance_class            = "db.t3.large"

  # Replica-specific settings
  auto_minor_version_upgrade = false
  publicly_accessible        = false

  # Enable automated backups on replica
  backup_retention_period    = 7

  tags = {
    Role = "replica"
  }
}

# Outputs
output "primary_endpoint" {
  value = aws_db_instance.fineract_primary.endpoint
}

output "replica_endpoint" {
  value = aws_db_instance.fineract_replica.endpoint
}
```

### Promotion to Primary

When DR region becomes active:

```bash
# Promote read replica to standalone instance
aws rds promote-read-replica \
  --db-instance-identifier fineract-production-replica \
  --region us-west-2

# Wait for promotion to complete
aws rds wait db-instance-available \
  --db-instance-identifier fineract-production-replica \
  --region us-west-2

# Update Fineract configuration to point to new endpoint
kubectl patch secret fineract-db-credentials -n fineract-production \
  --type merge \
  -p '{"stringData":{"host":"fineract-production-replica.xxx.us-west-2.rds.amazonaws.com"}}'
```

---

## Storage Replication

### S3 Cross-Region Replication

```hcl
# terraform/aws/modules/s3/main.tf

# Primary bucket
resource "aws_s3_bucket" "fineract_reports" {
  bucket = "fineract-${var.environment}-reports-${data.aws_region.current.name}"

  tags = {
    Environment = var.environment
    Role        = "primary"
  }
}

# Enable versioning (required for replication)
resource "aws_s3_bucket_versioning" "fineract_reports" {
  bucket = aws_s3_bucket.fineract_reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Replica bucket
resource "aws_s3_bucket" "fineract_reports_replica" {
  provider = aws.dr_region

  bucket = "fineract-${var.environment}-reports-us-west-2"

  tags = {
    Environment = var.environment
    Role        = "replica"
  }
}

# Enable versioning on replica
resource "aws_s3_bucket_versioning" "fineract_reports_replica" {
  provider = aws.dr_region
  bucket   = aws_s3_bucket.fineract_reports_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Replication configuration
resource "aws_s3_bucket_replication_configuration" "fineract_reports" {
  bucket = aws_s3_bucket.fineract_reports.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.fineract_reports_replica.arn
      storage_class = "STANDARD"
    }
  }
}

# IAM role for replication
resource "aws_iam_role" "replication" {
  name = "s3-replication-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
```

---

## Infrastructure as Code

### Terraform Multi-Region Setup

```hcl
# terraform/aws/providers.tf

provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

provider "aws" {
  alias  = "dr_region"
  region = "us-west-2"
}

# Use primary provider by default
provider "aws" {
  region = "us-east-1"
}
```

```hcl
# terraform/aws/environments/production/main.tf

module "primary_region" {
  source = "../../modules"

  providers = {
    aws = aws.primary
  }

  environment = "production"
  region_role = "primary"
}

module "dr_region" {
  source = "../../modules"

  providers = {
    aws = aws.dr_region
  }

  environment = "production"
  region_role = "dr"

  # Reference primary resources
  primary_db_arn    = module.primary_region.db_arn
  primary_s3_bucket = module.primary_region.s3_bucket
}
```

---

## Failover Procedures

### Automated Failover Triggers

```yaml
# .github/workflows/automated-failover.yaml

name: Automated Multi-Region Failover

on:
  repository_dispatch:
    types: [initiate-failover]

jobs:
  failover:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Validate failover request
        run: |
          # Require approval for production
          echo "⚠️ FAILOVER INITIATED"
          echo "Primary region: ${{ github.event.client_payload.primary_region }}"
          echo "DR region: ${{ github.event.client_payload.dr_region }}"

      - name: Promote RDS replica
        run: |
          aws rds promote-read-replica \
            --db-instance-identifier fineract-production-replica \
            --region us-west-2

      - name: Update DNS (Route 53)
        run: |
          # Update Route 53 health check and failover records
          aws route53 change-resource-record-sets \
            --hosted-zone-id $HOSTED_ZONE_ID \
            --change-batch file://failover-dns-update.json

      - name: Restore sealed secrets keys
        run: |
          export DR_REGION="us-west-2"
          ./scripts/restore-sealed-secrets-keys.sh production

      - name: Deploy to DR cluster
        run: |
          export KUBECONFIG=$KUBECONFIG_DR
          kubectl apply -k environments/production/

      - name: Verify applications
        run: |
          ./scripts/verify-deployment.sh production us-west-2
```

### Manual Failover Checklist

```markdown
# Multi-Region Failover Checklist

## Pre-Failover (Decision Phase)

- [ ] Confirm primary region outage (not false alarm)
- [ ] Verify DR region health
- [ ] Notify stakeholders of pending failover
- [ ] Start incident timer (RTO tracking)
- [ ] Gather team on incident call

## Failover Execution (20-30 minutes)

### Step 1: Database Failover (5 minutes)

- [ ] Promote RDS read replica to primary
  ```bash
  aws rds promote-read-replica \
    --db-instance-identifier fineract-production-replica \
    --region us-west-2
  ```
- [ ] Wait for promotion: `aws rds wait db-instance-available`
- [ ] Verify database is writable

### Step 2: DNS Failover (2 minutes)

- [ ] Update Route 53 to point to DR region
- [ ] Verify DNS propagation: `dig api.fineract.com`
- [ ] Test from multiple locations

### Step 3: Sealed Secrets (5 minutes)

- [ ] Restore sealed secrets keys from replica
  ```bash
  export DR_REGION="us-west-2"
  ./scripts/restore-sealed-secrets-keys.sh production
  ```
- [ ] Verify key compatibility
- [ ] Check controller logs

### Step 4: Application Deployment (10 minutes)

- [ ] Configure kubectl for DR cluster
  ```bash
  export KUBECONFIG=/path/to/dr-cluster-kubeconfig
  ```
- [ ] Deploy ArgoCD applications
  ```bash
  kubectl apply -k environments/production/
  ```
- [ ] Wait for all pods to be ready
- [ ] Verify service endpoints

### Step 5: Verification (5 minutes)

- [ ] Test Fineract API: `curl https://api.fineract.com/health`
- [ ] Test Keycloak authentication
- [ ] Test frontend applications
- [ ] Check all critical workflows

## Post-Failover

- [ ] Update incident status (failover complete)
- [ ] Monitor for 1 hour
- [ ] Document issues encountered
- [ ] Update audit log: `operations/sealed-secrets-key-audit.yaml`
- [ ] Schedule post-mortem
```

---

## Failback Procedures

### When to Failback

Failback to primary region when:

1. Primary region fully recovered (all services healthy)
2. DR region stable for >4 hours
3. Database fully synchronized
4. Maintenance window scheduled (minimize user impact)

### Failback Process

```markdown
# Multi-Region Failback Checklist

## Pre-Failback Planning

- [ ] Confirm primary region fully recovered
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Backup DR region state

## Failback Execution

### Step 1: Reverse Database Replication

- [ ] Create new read replica in primary region from DR database
- [ ] Wait for replication to catch up
- [ ] Promote replica to primary
- [ ] Update connection strings

### Step 2: Sealed Secrets Synchronization

- [ ] Verify primary region has current keys
- [ ] Test key compatibility in primary cluster

### Step 3: Application Redeployment

- [ ] Configure kubectl for primary cluster
- [ ] Deploy applications to primary
- [ ] Verify all services healthy

### Step 4: DNS Failback

- [ ] Update Route 53 back to primary region
- [ ] Verify DNS propagation
- [ ] Monitor for errors

### Step 5: Cleanup

- [ ] Keep DR region in standby (don't destroy)
- [ ] Verify cross-region replication re-established
- [ ] Document lessons learned
```

---

## Testing and Validation

### Quarterly DR Drill

```bash
#!/bin/bash
# scripts/quarterly-dr-drill.sh

set -e

echo "🚨 QUARTERLY DR DRILL - $(date)"
echo "This is a TEST. No production impact."

# Step 1: Verify backups exist
echo "Step 1: Verifying backups in both regions..."
for REGION in us-east-1 us-west-2; do
  aws secretsmanager describe-secret \
    --secret-id /fineract/production/sealed-secrets/master-key \
    --region $REGION
done

# Step 2: Test restore in DR region (non-prod namespace)
echo "Step 2: Testing restore in DR region..."
export DR_REGION="us-west-2"
export TEST_NAMESPACE="dr-drill-$(date +%s)"

kubectl create namespace $TEST_NAMESPACE

# Deploy controller
kubectl apply -k apps/sealed-secrets-controller/base/ -n $TEST_NAMESPACE

# Restore keys
./scripts/restore-sealed-secrets-keys.sh production

# Test decryption
./scripts/validate-sealed-secrets-compatibility.sh

# Step 3: Cleanup
echo "Step 3: Cleanup..."
kubectl delete namespace $TEST_NAMESPACE

echo "✅ DR DRILL COMPLETE"
echo "Results logged to: docs/compliance/dr-drill-$(date +%Y-%m-%d).md"
```

### Automated Testing

Add to `.github/workflows/test-sealed-secrets-backup.yaml`:

```yaml
test-multi-region-replication:
  name: Test Multi-Region Replication
  runs-on: ubuntu-latest

  steps:
    - name: Verify replica exists
      run: |
        for ENV in dev uat production; do
          aws secretsmanager describe-secret \
            --secret-id /fineract/$ENV/sealed-secrets/master-key \
            --region us-west-2
        done

    - name: Compare primary and replica
      run: |
        PRIMARY=$(aws secretsmanager get-secret-value \
          --secret-id /fineract/production/sealed-secrets/master-key \
          --region us-east-1 \
          --query SecretString --output text)

        REPLICA=$(aws secretsmanager get-secret-value \
          --secret-id /fineract/production/sealed-secrets/master-key \
          --region us-west-2 \
          --query SecretString --output text)

        if [ "$PRIMARY" = "$REPLICA" ]; then
          echo "✅ Primary and replica are synchronized"
        else
          echo "❌ FAILURE: Primary and replica differ"
          exit 1
        fi
```

---

## Cost Analysis

### Additional Costs for Multi-Region DR

| Component | Current Cost | Multi-Region Cost | Increase |
|-----------|-------------|-------------------|----------|
| **RDS Read Replica** | $0 | ~$200/month | +$200 |
| **S3 Replication** | $50/month | $75/month | +$25 |
| **Secrets Manager Replication** | $2/month | $2/month | $0 (free) |
| **EKS DR Cluster** | $0 | $144/month (control plane) | +$144 |
| **Data Transfer (cross-region)** | $0 | ~$50/month | +$50 |
| **Total** | ~$250/month | ~$669/month | **+$419/month** |

### Cost Optimization Strategies

1. **Smaller DR Cluster**: Use t3.medium nodes instead of t3.large
2. **On-Demand DR**: Only provision EKS when needed (not pre-provisioned)
3. **Snapshot-Based**: Use RDS snapshots instead of continuous read replica
4. **Lifecycle Policies**: Automatically delete old S3 replicas

### Cost vs. Benefit

- **Additional Cost**: ~$5,000/year
- **Benefit**: Reduced RTO from 2-4 hours to 30 minutes
- **Risk Mitigation**: Protection against regional AWS outage
- **Recommendation**: Implement for production only, not dev/UAT

---

## Implementation Roadmap

### Phase 1: Planning & Design (Week 1-2)

- [ ] Review and approve this document
- [ ] Identify ownership and responsibilities
- [ ] Budget approval for additional costs
- [ ] Select DR region (us-west-2 recommended)

### Phase 2: Sealed Secrets Replication (Week 3)

- [ ] Update Terraform for Secrets Manager replication
- [ ] Apply Terraform changes
- [ ] Verify replication working
- [ ] Update backup/restore scripts
- [ ] Test restore from DR region

### Phase 3: Database Replication (Week 4-5)

- [ ] Create RDS read replicas in DR region
- [ ] Wait for replication to catch up
- [ ] Test read performance
- [ ] Document promotion procedure

### Phase 4: Storage Replication (Week 6)

- [ ] Configure S3 cross-region replication
- [ ] Verify replication working
- [ ] Test failover procedures

### Phase 5: DR Cluster Setup (Week 7-8)

- [ ] Provision EKS cluster in DR region
- [ ] Configure networking (VPC, subnets)
- [ ] Deploy sealed-secrets-controller
- [ ] Deploy ArgoCD

### Phase 6: DNS & Routing (Week 9)

- [ ] Configure Route 53 health checks
- [ ] Set up failover routing policies
- [ ] Test DNS failover

### Phase 7: Testing (Week 10-11)

- [ ] Execute failover drill (non-production)
- [ ] Document issues and lessons learned
- [ ] Refine procedures
- [ ] Executive tabletop exercise

### Phase 8: Production Rollout (Week 12)

- [ ] Schedule maintenance window
- [ ] Execute production failover test
- [ ] Failback to primary
- [ ] Document final procedures

---

## Success Criteria

Multi-region DR implementation is considered successful when:

- [ ] Sealed secrets keys replicated to DR region (verified)
- [ ] RDS read replica in DR region (<15 min lag)
- [ ] S3 replication enabled and tested
- [ ] DR EKS cluster provisioned and healthy
- [ ] Failover procedures documented and tested
- [ ] RTO <30 minutes (measured in drill)
- [ ] RPO <15 minutes (continuous replication)
- [ ] No data loss in failover test
- [ ] Quarterly DR drill passing
- [ ] Team trained on procedures

---

## Related Documentation

- [Sealed Secrets DR Runbook](/docs/SEALED_SECRETS_DR_RUNBOOK.md)
- [Disaster Recovery Guide](/docs/DISASTER_RECOVERY.md)
- [ADR-003: Sealed Secrets](/docs/architecture/ADR-003-sealed-secrets.md)
- [ADR-004: PostgreSQL Managed Services](/docs/architecture/ADR-004-postgresql-managed-services.md)

---

## Approval

| Role | Name | Approval | Date |
|------|------|----------|------|
| **DevOps Lead** | [Name] | [ ] Approved | [Date] |
| **Security Lead** | [Name] | [ ] Approved | [Date] |
| **Engineering Manager** | [Name] | [ ] Approved | [Date] |
| **CTO/VP Engineering** | [Name] | [ ] Approved | [Date] |

---

**Document Version**: 1.0
**Last Updated**: 2025-01-19
**Next Review**: 2025-04-19 (90 days)
**Maintained By**: DevOps Team
