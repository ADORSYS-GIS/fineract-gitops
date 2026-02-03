terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get current AWS account ID for unique bucket naming
data "aws_caller_identity" "current" {}

# Documents Bucket (with account ID suffix for global uniqueness)
resource "aws_s3_bucket" "documents" {
  bucket        = "${var.cluster_name}-${var.environment}-docs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-docs-${data.aws_caller_identity.current.account_id}"
      Environment = var.environment
      Component   = "storage"
      Subcomponent = "s3"
      Purpose     = "documents"
    }
  )
}

# Backups Bucket (with account ID suffix for global uniqueness)
resource "aws_s3_bucket" "backups" {
  bucket        = "${var.cluster_name}-${var.environment}-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-backups-${data.aws_caller_identity.current.account_id}"
      Environment = var.environment
      Component   = "storage"
      Subcomponent = "s3"
      Purpose     = "backups"
    }
  )
}

# Documents Bucket - Versioning
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Backups Bucket - Versioning
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled" # Always enable for backups
  }
}

# Documents Bucket - Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = var.kms_key_id != null
  }
}

# Backups Bucket - Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = var.kms_key_id != null
  }
}

# Documents Bucket - Public Access Block
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Backups Bucket - Public Access Block
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Documents Bucket - Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  count  = var.documents_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.documents_noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "delete-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Backups Bucket - Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.backups_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = var.backups_transition_to_glacier_days
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backups_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "delete-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Documents Bucket - CORS (if needed)
resource "aws_s3_bucket_cors_configuration" "documents" {
  count  = var.enable_cors ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  cors_rule {
    allowed_headers = ["Content-Type", "Content-Length", "Authorization", "x-amz-date", "x-amz-security-token"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag", "x-amz-request-id"]
    max_age_seconds = 3000
  }
}

# Documents Bucket - Logging
resource "aws_s3_bucket_logging" "documents" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  target_bucket = var.logging_bucket_id != null ? var.logging_bucket_id : aws_s3_bucket.backups.id
  target_prefix = "documents-access-logs/"
}

# Backups Bucket - Logging
resource "aws_s3_bucket_logging" "backups" {
  count  = var.enable_access_logging && var.logging_bucket_id != null ? 1 : 0
  bucket = aws_s3_bucket.backups.id

  target_bucket = var.logging_bucket_id
  target_prefix = "backups-access-logs/"
}

# Enable S3 Transfer Acceleration (optional, for faster uploads)
resource "aws_s3_bucket_accelerate_configuration" "documents" {
  count  = var.enable_transfer_acceleration ? 1 : 0
  bucket = aws_s3_bucket.documents.id
  status = "Enabled"
}

# Documents Bucket - Intelligent Tiering
resource "aws_s3_bucket_intelligent_tiering_configuration" "documents" {
  count  = var.enable_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.documents.id
  name   = "EntireDocumentsBucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_archive_days
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_deep_archive_days
  }
}
