#!/bin/bash
# Deploy ArgoCD App-of-Apps

set -e

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

echo "Deploying app-of-apps for $ENV environment..."

# Apply app-of-apps
kubectl apply -f "$REPO_ROOT/argocd/bootstrap/$ENV/app-of-apps.yaml"

# Explicitly apply all ArgoCD applications
# This ensures all apps are created even if app-of-apps sync is delayed
echo "Ensuring all ArgoCD applications are created..."
kubectl apply -k "$REPO_ROOT/argocd/applications/$ENV/"

echo "App-of-apps deployed successfully!"
echo "All applications created and will be synced by ArgoCD"
