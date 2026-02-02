# ==============================================================================
# GCP Infrastructure for Fineract
# ==============================================================================
# This module creates the complete GCP infrastructure for running Fineract:
# - VPC with Cloud NAT and Private Google Access
# - GKE cluster with Workload Identity
# - Cloud SQL PostgreSQL
# - GCS buckets for documents and backups
# - IAM service accounts with Workload Identity bindings
# ==============================================================================

locals {
  common_labels = merge(
    var.labels,
    {
      project      = "fineract"
      environment  = var.environment
      managed-by   = "terraform"
      repository   = "fineract-gitops"
      cost-center  = var.cost_center
      billing-code = var.billing_code
    }
  )

  # Subnet CIDR derived from VPC CIDR
  subnet_cidr = cidrsubnet(var.vpc_cidr, 4, 0)  # First /20 from /16
}

# ==============================================================================
# VPC Module
# ==============================================================================
module "vpc" {
  source = "./modules/vpc"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  environment  = var.environment

  subnet_cidr         = local.subnet_cidr
  pods_range_cidr     = var.pods_range_cidr
  services_range_cidr = var.services_range_cidr

  enable_private_google_access = var.enable_private_google_access

  labels = local.common_labels
}

# ==============================================================================
# IAM Module (Service Accounts)
# ==============================================================================
module "iam" {
  source = "./modules/iam"

  project_id   = var.project_id
  cluster_name = var.cluster_name
  environment  = var.environment
  namespace    = var.kubernetes_namespace

  service_account_name = var.service_account_name

  # Bucket names for IAM bindings (created after GCS module)
  documents_bucket_name = module.gcs.documents_bucket_name
  backups_bucket_name   = module.gcs.backups_bucket_name

  labels = local.common_labels
}

# ==============================================================================
# GKE Module
# ==============================================================================
module "gke" {
  source = "./modules/gke"

  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  cluster_name = var.cluster_name
  environment  = var.environment
  gke_version  = var.gke_version

  # Network configuration
  network_self_link   = module.vpc.network_self_link
  subnet_self_link    = module.vpc.subnet_self_link
  pods_range_name     = module.vpc.pods_range_name
  services_range_name = module.vpc.services_range_name

  # Node configuration
  machine_type       = var.machine_type
  node_desired_count = var.node_desired_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count
  use_preemptible    = var.use_preemptible
  disk_size_gb       = var.disk_size_gb
  disk_type          = var.disk_type

  # Service account for nodes
  node_service_account_email = module.iam.gke_nodes_service_account_email

  # Cost tracking
  cost_center  = var.cost_center
  billing_code = var.billing_code
  labels       = local.common_labels

  depends_on = [module.vpc, module.iam]
}

# ==============================================================================
# Cloud SQL Module
# ==============================================================================
module "cloud_sql" {
  source = "./modules/cloud-sql"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  environment  = var.environment

  # Network configuration
  network_self_link = module.vpc.network_self_link

  # Instance configuration
  instance_tier         = var.sql_instance_tier
  disk_size             = var.sql_disk_size
  max_disk_size         = var.sql_max_disk_size
  availability_type     = var.sql_availability_type
  postgres_version      = var.sql_postgres_version
  master_username       = var.sql_master_username
  max_connections       = var.sql_max_connections
  backup_retention_count = var.sql_backup_retention_count
  deletion_protection   = var.sql_deletion_protection

  # Cost tracking
  cost_center  = var.cost_center
  billing_code = var.billing_code
  labels       = local.common_labels

  depends_on = [module.vpc]
}

# ==============================================================================
# GCS Module
# ==============================================================================
module "gcs" {
  source = "./modules/gcs"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  environment  = var.environment

  force_destroy           = var.gcs_force_destroy
  backups_expiration_days = var.gcs_backups_expiration_days
  enable_versioning       = var.gcs_enable_versioning

  # Cost tracking
  cost_center  = var.cost_center
  billing_code = var.billing_code
  labels       = local.common_labels
}

# ==============================================================================
# Cloud DNS Module (Optional)
# ==============================================================================
module "cloud_dns" {
  source = "./modules/cloud-dns"
  count  = var.enable_cloud_dns ? 1 : 0

  project_id   = var.project_id
  domain_name  = var.domain_name
  environment  = var.environment
  cluster_name = var.cluster_name

  labels = local.common_labels
}

# ==============================================================================
# Secret Manager Module
# ==============================================================================
module "secret_manager" {
  source = "./modules/secret-manager"

  project_id   = var.project_id
  cluster_name = var.cluster_name
  environment  = var.environment

  # Secrets to store
  db_password     = module.cloud_sql.master_password
  db_host         = module.cloud_sql.private_ip_address
  db_connection   = module.cloud_sql.connection_name

  labels = local.common_labels

  depends_on = [module.cloud_sql]
}

# ==============================================================================
# OAuth2 Secrets (for OAuth2-Proxy and Keycloak client configuration)
# ==============================================================================
resource "random_password" "oauth2_client_secret" {
  length  = 64
  special = false
  upper   = true
  lower   = true
  numeric = true

  lifecycle {
    ignore_changes = [length, special, upper, lower, numeric]
  }
}

resource "random_password" "oauth2_cookie_secret" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true

  lifecycle {
    ignore_changes = [length, special, upper, lower, numeric]
  }
}
