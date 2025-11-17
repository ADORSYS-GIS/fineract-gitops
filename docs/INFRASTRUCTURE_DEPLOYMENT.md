# Infrastructure Deployment Guide

**Purpose**: Complete guide for deploying the Fineract GitOps infrastructure components on AWS.

**Deployment Model**: GitOps with Terraform for AWS infrastructure and ArgoCD for Kubernetes resources.

---

## Overview

This guide covers the deployment of all AWS infrastructure components required for the Fineract platform, provisioned using Terraform. Kubernetes resources are then deployed and managed by ArgoCD.

---

## Architecture Layers

The infrastructure is composed of the following key AWS services and Kubernetes components:

```
┌─────────────────────────────────────────────────────────────┐
│                     Layer 4: Applications                    │
│         Fineract, Web Apps, Message Gateway                  │
└──────────────────┬──────────────────────────────────────────┘
                   │ deployed on
┌──────────────────▼──────────────────────────────────────────┐
│                  Layer 3: Kubernetes Cluster (K3s on EC2)    │
│         Keycloak, OAuth2 Proxy, Monitoring, Logging       │
└──────────────────┬──────────────────────────────────────────┘
                   │ interacts with
┌──────────────────▼──────────────────────────────────────────┐
│                  Layer 2: Managed AWS Services               │
│         AWS RDS (PostgreSQL), AWS S3, AWS ElastiCache (Redis)│
└──────────────────┬──────────────────────────────────────────┘
                   │ provisioned within
┌──────────────────▼──────────────────────────────────────────┐
│              Layer 1: AWS Core Infrastructure                │
│    VPC, Subnets, Security Groups, IAM Roles, EC2 Instances   │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### 1. AWS Account and Credentials

*   An active AWS account.
*   AWS CLI configured with programmatic access (Access Key ID and Secret Access Key) or an IAM role with sufficient permissions to create and manage the required resources (VPC, EC2, RDS, S3, IAM, etc.).

### 2. Terraform CLI

*   [Terraform](https://www.terraform.io/downloads) installed locally.

### 3. kubectl CLI

*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed locally.

### 4. Git Access

*   Ability to clone and push to this Git repository.

---

## Step-by-Step Deployment

The entire infrastructure deployment is orchestrated by the `deploy-full-stack.sh` script. This script first provisions the AWS infrastructure using Terraform, then sets up the Kubernetes cluster, and finally deploys all applications via ArgoCD.

For detailed steps on running the full deployment, refer to the [Automated Deployment Guide](AUTOMATED_DEPLOYMENT_GUIDE.md).

### Phase 1: AWS Infrastructure Provisioning (Terraform)

Terraform is responsible for setting up the foundational AWS resources:

*   **VPC (Virtual Private Cloud):** Configures the network environment, including public and private subnets.
*   **K3s Cluster on EC2:** Deploys EC2 instances (Graviton-based for cost optimization) and installs K3s (lightweight Kubernetes) on them. This forms the Kubernetes control plane and worker nodes.
*   **AWS RDS (PostgreSQL):** Provisions a managed PostgreSQL database instance for Fineract.
*   **AWS ElastiCache (Redis):** Provisions a managed Redis instance for caching.
*   **AWS S3 Buckets:** Creates S3 buckets for document storage and backups.
*   **AWS IAM Roles:** Configures IAM roles and instance profiles for EC2 instances and Kubernetes Service Accounts (IRSA) to interact securely with other AWS services.
*   **AWS SES (Simple Email Service):** (Optional) Configures SES for email sending capabilities.

### Phase 2: Kubernetes Cluster Setup and Application Deployment (ArgoCD)

Once the AWS infrastructure is ready, the `deploy-full-stack.sh` script proceeds to:

*   Configure `kubectl` to connect to the new K3s cluster.
*   Bootstrap core Kubernetes components like ArgoCD, Sealed Secrets Controller, and NGINX Ingress Controller.
*   Deploy all Fineract applications and supporting services (Keycloak, OAuth2 Proxy, Monitoring, Logging, etc.) using ArgoCD's GitOps workflow.

---

## Verification Checklist

After running the `deploy-full-stack.sh` script, you can verify the infrastructure components:

### AWS Infrastructure

*   **VPC:** Check the AWS VPC console for the created VPC, subnets, and route tables.
*   **EC2 Instances:** Verify that the K3s server and agent EC2 instances are running in the AWS EC2 console.
*   **RDS Instance:** Confirm the PostgreSQL database instance is available in the AWS RDS console.
*   **ElastiCache:** Confirm the Redis cluster is available in the AWS ElastiCache console.
*   **S3 Buckets:** Verify the S3 buckets exist in the AWS S3 console.
*   **IAM Roles:** Check the IAM console for the created roles and policies.

### Kubernetes Cluster

*   **Nodes:**
    ```bash
    kubectl get nodes
    ```
    Expected: K3s server and agent nodes should be in `Ready` status.
*   **Core Components:**
    ```bash
    kubectl get pods -n argocd
    kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
    kubectl get pods -n ingress-nginx
    ```
    Expected: ArgoCD, Sealed Secrets Controller, and NGINX Ingress Controller pods should be `Running`.
*   **Applications:**
    ```bash
    kubectl get applications -n argocd
    kubectl get pods -n fineract-dev # or your environment namespace
    ```
    Expected: All ArgoCD applications should be `Synced` and `Healthy`, and application pods should be `Running`.

---

## Troubleshooting

Refer to the [Automated Deployment Guide](AUTOMATED_DEPLOYMENT_GUIDE.md) for general troubleshooting steps related to the `deploy-full-stack.sh` script.

For specific AWS infrastructure issues, consult Terraform logs and the AWS console.

---

## Related Documentation

*   `AUTOMATED_DEPLOYMENT_GUIDE.md` - Detailed steps for running the full deployment script.
*   `SECRETS_MANAGEMENT.md` - How secrets are handled in this GitOps setup.
*   `AWS_IAM_SETUP_GUIDE.md` - Details on AWS IAM configurations.
*   `terraform/aws/README.md` - Specifics about the Terraform AWS module.

---

**Created**: 2025-11-02
**Status**: Production Ready
**Deployment Method**: GitOps with Terraform & ArgoCD
**Bootstrap Time**: ~30-60 minutes per environment (fully automated)