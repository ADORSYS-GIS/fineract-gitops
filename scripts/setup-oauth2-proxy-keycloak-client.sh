#!/bin/bash

################################################################################
# Setup OAuth2 Proxy Client in Keycloak
#
# This script creates and configures the OAuth2 Proxy client in Keycloak
# for the Fineract platform
#
# Usage: ./setup-oauth2-proxy-keycloak-client.sh [environment]
#   environment: dev | uat | prod (default: dev)
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
NAMESPACE="fineract-${ENVIRONMENT}"
KEYCLOAK_POD="keycloak-0"
REALM="fineract"
CLIENT_ID="oauth2-proxy"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}OAuth2 Proxy Keycloak Client Setup${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "Environment: ${GREEN}${ENVIRONMENT}${NC}"
echo -e "Namespace:   ${GREEN}${NAMESPACE}${NC}"
echo -e "Realm:       ${GREEN}${REALM}${NC}"
echo -e "Client ID:   ${GREEN}${CLIENT_ID}${NC}"
echo ""

# Check if Keycloak pod exists
echo -e "${BLUE}Checking Keycloak pod...${NC}"
if ! kubectl get pod "${KEYCLOAK_POD}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${RED}ERROR: Keycloak pod ${KEYCLOAK_POD} not found in namespace ${NAMESPACE}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Keycloak pod found${NC}"

# Generate a secure client secret
echo -e "${BLUE}Generating client secret...${NC}"
CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
echo -e "${GREEN}✓ Client secret generated${NC}"

# Generate cookie secret for OAuth2 Proxy
echo -e "${BLUE}Generating cookie secret...${NC}"
COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
echo -e "${GREEN}✓ Cookie secret generated${NC}"

# Create the OAuth2 Proxy client in Keycloak
echo -e "${BLUE}Creating OAuth2 Proxy client in Keycloak...${NC}"

kubectl exec -n "${NAMESPACE}" "${KEYCLOAK_POD}" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin

/opt/keycloak/bin/kcadm.sh create clients -r ${REALM} \
  -s clientId=${CLIENT_ID} \
  -s enabled=true \
  -s clientAuthenticatorType=client-secret \
  -s secret=${CLIENT_SECRET} \
  -s protocol=openid-connect \
  -s publicClient=false \
  -s bearerOnly=false \
  -s standardFlowEnabled=true \
  -s implicitFlowEnabled=false \
  -s directAccessGrantsEnabled=false \
  -s serviceAccountsEnabled=false \
  -s 'redirectUris=[\"https://apps.fineract.example.com/oauth2/callback\",\"http://localhost:4180/oauth2/callback\"]' \
  -s 'webOrigins=[\"https://apps.fineract.example.com\",\"http://localhost:4180\"]' \
  -s 'defaultClientScopes=[\"openid\",\"profile\",\"email\",\"roles\"]' \
  -s 'optionalClientScopes=[]' \
  -s 'attributes.\"access.token.lifespan\"=900' \
  -s 'attributes.\"oauth2.device.authorization.grant.enabled\"=false' \
  -s 'attributes.\"oidc.ciba.grant.enabled\"=false' \
  -s 'attributes.\"backchannel.logout.session.required\"=true' \
  -s 'attributes.\"backchannel.logout.revoke.offline.tokens\"=false'
" 2>&1 | grep -v "Logging into" || true

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ OAuth2 Proxy client created successfully${NC}"
else
    echo -e "${YELLOW}⚠ Client might already exist, attempting to update...${NC}"

    # Try to update the existing client
    kubectl exec -n "${NAMESPACE}" "${KEYCLOAK_POD}" -- bash -c "
    /opt/keycloak/bin/kcadm.sh config credentials \
      --server http://localhost:8080 \
      --realm master \
      --user admin \
      --password admin

    CLIENT_UUID=\$(/opt/keycloak/bin/kcadm.sh get clients -r ${REALM} --fields id,clientId | grep -B1 '\"clientId\" : \"${CLIENT_ID}\"' | grep '\"id\"' | sed 's/.*\"id\" : \"\(.*\)\".*/\1/')

    if [ -n \"\${CLIENT_UUID}\" ]; then
        /opt/keycloak/bin/kcadm.sh update clients/\${CLIENT_UUID} -r ${REALM} \
          -s secret=${CLIENT_SECRET} \
          -s enabled=true
        echo \"Client updated with new secret\"
    fi
    " 2>&1 | grep -v "Logging into" || true

    echo -e "${GREEN}✓ Client updated${NC}"
fi

# Create or update Kubernetes secret
echo -e "${BLUE}Creating/updating Kubernetes secret...${NC}"

kubectl create secret generic oauth2-proxy-secrets \
  -n "${NAMESPACE}" \
  --from-literal=client-id="${CLIENT_ID}" \
  --from-literal=client-secret="${CLIENT_SECRET}" \
  --from-literal=cookie-secret="${COOKIE_SECRET}" \
  --from-literal=redis-password="" \
  --dry-run=client -o yaml | kubectl apply -f -

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Kubernetes secret created/updated${NC}"
else
    echo -e "${RED}ERROR: Failed to create Kubernetes secret${NC}"
    exit 1
fi

# Display configuration summary
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Configuration Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "${GREEN}Client ID:${NC}     ${CLIENT_ID}"
echo -e "${GREEN}Client Secret:${NC} ${CLIENT_SECRET}"
echo -e "${GREEN}Cookie Secret:${NC} ${COOKIE_SECRET}"
echo ""
echo -e "${YELLOW}⚠  Store these secrets securely!${NC}"
echo ""
echo -e "${BLUE}Redirect URIs configured:${NC}"
echo -e "  - https://apps.fineract.example.com/oauth2/callback"
echo -e "  - http://localhost:4180/oauth2/callback (for local testing)"
echo ""

# Verify the client was created
echo -e "${BLUE}Verifying client configuration...${NC}"
kubectl exec -n "${NAMESPACE}" "${KEYCLOAK_POD}" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin

/opt/keycloak/bin/kcadm.sh get clients -r ${REALM} --fields clientId,enabled | grep -A1 '${CLIENT_ID}'
" 2>&1 | grep -v "Logging into" || true

echo ""
echo -e "${GREEN}✓ OAuth2 Proxy Keycloak client setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Deploy OAuth2 Proxy: ${GREEN}kubectl apply -k apps/oauth2-proxy/base${NC}"
echo -e "2. Verify pods are running: ${GREEN}kubectl get pods -n ${NAMESPACE} -l app=oauth2-proxy${NC}"
echo -e "3. Check OAuth2 Proxy logs: ${GREEN}kubectl logs -n ${NAMESPACE} -l app=oauth2-proxy --tail=50${NC}"
echo -e "4. Test authentication: ${GREEN}curl -I https://apps.fineract.example.com/${NC}"
echo ""
