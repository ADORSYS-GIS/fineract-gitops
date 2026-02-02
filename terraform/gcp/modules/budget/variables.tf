variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "billing_account_id" {
  description = "GCP billing account ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "budget_amount" {
  description = "Total budget amount in USD"
  type        = number
  default     = 200
}

variable "compute_budget_amount" {
  description = "Compute budget amount in USD"
  type        = number
  default     = 100
}

variable "database_budget_amount" {
  description = "Database budget amount in USD"
  type        = number
  default     = 50
}

variable "alert_thresholds" {
  description = "List of alert thresholds"
  type = list(object({
    percent = number
    basis   = string
  }))
  default = [
    { percent = 0.5, basis = "CURRENT_SPEND" },
    { percent = 0.8, basis = "CURRENT_SPEND" },
    { percent = 1.0, basis = "CURRENT_SPEND" },
    { percent = 1.2, basis = "FORECASTED_SPEND" }
  ]
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "disable_default_notifications" {
  description = "Disable default IAM recipient notifications"
  type        = bool
  default     = false
}

variable "enable_service_budgets" {
  description = "Enable separate budgets for compute and database"
  type        = bool
  default     = false
}

variable "filter_labels" {
  description = "Labels to filter budget by"
  type        = map(list(string))
  default     = {}
}
