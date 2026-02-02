variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the GKE subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_range_cidr" {
  description = "Secondary CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_range_cidr" {
  description = "Secondary CIDR range for services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for internal traffic to Google APIs"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
