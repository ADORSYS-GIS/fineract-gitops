# ==============================================================================
# Secret Manager Module
# Stores sensitive configuration in GCP Secret Manager
# ==============================================================================

# Database master password
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.cluster_name}-${var.environment}-db-password"
  project   = var.project_id

  labels = merge(var.labels, {
    environment = var.environment
    component   = "database"
  })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# Database host
resource "google_secret_manager_secret" "db_host" {
  secret_id = "${var.cluster_name}-${var.environment}-db-host"
  project   = var.project_id

  labels = merge(var.labels, {
    environment = var.environment
    component   = "database"
  })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_host" {
  secret      = google_secret_manager_secret.db_host.id
  secret_data = var.db_host
}

# Database connection name (for Cloud SQL Proxy)
resource "google_secret_manager_secret" "db_connection" {
  secret_id = "${var.cluster_name}-${var.environment}-db-connection"
  project   = var.project_id

  labels = merge(var.labels, {
    environment = var.environment
    component   = "database"
  })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_connection" {
  secret      = google_secret_manager_secret.db_connection.id
  secret_data = var.db_connection
}
