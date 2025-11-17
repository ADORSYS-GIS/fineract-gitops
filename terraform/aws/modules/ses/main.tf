terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# SES Email Identity Verification (Sandbox Mode)
# Create an email identity for each verified email address
resource "aws_ses_email_identity" "verified_emails" {
  for_each = toset(var.verified_emails)
  email    = each.value
}

# SES Domain Identity (for Production Mode - optional)
resource "aws_ses_domain_identity" "domain" {
  count  = var.domain != null ? 1 : 0
  domain = var.domain
}

# SES Domain DKIM (for Production Mode - optional)
resource "aws_ses_domain_dkim" "domain" {
  count  = var.domain != null ? 1 : 0
  domain = aws_ses_domain_identity.domain[0].domain
}

# Configuration Set for tracking email metrics
resource "aws_ses_configuration_set" "main" {
  name = "${var.cluster_name}-${var.environment}-ses-config"

  reputation_metrics_enabled = true
  sending_enabled            = true
}

# IAM User for SMTP Authentication
resource "aws_iam_user" "ses_smtp" {
  name = "${var.cluster_name}-${var.environment}-ses-smtp-user"
  path = "/fineract/"

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-${var.environment}-ses-smtp-user"
      Environment = var.environment
      Component   = "ses"
      Purpose     = "smtp-authentication"
    }
  )
}

# IAM Policy for SES Sending
resource "aws_iam_user_policy" "ses_smtp_policy" {
  name = "${var.cluster_name}-${var.environment}-ses-smtp-policy"
  user = aws_iam_user.ses_smtp.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ses:FromAddress" = var.allowed_sender_patterns
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ses:GetSendQuota",
          "ses:GetSendStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Access Key for SMTP Authentication
resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}

# Local values for SMTP configuration
locals {
  # SES SMTP Endpoints by region
  smtp_endpoints = {
    "us-east-1"      = "email-smtp.us-east-1.amazonaws.com"
    "us-east-2"      = "email-smtp.us-east-2.amazonaws.com"
    "us-west-1"      = "email-smtp.us-west-1.amazonaws.com"
    "us-west-2"      = "email-smtp.us-west-2.amazonaws.com"
    "eu-west-1"      = "email-smtp.eu-west-1.amazonaws.com"
    "eu-west-2"      = "email-smtp.eu-west-2.amazonaws.com"
    "eu-central-1"   = "email-smtp.eu-central-1.amazonaws.com"
    "ap-south-1"     = "email-smtp.ap-south-1.amazonaws.com"
    "ap-southeast-1" = "email-smtp.ap-southeast-1.amazonaws.com"
    "ap-southeast-2" = "email-smtp.ap-southeast-2.amazonaws.com"
    "ap-northeast-1" = "email-smtp.ap-northeast-1.amazonaws.com"
  }

  smtp_host = lookup(local.smtp_endpoints, var.aws_region, "email-smtp.${var.aws_region}.amazonaws.com")
  smtp_port = 587 # STARTTLS port

  # SMTP Username is the AWS Access Key ID
  smtp_username = aws_iam_access_key.ses_smtp.id

  # SMTP Password is derived from the Secret Access Key
  # AWS SES requires a special conversion of the secret key
  # This is a simplified approach - the actual SMTP password needs to be
  # generated using AWS's algorithm. We'll output the secret key and
  # document the conversion process.
  smtp_password = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
}

# SES Sending Authorization Policy (for cross-account sending - optional)
resource "aws_ses_identity_policy" "sender_policy" {
  count    = var.enable_cross_account_sending ? 1 : 0
  identity = var.sender_email
  name     = "${var.cluster_name}-${var.environment}-sender-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.authorized_sender_arns
        }
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "arn:aws:ses:${var.aws_region}:*:identity/${var.sender_email}"
      }
    ]
  })

  depends_on = [aws_ses_email_identity.verified_emails]
}
