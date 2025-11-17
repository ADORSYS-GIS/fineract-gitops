# EKS Cluster Outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "eks_cluster_oidc_issuer_url" {
  description = "OIDC provider URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.eks.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.eks.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.eks.private_subnet_ids
}

# EKS Node Group Outputs
output "eks_node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

# EKS Add-on Outputs
output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = module.eks.ebs_csi_driver_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = module.eks.cluster_autoscaler_role_arn
}

output "app_service_account_role_arn" {
  description = "IAM role ARN for application service account"
  value       = module.eks.app_service_account_role_arn
}

# Kubectl Configuration
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_id} --region ${var.aws_region}"
}

# Route53 Outputs
output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.route53.zone_id
}

output "route53_name_servers" {
  description = "Route53 nameservers (update at your registrar)"
  value       = module.route53.name_servers
}

# RDS Outputs
output "rds_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_instance_arn" {
  description = "RDS instance ARN"
  value       = module.rds.db_instance_arn
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = module.rds.master_username
  sensitive   = true
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.rds.security_group_id
}

# S3 Outputs
output "documents_bucket_name" {
  description = "S3 documents bucket name"
  value       = module.s3.documents_bucket_id
}

output "documents_bucket_arn" {
  description = "S3 documents bucket ARN"
  value       = module.s3.documents_bucket_arn
}

output "backups_bucket_name" {
  description = "S3 backups bucket name"
  value       = module.s3.backups_bucket_id
}

output "backups_bucket_arn" {
  description = "S3 backups bucket ARN"
  value       = module.s3.backups_bucket_arn
}

# IAM Outputs
output "irsa_role_arn" {
  description = "IAM role ARN for Fineract service account (IRSA)"
  value       = module.iam.role_arn
}

output "irsa_role_name" {
  description = "IAM role name for Fineract"
  value       = module.iam.role_name
}

# Kubernetes Outputs - Now managed by Sealed Secrets
# output "kubernetes_service_account_name" {
#   description = "Kubernetes service account name"
#   value       = "fineract-aws"  # Managed via sealed secrets
# }
#
# output "kubernetes_secrets_created" {
#   description = "List of Kubernetes secrets created"
#   value = {
#     rds_secret = "rds-connection"  # Managed via sealed secrets
#     s3_secret  = "s3-connection"   # Managed via sealed secrets
#   }
# }

# SES Outputs
output "ses_smtp_host" {
  description = "SES SMTP endpoint hostname"
  value       = var.ses_enabled ? module.ses[0].smtp_host : null
}

output "ses_smtp_port" {
  description = "SES SMTP port"
  value       = var.ses_enabled ? module.ses[0].smtp_port : null
}

output "ses_smtp_username" {
  description = "SES SMTP username"
  value       = var.ses_enabled ? module.ses[0].smtp_username : null
  sensitive   = true
}

output "ses_sender_email" {
  description = "SES default sender email"
  value       = var.ses_enabled ? module.ses[0].sender_email : null
}

output "ses_verified_emails" {
  description = "List of verified email addresses in SES"
  value       = var.ses_enabled ? module.ses[0].verified_emails : []
}

output "ses_configuration_set" {
  description = "SES configuration set name"
  value       = var.ses_enabled ? module.ses[0].configuration_set_name : null
}

output "ses_domain_verification_token" {
  description = "SES domain verification token (for production mode)"
  value       = var.ses_enabled ? module.ses[0].domain_verification_token : null
}

output "ses_dkim_tokens" {
  description = "SES DKIM tokens for DNS configuration (for production mode)"
  value       = var.ses_enabled ? module.ses[0].dkim_tokens : []
}

# Connection Details for Manual Setup (if needed)
output "connection_details" {
  description = "Connection details for manual configuration"
  value = {
    rds_endpoint      = module.rds.db_instance_endpoint
    documents_bucket  = module.s3.documents_bucket_id
    backups_bucket    = module.s3.backups_bucket_id
    service_account   = "fineract-aws"  # Managed via sealed secrets
    namespace         = var.kubernetes_namespace
    ses_smtp_endpoint = var.ses_enabled ? module.ses[0].smtp_host : null
    ses_sender_email  = var.ses_enabled ? module.ses[0].sender_email : null
  }
}

# Keycloak Database Credentials
output "keycloak_db_username" {
  description = "Keycloak database username"
  value       = module.rds.keycloak_db_username
}

# OAuth2 Secrets (for OAuth2-Proxy and Keycloak client configuration)
output "oauth2_client_secret" {
  description = "OAuth2 client secret for OAuth2-Proxy and Keycloak clients"
  value       = random_password.oauth2_client_secret.result
  sensitive   = true
}

output "oauth2_cookie_secret" {
  description = "OAuth2 cookie secret for OAuth2-Proxy session encryption"
  value       = random_password.oauth2_cookie_secret.result
  sensitive   = true
}

# NOTE: Sensitive outputs removed for security
# The following outputs have been intentionally removed to prevent exposure in Terraform state:
# - rds_master_password
# - ses_smtp_password
# - keycloak_db_password
#
# These values are now accessed directly from Terraform state in seal-terraform-secrets.sh
# using 'terraform show -json' to extract resource attributes without creating outputs.
