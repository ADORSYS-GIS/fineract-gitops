#!/bin/bash
# Script to update /etc/hosts with Fineract platform hostnames
# Run with: sudo bash scripts/update-etc-hosts.sh [environment]
# Example: sudo bash scripts/update-etc-hosts.sh dev

set -e

# Get environment (default: dev)
ENV="${1:-dev}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform/aws"

# Fetch IP address dynamically from Terraform output
echo "Fetching K3s server IP from Terraform output for environment: ${ENV}..."
cd "$TERRAFORM_DIR"
IP_ADDRESS=$(terraform output -json k3s_server_public_ips 2>/dev/null | grep -o '[0-9.]*' | head -1)

if [ -z "$IP_ADDRESS" ]; then
    echo "Error: Could not retrieve IP address from Terraform output"
    echo "Make sure Terraform has been applied for environment: ${ENV}"
    exit 1
fi

echo "Found IP address: $IP_ADDRESS"
cd - > /dev/null

HOSTS_FILE="/etc/hosts"
HOSTNAMES=("apps.fineract.example.com" "auth.fineract.example.com")

echo "Updating /etc/hosts with Fineract platform hostnames -> $IP_ADDRESS"
echo ""

for HOSTNAME in "${HOSTNAMES[@]}"; do
    echo "Processing: $HOSTNAME"

    # Check if entry already exists
    if grep -q "$HOSTNAME" "$HOSTS_FILE"; then
        echo "  Entry for $HOSTNAME already exists"
        grep "$HOSTNAME" "$HOSTS_FILE" | sed 's/^/  Current: /'

        read -p "  Update it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Remove old entry
            sed -i.backup "/$HOSTNAME/d" "$HOSTS_FILE"
            echo "  Old entry removed"
        else
            echo "  Skipping $HOSTNAME"
            continue
        fi
    fi

    # Add new entry
    echo "$IP_ADDRESS    $HOSTNAME" >> "$HOSTS_FILE"
    echo "  Successfully added: $IP_ADDRESS    $HOSTNAME"
    echo ""
done

# Verify all entries
echo "Current /etc/hosts entries for Fineract platform:"
for HOSTNAME in "${HOSTNAMES[@]}"; do
    if grep -q "$HOSTNAME" "$HOSTS_FILE"; then
        grep "$HOSTNAME" "$HOSTS_FILE" | sed 's/^/  /'
    fi
done

echo ""
echo "Access URLs:"
echo "  Web App:  https://apps.fineract.example.com"
  echo "  Keycloak: https://auth.fineract.example.com"echo ""
echo "Note: Browser will show security warnings for self-signed certificates"
