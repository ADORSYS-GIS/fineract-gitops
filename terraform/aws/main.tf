terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
  }
}

locals {
  common_tags = merge(
    var.tags,
    {
      Project     = "fineract"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "fineract-gitops"
      Migration   = "k3s-to-eks"
    }
  )
}

# EKS Module (managed Kubernetes cluster)
module "eks" {
  source = "./modules/eks"

  aws_region      = var.aws_region
  cluster_name    = var.cluster_name
  cluster_version = var.eks_cluster_version
  environment     = var.environment
  vpc_cidr        = var.vpc_cidr

  # Node configuration
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_capacity_type  = var.node_capacity_type  # SPOT for dev (70% cost savings)

  # Cluster access configuration
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Add-ons configuration
  enable_cloudwatch_observability = var.enable_cloudwatch_observability

  # Cost Optimization: VPC endpoints to reduce NAT Gateway costs
  enable_vpc_endpoints = var.enable_vpc_endpoints

  # IRSA configuration
  app_namespace             = var.kubernetes_namespace
  app_service_account_name  = "fineract-app"
  s3_bucket_name            = module.s3.documents_bucket_id

  tags = local.common_tags
}

# Route53 Module (optional DNS management)
module "route53" {
  source = "./modules/route53"

  domain_name = var.domain_name
  environment = var.environment
  tags        = local.common_tags
}

# RDS PostgreSQL
module "rds" {
  source = "./modules/rds"

  cluster_name            = var.cluster_name
  environment             = var.environment
  vpc_id                  = module.eks.vpc_id
  subnet_ids              = module.eks.private_subnet_ids
  allowed_security_groups = [
    module.eks.node_security_group_id,     # Node-to-RDS communication
    module.eks.cluster_security_group_id   # Pod-to-RDS communication (critical)
  ]

  postgres_version      = var.rds_postgres_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = var.rds_storage_type
  kms_key_id            = var.kms_key_id

  # Note: database_name parameter removed - no default database created
  # Applications create their own databases via Kubernetes jobs
  master_username = var.rds_master_username
  max_connections = var.rds_max_connections

  multi_az                = var.rds_multi_az
  backup_retention_period = var.rds_backup_retention_period

  performance_insights_enabled = var.rds_performance_insights_enabled
  monitoring_interval          = var.rds_monitoring_interval

  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = var.rds_skip_final_snapshot

  tags = local.common_tags
}

# S3 Buckets
module "s3" {
  source = "./modules/s3"

  cluster_name = var.cluster_name
  environment  = var.environment
  kms_key_id   = var.kms_key_id

  enable_versioning           = var.s3_enable_versioning
  documents_lifecycle_enabled = var.s3_documents_lifecycle_enabled
  backups_expiration_days     = var.s3_backups_expiration_days

  enable_transfer_acceleration = var.s3_enable_transfer_acceleration
  enable_intelligent_tiering   = var.s3_enable_intelligent_tiering
  force_destroy                = var.s3_force_destroy

  tags = local.common_tags
}

# AWS SES (Simple Email Service)
module "ses" {
  count  = var.ses_enabled ? 1 : 0
  source = "./modules/ses"

  cluster_name = var.cluster_name
  environment  = var.environment
  aws_region   = var.aws_region

  verified_emails = var.ses_verified_emails
  sender_email    = var.ses_sender_email
  sender_name     = var.ses_sender_name
  domain          = var.ses_domain

  allowed_sender_patterns      = var.ses_allowed_sender_patterns
  enable_cross_account_sending = var.ses_enable_cross_account_sending
  authorized_sender_arns       = var.ses_authorized_sender_arns

  tags = local.common_tags
}

# IAM Roles (IRSA for EKS)
module "iam" {
  source = "./modules/iam"

  cluster_name         = var.cluster_name
  environment          = var.environment
  namespace            = var.kubernetes_namespace
  service_account_name = var.service_account_name

  # EKS IRSA configuration
  use_instance_profile = false
  k3s_role_name        = null
  oidc_provider_url    = module.eks.cluster_oidc_issuer_url

  rds_instance_arn     = module.rds.db_instance_arn
  documents_bucket_arn = module.s3.documents_bucket_arn
  backups_bucket_arn   = module.s3.backups_bucket_arn
  kms_key_arn          = var.kms_key_id
  ses_enabled          = var.ses_enabled

  tags = local.common_tags
}

# ==============================================================================
# OAuth2 Secrets (for OAuth2-Proxy and Keycloak client configuration)
# ==============================================================================

resource "random_password" "oauth2_client_secret" {
  length  = 64
  special = false # Only alphanumeric for OAuth2 compatibility
  upper   = true
  lower   = true
  numeric = true

  lifecycle {
    ignore_changes = [length, special, upper, lower, numeric]
  }
}

resource "random_password" "oauth2_cookie_secret" {
  length  = 32
  special = false # Only alphanumeric for cookie compatibility
  upper   = true
  lower   = true
  numeric = true

  lifecycle {
    ignore_changes = [length, special, upper, lower, numeric]
  }
}

# Kubernetes Namespace and Secrets - Managed by ArgoCD + Sealed Secrets
# See: scripts/seal-terraform-secrets.sh for creating sealed secrets from Terraform outputs
#
# Removed from Terraform to follow GitOps best practices:
# - Namespace created via Kustomize manifests (environments/dev/namespace.yaml)
# - Secrets created as SealedSecrets and stored in Git (secrets/dev/*.yaml)
# - ArgoCD syncs and applies all Kubernetes resources
# - Sealed Secrets controller decrypts secrets automatically
#
# module "kubernetes_namespace" { ... }  # REMOVED
# module "kubernetes_secrets" { ... }    # REMOVED
