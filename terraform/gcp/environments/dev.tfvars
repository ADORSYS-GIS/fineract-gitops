# ==============================================================================
# GCP Development Environment Configuration
# ==============================================================================
# Cost-optimized settings for development/testing
# Estimated cost: ~$180/month
# ==============================================================================

# Project Configuration
project_id  = "fineract-486415"
environment = "dev"
region      = "us-central1"
zone        = "us-central1-a"

# GKE Configuration
cluster_name       = "apache-fineract"
gke_version        = "1.29"
machine_type       = "e2-standard-2"  # 2 vCPU, 8 GB - cost-effective
node_desired_count = 2
node_min_count     = 1
node_max_count     = 4
use_preemptible    = true  # 60-80% cost savings
disk_size_gb       = 100
disk_type          = "pd-balanced"

# VPC Configuration
vpc_cidr                     = "10.0.0.0/16"
pods_range_cidr              = "10.1.0.0/16"
services_range_cidr          = "10.2.0.0/20"
enable_private_google_access = true  # Cost optimization

# Cloud SQL Configuration
sql_instance_tier        = "db-custom-2-4096"  # 2 vCPU, 4 GB RAM
sql_disk_size            = 20
sql_max_disk_size        = 100
sql_availability_type    = "ZONAL"  # Single zone for dev (50% cheaper)
sql_backup_retention_count = 7
sql_postgres_version     = "POSTGRES_15"
sql_master_username      = "fineract"
sql_max_connections      = 100
sql_deletion_protection  = false  # Allow easy cleanup in dev

# GCS Configuration
gcs_force_destroy           = true  # Allow easy cleanup in dev
gcs_backups_expiration_days = 30
gcs_enable_versioning       = true

# Kubernetes Configuration
kubernetes_namespace = "fineract-dev"
service_account_name = "fineract-gcp"

# Cost Tracking Labels
cost_center  = "development"
billing_code = "DEV-001"
labels = {
  team        = "engineering"
  auto-stop   = "true"
  workload    = "development"
  criticality = "low"
}

# Optional Features
enable_cloud_dns = false
domain_name      = ""
