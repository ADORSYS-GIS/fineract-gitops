output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location (zone or region)"
  value       = google_container_cluster.primary.location
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = google_container_cluster.primary.master_version
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.project_id}.svc.id.goog"
}

output "primary_node_pool_name" {
  description = "Primary node pool name"
  value       = google_container_node_pool.primary.name
}

# Command to configure kubectl
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = var.environment == "production" ? "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}" : "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}
