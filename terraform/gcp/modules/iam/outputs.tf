output "gke_nodes_service_account_email" {
  description = "GKE nodes service account email"
  value       = google_service_account.gke_nodes.email
}

output "gke_nodes_service_account_name" {
  description = "GKE nodes service account name"
  value       = google_service_account.gke_nodes.name
}

output "fineract_service_account_email" {
  description = "Fineract service account email"
  value       = google_service_account.fineract.email
}

output "fineract_service_account_name" {
  description = "Fineract service account name"
  value       = google_service_account.fineract.name
}

output "cluster_autoscaler_service_account_email" {
  description = "Cluster autoscaler service account email"
  value       = google_service_account.cluster_autoscaler.email
}

output "cluster_autoscaler_service_account_name" {
  description = "Cluster autoscaler service account name"
  value       = google_service_account.cluster_autoscaler.name
}

# Annotation for Kubernetes ServiceAccount
output "workload_identity_annotation" {
  description = "Annotation to add to Kubernetes ServiceAccount for Workload Identity"
  value       = "iam.gke.io/gcp-service-account=${google_service_account.fineract.email}"
}
