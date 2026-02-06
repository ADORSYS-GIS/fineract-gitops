# Quick Sync Guide for Fineract GitOps

This guide provides the essential commands to clone the repository, connect to the existing AWS infrastructure, and verify your setup.

### Step 1: Clone the Repository and Checkout the Correct Branch

```bash
# Clone the repository using the specified branch
git clone -b deploy-key git@github.com:ADORSYS-GIS/fineract-gitops.git

# Enter the project directory
cd fineract-gitops
```

### Step 2: Configure Your AWS Credentials

Before you can interact with the infrastructure, you need to configure your local environment with the correct AWS credentials.

```bash
# Export the ADORSYS AWS credentials (replace placeholders with actual values)
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY_HERE"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY_HERE"
export AWS_SESSION_TOKEN="YOUR_SESSION_TOKEN_HERE" n"

# Verify your identity
aws sts get-caller-identity
```

### Step 3: Connect to the Kubernetes Cluster

This command will fetch the connection details for our Kubernetes cluster and save them to a dedicated local file.

```bash
# Connect to the 'apache-fineract-dev' cluster and save the configuration
# to a local file named '~/.kube/config-fineract-dev'
aws eks update-kubeconfig \
  --name apache-fineract-dev \
  --region eu-central-1 \
  --kubeconfig ~/.kube/config-fineract-dev

# Set the KUBECONFIG environment variable to ensure kubectl uses this specific file
export KUBECONFIG=~/.kube/config-fineract-dev

# Verify you can connect to the cluster
kubectl cluster-info
```

### Step 4: Initialize Terraform and Verify the Infrastructure State

Now, connect to the Terraform remote state to ensure your local setup matches the deployed infrastructure.

```bash
# Navigate to the terraform directory
cd terraform/aws

# Initialize Terraform. This will use the 'backend-dev.tfbackend' file
# to connect to the S3 bucket where our infrastructure state is stored.
terraform init -backend-config=backend-dev.tfbackend

# Run a plan to verify. This command should show "No changes" if your
# setup is correct, confirming you are synced with the existing infrastructure.
terraform plan -var-file=environments/dev-eks.tfvars
```

You are now fully synced and ready to continue working on the project.