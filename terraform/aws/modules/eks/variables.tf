# EKS Module Variables

variable "aws_region" {
  description = "AWS region where the EKS cluster will be created"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"  # EKS API accepts X.Y format (e.g., 1.31)

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.cluster_version))
    error_message = "EKS cluster version must be in format X.Y (e.g., 1.31). EKS does not accept X.Y.Z format - use only major.minor version."
  }
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
  description = "List of CIDR blocks allowed to access the EKS API endpoint. Empty list = no public access (most secure)"
  type        = list(string)
  default     = []  # No public access by default - must explicitly specify allowed CIDRs

  validation {
    condition     = alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All values in cluster_endpoint_public_access_cidrs must be valid CIDR blocks."
  }
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

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services (S3, ECR) to reduce NAT Gateway data transfer costs"
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

variable "ebs_csi_service_account_name" {
  description = "Name of EBS CSI driver service account"
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "cluster_autoscaler_service_account_name" {
  description = "Name of Cluster Autoscaler service account"
  type        = string
  default     = "cluster-autoscaler"
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
}
