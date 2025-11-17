#!/bin/bash
# Bootstrap ArgoCD and platform components

set -e

ENV="${1:-dev}"

echo "Bootstrapping ArgoCD for $ENV environment..."

# Create ArgoCD namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd

# Note: Sealed Secrets Controller will be deployed via ArgoCD app-of-apps

# Install Ingress NGINX Controller
echo "Installing Ingress NGINX Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

echo "ArgoCD and platform components bootstrapped successfully!"
echo ""
echo "Get ArgoCD admin password:"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
