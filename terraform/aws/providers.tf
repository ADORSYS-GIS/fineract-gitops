provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  # Configure kubernetes provider based on deployment type
  # For K3s: Uses local kubeconfig (generated after K3s installation)
  # For EKS: Uses AWS CLI configuration

  config_path = "~/.kube/config"

  # Note: For K3s, you need to run this after terraform apply:
  # terraform output -raw kubeconfig > ~/.kube/config-fineract-dev
  # export KUBECONFIG=~/.kube/config-fineract-dev

  # Alternative: Use EKS cluster endpoint (uncomment for EKS)
  # host                   = data.aws_eks_cluster.cluster[0].endpoint
  # cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data)
  # token                  = data.aws_eks_cluster_auth.cluster[0].token
}

# Uncomment for EKS deployments
# data "aws_eks_cluster" "cluster" {
#   count = var.deployment_type == "eks" ? 1 : 0
#   name  = var.cluster_name
# }
#
# data "aws_eks_cluster_auth" "cluster" {
#   count = var.deployment_type == "eks" ? 1 : 0
#   name  = var.cluster_name
# }

provider "random" {}
