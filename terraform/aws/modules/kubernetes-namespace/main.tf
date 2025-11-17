# Kubernetes Namespace Module
# Creates a Kubernetes namespace for Fineract deployment

terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

resource "kubernetes_namespace" "fineract" {
  metadata {
    name = var.namespace_name

    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "fineract"
        "environment"                  = var.environment
        "cluster"                      = var.cluster_name
      }
    )

    annotations = merge(
      var.annotations,
      {
        "terraform-managed" = "true"
        "description"       = "Fineract platform namespace for ${var.environment} environment"
        "managed-by"        = "fineract-gitops"
        "provisioned-by"    = "terraform"
      }
    )
  }
}
