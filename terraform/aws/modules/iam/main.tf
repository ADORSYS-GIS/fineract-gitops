terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data source for EKS cluster OIDC provider (only if using EKS)
# Note: We construct the ARN directly instead of using data source to avoid circular dependency
# data "aws_iam_openid_connect_provider" "eks" {
#   count = var.oidc_provider_url != null ? 1 : 0
#   url   = var.oidc_provider_url
# }

locals {
  # Extract OIDC provider ID from URL and construct ARN
  # URL format: https://oidc.eks.{region}.amazonaws.com/id/{id}
  oidc_provider_arn = var.oidc_provider_url != null ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.oidc_provider_url, "https://", "")}" : null
}

data "aws_caller_identity" "current" {}

# IAM Role for Fineract - supports both IRSA (EKS) and instance profiles (K3s)
resource "aws_iam_role" "fineract" {
  name = "${var.cluster_name}-${var.environment}-fineract-${var.use_instance_profile ? "instance" : "irsa"}"

  # Conditional assume role policy based on deployment type
  assume_role_policy = var.use_instance_profile ? jsonencode({
    # K3s: Allow EC2 instances to assume this role
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
    }) : jsonencode({
    # EKS: Allow pods with specific service account to assume this role (IRSA)
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-fineract-${var.use_instance_profile ? "instance" : "irsa"}"
      Environment = var.environment
      Component   = "iam"
      Type        = var.use_instance_profile ? "instance-profile" : "irsa"
    }
  )
}

# IAM Policy for RDS access
resource "aws_iam_policy" "rds_access" {
  name        = "${var.cluster_name}-${var.environment}-fineract-rds"
  description = "Policy for Fineract to access RDS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource"
        ]
        Resource = var.rds_instance_arn
      },
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = "${var.rds_instance_arn}/*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-fineract-rds"
      Environment = var.environment
    }
  )
}

# IAM Policy for S3 access
resource "aws_iam_policy" "s3_access" {
  name        = "${var.cluster_name}-${var.environment}-fineract-s3"
  description = "Policy for Fineract to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = [
          var.documents_bucket_arn,
          var.backups_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "${var.documents_bucket_arn}/*",
          "${var.backups_bucket_arn}/*"
        ]
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-fineract-s3"
      Environment = var.environment
    }
  )
}

# IAM Policy for KMS (if encryption is enabled)
resource "aws_iam_policy" "kms_access" {
  count       = var.kms_key_arn != null ? 1 : 0
  name        = "${var.cluster_name}-${var.environment}-fineract-kms"
  description = "Policy for Fineract to use KMS for encryption"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-fineract-kms"
      Environment = var.environment
    }
  )
}

# Attach policies to the IAM role
resource "aws_iam_role_policy_attachment" "rds" {
  role       = aws_iam_role.fineract.name
  policy_arn = aws_iam_policy.rds_access.arn
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.fineract.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "kms" {
  count      = var.kms_key_arn != null ? 1 : 0
  role       = aws_iam_role.fineract.name
  policy_arn = aws_iam_policy.kms_access[0].arn
}

# IAM Policy for SES access (optional - for Fineract to send emails via API)
resource "aws_iam_policy" "ses_access" {
  count       = var.ses_enabled ? 1 : 0
  name        = "${var.cluster_name}-${var.environment}-fineract-ses"
  description = "Policy for Fineract to access AWS SES for email sending"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "ses:SendEmail",
            "ses:SendRawEmail",
            "ses:SendTemplatedEmail",
            "ses:SendBulkTemplatedEmail"
          ]
          Resource = var.ses_identity_arn != null ? var.ses_identity_arn : "*"
          Condition = var.ses_identity_arn != null ? null : {
            StringLike = {
              "ses:FromAddress" = "*@*"
            }
          }
        }
      ],
      var.ses_identity_arn != null ? [
        {
          Effect = "Allow"
          Action = [
            "ses:GetSendQuota",
            "ses:GetSendStatistics",
            "ses:GetAccount"
          ]
          Resource = "*"
        }
      ] : []
    )
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-fineract-ses"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "ses" {
  count      = var.ses_enabled ? 1 : 0
  role       = aws_iam_role.fineract.name
  policy_arn = aws_iam_policy.ses_access[0].arn
}

# Attach policies to K3s instance role (if using K3s)
resource "aws_iam_role_policy_attachment" "k3s_rds" {
  count      = var.use_instance_profile && var.k3s_role_name != null ? 1 : 0
  role       = var.k3s_role_name
  policy_arn = aws_iam_policy.rds_access.arn
}

resource "aws_iam_role_policy_attachment" "k3s_s3" {
  count      = var.use_instance_profile && var.k3s_role_name != null ? 1 : 0
  role       = var.k3s_role_name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "k3s_kms" {
  count      = var.use_instance_profile && var.k3s_role_name != null && var.kms_key_arn != null ? 1 : 0
  role       = var.k3s_role_name
  policy_arn = aws_iam_policy.kms_access[0].arn
}

resource "aws_iam_role_policy_attachment" "k3s_ses" {
  count      = var.use_instance_profile && var.k3s_role_name != null && var.ses_enabled ? 1 : 0
  role       = var.k3s_role_name
  policy_arn = aws_iam_policy.ses_access[0].arn
}

# Kubernetes Service Account annotation
# This is informational - the actual ServiceAccount must be created in Kubernetes
locals {
  service_account_annotation = var.use_instance_profile ? {} : {
    "eks.amazonaws.com/role-arn" = aws_iam_role.fineract.arn
  }
}
