# AWS Cost Analysis - Fineract GitOps Architecture

## 💰 Monthly Cost Estimate

### Base Configuration (Development/UAT)

| Category | Component | Specifications | Monthly Cost (USD) |
|----------|-----------|---------------|-------------------|
| **Compute (EKS)** | Control Plane | EKS Cluster | $73 |
| | Worker Nodes (3x t3.2xlarge) | 8 vCPU, 32GB RAM each | $300 |
| | **Compute Subtotal** | | **$373** |
| **Storage** | EBS GP3 (685GB) | 3,000 IOPS, 125 MB/s | $68 |
| | EBS Snapshots (200GB) | Daily backups | $4 |
| | **Storage Subtotal** | | **$72** |
| **Networking** | Application Load Balancer | For web apps | $23 |
| | Network Load Balancer | For Fineract API | $23 |
| | NAT Gateway (2 AZs) | High availability | $90 |
| | Data Transfer (estimated) | 100GB/month outbound | $9 |
| | **Networking Subtotal** | | **$145** |
| **Managed Services** | RDS PostgreSQL (db.t3.large) | Optional alternative | $0 (using self-hosted) |
| | ElastiCache Redis (cache.t3.small) | Optional alternative | $0 (using self-hosted) |
| **Monitoring** | CloudWatch Logs (10GB) | Application logs | $5 |
| | CloudWatch Metrics | Custom metrics | $3 |
| | **Monitoring Subtotal** | | **$8** |

### **TOTAL - Development/UAT: ~$598/month**

---

### Production Configuration (High Availability)

| Category | Component | Specifications | Monthly Cost (USD) |
|----------|-----------|---------------|-------------------|
| **Compute (EKS)** | Control Plane | EKS Cluster | $73 |
| | Worker Nodes (6x m5.2xlarge) | 8 vCPU, 32GB RAM each, 3 AZs | $1,152 |
| | **Compute Subtotal** | | **$1,225** |
| **Storage** | EBS GP3 (2TB) | 12,000 IOPS, 500 MB/s | $200 |
| | EBS Snapshots (800GB) | Daily backups, 7 days | $16 |
| | **Storage Subtotal** | | **$216** |
| **Networking** | Application Load Balancer | Multi-AZ | $23 |
| | Network Load Balancer | Multi-AZ | $23 |
| | NAT Gateway (3 AZs) | Production HA | $135 |
| | Data Transfer (estimated) | 500GB/month outbound | $45 |
| | **Networking Subtotal** | | **$226** |
| **Monitoring** | CloudWatch Logs (50GB) | Application + audit logs | $25 |
| | CloudWatch Metrics | Custom + detailed | $10 |
| | **Monitoring Subtotal** | | **$35** |

### **TOTAL - Production: ~$1,702/month**

---

## 🎯 Cost Optimization Strategies

### **Level 1: Low-Hanging Fruit (Save 30-40%)**

#### 1. **Use AWS Managed Services** ($150-200/month savings)

Replace self-hosted components with AWS managed alternatives:

```yaml
# Current: Self-hosted PostgreSQL
# - 3 replicas × (550m CPU, 1Gi RAM, 50Gi storage)
# - Total: 1650m CPU, 3Gi RAM, 150Gi storage
# - Requires operational overhead

# Optimized: RDS PostgreSQL
# - db.t3.large (2 vCPU, 8GB RAM)
# - Multi-AZ for HA
# - Automated backups, patching, monitoring
# Cost: $110/month (vs ~$150 compute + ops time)
# Savings: ~$40/month + reduced operations
```

**Replace:**
- **PostgreSQL** → RDS PostgreSQL (db.t3.large Multi-AZ): $110/month
- **Redis** → ElastiCache Redis (cache.t3.small): $37/month
- **MinIO** → S3 Standard (400GB + requests): $9/month

**Impact:**
- Remove 9 pods (3 PostgreSQL, 3 Redis, 1 MinIO = 4 pods)
- Free up: 2,550m CPU, 4.5Gi RAM, 475Gi storage
- Savings: ~$180/month in compute + storage

