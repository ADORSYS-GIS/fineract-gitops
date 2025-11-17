#!/bin/bash
set -e

# K3s Agent Installation Script
# Installs K3s worker node on EC2 instance

echo "=== Starting K3s Agent Installation ==="

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl wget

# Configure hostname
hostnamectl set-hostname ${cluster_name}-agent

# Disable swap (required for Kubernetes)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Wait for server to be ready (retry for up to 5 minutes)
echo "Waiting for K3s server to be ready..."
for i in {1..60}; do
  if curl -k https://${server_url}/ping &>/dev/null; then
    echo "Server is ready!"
    break
  fi
  echo "Attempt $i: Server not ready yet, waiting..."
  sleep 5
done

# Install K3s agent
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${k3s_version}" \
  K3S_TOKEN="${k3s_token}" \
  K3S_URL="${server_url}" \
  sh -s - agent \
    --node-label="node-role.kubernetes.io/worker=true" \
    --kubelet-arg="cloud-provider=external"

# Install AWS CLI (for S3, ECR access)
snap install aws-cli --classic

echo "=== K3s Agent Installation Complete ==="
echo "Cluster: ${cluster_name}"
echo "Node: $(hostname)"
echo "Server: ${server_url}"
