# Route53 Module Variables

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
}
