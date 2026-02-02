output "budget_name" {
  description = "Name of the environment budget"
  value       = google_billing_budget.environment.display_name
}

output "budget_id" {
  description = "ID of the environment budget"
  value       = google_billing_budget.environment.id
}

output "compute_budget_id" {
  description = "ID of the compute budget"
  value       = var.enable_service_budgets ? google_billing_budget.compute[0].id : null
}

output "database_budget_id" {
  description = "ID of the database budget"
  value       = var.enable_service_budgets ? google_billing_budget.database[0].id : null
}
