#!/bin/bash

# K3s Server Installation Script
# Installs K3s control plane on EC2 instance
# Note: Don't use "set -e" so we can capture errors

echo "=== Starting K3s Server Installation ==="

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl wget

# Configure hostname
hostnamectl set-hostname ${cluster_name}-server

# Disable swap (required for Kubernetes)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Install K3s server
%{ if is_first_server }
# First server node - bootstrap the cluster
echo "Installing K3s server (first node)..."
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${k3s_version}" \
  K3S_TOKEN="${k3s_token}" \
  sh -s - server \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --tls-san=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) \
    --tls-san=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
    --node-external-ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Check if K3s installation succeeded
if [ $? -ne 0 ]; then
  echo "ERROR: K3s installation failed!"
  echo "K3s service status:"
  systemctl status k3s.service --no-pager || true
  echo "K3s service logs:"
  journalctl -u k3s.service -n 100 --no-pager || true
  exit 1
fi
%{ else }
# Additional server nodes - join existing cluster
echo "Installing K3s server (joining cluster)..."
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${k3s_version}" \
  K3S_TOKEN="${k3s_token}" \
  sh -s - server \
    --server="${server_url}" \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --tls-san=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) \
    --tls-san=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
    --node-external-ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Check if K3s installation succeeded
if [ $? -ne 0 ]; then
  echo "ERROR: K3s installation failed!"
  echo "K3s service status:"
  systemctl status k3s.service --no-pager || true
  echo "K3s service logs:"
  journalctl -u k3s.service -n 100 --no-pager || true
  exit 1
fi
%{ endif }

# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
for i in {1..60}; do
  if kubectl get nodes &>/dev/null; then
    echo "K3s is ready!"
    break
  fi
  echo "Attempt $i/60: Waiting for K3s API..."
  sleep 5
done

# Check if K3s is actually ready
if ! kubectl get nodes &>/dev/null; then
  echo "ERROR: K3s API never became ready!"
  echo "K3s service status:"
  systemctl status k3s.service --no-pager
  echo "K3s service logs:"
  journalctl -u k3s.service -n 100 --no-pager
  exit 1
fi

# Install AWS CLI (for S3, ECR access)
snap install aws-cli --classic

echo "=== K3s Server Installation Complete ==="
echo "Cluster: ${cluster_name}"
echo "Node: $(hostname)"
echo "Status: $(kubectl get nodes)"
