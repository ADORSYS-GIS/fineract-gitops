variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

# RDS Variables
variable "rds_jdbc_url" {
  description = "RDS JDBC connection URL"
  type        = string
  sensitive   = true
}

variable "rds_host" {
  description = "RDS host address"
  type        = string
}

variable "rds_port" {
  description = "RDS port"
  type        = number
}

variable "rds_database" {
  description = "RDS database name"
  type        = string
}

variable "rds_username" {
  description = "RDS username"
  type        = string
  sensitive   = true
}

variable "rds_password" {
  description = "RDS password"
  type        = string
  sensitive   = true
}

# S3 Variables
variable "documents_bucket_name" {
  description = "S3 documents bucket name"
  type        = string
}

variable "backups_bucket_name" {
  description = "S3 backups bucket name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "s3_acceleration_enabled" {
  description = "Whether S3 transfer acceleration is enabled"
  type        = bool
  default     = false
}

# S3 IAM Credentials (optional - use IRSA when possible)
variable "s3_use_irsa" {
  description = "Use IRSA (IAM Roles for Service Accounts) instead of static credentials"
  type        = bool
  default     = true
}

variable "s3_access_key_id" {
  description = "AWS access key ID for S3 access (only if not using IRSA)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "AWS secret access key for S3 access (only if not using IRSA)"
  type        = string
  default     = ""
  sensitive   = true
}

# Redis Variables
variable "redis_host" {
  description = "Redis host address (in-cluster fineract-redis)"
  type        = string
  default     = "fineract-redis"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

# SES Variables
variable "ses_enabled" {
  description = "Whether AWS SES is enabled"
  type        = bool
  default     = false
}

variable "ses_smtp_host" {
  description = "SES SMTP host"
  type        = string
  default     = ""
}

variable "ses_smtp_port" {
  description = "SES SMTP port"
  type        = number
  default     = 587
}

variable "ses_smtp_username" {
  description = "SES SMTP username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ses_smtp_password" {
  description = "SES SMTP password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ses_sender_email" {
  description = "SES sender email address"
  type        = string
  default     = ""
}

variable "ses_sender_name" {
  description = "SES sender name"
  type        = string
  default     = ""
}

# IRSA Variables
variable "irsa_role_arn" {
  description = "IAM role ARN for IRSA"
  type        = string
}

# Labels and Annotations
variable "labels" {
  description = "Additional labels for Kubernetes resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations for Kubernetes resources"
  type        = map(string)
  default     = {}
}
