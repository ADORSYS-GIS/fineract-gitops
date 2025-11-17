#!/bin/bash
# Retrieve K3s kubeconfig from server

set -e

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform/aws"

echo "Retrieving kubeconfig for $ENV environment..."

cd "$TERRAFORM_DIR"

# Get server IP from Terraform output
SERVER_IP=$(terraform output -json k3s_server_public_ips 2>/dev/null | grep -o '[0-9.]*' | head -1)

if [ -z "$SERVER_IP" ]; then
    echo "ERROR: Could not get K3s server IP from Terraform"
    exit 1
fi

echo "K3s Server IP: $SERVER_IP"

# Wait for SSH to be available
echo "Waiting for SSH to be available..."
for i in {1..30}; do
    if ssh -i ~/.ssh/fineract-k3s -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$SERVER_IP "echo 'SSH OK'" 2>/dev/null; then
        echo "SSH connection established"
        break
    fi
    echo "Retry $i/30..."
    sleep 10
done

# Download kubeconfig
echo "Downloading kubeconfig..."
ssh -i ~/.ssh/fineract-k3s -o StrictHostKeyChecking=no ubuntu@$SERVER_IP \
    "sudo cat /etc/rancher/k3s/k3s.yaml" | \
    sed "s/127.0.0.1/$SERVER_IP/g" > ~/.kube/config-fineract-$ENV

chmod 600 ~/.kube/config-fineract-$ENV

# Set KUBECONFIG
export KUBECONFIG=~/.kube/config-fineract-$ENV
echo "export KUBECONFIG=~/.kube/config-fineract-$ENV" > $SCRIPT_DIR/../.kubeconfig-$ENV

echo "Kubeconfig saved to ~/.kube/config-fineract-$ENV"
echo "Run: export KUBECONFIG=~/.kube/config-fineract-$ENV"

# Test connection
kubectl get nodes

echo "Kubeconfig setup complete!"
