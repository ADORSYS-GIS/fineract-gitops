output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "VPC network self link"
  value       = google_compute_network.main.self_link
}

output "subnet_id" {
  description = "GKE subnet ID"
  value       = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  description = "GKE subnet name"
  value       = google_compute_subnetwork.gke.name
}

output "subnet_self_link" {
  description = "GKE subnet self link"
  value       = google_compute_subnetwork.gke.self_link
}

output "pods_range_name" {
  description = "Name of the pods secondary range"
  value       = "${var.cluster_name}-pods"
}

output "services_range_name" {
  description = "Name of the services secondary range"
  value       = "${var.cluster_name}-services"
}

output "router_name" {
  description = "Cloud Router name"
  value       = google_compute_router.main.name
}

output "nat_name" {
  description = "Cloud NAT name"
  value       = google_compute_router_nat.main.name
}
