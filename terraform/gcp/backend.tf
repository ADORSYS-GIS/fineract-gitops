# GCS Backend Configuration for Terraform State
#
# Before running terraform init, create the GCS bucket:
#   gsutil mb -p PROJECT_ID -l us-central1 gs://fineract-terraform-state-PROJECT_ID
#   gsutil versioning set on gs://fineract-terraform-state-PROJECT_ID
#
# Then uncomment the backend configuration below and run:
#   terraform init -backend-config="bucket=fineract-terraform-state-PROJECT_ID" \
#                  -backend-config="prefix=terraform/state/ENV"

# terraform {
#   backend "gcs" {
#     # bucket  = "fineract-terraform-state-PROJECT_ID"  # Set via -backend-config
#     # prefix  = "terraform/state/dev"                  # Set via -backend-config
#   }
# }

# For initial development, use local backend
# Comment this out and uncomment the GCS backend above for production use
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
