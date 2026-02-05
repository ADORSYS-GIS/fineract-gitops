# ==============================================================================
# Cloud SQL PostgreSQL Module
# ==============================================================================

# Random suffix for instance name (Cloud SQL names are globally unique)
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

# Generate random password for master user
resource "random_password" "master_password" {
  length  = 32
  special = false  # Some special chars cause issues with connection strings
  upper   = true
  lower   = true
  numeric = true
}

# Private Service Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.cluster_name}-${var.environment}-sql-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "fineract" {
  name             = "${var.cluster_name}-${var.environment}-${random_id.db_name_suffix.hex}"
  project          = var.project_id
  region           = var.region
  database_version = var.postgres_version

  # Deletion protection (enable for production)
  deletion_protection = var.deletion_protection

  settings {
    # Tier: db-custom-CPU-RAM (e.g., db-custom-2-4096 = 2 vCPU, 4GB RAM)
    tier = var.instance_tier

    # Availability type: ZONAL (single zone) or REGIONAL (HA)
    availability_type = var.availability_type

    # Disk configuration
    disk_size         = var.disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    disk_autoresize_limit = var.max_disk_size

    # Activation policy
    activation_policy = "ALWAYS"

    # IP configuration - Private IP only
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
      require_ssl     = var.require_ssl
    }

    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"  # 2 AM UTC
      point_in_time_recovery_enabled = var.availability_type == "REGIONAL"
      transaction_log_retention_days = var.availability_type == "REGIONAL" ? 7 : 1

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    # Maintenance window (Sunday 3 AM UTC)
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3
      update_track = var.environment == "production" ? "stable" : "canary"
    }

    # Database flags (PostgreSQL tuning)
    database_flags {
      name  = "max_connections"
      value = tostring(var.max_connections)
    }

    # Query Insights for performance monitoring
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    # User labels for cost tracking
    user_labels = merge(var.labels, {
      environment  = var.environment
      component    = "database"
      cost-center  = var.cost_center
      billing-code = var.billing_code
    })
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Master user
resource "google_sql_user" "master" {
  name     = var.master_username
  instance = google_sql_database_instance.fineract.name
  password = random_password.master_password.result
  project  = var.project_id
}

# Keycloak database user
resource "random_password" "keycloak_password" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "google_sql_user" "keycloak" {
  name     = "keycloak"
  instance = google_sql_database_instance.fineract.name
  password = random_password.keycloak_password.result
  project  = var.project_id
}

# Keycloak database - created by Terraform for full automation
resource "google_sql_database" "keycloak" {
  name     = "keycloak"
  instance = google_sql_database_instance.fineract.name
  project  = var.project_id
}

# Note: Fineract databases are created by application migrations
# - fineract_tenants (created by Fineract schema migration)
# - fineract_default (created by Fineract schema migration)
