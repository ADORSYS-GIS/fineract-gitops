variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where SES is configured"
  type        = string
}

variable "verified_emails" {
  description = "List of email addresses to verify for sending and receiving (sandbox mode)"
  type        = list(string)

  validation {
    condition     = length(var.verified_emails) > 0
    error_message = "At least one verified email address is required"
  }
}

variable "sender_email" {
  description = "Default sender email address (must be in verified_emails list)"
  type        = string
}

variable "sender_name" {
  description = "Default sender name for emails"
  type        = string
  default     = "Fineract Platform"
}

variable "domain" {
  description = "Domain name for SES domain identity (for production mode, optional)"
  type        = string
  default     = null
}

variable "allowed_sender_patterns" {
  description = "List of allowed sender email patterns (e.g., *@yourdomain.com)"
  type        = list(string)
  default     = ["*"]
}

variable "enable_cross_account_sending" {
  description = "Enable cross-account sending authorization"
  type        = bool
  default     = false
}

variable "authorized_sender_arns" {
  description = "List of AWS account ARNs authorized to send emails (if cross-account enabled)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
