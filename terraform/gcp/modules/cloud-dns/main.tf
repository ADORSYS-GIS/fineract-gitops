# ==============================================================================
# Cloud DNS Module (Optional)
# ==============================================================================

resource "google_dns_managed_zone" "main" {
  count = var.domain_name != "" ? 1 : 0

  name        = "${var.cluster_name}-${var.environment}-zone"
  project     = var.project_id
  dns_name    = "${var.domain_name}."
  description = "DNS zone for ${var.cluster_name} ${var.environment}"

  labels = merge(var.labels, {
    environment = var.environment
  })

  dnssec_config {
    state = "on"
  }
}
