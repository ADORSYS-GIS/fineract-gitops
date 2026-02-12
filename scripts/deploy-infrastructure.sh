#!/bin/bash
# Deploy AWS Infrastructure via Terraform (EKS)

set -e

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform/aws"

echo "Deploying infrastructure for $ENV environment..."

cd "$TERRAFORM_DIR"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Apply infrastructure
echo "Applying Terraform configuration..."
echo "NOTE: This will create EKS cluster, RDS, S3, and other AWS resources"
terraform apply -var-file=environments/${ENV}-eks.tfvars -auto-approve || {
    echo "Terraform apply had errors."
    echo "Check the output above for details."
    exit 1
}

# Use the post-terraform setup script to handle kubeconfig and secrets
echo "Running post-terraform setup (kubeconfig + secrets)..."
"$SCRIPT_DIR/post-terraform-setup.sh" "$ENV"

echo "Infrastructure deployment complete!"
