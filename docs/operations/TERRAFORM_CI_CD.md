# Terraform CI/CD Workflow

This document explains the continuous integration and continuous delivery (CI/CD) workflow for Terraform, which automates the validation and planning of infrastructure changes.

## Overview

The Terraform CI/CD workflow is designed to bring automation and a consistent review process to infrastructure changes. It is triggered on every pull request that modifies files in the `terraform/aws/` directory.

The workflow performs the following steps:

1.  **Checkout Code**: It checks out the code from the pull request branch.
2.  **Configure AWS Credentials**: It configures the necessary AWS credentials to interact with your AWS account.
3.  **Setup Terraform**: It installs and configures the specified version of Terraform.
4.  **Terraform Init**: It initializes the Terraform working directory, downloading the necessary providers and modules.
5.  **Terraform Validate**: It validates the Terraform configuration to ensure it is syntactically correct and internally consistent.
6.  **Terraform Plan**: It creates an execution plan, which shows the changes that Terraform will make to your infrastructure.
7.  **Comment on PR**: It posts the output of the `terraform plan` as a comment on the pull request, allowing for a thorough review of the proposed changes before merging.

## How to Use

1.  **Create a Pull Request**: Make your desired infrastructure changes in a new branch and create a pull request targeting the `main` branch.
2.  **Review the Plan**: Once the "Terraform CI" GitHub Actions workflow completes, a comment will be posted on your pull request with the `terraform plan` output.
3.  **Interpret the Plan**:
    *   `+` (create): A new resource will be created.
    *   `-` (destroy): An existing resource will be destroyed.
    *   `~` (update): An existing resource will be modified in-place.
    *   `-/+` (replace): An existing resource will be destroyed and a new one will be created in its place.
4.  **Merge the Pull Request**: If the plan is acceptable, merge the pull request into the `main` branch.

## Prerequisites

For this workflow to function correctly, you must configure the following secrets in your GitHub repository settings under **Settings** > **Secrets and variables** > **Actions**:

*   `AWS_ACCESS_KEY_ID`: Your AWS access key ID.
*   `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key.
*   `AWS_REGION`: The AWS region where your resources are deployed (e.g., `us-east-2`).

**Important**: It is highly recommended to use a dedicated IAM user with the principle of least privilege for this workflow, rather than a user with full administrative access.

## Future Enhancements

*   **Automated Apply**: The workflow can be extended to automatically apply the Terraform changes (`terraform apply`) after a pull request is merged into the `main` branch.
*   **Environment-Specific Plans**: The workflow can be modified to generate plans for different environments (e.g., dev, uat, prod) based on the branch or other triggers.
*   **Cost Estimation**: The `terraform plan` can be integrated with tools like Infracost to provide cost estimates for the proposed changes.
