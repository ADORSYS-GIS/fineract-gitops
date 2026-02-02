# ==============================================================================
# GCP Project Configuration
# ==============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone (for zonal resources like dev cluster)"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, uat, production)"
  type        = string

  validation {
    condition     = contains(["dev", "uat", "production"], var.environment)
    error_message = "Environment must be one of: dev, uat, production"
  }
}

# ==============================================================================
# GKE Configuration
# ==============================================================================

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "apache-fineract"
}

variable "gke_version" {
  description = "Kubernetes version for GKE cluster (use 'latest' for latest available)"
  type        = string
  default     = "1.29"
}

variable "machine_type" {
  description = "Machine type for GKE nodes (e2-standard-2 for cost-effective, n2d-standard-4 for production)"
  type        = string
  default     = "e2-standard-2"
}

variable "node_desired_count" {
  description = "Desired number of nodes per zone"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of nodes per zone for autoscaling"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum number of nodes per zone for autoscaling"
  type        = number
  default     = 5
}

variable "use_preemptible" {
  description = "Use preemptible VMs for cost savings (60-80% cheaper, but can be terminated). Recommended for dev/uat."
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for GKE nodes"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "Boot disk type (pd-balanced, pd-ssd, pd-standard)"
  type        = string
  default     = "pd-balanced"
}

# ==============================================================================
# VPC Configuration
# ==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC (primary range)"
  type        = string
  default     = "10.0.0.0/16"
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
  description = "Enable Private Google Access for internal traffic to Google APIs (cost optimization)"
  type        = bool
  default     = true
}

# ==============================================================================
# Cloud SQL Configuration
# ==============================================================================

variable "sql_instance_tier" {
  description = "Cloud SQL instance tier (db-custom-CPU-RAM format, e.g., db-custom-2-4096 for 2 vCPU, 4GB RAM)"
  type        = string
  default     = "db-custom-2-4096"
}

variable "sql_disk_size" {
  description = "Initial disk size in GB for Cloud SQL"
  type        = number
  default     = 20
}

variable "sql_max_disk_size" {
  description = "Maximum disk size for auto-resize in GB"
  type        = number
  default     = 100
}

variable "sql_availability_type" {
  description = "Availability type for Cloud SQL (ZONAL for single zone, REGIONAL for HA)"
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.sql_availability_type)
    error_message = "sql_availability_type must be ZONAL or REGIONAL"
  }
}

variable "sql_backup_retention_count" {
  description = "Number of backups to retain"
  type        = number
  default     = 7
}

variable "sql_postgres_version" {
  description = "PostgreSQL version for Cloud SQL"
  type        = string
  default     = "POSTGRES_15"
}

variable "sql_master_username" {
  description = "Master username for Cloud SQL"
  type        = string
  default     = "fineract"
}

variable "sql_max_connections" {
  description = "Maximum database connections"
  type        = number
  default     = 100
}

variable "sql_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL"
  type        = bool
  default     = true
}

# ==============================================================================
# GCS Configuration
# ==============================================================================

variable "gcs_force_destroy" {
  description = "Force destroy GCS buckets even if they contain objects (true for dev, false for production)"
  type        = bool
  default     = false
}

variable "gcs_backups_expiration_days" {
  description = "Days before expiring backups in GCS"
  type        = number
  default     = 90
}

variable "gcs_enable_versioning" {
  description = "Enable versioning for documents bucket"
  type        = bool
  default     = true
}

# ==============================================================================
# Kubernetes Configuration
# ==============================================================================

variable "kubernetes_namespace" {
  description = "Kubernetes namespace for Fineract"
  type        = string
  default     = "fineract-dev"
}

variable "service_account_name" {
  description = "Kubernetes service account name for Fineract workloads with Workload Identity"
  type        = string
  default     = "fineract-gcp"
}

# ==============================================================================
# Redis Configuration (in-cluster)
# ==============================================================================

variable "redis_host" {
  description = "Redis host address (in-cluster fineract-redis service name)"
  type        = string
  default     = "fineract-redis"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

# ==============================================================================
# Cost Tracking Labels
# ==============================================================================

variable "cost_center" {
  description = "Cost center for billing tracking"
  type        = string
  default     = "engineering"
}

variable "billing_code" {
  description = "Billing code for cost allocation"
  type        = string
  default     = "DEV-001"
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# Optional Features
# ==============================================================================

variable "enable_cloud_dns" {
  description = "Enable Cloud DNS for domain management"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for Cloud DNS (if enabled)"
  type        = string
  default     = ""
}
