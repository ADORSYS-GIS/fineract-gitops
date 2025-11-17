# Kubernetes Namespace Module Variables

variable "namespace_name" {
  description = "Name of the Kubernetes namespace to create"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "labels" {
  description = "Additional labels to apply to the namespace"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations to apply to the namespace"
  type        = map(string)
  default     = {}
}