#### 2. **Right-Size EC2 Instances** ($100-150/month savings)

Current allocation wastes resources due to over-provisioning:

```bash
# Current Resource Usage (Base)
CPU Requests: 16.85 cores (but limits: 39.2 cores)
Memory Requests: 28.6Gi (but limits: 67.5Gi)

# Actual usage typically: 60-70% of requests
Real CPU need: ~10-12 cores
Real Memory need: ~17-20Gi
```

**Optimization:**
```yaml
# Current: 3x t3.2xlarge (24 vCPU, 96GB RAM) = $300/month
# Optimized: 2x m5.xlarge (8 vCPU, 32GB RAM) = $140/month
# Savings: $160/month
```

#### 3. **Use Spot Instances for Non-Critical Workloads** ($80-120/month savings)

```yaml
# Apply to:
# - Fineract batch workers (can tolerate interruption)
# - Frontend web apps (stateless, quick restart)
# - Monitoring/logging pods (non-critical)

# Savings: 70% off on-demand price
# 40% of workload on Spot = $120/month saved
```

#### 4. **Optimize NAT Gateway** ($45-90/month savings)

```yaml
# Current: NAT Gateway in each AZ (2-3 gateways)
# Cost: $45/month per gateway = $90-135/month

# Option A: Single NAT Gateway (dev/uat)
# - Risk: Single point of failure
# - Savings: $45-90/month

# Option B: NAT Instances (t3.nano)
# - Cost: $5-10/month
# - Savings: $80-125/month
# - Trade-off: Manual management

# Recommended for Dev/UAT: Single NAT Gateway
# Recommended for Prod: Keep Multi-AZ NAT
```

#### 5. **Reduce Load Balancers** ($23/month savings)

```yaml
# Current: 2 Load Balancers
# - ALB for web apps: $23/month
# - NLB for Fineract API: $23/month

# Optimized: 1 ALB for everything
# - Use path-based routing: /api/* → Fineract, /* → web apps
# - Savings: $23/month
```

### **Level 1 Total Savings: $460-610/month (40-70%)**

---

### **Level 2: Architecture Optimizations (Save Additional 20-30%)**

#### 6. **Reduce Fineract Read Replicas in Dev/UAT** ($50/month savings)

```yaml
# Current: 3 read replicas (for load testing)
# Production need: 3-5 replicas
# Dev/UAT need: 1-2 replicas

# Optimization:
environments/dev/patches/fineract-replicas.yaml:
  fineract-read: 1 replica  # was: 3

# Freed resources: 2000m CPU, 4Gi RAM
# Savings: ~$50/month
```

#### 7. **Consolidate Frontend Apps** ($30/month savings)

```yaml
# Current: 4 separate web apps × 2 replicas = 8 pods
# - admin, account-manager, branch-manager, cashier
# - Each: 50m CPU, 64Mi RAM

# Optimized: Single microfrontend with lazy loading
# - 1 app × 2 replicas = 2 pods
# - Freed: 300m CPU, 384Mi RAM
# - Savings: ~$30/month
```

#### 8. **Use EBS GP3 with Lower IOPS** ($20-30/month savings)

```yaml
# Current: Default GP3 (3,000 IOPS)
# Actual need (dev/uat): 1,000-1,500 IOPS

# Optimization:
# - PostgreSQL: 2,000 IOPS (vs 3,000)
# - Kafka: 2,000 IOPS (vs 3,000)
# - Others: 1,000 IOPS baseline

# GP3 pricing: $0.005/IOPS/month
# Savings: ~$25/month
```

#### 9. **Implement Pod Disruption Budgets + Cluster Autoscaler** ($100-150/month)

```yaml
# Enable aggressive scale-down during off-hours
# - Scale to 50% capacity nights/weekends (dev/uat)
# - 40 hours/week at 50% = 24% monthly savings

# Dev/UAT compute: $300/month
# Savings: ~$72/month

# Add Karpenter for better bin-packing
# - Reduce node count by 20-30%
# - Additional savings: $60/month
```

