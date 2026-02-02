# ==============================================================================
# GCP Production Environment Configuration
# ==============================================================================
# High-availability settings for production workloads
# Estimated cost: ~$750/month (without Committed Use Discounts)
# With 1-year CUD: ~$525/month (30% savings)
# ==============================================================================

# Project Configuration
project_id  = "fineract-prod-project"  # Replace with your GCP project ID
environment = "production"
region      = "us-central1"
zone        = "us-central1-a"  # Not used for regional cluster

# GKE Configuration
cluster_name       = "apache-fineract"
gke_version        = "1.29"
machine_type       = "n2d-standard-4"  # 4 vCPU, 16 GB - AMD (20% cheaper than Intel)
node_desired_count = 3
node_min_count     = 3
node_max_count     = 10
use_preemptible    = false  # On-demand for production stability
disk_size_gb       = 100
disk_type          = "pd-ssd"  # SSD for production performance

# VPC Configuration
vpc_cidr                     = "10.0.0.0/16"
pods_range_cidr              = "10.1.0.0/16"
services_range_cidr          = "10.2.0.0/20"
enable_private_google_access = true

# Cloud SQL Configuration
sql_instance_tier        = "db-custom-4-16384"  # 4 vCPU, 16 GB RAM
sql_disk_size            = 100
sql_max_disk_size        = 1000
sql_availability_type    = "REGIONAL"  # HA with automatic failover
sql_backup_retention_count = 30
sql_postgres_version     = "POSTGRES_15"
sql_master_username      = "fineract"
sql_max_connections      = 200
sql_deletion_protection  = true  # Prevent accidental deletion

# GCS Configuration
gcs_force_destroy           = false  # Never force destroy in production
gcs_backups_expiration_days = 365
gcs_enable_versioning       = true

# Kubernetes Configuration
kubernetes_namespace = "fineract-production"
service_account_name = "fineract-gcp"

# Cost Tracking Labels
cost_center  = "operations"
billing_code = "PROD-001"
labels = {
  team        = "platform"
  auto-stop   = "false"
  workload    = "production"
  criticality = "high"
  sla         = "99-9"
}

# Optional Features
enable_cloud_dns = false  # Set to true and provide domain_name if needed
domain_name      = ""
