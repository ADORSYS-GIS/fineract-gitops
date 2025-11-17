# Terraform Backend Configuration
#
# Uses S3 for state storage and DynamoDB for state locking.
# Backend configuration uses partial configuration pattern for security.
#
# Usage:
#   terraform init -backend-config=backend-dev.tfbackend
#   terraform init -backend-config=backend-prod.tfbackend
#
# This approach keeps sensitive backend configuration (bucket names, regions)
# out of version control while maintaining infrastructure as code.

terraform {
  backend "s3" {
    # Partial backend configuration
    # Actual values provided via -backend-config flag during init
    #
    # Required in .tfbackend file:
    # - bucket         = "your-terraform-state-bucket"
    # - key            = "fineract/dev/terraform.tfstate"
    # - region         = "us-east-1"
    # - dynamodb_table = "terraform-state-lock"
    # - encrypt        = true

    # Optional: Can be set here if same across all environments
    encrypt = true
  }
}
