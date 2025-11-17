#!/bin/bash
# EKS Migration Files Generator
# This script generates all necessary files for the K3s to EKS migration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== EKS Migration Files Generator ==="
echo "This script will create all necessary files for migrating from K3s to EKS"
echo ""

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

created_files=0
skipped_files=0

# Function to create file with content
create_file() {
    local file_path="$1"
    local content="$2"

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$file_path")"

    if [ -f "$file_path" ]; then
        echo -e "${YELLOW}⊙${NC} Skipping (exists): $file_path"
        ((skipped_files++))
    else
        echo "$content" > "$file_path"
        echo -e "${GREEN}✓${NC} Created: $file_path"
        ((created_files++))
    fi
}

echo "Creating EKS Terraform module files..."
echo ""

# ============================================================================
# EKS Module: addons.tf
# ============================================================================
create_file "$PROJECT_ROOT/terraform/aws/modules/eks/addons.tf" '# EKS Add-ons Configuration
# This file manages EKS add-ons like VPC-CNI, EBS CSI Driver, and CloudWatch

# VPC CNI Add-on (required for pod networking)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = var.vpc_cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# CoreDNS Add-on (required for DNS resolution)
resource "aws_eks_addon" "coredns" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "coredns"
  addon_version            = var.coredns_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_node_group.main
  ]
}

# kube-proxy Add-on (required for service networking)
resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "kube-proxy"
  addon_version            = var.kube_proxy_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# EBS CSI Driver Add-on (required for persistent volumes)
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_driver_version
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_driver
  ]
}

# CloudWatch Observability Add-on (optional but recommended)
resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enable_cloudwatch_observability ? 1 : 0

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "amazon-cloudwatch-observability"
  addon_version            = var.cloudwatch_observability_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_node_group.main
  ]
}'

# ============================================================================
# EKS Module: security.tf
# ============================================================================
create_file "$PROJECT_ROOT/terraform/aws/modules/eks/security.tf" '# Security Groups for EKS Cluster
# This file manages security groups for the EKS cluster and node groups

