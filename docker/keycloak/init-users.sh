#!/bin/sh
# =============================================================================
# Keycloak User Password Initialization
# =============================================================================
# keycloak-config-cli does NOT update existing user credentials on re-import.
# This script runs after realm import to ensure passwords are always correct.
# =============================================================================

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
REALM="${REALM:-fineract}"

# Install dependencies
apk add --no-cache curl jq > /dev/null 2>&1

echo "Waiting for Keycloak to be ready..."
MAX_RETRIES=30
RETRY=0
until [ $RETRY -eq $MAX_RETRIES ]; do
  if curl -sf "${KEYCLOAK_URL}/realms/master" > /dev/null 2>&1; then
    echo "Keycloak is ready."
    break
  fi
  RETRY=$((RETRY + 1))
  echo "  attempt $RETRY/$MAX_RETRIES..."
  sleep 2
done

if [ $RETRY -eq $MAX_RETRIES ]; then
  echo "ERROR: Keycloak not ready after $MAX_RETRIES attempts"
  exit 1
fi

# Get admin token
echo "Authenticating as admin..."
ADMIN_TOKEN=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=${KEYCLOAK_ADMIN}&password=${KEYCLOAK_ADMIN_PASSWORD}" \
  | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
  echo "ERROR: Failed to get admin token"
  exit 1
fi

# Function to set user password
set_password() {
  username="$1"
  password="$2"

  if [ -z "$password" ]; then
    echo "  SKIP $username (no password configured)"
    return
  fi

  # Find user by username
  user_id=$(curl -sf "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}&exact=true" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    | jq -r '.[0].id // empty')

  if [ -z "$user_id" ]; then
    echo "  SKIP $username (user not found)"
    return
  fi

  # Reset password
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}/reset-password" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}")

  if [ "$http_code" = "204" ]; then
    echo "  OK $username"
  else
    echo "  FAIL $username (HTTP $http_code)"
  fi
}

echo "Setting user passwords in realm '$REALM'..."
set_password "admin" "${ADMIN_USER_PASSWORD}"
set_password "mifos" "${MIFOS_PASSWORD}"

echo "User password initialization complete."
