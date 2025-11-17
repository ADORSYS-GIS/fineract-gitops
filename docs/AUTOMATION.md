# Fineract GitOps - Automated Deployment Guide

**Last Updated:** 2025-10-29

This document describes the automated deployment system for Fineract GitOps.

---

## Overview

The Fineract GitOps project includes comprehensive automation that reduces deployment from **30 manual steps (3-4 hours)** to a **single command (20 minutes)**.

### What Gets Automated

- AWS Infrastructure provisioning (Terraform)
- K3s Kubernetes cluster setup
- Kubeconfig retrieval and configuration
- ArgoCD installation and bootstrap
- Application deployment via GitOps
- Monitoring stack (Prometheus, Grafana, AlertManager)
- Logging stack (Loki, Promtail)
- Health checks and validation
- Smoke tests

---

## Quick Start

### One-Command Deployment

```bash
# Deploy complete Fineract environment
make deploy ENV=dev
```

That's it! The automation will:
1. Provision AWS infrastructure
2. Deploy K3s cluster
3. Install ArgoCD
4. Deploy all applications
5. Configure monitoring and logging
6. Run health checks

### Expected Duration

- **Infrastructure deployment**: 5-7 minutes
- **K3s initialization**: 3-5 minutes
- **ArgoCD bootstrap**: 2-3 minutes
- **Application sync**: 5-10 minutes
- **Total**: ~20 minutes

---

## Prerequisites

### Required Tools

- AWS CLI (configured with credentials)
- Terraform >= 1.5
- kubectl >= 1.28
- SSH client
- make

### Verify Installation

```bash
make validate-prereqs
```

### AWS Credentials

Ensure AWS CLI is configured:

```bash
aws configure
# OR
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-2"
```

---

## Usage

### Makefile Commands

```bash
# Show help
make help

# Deploy specific environment
make deploy ENV=dev
make deploy ENV=uat
make deploy ENV=prod  # Requires confirmation

# Environment-specific shortcuts
make deploy-dev
make deploy-uat
make deploy-prod  # Requires typing "DEPLOY_PROD"

# Check deployment status
make status ENV=dev

# Run smoke tests
make test ENV=dev

# Destroy infrastructure
make destroy ENV=dev  # Requires typing "DESTROY"

# Clean up logs
make clean

# Show deployment info
make info
```

### Component Deployment

Deploy specific components individually:

```bash
# Infrastructure only
make deploy-infrastructure ENV=dev

# ArgoCD only
make deploy-argocd ENV=dev

# Applications only
make deploy-apps ENV=dev
```

---

## Architecture

### Deployment Flow

```
make deploy
    |
    |---> deploy-infrastructure.sh
    |       |-- Generate SSH key
    |       |-- Terraform init
    |       |-- Terraform apply
    |       |-- Wait for K3s (3 min)
    |       |-- Create K8s secrets
    |
    |---> setup-kubeconfig.sh
    |       |-- Retrieve K3s server IP
    |       |-- Download kubeconfig
    |       |-- Configure kubectl
    |
    |---> bootstrap-argocd.sh
    |       |-- Install ArgoCD
    |       |-- Install Sealed Secrets
    |       |-- Install Ingress NGINX
    |
    |---> wait-for-argocd.sh
    |       |-- Wait for deployments
    |
    |---> deploy-app-of-apps.sh
    |       |-- Apply app-of-apps manifest
    |
    |---> wait-for-sync.sh
    |       |-- Wait for ArgoCD sync
    |
    |---> deployment-health-check.sh
            |-- Check nodes
            |-- Check pods
            |-- Check applications
```

### Scripts

| Script | Purpose |
|--------|---------|
| `deploy-full-stack.sh` | Master orchestration script |
| `deploy-infrastructure.sh` | Terraform AWS deployment |
| `setup-kubeconfig.sh` | Retrieve K3s kubeconfig |
| `bootstrap-argocd.sh` | Install ArgoCD + platform tools |
| `wait-for-argocd.sh` | Wait for ArgoCD ready |
| `deploy-app-of-apps.sh` | Deploy ArgoCD applications |
| `wait-for-sync.sh` | Wait for app sync |
| `deployment-health-check.sh` | Comprehensive health checks |

---

## Troubleshooting

### Deployment Fails at Infrastructure Step

**Symptoms**: Terraform errors

**Solutions**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check Terraform state
cd terraform/aws
terraform show

# Clean and retry
terraform destroy -var-file=environments/dev-k3s.tfvars
make deploy ENV=dev
```

### Kubeconfig Not Working

**Symptoms**: `kubectl` cannot connect

**Solutions**:
```bash
# Manually retrieve kubeconfig
cd terraform/aws
SERVER_IP=$(terraform output -json k3s_server_public_ips | grep -o '[0-9.]*' | head -1)
ssh -i ~/.ssh/fineract-k3s ubuntu@$SERVER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed "s/127.0.0.1/$SERVER_IP/g" > ~/.kube/config-fineract-dev

