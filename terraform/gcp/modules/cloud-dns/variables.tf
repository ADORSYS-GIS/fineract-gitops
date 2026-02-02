variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the DNS zone"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "labels" {
  description = "Additional labels"
  type        = map(string)
  default     = {}
}
