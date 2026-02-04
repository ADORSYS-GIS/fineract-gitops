# ==============================================================================
# IAM Module
# Creates service accounts and Workload Identity bindings for GKE
# ==============================================================================

# ==============================================================================
# GKE Nodes Service Account
# ==============================================================================
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes-${var.environment}"
  display_name = "GKE Nodes Service Account for ${var.environment}"
  project      = var.project_id
}

# Minimal permissions for GKE nodes
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ==============================================================================
# Fineract Application Service Account (Workload Identity)
# ==============================================================================
resource "google_service_account" "fineract" {
  account_id   = "fineract-${var.environment}"
  display_name = "Fineract Service Account for ${var.environment}"
  project      = var.project_id
}

# Cloud SQL Client role for database access
resource "google_project_iam_member" "fineract_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.fineract.email}"
}

# GCS access for documents bucket
resource "google_storage_bucket_iam_member" "fineract_documents" {
  bucket = var.documents_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.fineract.email}"
}

# GCS access for backups bucket
resource "google_storage_bucket_iam_member" "fineract_backups" {
  bucket = var.backups_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.fineract.email}"
}

# Secret Manager access
resource "google_project_iam_member" "fineract_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.fineract.email}"
}

# ==============================================================================
# Workload Identity Binding
# Allows Kubernetes ServiceAccount to impersonate GCP Service Account
# NOTE: Only created when GKE cluster exists (identity pool is created with cluster)
# ==============================================================================
resource "google_service_account_iam_member" "fineract_workload_identity" {
  count              = var.enable_workload_identity && var.gke_cluster_id != "" ? 1 : 0
  service_account_id = google_service_account.fineract.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.service_account_name}]"
}

# ==============================================================================
# Cluster Autoscaler Service Account (if needed for node scaling)
# ==============================================================================
resource "google_service_account" "cluster_autoscaler" {
  account_id   = "cluster-autoscaler-${var.environment}"
  display_name = "Cluster Autoscaler for ${var.environment}"
  project      = var.project_id
}

resource "google_project_iam_member" "cluster_autoscaler" {
  project = var.project_id
  role    = "roles/container.clusterAdmin"
  member  = "serviceAccount:${google_service_account.cluster_autoscaler.email}"
}

resource "google_service_account_iam_member" "cluster_autoscaler_workload_identity" {
  count              = var.enable_workload_identity && var.gke_cluster_id != "" ? 1 : 0
  service_account_id = google_service_account.cluster_autoscaler.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[kube-system/cluster-autoscaler]"
}
