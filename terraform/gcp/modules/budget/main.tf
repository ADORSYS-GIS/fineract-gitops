# ==============================================================================
# GCP Budget Alerts Module
# ==============================================================================
# Creates budget alerts for cost monitoring and anomaly detection
# ==============================================================================

# Budget for the environment
resource "google_billing_budget" "environment" {
  billing_account = var.billing_account_id
  display_name    = "${var.cluster_name}-${var.environment}-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]

    # Filter by labels if needed
    labels = var.filter_labels
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  # Alert thresholds
  dynamic "threshold_rules" {
    for_each = var.alert_thresholds
    content {
      threshold_percent = threshold_rules.value.percent
      spend_basis       = threshold_rules.value.basis
    }
  }

  # Notification channels
  all_updates_rule {
    monitoring_notification_channels = var.notification_channels
    disable_default_iam_recipients   = var.disable_default_notifications
  }
}

# Separate budgets for compute, storage, and database (optional)
resource "google_billing_budget" "compute" {
  count = var.enable_service_budgets ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "${var.cluster_name}-${var.environment}-compute-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/6F81-5844-456A"  # Compute Engine
    ]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.compute_budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = var.notification_channels
    disable_default_iam_recipients   = var.disable_default_notifications
  }
}

resource "google_billing_budget" "database" {
  count = var.enable_service_budgets ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "${var.cluster_name}-${var.environment}-database-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/9662-B51E-5089"  # Cloud SQL
    ]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.database_budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = var.notification_channels
    disable_default_iam_recipients   = var.disable_default_notifications
  }
}
