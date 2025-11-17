# Automated Deployment Guide

This guide shows you how to deploy the entire Fineract platform automatically using the unified deployment script.

## 🎯 Overview

The `deploy-full-stack.sh` script orchestrates the entire deployment process, from provisioning cloud infrastructure with Terraform to deploying the applications with ArgoCD. This provides a "one-click" method to stand up a complete environment.

---

## 📋 Prerequisites

Before starting, ensure you have the following tools installed and configured:

*   **AWS CLI:** Configured with credentials for the target AWS account.
*   **Terraform CLI:** To provision the underlying infrastructure.
*   **kubectl:** For interacting with the Kubernetes cluster.
*   **SSH:** An SSH client and the private key required by the Terraform configuration.

---

## 🚀 The Automated Deployment Command

The entire deployment is initiated by running a single script.

```bash
# Navigate to the root of the repository
cd /path/to/fineract-gitops

# Run the full-stack deployment script for the desired environment (e.g., dev)
./scripts/deploy-full-stack.sh dev
```

---

## 📝 What the Script Does

The script executes the following steps in sequence, logging all output to a file in the `logs/` directory.

1.  **Validating Prerequisites:** Checks if all required CLI tools (`aws`, `terraform`, `kubectl`, `ssh`) are installed and if AWS credentials are valid.
2.  **Deploying AWS Infrastructure:** Runs `terraform apply` to create the VPC, K3s cluster on EC2, RDS database, ElastiCache, and S3 buckets.
3.  **Retrieving Kubeconfig:** Fetches the kubeconfig from the newly created K3s cluster so `kubectl` can connect to it.
4.  **Bootstrapping ArgoCD:** Installs ArgoCD, the Sealed Secrets Controller, and the Ingress NGINX Controller into the cluster.
5.  **Waiting for ArgoCD:** Pauses until the ArgoCD server is ready to accept configurations.
6.  **Deploying Fineract Applications:** Applies the main ArgoCD ApplicationSet, which triggers the deployment of all other platform and application components (Keycloak, Redis, Fineract, etc.).
7.  **Waiting for ArgoCD Sync:** Monitors the ArgoCD applications and waits for them to report a synced and healthy status.
8.  **Running Health Checks:** Performs a final health check on the deployment.

---

## 📊 Post-Deployment Summary

Once the script is complete, it will print a summary with important information, including:

*   The total deployment time.
*   The path to the detailed log file.
*   Instructions for accessing the ArgoCD UI.
*   `kubectl` commands for port-forwarding to key services like Grafana and the Fineract API.

### Example Summary Output:

```
========================================
  DEPLOYMENT COMPLETE!
========================================

INFO: Environment: dev
INFO: Deployment Time: 25 minutes 10 seconds
INFO: Log file: /Users/guymoyo/dev/fineract-gitops/logs/deploy-full-stack-dev-20251102-143000.log

Next steps:
1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443
2. Get ArgoCD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
...
```

---

## 🐛 Troubleshooting

If the script fails at any step, it will exit immediately. You can find the detailed error messages in two places:

1.  **Console Output:** The error will be printed directly to your terminal.
2.  **Log File:** A complete log of the entire process is saved in the `logs/` directory. Check the latest log file for a full traceback of what happened.

Common failure points include:
*   Invalid AWS credentials.
*   Terraform errors due to resource conflicts or permissions.
*   Network issues preventing connection to the new cluster.