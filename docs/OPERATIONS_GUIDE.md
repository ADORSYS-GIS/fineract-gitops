# Operations Guide: Managing Updates and Deployments

This guide provides a comprehensive overview of the operational procedures for managing the Fineract GitOps platform after the initial setup. It covers how to update the infrastructure, deploy and update applications, and handle a full disaster recovery scenario.

## 1. Updating the Infrastructure (Terraform)

After the initial `terraform apply`, all subsequent infrastructure changes should be managed through a pull request workflow to ensure proper review and validation.

**Do not run `terraform apply` directly on your local machine for updates.**

### The Infrastructure Update Workflow

1.  **Create a New Branch**:
    Create a new branch in this GitOps repository for your infrastructure changes.
    ```bash
    git checkout -b feature/update-rds-instance-type
    ```

2.  **Modify Terraform Code**:
    Make your desired changes to the Terraform files in the `terraform/aws/` directory (e.g., update the `instance_class` in `variables.tf` or modify a module).

3.  **Create a Pull Request**:
    Commit your changes and create a pull request targeting the `main` branch.

4.  **Automated Validation and Plan**:
    The `terraform-ci.yml` GitHub Actions workflow will automatically trigger. It will:
    *   Run `terraform validate` to check for syntax errors.
    *   Run `terraform plan` to generate an execution plan.
    *   Post the plan as a comment on your pull request.

5.  **Review and Approve**:
    Review the `terraform plan` in the pull request comment to ensure that the proposed changes are correct.

6.  **Merge and Apply**:
    Once the pull request is approved and merged into the `main` branch, you have two options for applying the changes:

    *   **Manual Apply (Recommended for Production)**: A team member with the appropriate AWS credentials can then pull the `main` branch and run `terraform apply` from their local machine.
        ```bash
        git checkout main
        git pull origin main
        cd terraform/aws
        terraform apply -var-file=environments/dev-k3s.tfvars -auto-approve
        ```
    *   **Automated Apply (for Dev/UAT)**: The `terraform-ci.yml` workflow can be extended to automatically run `terraform apply` after a pull request is merged. (This is a future enhancement).

## 2. Deploying and Updating Applications

All application deployments and updates are managed through the GitOps workflow. **You should never use `kubectl apply` or `kubectl edit` directly on the cluster.**

### The Application Deployment Workflow

1.  **Update Kubernetes Manifests**:
    Make your desired changes to the Kubernetes manifests in the `apps/`, `environments/`, or `operations/` directories in a new branch. This could be:
    *   Updating an image tag in a `kustomization.yaml` file.
    *   Modifying a `ConfigMap`.
    *   Changing the number of replicas in a `Deployment` or `Rollout`.

2.  **Create a Pull Request**:
    Commit your changes and create a pull request targeting the appropriate branch (`develop` for `dev` environment, `main` for `uat` and `prod`).

3.  **Automated Deployment (for Dev)**:
    *   For the `dev` environment, pull requests to the `develop` branch are automatically merged.
    *   ArgoCD detects the change in the `develop` branch and automatically syncs the application to the `dev` cluster.

4.  **Manual Promotion (for UAT and Prod)**:
    *   For `uat` and `prod`, use the promotion scripts:
        ```bash
        # Promote a specific commit to UAT
        ./scripts/promote-to-uat.sh <commit_sha>

        # Promote a release to Production
        ./scripts/promote-to-prod.sh <release_version>
        ```
    *   This will create a pull request to the `main` branch.
    *   After the pull request is reviewed and merged, you will need to manually sync the corresponding ArgoCD application.
        ```bash
        # Sync the UAT application
        argocd app sync fineract-uat-fineract

        # Sync the Production application
        argocd app sync fineract-prod-fineract
        ```

## 3. Disaster Recovery: Full Re-provisioning

In the event of a complete disaster where the entire infrastructure needs to be re-provisioned from scratch, follow these steps:

1.  **Restore the Terraform State**:
    If you are using an S3 backend for your Terraform state (which is highly recommended), your state file should be safe. If you are using a local state file, you will need to restore it from a backup.

2.  **Re-provision the Infrastructure**:
    Run `terraform apply` to re-create all the AWS resources.
    ```bash
    cd terraform/aws
    terraform apply -var-file=environments/dev-k3s.tfvars -auto-approve
    ```

3.  **Restore the Database**:
    Follow the database restore procedures outlined in the [Disaster Recovery Guide](disaster-recovery/DR_GUIDE.md) to restore the RDS database from a snapshot.

4.  **Deploy All Applications**:
    Once the infrastructure and database are restored, you can deploy all the applications by syncing the top-level "app of apps" in ArgoCD.
    ```bash
    # Sync the main app-of-apps for the desired environment
    argocd app sync fineract-dev-app-of-apps
    ```
    This will trigger the deployment of all the applications for that environment in the correct order, as defined by the sync waves in the ArgoCD application manifests.
