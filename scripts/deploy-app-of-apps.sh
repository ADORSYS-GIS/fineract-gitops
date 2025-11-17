#!/bin/bash
# Deploy ArgoCD App-of-Apps

set -e

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

echo "Deploying app-of-apps for $ENV environment..."

# Apply app-of-apps
kubectl apply -f "$REPO_ROOT/argocd/bootstrap/$ENV/app-of-apps.yaml"

echo "App-of-apps deployed successfully!"
echo "Applications will be automatically synced by ArgoCD"
