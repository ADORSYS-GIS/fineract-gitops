output "role_arn" {
  description = "IAM role ARN for Fineract service account"
  value       = aws_iam_role.fineract.arn
}

output "role_name" {
  description = "IAM role name"
  value       = aws_iam_role.fineract.name
}

output "service_account_annotation" {
  description = "Annotation to add to Kubernetes ServiceAccount"
  value       = local.service_account_annotation
}

output "rds_policy_arn" {
  description = "RDS access policy ARN"
  value       = aws_iam_policy.rds_access.arn
}

output "s3_policy_arn" {
  description = "S3 access policy ARN"
  value       = aws_iam_policy.s3_access.arn
}

output "kms_policy_arn" {
  description = "KMS access policy ARN"
  value       = var.kms_key_arn != null ? aws_iam_policy.kms_access[0].arn : null
}
