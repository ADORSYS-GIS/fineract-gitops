# Production Environment Configuration
# High availability, performance, and reliability optimized

# Basic Configuration
cluster_name = "fineract-prod"
environment  = "production"
aws_region   = "us-east-2"

# Network Configuration
# IMPORTANT: Replace these with your actual VPC and subnet IDs
# Use subnets in different AZs for high availability
vpc_id              = "vpc-xxxxx"                                      # Your production VPC ID
database_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy", "subnet-zzzzz"] # Private subnets in 3 AZs
cache_subnet_ids    = ["subnet-xxxxx", "subnet-yyyyy", "subnet-zzzzz"] # Private subnets in 3 AZs

# EKS Configuration
# IMPORTANT: Replace these with your EKS cluster details
eks_cluster_security_group_id = "sg-xxxxx"                                          # Your EKS cluster security group
eks_oidc_provider_url         = "https://oidc.eks.us-east-2.amazonaws.com/id/XXXXX" # Your EKS OIDC provider URL

# Kubernetes
kubernetes_namespace = "fineract-production"

# RDS Configuration - Production Grade
# Note: PostgreSQL 15.14 is recommended (see docs/VERSION_MATRIX.md)
# Update carefully during maintenance window: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.PostgreSQL.html
rds_postgres_version      = "15.14"
rds_instance_class        = "db.r6g.large" # Production instance with 16GB RAM
rds_allocated_storage     = 100
rds_max_allocated_storage = 1000  # Allow growth to 1TB
rds_storage_type          = "gp3" # Or "io2" for high IOPS workloads

# Note: rds_database_name removed - no default database created
# Applications create their own databases via Kubernetes jobs
rds_master_username = "fineract"
rds_max_connections = "500"

# Multi-AZ for high availability
rds_multi_az                = true
rds_backup_retention_period = 30 # 30 days of backups

# Monitoring
rds_performance_insights_enabled = true
rds_monitoring_interval          = 30 # Enhanced monitoring every 30s

# Deletion protection ON for production
rds_deletion_protection = true

# ElastiCache Configuration - Production Grade
redis_version            = "7.0"
redis_node_type          = "cache.r6g.large" # Production instance with 13GB RAM
redis_num_cache_clusters = 3                 # Primary + 2 replicas across AZs

# Encryption
redis_encryption_at_rest    = true
redis_encryption_in_transit = true # TLS enabled for security
redis_auth_token_enabled    = true # Redis AUTH enabled

redis_snapshot_retention_limit = 14 # 14 days of snapshots

# S3 Configuration
s3_enable_versioning           = true
s3_documents_lifecycle_enabled = true
s3_backups_expiration_days     = 2555 # 7 years for compliance

# Performance features
s3_enable_transfer_acceleration = true # Faster uploads globally
s3_enable_intelligent_tiering   = true # Automatic cost optimization

# Encryption with customer-managed keys (recommended)
# kms_key_id = "arn:aws:kms:us-east-2:123456789012:key/xxxxx"

# Additional Tags
tags = {
  # Existing tags
  Project     = "fineract"
  Environment = "production"
  ManagedBy   = "terraform"
  Repository  = "fineract-gitops"
  Migration   = "k3s-to-eks"
  CostCenter  = "operations"
  Team        = "platform"
  Purpose     = "production"
  Compliance  = "required"
  Backup      = "daily"
  Monitoring  = "24x7"

  # NEW: Additional cost tracking tags
  Owner       = "platform-team"
  Component   = "production"
  Workload    = "production"
  Criticality = "high"
  SLA         = "99.9"
  BillingCode = "PROD-001"
}

# Estimated Monthly Cost: ~$600-700
# - RDS db.r6g.large Multi-AZ: ~$380
# - ElastiCache cache.r6g.large x3: ~$240
# - S3 storage: ~$30-50 (for moderate usage)
# - Data transfer: ~$20-30
# - Backups: ~$10-20
# - KMS: ~$1
# - Transfer Acceleration: ~$5-10

# Cost Optimization Notes:
# 1. Use Reserved Instances for 30-40% discount (1-year commitment)
# 2. Consider Savings Plans for flexible commitments
# 3. Use Graviton instances (r6g) instead of Intel (r6i) for 20% cost savings
# 4. Monitor and adjust instance sizes based on actual usage
# 5. Use S3 Intelligent Tiering to automatically move data to cheaper tiers
