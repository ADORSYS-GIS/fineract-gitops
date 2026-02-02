output "db_password_secret_id" {
  description = "Secret ID for database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "db_host_secret_id" {
  description = "Secret ID for database host"
  value       = google_secret_manager_secret.db_host.secret_id
}

output "db_connection_secret_id" {
  description = "Secret ID for database connection name"
  value       = google_secret_manager_secret.db_connection.secret_id
}
