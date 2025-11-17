#!/bin/bash
# Step 5: Verify Deployment

set -e
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo "Verifying deployment..."
echo ""

FAILED=0

# Check Redis (must be in fineract-dev, not default)
echo "→ Checking Redis..."
REDIS_NS=$(kubectl get statefulset -A 2>/dev/null | grep fineract-redis | awk '{print $1}' || echo "not-found")
if [ "$REDIS_NS" = "fineract-dev" ]; then
    REDIS_READY=$(kubectl get statefulset fineract-redis -n fineract-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$REDIS_READY" = "1" ]; then
        echo -e "${GREEN}✓${NC} Redis running in fineract-dev ($REDIS_READY/1 ready)"
    else
        echo -e "${YELLOW}⚠${NC} Redis found but not ready ($REDIS_READY/1)"
    fi
else
    echo -e "${RED}✗${NC} Redis not in fineract-dev namespace (found in: $REDIS_NS)"
    FAILED=1
fi

# Check Keycloak
echo "→ Checking Keycloak..."
KC_READY=$(kubectl get deployment keycloak -n fineract-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$KC_READY" = "1" ]; then
    echo -e "${GREEN}✓${NC} Keycloak running ($KC_READY/1 ready)"
else
    echo -e "${YELLOW}⚠${NC} Keycloak not ready ($KC_READY/1)"
fi

# Check Fineract deployments
echo "→ Checking Fineract..."
for service in write read; do
    READY=$(kubectl get deployment fineract-$service -n fineract-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment fineract-$service -n fineract-dev -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [ "$READY" = "$DESIRED" ]; then
        echo -e "${GREEN}✓${NC} fineract-$service running ($READY/$DESIRED ready)"
    else
        echo -e "${YELLOW}⚠${NC} fineract-$service not ready ($READY/$DESIRED)"
    fi
done

# Get LoadBalancer DNS
echo ""
echo "→ Getting LoadBalancer DNS..."
LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "not-assigned")
echo -e "${BLUE}LoadBalancer DNS:${NC} $LB_DNS"

# Show /etc/hosts entries
if [ "$LB_DNS" != "not-assigned" ]; then
    LB_IP=$(dig +short $LB_DNS | head -1 || echo "")
    echo ""
    echo -e "${YELLOW}Add these to /etc/hosts for local access:${NC}"
    echo "$LB_IP   apps.dev.fineract.com"
    echo "$LB_IP   auth.dev.fineract.com"
fi

# Final summary
echo ""
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment verification complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Update /etc/hosts with LoadBalancer IP"
    echo "  2. Access Fineract at: https://apps.dev.fineract.com"
    echo "  3. Access Keycloak at: https://auth.dev.fineract.com"
    exit 0
else
    echo -e "${RED}✗ Some checks failed${NC}"
    exit 1
fi
