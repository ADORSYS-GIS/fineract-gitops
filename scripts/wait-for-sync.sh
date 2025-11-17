#!/bin/bash
# Wait for ArgoCD applications to sync

set -e

ENV="${1:-dev}"

echo "Waiting for ArgoCD applications to sync..."

# Wait for app-of-apps
echo "Waiting for app-of-apps..."
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
    --timeout=600s application/fineract-$ENV-app-of-apps -n argocd || echo "App-of-apps sync timeout (may still be in progress)"

# Wait a bit for child applications to be created
sleep 30

# List all applications
echo "ArgoCD Applications:"
kubectl get applications -n argocd

echo "Sync wait complete!"
