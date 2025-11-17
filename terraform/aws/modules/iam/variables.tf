variable "cluster_name" {
  description = "Name of the cluster (EKS or K3s)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Fineract"
  type        = string
  default     = "fineract-dev"
}

variable "service_account_name" {
  description = "Kubernetes service account name for Fineract workloads with IRSA"
  type        = string
  default     = "fineract-aws"
}

variable "use_instance_profile" {
  description = "Use EC2 instance profile instead of IRSA (for K3s deployments)"
  type        = bool
  default     = false
}

variable "k3s_role_name" {
  description = "K3s IAM role name to attach policies (optional, for K3s deployments)"
  type        = string
  default     = null
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (required for EKS, not needed for K3s)"
  type        = string
  default     = null
}

variable "rds_instance_arn" {
  description = "RDS instance ARN"
  type        = string
}

variable "documents_bucket_arn" {
  description = "Documents S3 bucket ARN"
  type        = string
}

variable "backups_bucket_arn" {
  description = "Backups S3 bucket ARN"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN (optional)"
  type        = string
  default     = null
}

variable "ses_enabled" {
  description = "Whether AWS SES is enabled (adds SES permissions to IAM role)"
  type        = bool
  default     = false
}

variable "ses_identity_arn" {
  description = "SES identity ARN to scope email sending (e.g., arn:aws:ses:us-east-1:123456789:identity/example.com)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
