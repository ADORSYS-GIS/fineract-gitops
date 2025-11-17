# Fineract GitOps - AWS Deployment Guide

This guide walks you through deploying the Fineract platform on AWS using Terraform and K3s.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5
- kubectl
- SSH client
- jq (optional, for easier JSON parsing)

## Deployment Architecture

- **Compute**: K3s on EC2 (t3a.small instances)
- **Database**: Amazon RDS PostgreSQL 15.14 (db.t4g.micro)
- **Cache**: Amazon ElastiCache Redis 7.0 (cache.t4g.micro)
- **Storage**: Amazon S3 (documents and backups)
- **Networking**: VPC with public/private subnets
- **Cost**: ~$55-60/month (optimized for development)

## Step-by-Step Deployment

### 1. Generate SSH Key (One-Time Setup)

```bash
# Generate SSH key pair for K3s instances
ssh-keygen -t rsa -b 2048 -f ~/.ssh/fineract-k3s -N '' -C "fineract-k3s"

# Upload public key to AWS
aws ec2 import-key-pair \
  --key-name fineract-k3s \
  --public-key-material fileb://~/.ssh/fineract-k3s.pub \
  --region us-east-2
```

**Note**: The key name `fineract-k3s` must match the value in `environments/dev-k3s.tfvars`.

### 2. Initialize Terraform

```bash
cd /Users/guymoyo/dev/fineract-gitops/terraform/aws

terraform init
```

### 3. Review Configuration

Edit `environments/dev-k3s.tfvars` if you need to customize:
- Region
- Instance sizes
- Database settings
- Cost optimization options

### 4. Deploy Infrastructure

```bash
# Review what will be created
terraform plan -var-file=environments/dev-k3s.tfvars

# Deploy (takes ~5-7 minutes)
terraform apply -var-file=environments/dev-k3s.tfvars
```

**Expected Resources**:
- VPC with 2 AZs (public/private subnets)
- K3s cluster (1 server + 1 agent node)
- RDS PostgreSQL instance
- ElastiCache Redis cluster
- S3 buckets (documents, backups)
- IAM roles and policies
- Security groups
- Kubernetes namespace and secrets

### 5. Wait for K3s Initialization

After Terraform completes, wait 3-5 minutes for K3s to fully initialize on the EC2 instances.

```bash
# Get the server IP from Terraform output
SERVER_IP=$(terraform output -raw k3s_server_public_ips | jq -r '.[0]')

# Alternative if jq not installed
SERVER_IP=$(terraform output -json k3s_server_public_ips | grep -o '[0-9.]*')

echo "K3s Server IP: $SERVER_IP"
```

### 6. Retrieve Kubeconfig

```bash
# Download kubeconfig from K3s server via SSH
ssh -i ~/.ssh/fineract-k3s -o StrictHostKeyChecking=no ubuntu@$SERVER_IP \
  "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed "s/127.0.0.1/$SERVER_IP/g" > ~/.kube/config

# Set permissions
chmod 600 ~/.kube/config
```

**Alternative**: If you want to keep multiple kubeconfig files:

```bash
# Save to separate file
ssh -i ~/.ssh/fineract-k3s -o StrictHostKeyChecking=no ubuntu@$SERVER_IP \
  "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed "s/127.0.0.1/$SERVER_IP/g" > ~/.kube/config-fineract-dev

# Use it
export KUBECONFIG=~/.kube/config-fineract-dev
```

### 7. Verify Deployment

```bash
# Check K3s nodes
kubectl get nodes

# Expected output:
# NAME                  STATUS   ROLES                  AGE   VERSION
# fineract-dev-server   Ready    control-plane,master   Xm    v1.28.5+k3s1

# Check namespace
kubectl get namespace fineract-dev

# Check secrets
kubectl get secrets -n fineract-dev

# Expected secrets:
# - rds-connection
# - elasticache-connection
# - s3-connection

# Check service account
kubectl get serviceaccount -n fineract-dev
```

### 8. View Connection Details

```bash
# Display all connection information
terraform output connection_details

# Individual outputs
terraform output rds_instance_endpoint
terraform output elasticache_primary_endpoint
terraform output documents_bucket_name
terraform output backups_bucket_name
```

## Next Steps

### Deploy Fineract Applications

