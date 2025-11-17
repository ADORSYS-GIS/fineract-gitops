variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (optional)"
  type        = string
  default     = null
}

variable "enable_versioning" {
  description = "Enable versioning for documents bucket"
  type        = bool
  default     = true
}

variable "documents_lifecycle_enabled" {
  description = "Enable lifecycle rules for documents bucket"
  type        = bool
  default     = true
}

variable "documents_noncurrent_version_expiration_days" {
  description = "Days to expire noncurrent document versions"
  type        = number
  default     = 365
}

variable "backups_transition_to_ia_days" {
  description = "Days before transitioning backups to Infrequent Access"
  type        = number
  default     = 30
}

variable "backups_transition_to_glacier_days" {
  description = "Days before transitioning backups to Glacier"
  type        = number
  default     = 90
}

variable "backups_expiration_days" {
  description = "Days before expiring backups"
  type        = number
  default     = 365
}

variable "enable_cors" {
  description = "Enable CORS for documents bucket"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "Allowed origins for CORS - must be explicitly set per environment (no wildcard default)"
  type        = list(string)
  default     = []
}

variable "enable_access_logging" {
  description = "Enable access logging"
  type        = bool
  default     = false
}

variable "logging_bucket_id" {
  description = "S3 bucket ID for access logs (optional)"
  type        = string
  default     = null
}

variable "enable_transfer_acceleration" {
  description = "Enable S3 Transfer Acceleration"
  type        = bool
  default     = false
}

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering"
  type        = bool
  default     = false
}

variable "intelligent_tiering_archive_days" {
  description = "Number of days before transitioning to ARCHIVE_ACCESS tier"
  type        = number
  default     = 90
}

variable "intelligent_tiering_deep_archive_days" {
  description = "Number of days before transitioning to DEEP_ARCHIVE_ACCESS tier"
  type        = number
  default     = 180
}

variable "force_destroy" {
  description = "Force destroy S3 buckets even if they contain objects (true for dev, false for production)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
