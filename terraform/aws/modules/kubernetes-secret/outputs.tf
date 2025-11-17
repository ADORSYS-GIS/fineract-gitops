output "rds_secret_name" {
  description = "Name of the RDS connection secret"
  value       = kubernetes_secret.rds_connection.metadata[0].name
}

output "s3_secret_name" {
  description = "Name of the S3 connection secret"
  value       = kubernetes_secret.s3_connection.metadata[0].name
}

output "aws_rds_credentials_secret_name" {
  description = "Name of the AWS RDS credentials secret"
  value       = kubernetes_secret.aws_rds_credentials.metadata[0].name
}

output "fineract_db_credentials_secret_name" {
  description = "Name of the Fineract database credentials secret"
  value       = kubernetes_secret.fineract_db_credentials.metadata[0].name
}

output "fineract_redis_credentials_secret_name" {
  description = "Name of the Fineract Redis credentials secret"
  value       = kubernetes_secret.fineract_redis_credentials.metadata[0].name
}

output "aws_s3_credentials_secret_name" {
  description = "Name of the AWS S3 credentials secret (only created if not using IRSA)"
  value       = var.s3_use_irsa ? null : kubernetes_secret.aws_s3_credentials[0].metadata[0].name
}

output "smtp_credentials_secret_name" {
  description = "Name of the SMTP credentials secret (for Keycloak)"
  value       = var.ses_enabled ? kubernetes_secret.smtp_credentials[0].metadata[0].name : null
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account.fineract_aws.metadata[0].name
}

output "service_account_namespace" {
  description = "Namespace of the Kubernetes service account"
  value       = kubernetes_service_account.fineract_aws.metadata[0].namespace
}
