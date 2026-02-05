variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster (used in resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_self_link" {
  description = "VPC network self link for private IP"
  type        = string
}

variable "instance_tier" {
  description = "Cloud SQL instance tier (db-custom-CPU-RAM)"
  type        = string
  default     = "db-custom-2-4096"
}

variable "disk_size" {
  description = "Initial disk size in GB"
  type        = number
  default     = 20
}

variable "max_disk_size" {
  description = "Maximum disk size for auto-resize in GB"
  type        = number
  default     = 100
}

variable "availability_type" {
  description = "ZONAL for single zone, REGIONAL for HA"
  type        = string
  default     = "ZONAL"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_15"
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "fineract"
}

variable "max_connections" {
  description = "Maximum database connections"
  type        = number
  default     = 100
}

variable "backup_retention_count" {
  description = "Number of backups to retain"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection"
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

variable "require_ssl" {
  description = "Require SSL connections (disable for dev/testing)"
  type        = bool
  default     = false
}
