#!/bin/bash
# Comprehensive deployment health check

set -e

ENV="${1:-dev}"

echo "=========================================="
echo "  Deployment Health Check - $ENV"
echo "=========================================="
echo ""

# Check K8s nodes
echo "=== Kubernetes Nodes ==="
kubectl get nodes
echo ""

# Check ArgoCD applications
echo "=== ArgoCD Applications ==="
kubectl get applications -n argocd
echo ""

# Check namespaces
echo "=== Namespaces ==="
kubectl get namespaces
echo ""

# Check pods in fineract namespace
echo "=== Fineract Pods ==="
kubectl get pods -n fineract-$ENV || echo "Fineract namespace not ready yet"
echo ""

# Check monitoring pods
echo "=== Monitoring Pods ==="
kubectl get pods -n monitoring || echo "Monitoring namespace not ready yet"
echo ""

# Check logging pods
echo "=== Logging Pods ==="
kubectl get pods -n logging || echo "Logging namespace not ready yet"
echo ""

# Check ArgoCD pods
echo "=== ArgoCD Pods ==="
kubectl get pods -n argocd
echo ""

echo "=========================================="
echo "  Health Check Complete"
echo "=========================================="
