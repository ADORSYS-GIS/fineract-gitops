variable "project_id" {
  description = "GCP project ID"
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

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "Database host/IP"
  type        = string
}

variable "db_connection" {
  description = "Cloud SQL connection name"
  type        = string
}

variable "labels" {
  description = "Additional labels"
  type        = map(string)
  default     = {}
}
