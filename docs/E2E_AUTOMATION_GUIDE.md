# End-to-End Automation Guide

This guide provides a comprehensive overview of the end-to-end automated workflow for the Fineract GitOps platform, from initial infrastructure provisioning to application deployment and promotion across environments.

## 1. Introduction

This project follows the GitOps methodology, where Git is the single source of truth for both infrastructure and applications. All changes are made through pull requests, which are then automatically validated and deployed.

The goal of this automated pipeline is to provide a fast, reliable, and secure way to deliver changes to the Fineract platform.

## 2. Prerequisites

Before you can use the automated workflow, you must have the following tools installed and configured:

### Tools

*   **`git`**: For version control.
*   **`kubectl`**: For interacting with the Kubernetes cluster.
*   **`terraform`**: For provisioning the infrastructure on AWS.
*   **`gh`**: The GitHub CLI, for creating pull requests.
*   **`yq`**: A command-line YAML processor, for updating YAML files.

### Secrets

You must configure the following secrets in your GitHub repository settings under **Settings** > **Secrets and variables** > **Actions**:

*   **`AWS_ACCESS_KEY_ID`**: Your AWS access key ID.
*   **`AWS_SECRET_ACCESS_KEY`**: Your AWS secret access key.
*   **`AWS_REGION`**: The AWS region where your resources are deployed (e.g., `us-east-2`).
*   **`GITOPS_APP_ID`**: The App ID of the GitHub App used for GitOps authentication.
*   **`GITOPS_APP_PRIVATE_KEY`**: The private key of the GitHub App.

**Important**: It is highly recommended to use a dedicated IAM user with the principle of least privilege for the AWS credentials, and a dedicated GitHub App for GitOps authentication.

## 3. The End-to-End Workflow

This section describes the "happy path" for deploying changes, from infrastructure to application updates.

### Step 1: Infrastructure Provisioning (One-Time Setup)

The first step is to provision the initial infrastructure on AWS using Terraform.

1.  **Navigate to the Terraform directory**:
    ```bash
    cd terraform/aws
    ```

2.  **Initialize Terraform**:
    ```bash
    terraform init
    ```

3.  **Apply the Terraform configuration**:
    ```bash
    terraform apply -var-file=environments/dev-k3s.tfvars -auto-approve
    ```
    This will provision the VPC, K3s cluster, RDS database, and other necessary AWS resources for the `dev` environment.

**Note**: The `dev` environment is configured to use `t4g.large` instances, which are ARM-based Graviton2 instances. Ensure that all your Docker images are available for the ARM64 architecture.

### Step 2: Application Deployment (CI/CD)

Once the infrastructure is provisioned, application changes are deployed automatically through the CI/CD pipeline.

1.  **Make a code change**: A developer makes a code change in the Fineract source repository and pushes it to the `develop` branch.
2.  **CI/CD Pipeline**: This triggers a GitHub Actions workflow that:
    *   Runs tests.
    *   Builds a new Docker image.
    *   Pushes the image to the container registry.
    *   Creates a pull request in this GitOps repository to update the image tag in the `environments/dev/fineract-image-version.yaml` file.
3.  **Auto-merge and Deploy**: The pull request is automatically merged, and ArgoCD detects the change and deploys the new image to the `dev` environment.

### Step 3: Promotion to UAT

After the changes have been tested in the `dev` environment, they can be promoted to the `uat` environment.

1.  **Run the promotion script**:
    ```bash
    ./scripts/promote-to-uat.sh <commit_sha>
    ```
    Replace `<commit_sha>` with the Git commit SHA of the version you want to promote.

2.  **Review and Merge**: This will create a pull request to update the image tag in the `uat` environment. After the pull request is reviewed and merged, ArgoCD will deploy the new version to the `uat` environment.

### Step 4: Promotion to Production

After the changes have been validated in the `uat` environment, they can be promoted to the `production` environment.

1.  **Run the promotion script**:
    ```bash
    ./scripts/promote-to-prod.sh <release_version>
    ```
    Replace `<release_version>` with the semantic version of the release you want to promote (e.g., `1.12.1`).

2.  **Review and Merge**: This will create a pull request to update the image tag in the `production` environment. After the pull request is reviewed, approved, and merged, ArgoCD will deploy the new release to the `production` environment.

### Step 5: Progressive Delivery

The `fineract-read` instances are deployed using a canary release strategy with Argo Rollouts.

1.  **Monitor the Rollout**: When a new version is deployed, you can monitor the progress of the rollout using the Argo Rollouts kubectl plugin:
    ```bash
    kubectl argo rollouts get rollout fineract-read -n fineract-dev -w
    ```

2.  **Promote the Rollout**: When the rollout is paused, you can manually promote it to the next step:
    ```bash
    kubectl argo rollouts promote fineract-read -n fineract-dev
    ```

## 4. Rollbacks and Emergency Procedures

If you need to roll back to a previous version, you can use the `rollback-fineract-image.sh` script:

```bash
# To revert the last image update for a specific environment (e.g., dev):
./scripts/rollback-fineract-image.sh dev

# To rollback to a specific image tag for an environment (e.g., production to v1.12.0):
./scripts/rollback-fineract-image.sh production 1.12.0
```

This will create a pull request to revert the image tag to the specified version.

## 5. Cost Optimization

The `dev` and `uat` environments are automatically shut down outside of business hours to reduce costs. This is managed by a set of Kubernetes `CronJob` resources that scale down the Fineract resources and stop the RDS instances.

The schedule for the shutdown and startup can be configured in the `scale-down-cronjob.yaml`, `scale-up-cronjob.yaml`, and `rds-shutdown-cronjob.yaml` files in the `apps/fineract/base/` directory.
