variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "force_destroy" {
  description = "Force destroy buckets even if they contain objects"
  type        = bool
  default     = false
}

variable "backups_expiration_days" {
  description = "Days before deleting backups"
  type        = number
  default     = 90
}

variable "enable_versioning" {
  description = "Enable versioning for documents bucket"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center label"
  type        = string
  default     = "engineering"
}

variable "billing_code" {
  description = "Billing code label"
  type        = string
  default     = "DEV-001"
}

variable "labels" {
  description = "Additional labels"
  type        = map(string)
  default     = {}
}
