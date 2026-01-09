variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production"
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# EKS Configuration
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"  # EKS API accepts X.Y format (e.g., 1.31)

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.eks_cluster_version))
    error_message = "EKS cluster version must be in format X.Y (e.g., 1.31). EKS does not accept X.Y.Z format - use only major.minor version."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes for autoscaling"
  type        = number
  default     = 4
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the EKS cluster endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cloudwatch_observability" {
  description = "Enable CloudWatch Observability add-on (set to false to use Grafana/Prometheus instead)"
  type        = bool
  default     = true
}

# Route53 Configuration
variable "domain_name" {
  description = "Domain name for Route53 hosted zone (leave empty to skip DNS setup)"
  type        = string
  default     = ""
}

# Kubernetes Configuration
variable "kubernetes_namespace" {
  description = "Kubernetes namespace for Fineract"
  type        = string
  default     = "fineract-dev"
}

variable "service_account_name" {
  description = "Kubernetes service account name for Fineract workloads with IRSA"
  type        = string
  default     = "fineract-aws"
}

# RDS Configuration
variable "rds_postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.14"  # Current running version (cannot downgrade from 15.14 to 15.4)
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.small"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GB"
  type        = number
  default     = 100
}

variable "rds_storage_type" {
  description = "Storage type (gp3, gp2, io1)"
  type        = string
  default     = "gp3"
}

# Note: rds_database_name variable removed
# No default database is created by RDS
# Applications create their own databases via Kubernetes jobs:
# - fineract_tenants (created by Fineract schema migration job)
# - fineract_default (created by Fineract schema migration job)
# - keycloak (created by Keycloak database setup job)

variable "rds_master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "fineract"
}

variable "rds_max_connections" {
  description = "Maximum number of database connections (dynamically calculated if not set)"
  type        = number
  default     = null
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "rds_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "rds_performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "rds_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS instance (true for dev, false for production)"
  type        = bool
  default     = false
}

# S3 Configuration
variable "s3_enable_versioning" {
  description = "Enable versioning for documents bucket"
  type        = bool
  default     = true
}

variable "s3_documents_lifecycle_enabled" {
  description = "Enable lifecycle rules for documents bucket"
  type        = bool
  default     = true
}

variable "s3_backups_expiration_days" {
  description = "Days before expiring backups"
  type        = number
  default     = 365
}

variable "s3_enable_transfer_acceleration" {
  description = "Enable S3 Transfer Acceleration"
  type        = bool
  default     = false
}

variable "s3_enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering"
  type        = bool
  default     = false
}

variable "s3_force_destroy" {
  description = "Force destroy S3 buckets even if they contain objects (true for dev, false for production)"
  type        = bool
  default     = false
}

# Redis Variables (in-cluster fineract-redis)
variable "redis_host" {
  description = "Redis host address (in-cluster fineract-redis service name)"
  type        = string
  default     = "fineract-redis"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

# Encryption
variable "kms_key_id" {
  description = "KMS key ID for encryption (optional, will use AWS managed keys if not provided)"
  type        = string
  default     = null
}

# SES Configuration
variable "ses_enabled" {
  description = "Enable AWS SES for email sending"
  type        = bool
  default     = false
}

variable "ses_verified_emails" {
  description = "List of email addresses to verify for sending and receiving (sandbox mode)"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.ses_enabled || length(var.ses_verified_emails) > 0
    error_message = "At least one verified email address is required when SES is enabled"
  }
}

variable "ses_sender_email" {
  description = "Default sender email address (must be in verified_emails list)"
  type        = string
  default     = ""
}

variable "ses_sender_name" {
  description = "Default sender name for emails"
  type        = string
  default     = "Fineract Platform"
}

variable "ses_domain" {
  description = "Domain name for SES domain identity (for production mode, optional)"
  type        = string
  default     = null
}

variable "ses_allowed_sender_patterns" {
  description = "List of allowed sender email patterns (e.g., *@yourdomain.com)"
  type        = list(string)
  default     = ["*"]
}

variable "ses_enable_cross_account_sending" {
  description = "Enable cross-account sending authorization"
  type        = bool
  default     = false
}

variable "ses_authorized_sender_arns" {
  description = "List of AWS account ARNs authorized to send emails (if cross-account enabled)"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# GitHub Token for ArgoCD - REMOVED (P0 Security Fix)
# GitHub tokens are now stored in AWS Secrets Manager instead of Terraform variables
#
# To create the secret:
#   aws secretsmanager create-secret \
#     --name /fineract/dev/github-token \
#     --description "GitHub PAT for ArgoCD repository access" \
#     --secret-string "ghp_your_token_here"
#
# The seal-argocd-github-credentials.sh script can fetch the token from Secrets Manager
# See: scripts/seal-argocd-github-credentials.sh --help
