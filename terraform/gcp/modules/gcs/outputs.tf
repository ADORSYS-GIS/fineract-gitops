output "documents_bucket_name" {
  description = "Documents bucket name"
  value       = google_storage_bucket.documents.name
}

output "documents_bucket_url" {
  description = "Documents bucket URL"
  value       = google_storage_bucket.documents.url
}

output "documents_bucket_self_link" {
  description = "Documents bucket self link"
  value       = google_storage_bucket.documents.self_link
}

output "backups_bucket_name" {
  description = "Backups bucket name"
  value       = google_storage_bucket.backups.name
}

output "backups_bucket_url" {
  description = "Backups bucket URL"
  value       = google_storage_bucket.backups.url
}

output "backups_bucket_self_link" {
  description = "Backups bucket self link"
  value       = google_storage_bucket.backups.self_link
}