# Test
export KUBECONFIG=~/.kube/config-fineract-dev
kubectl get nodes
```

### ArgoCD Not Syncing

**Symptoms**: Applications stuck in "OutOfSync"

**Solutions**:
```bash
# Check ArgoCD status
kubectl get applications -n argocd

# Manually sync
kubectl patch application fineract-dev-app-of-apps -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### Pods Not Starting

**Symptoms**: Pods in `Pending` or `CrashLoopBackOff`

**Solutions**:
```bash
# Check pod status
kubectl get pods -A

# Describe specific pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
```

---

## Logs

### Log Locations

All automation scripts log to:
```
logs/deploy-full-stack-<env>-<timestamp>.log
```

### View Logs

```bash
# Latest deployment log
ls -lt logs/ | head -1

# Tail deployment log
tail -f logs/deploy-full-stack-dev-*.log

# Search for errors
grep -i error logs/deploy-full-stack-dev-*.log
```

---

## Post-Deployment

### Access ArgoCD UI

```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Open browser
open https://localhost:8080
# Username: admin
# Password: (from above command)
```

### Access Grafana

```bash
# Port-forward
kubectl port-forward -n monitoring svc/grafana 3000:80

# Open browser
open http://localhost:3000
```

### Access Fineract API

```bash
# Port-forward
kubectl port-forward -n fineract-dev svc/fineract 8443:8443

# Test API
curl -k https://localhost:8443/fineract-provider/actuator/health
```

---

## Environment Variables

### Supported Environments

- `dev` - Development environment
- `uat` - User Acceptance Testing
- `prod` - Production (requires manual approval)

### Environment-Specific Configuration

Each environment has:
- `terraform/aws/environments/<env>-k3s.tfvars` - Infrastructure config
- `argocd/applications/<env>/` - Application manifests

---

## Cost Optimization

### Stop Resources

```bash
# Stop EC2 instances (saves ~50%)
aws ec2 stop-instances --instance-ids $(terraform output -json k3s_server_public_ips | jq -r 'keys[0]')

# Stop RDS
aws rds stop-db-instance --db-instance-identifier fineract-dev-db
```

### Destroy Environment

```bash
# Complete teardown
make destroy ENV=dev
```

---

## Advanced Usage

### Custom Repository URL

Edit ArgoCD application manifests:
```yaml
spec:
  source:
    repoURL: https://github.com/ADORSYS-GIS/fineract-gitops.git
```

### Multiple Kubeconfigs

```bash
# Use environment-specific kubeconfig
export KUBECONFIG=~/.kube/config-fineract-dev
# OR
export KUBECONFIG=~/.kube/config-fineract-uat
```

### Debug Mode

```bash
# Run scripts with debug output
set -x
./scripts/deploy-full-stack.sh dev
```

---

## Comparison: Manual vs Automated

| Aspect | Manual | Automated |
|--------|--------|-----------|
| **Time** | 3-4 hours | 20 minutes |
| **Steps** | ~30 steps | 1 command |
| **Error-prone** | High | Low |
| **Reproducible** | No | Yes |
| **Documentation** | Separate doc | Self-documenting code |
| **Monitoring** | Manual setup | Auto-deployed |
| **Logging** | Manual setup | Auto-deployed |
| **Rollback** | Complex | Single command |

---

## Security Considerations

### SSH Keys

- Generated automatically if not exists
- Stored in `~/.ssh/fineract-k3s`
- Uploaded to AWS Key Pairs

### Secrets Management

- Sealed Secrets for GitOps-friendly secrets
- Kubernetes secrets created by Terraform
- Database credentials in AWS Secrets Manager (recommended)

### Network Security

- Private subnets for databases
- Security groups restrict access
- No public database endpoints

---

## Next Steps

After successful deployment:

1. **Configure DNS** - Point domains to Load Balancer
2. **Setup CI/CD** - Automate deployments on git push
3. **Enable backups** - Configure automated backups
4. **Set up alerts** - Configure AlertManager rules
5. **Load test data** - Run data loading jobs

---

## References

- [Terraform AWS Deployment](../terraform/aws/DEPLOYMENT.md)
- [Database Strategy](DATABASE_STRATEGY.md)
- [Keycloak Configuration](../operations/keycloak-config/README.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

## Support

For issues:
1. Check logs in `logs/` directory
2. Review this troubleshooting guide
3. Check component-specific README files
4. Open GitHub issue with log files

---

**Happy Deploying!**
