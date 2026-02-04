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

variable "namespace" {
  description = "Kubernetes namespace for Fineract"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "fineract-gcp"
}

variable "documents_bucket_name" {
  description = "Name of the documents GCS bucket"
  type        = string
}

variable "backups_bucket_name" {
  description = "Name of the backups GCS bucket"
  type        = string
}

variable "labels" {
  description = "Additional labels"
  type        = map(string)
  default     = {}
}

variable "gke_cluster_id" {
  description = "GKE cluster ID - used to ensure Workload Identity bindings are created after the cluster"
  type        = string
  default     = ""
}

variable "enable_workload_identity" {
  description = "Whether to create Workload Identity bindings (requires GKE cluster to exist)"
  type        = bool
  default     = true
}