#### 10. **Disable Kafka/ZooKeeper in Dev (Events Optional)** ($60/month savings)

```yaml
# Current: Kafka + ZooKeeper always running
# - Kafka: 1050m CPU, 2Gi RAM, 100Gi storage
# - ZooKeeper: 300m CPU, 576Mi RAM, 15Gi storage

# Optimization (dev/uat):
environments/dev/kustomization.yaml:
  # Comment out Kafka resources
  # - ../apps/kafka/base

# Freed: 1350m CPU, 2.5Gi RAM, 115Gi storage
# Savings: ~$60/month
```

### **Level 2 Total Savings: $330-400/month (20-30%)**

---

### **Level 3: Advanced Optimizations (Save Additional 10-15%)**

#### 11. **Use Reserved Instances / Savings Plans** ($150-250/month)

```yaml
# 1-year Partial Upfront Reserved Instances
# Discount: 30-40% vs On-Demand

# Apply to baseline capacity:
# - 2x m5.xlarge (always-on production nodes)
# - Savings: $150-250/month
```

#### 12. **Implement Intelligent Tiering for Logs/Backups** ($15-25/month)

```yaml
# Current: All logs/backups in hot storage

# Optimized:
# - CloudWatch Logs: Retention 7 days → Glacier after
# - EBS Snapshots: Lifecycle policy (30 days → deleted)
# - Loki: 7 days hot → 30 days S3 Standard-IA → 90 days Glacier

# Savings: ~$20/month
```

#### 13. **Use AWS Graviton Instances** ($60-90/month)

```yaml
# Graviton (ARM64) instances: 20% cheaper, 40% better performance

# Replace:
# - t3.2xlarge → t4g.2xlarge (-20% cost)
# - m5.xlarge → m6g.xlarge (-20% cost)

# Requirement: Fineract must support ARM64
# Check: java -version (ARM64 JDK available)

# Savings: ~$75/month (20% of $375 compute)
```

#### 14. **Optimize Docker Images** ($10-20/month savings)

```yaml
# Current: Full JDK images (~500MB+)
# Optimized: Distroless/Alpine JRE images (~200MB)

# Benefits:
# - Faster pod startup (reduced EBS I/O)
# - Lower image pull costs
# - Reduced storage for image layers

# Savings: ~$15/month (reduced IOPS + storage)
```

### **Level 3 Total Savings: $235-385/month (15-25%)**

---

## 💡 Recommended Optimization Roadmap

### **Phase 1: Immediate (Week 1) - Save $460/month**

1. ✅ Switch to managed services (PostgreSQL → RDS, Redis → ElastiCache)
2. ✅ Use S3 instead of MinIO
3. ✅ Right-size EC2 instances (3x t3.2xlarge → 2x m5.xlarge)
4. ✅ Single NAT Gateway for dev/uat
5. ✅ Consolidate to 1 ALB

**New Dev/UAT Cost: $138/month (was $598)**

### **Phase 2: Short-term (Month 1) - Save Additional $330/month**

6. ✅ Reduce Fineract read replicas in dev/uat (3 → 1)
7. ✅ Disable Kafka/ZooKeeper in dev (events optional)
8. ✅ Implement cluster autoscaler with aggressive scale-down
9. ✅ Consolidate frontend apps (microfrontend architecture)
10. ✅ Lower EBS IOPS for dev/uat workloads

**New Dev/UAT Cost: $108/month (was $138)**
**Savings from baseline: $490/month (82%)**

### **Phase 3: Long-term (Quarters 2-3) - Save Additional $235/month**

11. ✅ Purchase 1-year Reserved Instances for production
12. ✅ Migrate to Graviton instances (ARM64)
13. ✅ Implement intelligent tiering for logs/backups
14. ✅ Optimize Docker images (distroless + multi-stage builds)

---

## 📊 Final Cost Comparison

