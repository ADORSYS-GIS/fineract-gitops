# ==============================================================================
# GKE Cluster Outputs
# ==============================================================================

output "gke_cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = module.gke.cluster_endpoint
}

output "gke_cluster_version" {
  description = "Kubernetes version of the GKE cluster"
  value       = module.gke.cluster_version
}

output "gke_cluster_location" {
  description = "GKE cluster location (zone or region)"
  value       = module.gke.cluster_location
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = module.gke.workload_identity_pool
}

# Kubectl Configuration
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = module.gke.kubeconfig_command
}

# ==============================================================================
# VPC Outputs
# ==============================================================================

output "vpc_id" {
  description = "VPC network ID"
  value       = module.vpc.network_id
}

output "vpc_name" {
  description = "VPC network name"
  value       = module.vpc.network_name
}

output "subnet_name" {
  description = "GKE subnet name"
  value       = module.vpc.subnet_name
}

# ==============================================================================
# Cloud SQL Outputs
# ==============================================================================

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.cloud_sql.instance_name
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (PROJECT:REGION:INSTANCE)"
  value       = module.cloud_sql.connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = module.cloud_sql.private_ip_address
}

output "db_master_username" {
  description = "Database master username"
  value       = module.cloud_sql.master_username
  sensitive   = true
}

# ==============================================================================
# GCS Outputs
# ==============================================================================

output "documents_bucket_name" {
  description = "GCS documents bucket name"
  value       = module.gcs.documents_bucket_name
}

output "documents_bucket_url" {
  description = "GCS documents bucket URL"
  value       = module.gcs.documents_bucket_url
}

output "backups_bucket_name" {
  description = "GCS backups bucket name"
  value       = module.gcs.backups_bucket_name
}

output "backups_bucket_url" {
  description = "GCS backups bucket URL"
  value       = module.gcs.backups_bucket_url
}

# ==============================================================================
# IAM Outputs
# ==============================================================================

output "fineract_service_account_email" {
  description = "Fineract GCP service account email (for Workload Identity)"
  value       = module.iam.fineract_service_account_email
}

output "workload_identity_annotation" {
  description = "Annotation to add to Kubernetes ServiceAccount for Workload Identity"
  value       = module.iam.workload_identity_annotation
}

output "gke_nodes_service_account_email" {
  description = "GKE nodes service account email"
  value       = module.iam.gke_nodes_service_account_email
}

# ==============================================================================
# Cloud DNS Outputs
# ==============================================================================

output "dns_zone_name" {
  description = "Cloud DNS zone name"
  value       = var.enable_cloud_dns ? module.cloud_dns[0].zone_name : null
}

output "dns_name_servers" {
  description = "Cloud DNS nameservers (update at your registrar)"
  value       = var.enable_cloud_dns ? module.cloud_dns[0].name_servers : []
}

# ==============================================================================
# OAuth2 Secrets
# ==============================================================================

output "oauth2_client_secret" {
  description = "OAuth2 client secret for OAuth2-Proxy and Keycloak clients"
  value       = random_password.oauth2_client_secret.result
  sensitive   = true
}

output "oauth2_cookie_secret" {
  description = "OAuth2 cookie secret for OAuth2-Proxy session encryption"
  value       = random_password.oauth2_cookie_secret.result
  sensitive   = true
}

output "redis_password" {
  description = "Redis password for in-cluster Redis session store"
  value       = random_password.redis_password.result
  sensitive   = true
}

output "keycloak_admin_password" {
  description = "Keycloak admin password"
  value       = random_password.keycloak_admin_password.result
  sensitive   = true
}

output "keycloak_db_username" {
  description = "Keycloak database username"
  value       = module.cloud_sql.keycloak_username
}

output "keycloak_db_password" {
  description = "Keycloak database password"
  value       = module.cloud_sql.keycloak_password
  sensitive   = true
}

# ==============================================================================
# Connection Details Summary
# ==============================================================================

output "connection_details" {
  description = "Connection details for manual configuration"
  value = {
    gke_cluster       = module.gke.cluster_name
    sql_connection    = module.cloud_sql.connection_name
    sql_private_ip    = module.cloud_sql.private_ip_address
    documents_bucket  = module.gcs.documents_bucket_name
    backups_bucket    = module.gcs.backups_bucket_name
    service_account   = var.service_account_name
    namespace         = var.kubernetes_namespace
    project_id        = var.project_id
    region            = var.region
  }
}
