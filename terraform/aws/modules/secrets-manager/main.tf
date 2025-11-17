# AWS Secrets Manager Module
#
# This module creates AWS Secrets Manager secrets for sensitive configuration
# that should not be stored in Terraform variables or version control.
#
# Usage:
#   1. Create secrets via AWS CLI or Console
#   2. Reference secrets using data sources in this module
#   3. Outputs provide secret ARNs and names for IAM policies

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# GitHub Token Secret (must be created manually)
# This secret stores the GitHub Personal Access Token for ArgoCD
#
# To create this secret:
#   aws secretsmanager create-secret \
#     --name /fineract/dev/github-token \
#     --description "GitHub PAT for ArgoCD repository access" \
#     --secret-string "ghp_your_token_here"
#
# Security: The actual token value is NEVER stored in Terraform
data "aws_secretsmanager_secret" "github_token" {
  name = "${var.secret_prefix}/github-token"
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = data.aws_secretsmanager_secret.github_token.id
}

# Sealed Secrets Controller Keys Secret
# This secret is created as a placeholder - the actual keys are populated by backup script
#
# The secret stores the Sealed Secrets controller encryption keys for disaster recovery.
# If the cluster is destroyed, these keys can be restored to decrypt existing sealed secrets.
#
# Lifecycle:
#   1. Terraform creates empty secret placeholder
#   2. After Sealed Secrets controller generates keys, backup script populates secret:
#      ./scripts/backup-sealed-secrets-keys.sh <env>
#   3. On cluster recreation, restore script applies keys before controller starts:
#      ./scripts/restore-sealed-secrets-keys.sh <env>
#
# Security:
#   - Keys are encrypted at rest by AWS Secrets Manager
#   - Access controlled by IAM policies
#   - All access logged by CloudTrail
#   - Versions retained indefinitely for point-in-time recovery
#
resource "aws_secretsmanager_secret" "sealed_secrets_keys" {
  name        = "${var.secret_prefix}/${var.environment}/sealed-secrets/master-key"
  description = "Sealed Secrets controller encryption keys for ${var.environment} environment (disaster recovery)"

  # Recovery window for accidental deletion (7-30 days)
  # Secrets Manager will permanently delete after this window
  # Dev: 7 days (faster cleanup), Production: 30 days (data safety)
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.tags,
    {
      Name          = "${var.cluster_name}-${var.environment}-sealed-secrets-keys"
      Purpose       = "disaster-recovery"
      ManagedBy     = "terraform"
      BackupScript  = "scripts/backup-sealed-secrets-keys.sh"
      RestoreScript = "scripts/restore-sealed-secrets-keys.sh"
    }
  )

}

# Create initial empty version to satisfy AWS Secrets Manager requirement
# The backup script will replace this with actual keys
resource "aws_secretsmanager_secret_version" "sealed_secrets_keys_placeholder" {
  secret_id = aws_secretsmanager_secret.sealed_secrets_keys.id
  secret_string = jsonencode({
    keys              = ""
    timestamp         = ""
    environment       = var.environment
    cluster_context   = ""
    key_count         = 0
    backup_version    = "1.0"
    status            = "placeholder-awaiting-backup"
  })

  # Ignore changes after initial creation - backup script manages versions
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# KMS key for encrypting secrets (optional - Secrets Manager uses default key if not specified)
# Uncomment if you want to use a customer-managed KMS key
# resource "aws_kms_key" "secrets" {
#   description             = "KMS key for Secrets Manager secrets"
#   deletion_window_in_days = 10
#   enable_key_rotation     = true
#
#   tags = merge(
#     var.tags,
#     {
#       Name = "${var.cluster_name}-${var.environment}-secrets-kms"
#     }
#   )
# }
#
# resource "aws_kms_alias" "secrets" {
#   name          = "alias/${var.cluster_name}-${var.environment}-secrets"
#   target_key_id = aws_kms_key.secrets.key_id
# }
