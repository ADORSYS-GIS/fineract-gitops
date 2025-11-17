output "smtp_host" {
  description = "SES SMTP endpoint hostname"
  value       = local.smtp_host
}

output "smtp_port" {
  description = "SES SMTP port (STARTTLS)"
  value       = local.smtp_port
}

output "smtp_username" {
  description = "SMTP username (IAM access key ID)"
  value       = local.smtp_username
  sensitive   = true
}

output "smtp_password" {
  description = "SMTP password (SES SMTP password v4)"
  value       = local.smtp_password
  sensitive   = true
}

output "sender_email" {
  description = "Default sender email address"
  value       = var.sender_email
}

output "sender_name" {
  description = "Default sender name"
  value       = var.sender_name
}

output "verified_emails" {
  description = "List of verified email identities"
  value       = [for email in aws_ses_email_identity.verified_emails : email.email]
}

output "configuration_set_name" {
  description = "SES configuration set name for tracking"
  value       = aws_ses_configuration_set.main.name
}

output "iam_user_arn" {
  description = "ARN of the IAM user created for SMTP"
  value       = aws_iam_user.ses_smtp.arn
}

output "iam_user_name" {
  description = "Name of the IAM user created for SMTP"
  value       = aws_iam_user.ses_smtp.name
}

output "domain_verification_token" {
  description = "Domain verification token (if domain identity is configured)"
  value       = var.domain != null ? aws_ses_domain_identity.domain[0].verification_token : null
}

output "dkim_tokens" {
  description = "DKIM tokens for DNS configuration (if domain identity is configured)"
  value       = var.domain != null ? aws_ses_domain_dkim.domain[0].dkim_tokens : []
}

output "ses_region" {
  description = "AWS region where SES is configured"
  value       = var.aws_region
}

# Connection string for applications
output "smtp_connection_string" {
  description = "SMTP connection string for application configuration"
  value       = "smtp://${local.smtp_username}:${local.smtp_password}@${local.smtp_host}:${local.smtp_port}"
  sensitive   = true
}