```bash
cd /Users/guymoyo/dev/fineract-gitops

# Deploy using Kustomize
kubectl apply -k environments/dev-aws
```

### Enable AWS SES (Optional - Email Notifications)

See [SES_SETUP.md](SES_SETUP.md) for email configuration.

## Troubleshooting

### SSH Connection Issues

```bash
# Test SSH access
ssh -i ~/.ssh/fineract-k3s ubuntu@$SERVER_IP "echo 'SSH works!'"

# Check K3s service status
ssh -i ~/.ssh/fineract-k3s ubuntu@$SERVER_IP "sudo systemctl status k3s"

# View K3s logs
ssh -i ~/.ssh/fineract-k3s ubuntu@$SERVER_IP "sudo journalctl -u k3s -f"
```

### Kubeconfig Issues

```bash
# Verify kubeconfig
kubectl config view

# Test cluster connectivity
kubectl cluster-info

# Check API server
curl -k https://$SERVER_IP:6443
```

### Kubernetes Secret Issues

```bash
# Re-apply secrets (if needed)
terraform apply -var-file=environments/dev-k3s.tfvars -target=module.kubernetes_secrets
```

### Check EC2 Instance Console Output

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -json k3s_server_public_ips | jq -r 'keys[0]')

# View console output
aws ec2 get-console-output \
  --instance-id $INSTANCE_ID \
  --region us-east-2 \
  --query 'Output' \
  --output text | tail -100
```

## Cleanup / Destroy

To remove all resources:

```bash
# Destroy everything (careful!)
terraform destroy -var-file=environments/dev-k3s.tfvars

# Remove SSH key from AWS
aws ec2 delete-key-pair --key-name fineract-k3s --region us-east-2
```

## Cost Optimization Tips

### Auto-Shutdown (Save ~50%)

Stop instances after work hours:

```bash
# Stop K3s instances
aws ec2 stop-instances --instance-ids $(terraform output -json k3s_server_public_ips | jq -r 'keys[0]')

# Stop RDS
aws rds stop-db-instance --db-instance-identifier $(terraform output -raw rds_instance_arn | cut -d: -f7)
```

**Note**: You'll need to restart them and retrieve a new kubeconfig when you resume.

### Production Optimizations

For production deployments:
- Enable Multi-AZ for RDS (`rds_multi_az = true`)
- Enable high availability for K3s (`k3s_high_availability = true`)
- Use Reserved Instances (save 30-40%)
- Enable NAT Gateway for private subnet isolation
- Increase backup retention periods

## Architecture Decisions

### Why K3s instead of EKS?

- **Cost**: ~$100/month cheaper than EKS ($55 vs $150)
- **Simplicity**: Single binary, minimal configuration
- **Full Kubernetes**: 100% compatible with standard K8s
- **Control**: Direct EC2 access for troubleshooting

### Why t3a.small?

- **Proven**: Successfully tested with Fineract workloads
- **Balanced**: 2 vCPU, 4GB RAM sufficient for dev/staging
- **Cost-effective**: ~$12/month per instance
- **AMD**: Cheaper than t3 (Intel) equivalent

### Why Disable NAT Gateway?

- **Cost savings**: $32/month
- **Dev environment**: Direct internet access acceptable
- **Security**: Still protected by security groups
- **Production**: Re-enable for isolation

## File Structure

```
terraform/aws/
├── main.tf                           # Root module configuration
├── variables.tf                      # Root variables
├── providers.tf                      # Provider configuration
├── outputs.tf                        # Root outputs
├── environments/
│   └── dev-k3s.tfvars               # Dev environment config
├── modules/
│   ├── vpc/                         # VPC networking
│   ├── k3s/                         # K3s cluster on EC2
│   ├── rds/                         # PostgreSQL database
│   ├── elasticache/                 # Redis cache
│   ├── s3/                          # S3 buckets
│   ├── iam/                         # IAM roles & policies
│   ├── ses/                         # Email service (optional)
│   ├── kubernetes-namespace/        # K8s namespace creation
│   └── kubernetes-secret/           # K8s secrets management
└── DEPLOYMENT.md                    # This file
```

## Support

For issues or questions:
1. Check Terraform state: `terraform show`
2. Review AWS console for resource status
3. Check K3s logs on server instances
4. Verify security groups allow required traffic

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Fineract Documentation](https://fineract.apache.org/)
