variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone (for zonal clusters)"
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

variable "gke_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

# Network configuration
variable "network_self_link" {
  description = "VPC network self link"
  type        = string
}

variable "subnet_self_link" {
  description = "Subnet self link"
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary range for services"
  type        = string
}

# Node pool configuration
variable "machine_type" {
  description = "Machine type for nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "node_desired_count" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum nodes for autoscaling"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum nodes for autoscaling"
  type        = number
  default     = 5
}

variable "use_preemptible" {
  description = "Use preemptible VMs"
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "Boot disk type"
  type        = string
  default     = "pd-balanced"
}

variable "node_service_account_email" {
  description = "Service account email for GKE nodes"
  type        = string
}

variable "enable_batch_node_pool" {
  description = "Enable dedicated batch node pool"
  type        = bool
  default     = false
}

# Cost tracking
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
