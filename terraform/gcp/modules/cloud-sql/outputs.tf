output "instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.fineract.name
}

output "connection_name" {
  description = "Cloud SQL connection name (PROJECT:REGION:INSTANCE)"
  value       = google_sql_database_instance.fineract.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance"
  value       = google_sql_database_instance.fineract.private_ip_address
}

output "master_username" {
  description = "Master username"
  value       = google_sql_user.master.name
}

output "master_password" {
  description = "Master password"
  value       = random_password.master_password.result
  sensitive   = true
}

output "keycloak_username" {
  description = "Keycloak database username"
  value       = google_sql_user.keycloak.name
}

output "keycloak_password" {
  description = "Keycloak database password"
  value       = random_password.keycloak_password.result
  sensitive   = true
}

output "instance_self_link" {
  description = "Self link of the instance"
  value       = google_sql_database_instance.fineract.self_link
}
