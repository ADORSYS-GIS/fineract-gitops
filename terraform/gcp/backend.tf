# ==============================================================================
# Terraform Backend Configuration
# ==============================================================================
# Store state in GCS bucket for team collaboration
# ==============================================================================

terraform {
  backend "gcs" {
    bucket = "fineract-486415-terraform-state"
    prefix = "fineract/dev"
  }
}
