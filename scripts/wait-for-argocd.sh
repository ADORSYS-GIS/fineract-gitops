#!/bin/bash
# Wait for ArgoCD to be fully ready

set -e

echo "Waiting for ArgoCD to be ready..."

# Wait for deployments
for deployment in argocd-server argocd-repo-server argocd-application-controller argocd-redis; do
    echo "Waiting for $deployment..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/$deployment -n argocd || true
done

echo "ArgoCD is ready!"
