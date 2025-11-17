#!/bin/bash
#
# Local Frontend Development Proxy Script
#
# This script port-forwards the OAuth2 Proxy service so you can develop
# frontend applications locally while connecting to deployed backend services.
#
# It sets up a proxy to the cluster, allowing your local development server
# to make API calls to services protected by OAuth2 Proxy.
#
# Usage:
#   ./scripts/dev-proxy.sh [namespace] [local_port]
#
# Examples:
#   ./scripts/dev-proxy.sh                    # Uses defaults: fineract-dev, port 4180
#   ./scripts/dev-proxy.sh fineract-staging   # Uses staging namespace
#   ./scripts/dev-proxy.sh fineract-dev 9080  # Uses custom local port

set -e

# Configuration
NAMESPACE="${1:-fineract-dev}"
LOCAL_PORT="${2:-4180}"
SERVICE_NAME="oauth2-proxy"
SERVICE_PORT="4180"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
echo ""
echo "======================================================================"
echo "  Fineract Local Development Proxy (OAuth2)"
echo "======================================================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check if service exists
echo -e "${YELLOW}Checking if service '$SERVICE_NAME' exists in namespace '$NAMESPACE'...${NC}"
if ! kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: Service '$SERVICE_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo ""
    echo "Available services in $NAMESPACE:"
    kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "  Namespace not found or no access"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Service found${NC}"
echo ""

# Display configuration
echo "Proxy Configuration:"
echo "  Namespace:    $NAMESPACE"
echo "  Service:      $SERVICE_NAME"
echo "  Local Port:   $LOCAL_PORT"
echo "  Service Port: $SERVICE_PORT"
echo ""

# Display connection info
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Frontend Connection Details:${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Configure your frontend application to make API calls to:"
echo ""
echo -e "  ${YELLOW}API Base URL:${NC}    http://localhost:$LOCAL_PORT"
echo -e "  ${YELLOW}Fineract API:${NC}    http://localhost:$LOCAL_PORT/fineract-provider/api/v1"
echo ""
echo "Authentication is handled by OAuth2 Proxy. Your app does not need to"
echo "manage tokens directly. Simply make requests to the protected endpoints."
echo ""


# Check if port is already in use
if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}Warning: Port $LOCAL_PORT is already in use${NC}"
    echo ""
    echo "Process using port $LOCAL_PORT:"
    lsof -Pi :$LOCAL_PORT -sTCP:LISTEN
    echo ""
    read -p "Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Display environment variable examples
echo -e "${YELLOW}Example Frontend Configuration (.env.local):${NC}"
echo ""
echo "# React/Vite/Next.js"
echo "VITE_API_BASE_URL=http://localhost:$LOCAL_PORT"
echo "NEXT_PUBLIC_API_URL=http://localhost:$LOCAL_PORT"
echo ""
echo "# Angular (environment.ts)"
echo "export const environment = {"
echo "  production: false,"
echo "  apiUrl: 'http://localhost:$LOCAL_PORT'"
echo "};"
echo ""

echo -e "${YELLOW}================================${NC}"
echo ""
echo -e "${GREEN}Starting port-forward...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo -e "${YELLOW}Stopping port-forward...${NC}"
    # Kill any background port-forward processes
    pkill -P $$ 2>/dev/null || true
    echo -e "${GREEN}Port-forward stopped${NC}"
    exit 0
}

# Trap Ctrl+C
trap cleanup INT TERM

# Start port-forward with auto-reconnect
CONNECTION_LOST_COUNT=0
MAX_RECONNECT_ATTEMPTS=5

while true; do
    # Reset counter on successful connection for more than 10 seconds
    START_TIME=$(date +%s)

    # Start port-forward
    kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" "$LOCAL_PORT:$SERVICE_PORT" 2>&1 | while read -r line; do
        # Check if connection is established
        if echo "$line" | grep -q "Forwarding from"; then
            echo -e "${GREEN}✓ Connected!${NC} $line"
            CONNECTION_LOST_COUNT=0
        else
            echo "$line"
        fi
    done

    # Check if connection lasted long enough
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ $DURATION -gt 10 ]; then
        # Connection lasted more than 10 seconds, reset counter
        CONNECTION_LOST_COUNT=0
    fi

    # Connection lost
    CONNECTION_LOST_COUNT=$((CONNECTION_LOST_COUNT + 1))

    if [ $CONNECTION_LOST_COUNT -ge $MAX_RECONNECT_ATTEMPTS ]; then
        echo ""
        echo -e "${RED}Error: Connection to '$SERVICE_NAME' lost multiple times.${NC}"
        echo "This might indicate a problem with the cluster, network, or the service itself."
        echo ""
        read -p "Do you want to keep trying to reconnect? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            cleanup
        fi
        CONNECTION_LOST_COUNT=0
    fi

    echo ""
    echo -e "${YELLOW}Connection lost. Reconnecting in 3 seconds...${NC}"
    echo ""
    sleep 3
done