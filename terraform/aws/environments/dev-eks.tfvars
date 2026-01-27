# Environment Configuration
environment  = "dev"
aws_region   = "eu-central-1"
cluster_name = "apache-fineract-dev"

# EKS Configuration
eks_cluster_version = "1.31"
node_instance_types = ["t3.large"]
node_desired_size   = 3
node_min_size       = 2
node_max_size       = 4
# Cost Optimization: Use Spot instances for dev (70% savings)
# Note: Spot instances may be interrupted with 2-minute warning
node_capacity_type = "SPOT"
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]  # Allow from anywhere for dev
enable_cloudwatch_observability = false  # Disabled - using Grafana/Prometheus instead
# Cost Optimization: Enable VPC endpoints to reduce NAT Gateway data transfer costs
enable_vpc_endpoints = true

# VPC Configuration
vpc_cidr = "10.0.0.0/16"

# Route53 Configuration (leave empty to skip DNS setup)
domain_name = ""  # Update to your domain when ready (e.g., "fineract.com")

# Kubernetes Configuration
kubernetes_namespace = "fineract-dev"

# RDS Configuration
rds_postgres_version      = "15.14"
rds_instance_class        = "db.t4g.small"
rds_allocated_storage     = 20
rds_max_allocated_storage = 100
rds_storage_type          = "gp3"
# Note: rds_database_name removed - no default database created
# Applications create their own databases via Kubernetes jobs
rds_master_username       = "fineract"
rds_max_connections       = "200"
rds_multi_az              = false
rds_backup_retention_period     = 7
rds_performance_insights_enabled = true
rds_monitoring_interval          = 60
# Dev: Disable deletion protection for easy destroy (zero cost when not in use)
# Production should set this to true
rds_deletion_protection          = false
rds_skip_final_snapshot          = true  # No final snapshot needed in dev

# S3 Configuration
s3_enable_versioning           = true
s3_documents_lifecycle_enabled = true
s3_backups_expiration_days     = 365
s3_enable_transfer_acceleration = false
# Cost Optimization: Enable intelligent tiering for automatic storage class transitions
s3_enable_intelligent_tiering   = true
# Dev: Enable force_destroy to allow terraform destroy to delete buckets with objects
# Production should set this to false for data protection
s3_force_destroy               = true

# Redis Configuration (in-cluster)
redis_host = "fineract-redis"
redis_port = 6379

# SES Configuration (disabled by default)
ses_enabled = false
# ses_verified_emails = ["admin@example.com"]
# ses_sender_email    = "admin@example.com"
# ses_sender_name     = "Fineract Platform"

# Tags
tags = {
  Project     = "fineract"
  Environment = "dev"
  ManagedBy   = "terraform"
  Migration   = "k3s-to-eks"
}
