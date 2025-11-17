output "documents_bucket_id" {
  description = "Documents S3 bucket ID"
  value       = aws_s3_bucket.documents.id
}

output "documents_bucket_arn" {
  description = "Documents S3 bucket ARN"
  value       = aws_s3_bucket.documents.arn
}

output "documents_bucket_domain_name" {
  description = "Documents S3 bucket domain name"
  value       = aws_s3_bucket.documents.bucket_domain_name
}

output "documents_bucket_regional_domain_name" {
  description = "Documents S3 bucket regional domain name"
  value       = aws_s3_bucket.documents.bucket_regional_domain_name
}

output "backups_bucket_id" {
  description = "Backups S3 bucket ID"
  value       = aws_s3_bucket.backups.id
}

output "backups_bucket_arn" {
  description = "Backups S3 bucket ARN"
  value       = aws_s3_bucket.backups.arn
}

output "backups_bucket_domain_name" {
  description = "Backups S3 bucket domain name"
  value       = aws_s3_bucket.backups.bucket_domain_name
}

output "backups_bucket_regional_domain_name" {
  description = "Backups S3 bucket regional domain name"
  value       = aws_s3_bucket.backups.bucket_regional_domain_name
}
