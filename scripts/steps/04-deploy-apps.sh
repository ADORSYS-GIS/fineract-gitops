#!/bin/bash
# Step 4: Deploy Applications via ArgoCD

set -e
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo "Deploying applications via ArgoCD..."

# Apply ArgoCD project
echo "→ Creating ArgoCD project..."
kubectl apply -f argocd/projects/project-dev.yaml
echo -e "${GREEN}✓${NC} Project created"

# Apply app-of-apps
echo "→ Deploying app-of-apps..."
kubectl apply -f argocd/bootstrap/dev/app-of-apps.yaml
echo -e "${GREEN}✓${NC} App-of-apps deployed"

# Explicitly apply all ArgoCD applications
# This ensures all apps are created even if app-of-apps sync is delayed
echo "→ Ensuring all ArgoCD applications are created..."
kubectl apply -k argocd/applications/dev/
echo -e "${GREEN}✓${NC} All ArgoCD applications created"

# Watch ArgoCD sync
echo ""
echo -e "${BLUE}Watching ArgoCD sync progress...${NC}"
echo "This may take 5-10 minutes. Applications will deploy in order by sync-wave."
echo ""

# Wait for initial sync
sleep 10

# Monitor sync status
for i in {1..60}; do
    echo -ne "${BLUE}⏳ Checking sync status (${i}/60)...${NC}\r"
    
    SYNCED=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c "Synced" || echo "0")
    TOTAL=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$SYNCED" -gt 0 ] && [ "$SYNCED" -eq "$TOTAL" ]; then
        echo -e "\n${GREEN}✓${NC} All applications synced ($SYNCED/$TOTAL)"
        break
    fi
    
    sleep 10
done

# Show application status
echo ""
echo "Application Status:"
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || echo "Unable to fetch status"

echo ""
echo -e "${GREEN}Applications deployed! Check ArgoCD UI for details.${NC}"
echo "To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