# Additional security group for cluster
resource "aws_security_group" "cluster_additional" {
  name_prefix = "${var.cluster_name}-cluster-additional-"
  description = "Additional security group for EKS cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-additional-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow inbound HTTPS from anywhere (for kubectl access)
resource "aws_security_group_rule" "cluster_additional_ingress_https" {
  count = var.cluster_endpoint_public_access ? 1 : 0

  security_group_id = aws_security_group.cluster_additional.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.cluster_endpoint_public_access_cidrs
  description       = "Allow HTTPS access to cluster API"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "cluster_additional_egress_all" {
  security_group_id = aws_security_group.cluster_additional.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

# Security group for node groups
resource "aws_security_group" "node_group" {
  name_prefix = "${var.cluster_name}-node-"
  description = "Security group for EKS node groups"
  vpc_id      = aws_vpc.eks_vpc.id

  tags = merge(
    var.tags,
    {
      Name                                           = "${var.cluster_name}-node-sg"
      "kubernetes.io/cluster/${var.cluster_name}"    = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "node_group_ingress_self" {
  security_group_id        = aws_security_group.node_group.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.node_group.id
  description              = "Allow nodes to communicate with each other"
}

# Allow pods to communicate with cluster API
resource "aws_security_group_rule" "node_group_ingress_cluster_https" {
  security_group_id        = aws_security_group.node_group.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description              = "Allow pods to communicate with cluster API"
}

# Allow all outbound traffic from nodes
resource "aws_security_group_rule" "node_group_egress_all" {
  security_group_id = aws_security_group.node_group.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

# Allow cluster to communicate with nodes
resource "aws_security_group_rule" "cluster_to_node_ingress" {
  security_group_id        = aws_security_group.node_group.id
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description              = "Allow cluster to communicate with nodes"
}'

# ============================================================================
# EKS Module: variables.tf
# ============================================================================
create_file "$PROJECT_ROOT/terraform/aws/modules/eks/variables.tf" '# EKS Module Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the cluster endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_encryption_key_arn" {
  description = "ARN of KMS key for cluster encryption (optional)"
  type        = string
  default     = ""
}

# Node group variables
variable "node_instance_types" {
  description = "List of instance types for node groups"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Disk size in GB for nodes"
  type        = number
  default     = 50
}

variable "node_capacity_type" {
  description = "Capacity type for nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_taints" {
  description = "List of taints to apply to nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

# Add-on versions
variable "vpc_cni_version" {
  description = "Version of VPC CNI add-on"
  type        = string
  default     = "v1.18.1-eksbuild.3"
}

variable "coredns_version" {
  description = "Version of CoreDNS add-on"
  type        = string
  default     = "v1.11.1-eksbuild.9"
}

variable "kube_proxy_version" {
  description = "Version of kube-proxy add-on"
  type        = string
  default     = "v1.31.0-eksbuild.5"
}

variable "ebs_csi_driver_version" {
  description = "Version of EBS CSI driver add-on"
  type        = string
  default     = "v1.35.0-eksbuild.1"
}

variable "cloudwatch_observability_version" {
  description = "Version of CloudWatch Observability add-on"
  type        = string
  default     = "v2.1.0-eksbuild.1"
}

variable "enable_cloudwatch_observability" {
  description = "Enable CloudWatch Observability add-on"
  type        = bool
  default     = true
}

# IRSA variables
variable "app_namespace" {
  description = "Namespace for application service accounts"
  type        = string
  default     = "fineract-dev"
}

variable "app_service_account_name" {
  description = "Name of application service account"
  type        = string
  default     = "fineract-app"
}

variable "s3_bucket_name" {
  description = "Name of S3 bucket for application access"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, uat, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}'

# ============================================================================
# EKS Module: outputs.tf
# ============================================================================
create_file "$PROJECT_ROOT/terraform/aws/modules/eks/outputs.tf" '# EKS Module Outputs

output "cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = try(aws_eks_cluster.main.identity[0].oidc[0].issuer, null)
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.eks_vpc.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.eks_vpc.cidr_block
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = aws_security_group.node_group.id
}

output "node_iam_role_arn" {
  description = "IAM role ARN for EKS nodes"
  value       = aws_iam_role.eks_nodes.arn
}

output "node_iam_role_name" {
  description = "IAM role name for EKS nodes"
  value       = aws_iam_role.eks_nodes.name
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "app_service_account_role_arn" {
  description = "IAM role ARN for application service account"
  value       = aws_iam_role.app_service_account.arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${data.aws_availability_zones.available.id}"
}'

echo ""
echo "Creating Route53 Terraform module files..."
echo ""

# ============================================================================
# Route53 Module: main.tf
# ============================================================================
create_file "$PROJECT_ROOT/terraform/aws/modules/route53/main.tf" '# Route53 Module for DNS Management

# Create hosted zone
resource "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0

  name = var.domain_name

  tags = merge(
    var.tags,
    {
      Name        = var.domain_name
      Environment = var.environment
    }
  )
}

# Outputs for nameservers
output "zone_id" {
  description = "The hosted zone ID"
  value       = try(aws_route53_zone.main[0].zone_id, "")
}

output "name_servers" {
  description = "List of name servers for the hosted zone"
  value       = try(aws_route53_zone.main[0].name_servers, [])
}

output "zone_arn" {
  description = "The ARN of the hosted zone"
  value       = try(aws_route53_zone.main[0].arn, "")
}'

# ============================================================================
# Route53 Module: variables.tf
# ============================================================================
create_file "$PROJECT_ROOT/terraform/aws/modules/route53/variables.tf" '# Route53 Module Variables

variable "domain_name" {
  description = "Domain name for Route53 hosted zone"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, uat, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to Route53 resources"
  type        = map(string)
  default     = {}
}'

echo ""
echo "=== File Generation Summary ==="
echo -e "${GREEN}✓ Created: $created_files files${NC}"
echo -e "${YELLOW}⊙ Skipped: $skipped_files files (already exist)${NC}"
echo ""
echo "Next steps:"
echo "1. Review the generated files"
echo "2. Run: terraform fmt -recursive terraform/"
echo "3. Update main.tf to use the EKS module"
echo "4. Create dev-eks.tfvars with your configuration"
echo ""
'

chmod +x "$PROJECT_ROOT/scripts/generate-eks-migration-files.sh"
