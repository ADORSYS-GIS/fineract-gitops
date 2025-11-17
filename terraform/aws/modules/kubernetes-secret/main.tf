terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# RDS Connection Secret (legacy name - kept for compatibility)
resource "kubernetes_secret" "rds_connection" {
  metadata {
    name      = "rds-connection"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "database"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "RDS PostgreSQL connection details for Fineract"
      }
    )
  }

  data = {
    jdbc-url = var.rds_jdbc_url
    host     = var.rds_host
    port     = tostring(var.rds_port)
    database = var.rds_database
    username = var.rds_username
    password = var.rds_password
  }

  type = "Opaque"
}

# AWS RDS Credentials Secret (for Fineract RDS_ENDPOINT)
resource "kubernetes_secret" "aws_rds_credentials" {
  metadata {
    name      = "aws-rds-credentials"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "database"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "AWS RDS endpoint for Fineract"
      }
    )
  }

  data = {
    endpoint = var.rds_host
  }

  type = "Opaque"
}

# Fineract Database Credentials Secret
resource "kubernetes_secret" "fineract_db_credentials" {
  metadata {
    name      = "fineract-db-credentials"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "database"
        "app.kubernetes.io/name"       = "fineract"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "Fineract database credentials for RDS PostgreSQL"
      }
    )
  }

  data = {
    username = var.rds_username
    password = var.rds_password
  }

  type = "Opaque"
}

# S3 Connection Secret (legacy name - kept for compatibility)
resource "kubernetes_secret" "s3_connection" {
  metadata {
    name      = "s3-connection"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "storage"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "S3 bucket details for Fineract documents and backups"
      }
    )
  }

  data = {
    documents-bucket     = var.documents_bucket_name
    backups-bucket       = var.backups_bucket_name
    region               = var.aws_region
    acceleration-enabled = var.s3_acceleration_enabled ? "true" : "false"
  }

  type = "Opaque"
}

# AWS S3 Credentials Secret (for Fineract S3 access)
# Note: Using IRSA (IAM Roles for Service Accounts) is recommended over static credentials
resource "kubernetes_secret" "aws_s3_credentials" {
  count = var.s3_use_irsa ? 0 : 1

  metadata {
    name      = "aws-s3-credentials"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "storage"
        "app.kubernetes.io/name"       = "fineract"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "AWS S3 credentials for Fineract (use IRSA instead when possible)"
      }
    )
  }

  data = {
    bucket-name       = var.documents_bucket_name
    access-key-id     = var.s3_access_key_id
    secret-access-key = var.s3_secret_access_key
    region            = var.aws_region
  }

  type = "Opaque"
}

# Fineract Redis Credentials Secret (for in-cluster Redis)
resource "kubernetes_secret" "fineract_redis_credentials" {
  metadata {
    name      = "fineract-redis-credentials"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "cache"
        "app.kubernetes.io/name"       = "fineract"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "Redis connection details for Fineract (in-cluster fineract-redis)"
      }
    )
  }

  data = {
    endpoint = var.redis_host
    port     = tostring(var.redis_port)
  }

  type = "Opaque"
}

# SMTP Credentials Secret for Keycloak
resource "kubernetes_secret" "smtp_credentials" {
  count = var.ses_enabled ? 1 : 0

  metadata {
    name      = "smtp-credentials"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/component"  = "email"
        "app"                          = "keycloak"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "SES SMTP credentials for Keycloak"
      }
    )
  }

  data = {
    username = var.ses_smtp_username
    password = var.ses_smtp_password
  }

  type = "Opaque"
}

# Service Account with IRSA annotation
resource "kubernetes_service_account" "fineract_aws" {
  metadata {
    name      = "fineract-aws"
    namespace = var.namespace

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "fineract"
      }
    )

    annotations = merge(
      var.annotations,
      {
        "eks.amazonaws.com/role-arn" = var.irsa_role_arn
        "terraform-managed"          = "true"
        "description"                = "Service account for Fineract with IRSA (IAM Roles for Service Accounts)"
      }
    )
  }

  automount_service_account_token = true
}
