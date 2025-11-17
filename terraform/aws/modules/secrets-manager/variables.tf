variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, uat, production)"
  type        = string
}

variable "secret_prefix" {
  description = "Prefix for secret names in AWS Secrets Manager"
  type        = string
  default     = "/fineract"
}

variable "recovery_window_in_days" {
  description = "Recovery window for secret deletion in days (7-30, shorter for dev, longer for production)"
  type        = number
  default     = 7
  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "Recovery window must be between 7 and 30 days."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
