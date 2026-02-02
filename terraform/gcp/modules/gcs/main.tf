# ==============================================================================
# GCS (Cloud Storage) Module
# ==============================================================================

# Documents Bucket
resource "google_storage_bucket" "documents" {
  name          = "${var.cluster_name}-${var.environment}-docs-${var.project_id}"
  project       = var.project_id
  location      = var.region
  force_destroy = var.force_destroy

  # Storage class
  storage_class = "STANDARD"

  # Versioning
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle rules for cost optimization
  # Transition to Nearline after 30 days
  lifecycle_rule {
    condition {
      age                   = 30
      with_state            = "ARCHIVED"
      num_newer_versions    = 3
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Transition to Coldline after 90 days
  lifecycle_rule {
    condition {
      age        = 90
      with_state = "ARCHIVED"
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Delete old versions after 365 days
  lifecycle_rule {
    condition {
      age                = 365
      with_state         = "ARCHIVED"
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access (recommended)
  uniform_bucket_level_access = true

  # Public access prevention
  public_access_prevention = "enforced"

  # Labels for cost tracking
  labels = merge(var.labels, {
    environment  = var.environment
    purpose      = "documents"
    cost-center  = var.cost_center
    billing-code = var.billing_code
  })
}

# Backups Bucket
resource "google_storage_bucket" "backups" {
  name          = "${var.cluster_name}-${var.environment}-backups-${var.project_id}"
  project       = var.project_id
  location      = var.region
  force_destroy = var.force_destroy

  # Use Nearline for backups (cost optimization)
  storage_class = "NEARLINE"

  # Versioning for backups
  versioning {
    enabled = true
  }

  # Lifecycle rules
  # Transition to Coldline after 30 days
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Delete after expiration days
  lifecycle_rule {
    condition {
      age = var.backups_expiration_days
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = merge(var.labels, {
    environment  = var.environment
    purpose      = "backups"
    cost-center  = var.cost_center
    billing-code = var.billing_code
  })
}