| Environment | Current | Phase 1 | Phase 2 | Phase 3 | Total Savings |
|-------------|---------|---------|---------|---------|---------------|
| **Dev** | $598 | $138 | $54 | $40 | **93% saved** |
| **UAT** | $598 | $138 | $54 | $40 | **93% saved** |
| **Production** | $1,702 | $1,150 | $950 | $700 | **59% saved** |
| **TOTAL (all 3)** | **$2,898** | **$1,426** | **$1,058** | **$780** | **73% saved** |

---

## 🚀 Ultra-Low-Cost Architecture (Single-Node Dev)

For development/testing only:

```yaml
# Single t3.xlarge node (4 vCPU, 16GB RAM): $61/month
# + EKS control plane: $73/month
# + 100GB EBS: $10/month
# + Single ALB: $23/month
# = $167/month total

# Trade-offs:
# - No high availability
# - Limited scalability
# - Single point of failure
# - Suitable for: personal dev, demos, testing
```

**Components to run:**
- Fineract (1 write, 1 read, 1 batch)
- PostgreSQL (1 replica, local PVC)
- Redis (1 replica, local PVC)
- Apache Gateway + Keycloak + 1 web app

**Not included:**
- Kafka/ZooKeeper
- MinIO (use S3 free tier: 5GB)
- Multiple AZs
- High availability

---

## 🔍 Cost Monitoring & Alerts

### Set Up AWS Cost Anomaly Detection

```bash
# Create budget alert
aws budgets create-budget \
  --account-id ACCOUNT_ID \
  --budget file://budget.json

# budget.json
{
  "BudgetName": "fineract-monthly-budget",
  "BudgetLimit": {
    "Amount": "200",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

### Tag Resources for Cost Tracking

```yaml
# Add to all resources
labels:
  cost-center: fineract
  environment: dev|uat|prod
  component: compute|storage|networking|managed-services

# Enable AWS Cost Explorer filtering
```

### Monthly Cost Review Checklist

- [ ] Review AWS Cost Explorer by service
- [ ] Check EBS volumes without attachments
- [ ] Review EBS snapshots older than 30 days
- [ ] Check Load Balancer idle time (>50% idle = waste)
- [ ] Review NAT Gateway data processed
- [ ] Check CloudWatch Logs retention (reduce if >7 days)
- [ ] Review RDS/ElastiCache utilization (<60% = downsize)
- [ ] Check for unused Elastic IPs

---

## 📝 Additional Cost Considerations

### Not Included in Estimates:

1. **Domain & SSL Certificates**
   - Route53: $0.50/hosted zone/month
   - ACM certificates: Free

2. **Backups & Disaster Recovery**
   - S3 backup storage: ~$10-30/month
   - RDS automated backups: Free (7 days)

3. **Development Tools**
   - GitHub Actions: Free tier sufficient
   - ArgoCD: Self-hosted (already included)

4. **Support Plans**
   - Developer: $29/month
   - Business: $100/month (min)

5. **Data Transfer Costs**
   - Inter-AZ: $0.01/GB
   - To Internet: $0.09/GB
   - Highly variable based on usage

---

## 🎯 Recommended Configuration

### **Development Environment: $54/month**

- 1x t3.xlarge node
- RDS PostgreSQL db.t3.micro
- ElastiCache Redis cache.t3.micro
- S3 for object storage
- Single ALB
- Single NAT Gateway
- Autoscaling off-hours (50% scale-down)

### **Production Environment: $700/month**

- 3x m6g.xlarge nodes (Graviton, ARM64)
- RDS PostgreSQL db.t3.large Multi-AZ
- ElastiCache Redis cache.t3.small Multi-AZ
- S3 with Intelligent Tiering
- ALB with WAF
- NAT Gateway per AZ (3)
- Reserved Instances (1-year)
- CloudWatch detailed monitoring

---

## 🔗 References

- [AWS EKS Pricing](https://aws.amazon.com/eks/pricing/)
- [AWS EC2 Pricing Calculator](https://calculator.aws)
- [AWS Cost Optimization Best Practices](https://aws.amazon.com/economics/)
- [Kubernetes Cluster Autoscaler](https://github.com/kubernetes/autoscaler)
- [Karpenter](https://karpenter.sh/) - Better node autoscaling for EKS
