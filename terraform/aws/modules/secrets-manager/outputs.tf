output "github_token_secret_arn" {
  description = "ARN of the GitHub token secret in AWS Secrets Manager"
  value       = data.aws_secretsmanager_secret.github_token.arn
}

output "github_token_secret_name" {
  description = "Name of the GitHub token secret in AWS Secrets Manager"
  value       = data.aws_secretsmanager_secret.github_token.name
}

output "github_token_value" {
  description = "Value of the GitHub token (sensitive)"
  value       = data.aws_secretsmanager_secret_version.github_token.secret_string
  sensitive   = true
}

output "sealed_secrets_keys_secret_arn" {
  description = "ARN of the Sealed Secrets keys secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.sealed_secrets_keys.arn
}

output "sealed_secrets_keys_secret_name" {
  description = "Name of the Sealed Secrets keys secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.sealed_secrets_keys.name
}
