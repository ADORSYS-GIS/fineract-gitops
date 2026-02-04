# ==============================================================================
# GCP UAT Environment Configuration
# ==============================================================================
# Balanced settings for user acceptance testing
# Estimated cost: ~$250/month
# ==============================================================================

# Project Configuration
project_id  = "fineract-486415"
environment = "uat"
region      = "us-central1"
zone        = "us-central1-a"

# GKE Configuration
cluster_name       = "apache-fineract"
gke_version        = "1.29"
machine_type       = "e2-standard-2"  # 2 vCPU, 8 GB
node_desired_count = 2
node_min_count     = 2
node_max_count     = 5
use_preemptible    = true  # Still use preemptible for UAT
disk_size_gb       = 100
disk_type          = "pd-balanced"

# VPC Configuration
vpc_cidr                     = "10.0.0.0/16"
pods_range_cidr              = "10.1.0.0/16"
services_range_cidr          = "10.2.0.0/20"
enable_private_google_access = true

# Cloud SQL Configuration
sql_instance_tier        = "db-custom-2-8192"  # 2 vCPU, 8 GB RAM
sql_disk_size            = 50
sql_max_disk_size        = 200
sql_availability_type    = "ZONAL"  # Single zone for UAT
sql_backup_retention_count = 14
sql_postgres_version     = "POSTGRES_15"
sql_master_username      = "fineract"
sql_max_connections      = 150
sql_deletion_protection  = true

# GCS Configuration
gcs_force_destroy           = false
gcs_backups_expiration_days = 60
gcs_enable_versioning       = true

# Kubernetes Configuration
kubernetes_namespace = "fineract-uat"
service_account_name = "fineract-gcp"

# Cost Tracking Labels
cost_center  = "qa-testing"
billing_code = "uat-001"
labels = {
  team        = "qa"
  auto-stop   = "true"
  workload    = "testing"
  criticality = "medium"
}

# Optional Features
enable_cloud_dns = false
domain_name      = ""
