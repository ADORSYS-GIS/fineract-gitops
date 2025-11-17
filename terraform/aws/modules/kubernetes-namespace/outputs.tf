# Kubernetes Namespace Module Outputs

output "namespace_name" {
  description = "Name of the created Kubernetes namespace"
  value       = kubernetes_namespace.fineract.metadata[0].name
}

output "namespace_id" {
  description = "ID of the created Kubernetes namespace"
  value       = kubernetes_namespace.fineract.id
}

output "namespace_labels" {
  description = "Labels applied to the namespace"
  value       = kubernetes_namespace.fineract.metadata[0].labels
}

output "namespace_annotations" {
  description = "Annotations applied to the namespace"
  value       = kubernetes_namespace.fineract.metadata[0].annotations
}
