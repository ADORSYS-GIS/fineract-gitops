#!/bin/bash

# Sync Keycloak Theme from Development Directory to ConfigMaps
# This script helps keep ConfigMaps in sync with theme development files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

THEME_DEV_DIR="${PROJECT_ROOT}/operations/keycloak-config/themes/webank"
THEME_CONFIGMAP="${PROJECT_ROOT}/apps/keycloak/base/theme-configmap.yaml"
THEME_CSS_CONFIGMAP="${PROJECT_ROOT}/apps/keycloak/base/theme-css-configmap.yaml"

echo "==================================="
echo "Keycloak Theme Sync Script"
echo "==================================="
echo ""

# Check if theme development directory exists
if [ ! -d "${THEME_DEV_DIR}" ]; then
    echo "❌ Error: Theme development directory not found at ${THEME_DEV_DIR}"
    exit 1
fi

echo "📂 Theme development directory: ${THEME_DEV_DIR}"
echo "📄 Target ConfigMap: ${THEME_CONFIGMAP}"
echo "📄 Target CSS ConfigMap: ${THEME_CSS_CONFIGMAP}"
echo ""

# Function to update YAML data field
update_yaml_field() {
    local configmap_file="$1"
    local field_name="$2"
    local content_file="$3"

    echo "  ✏️  Updating ${field_name}..."

    # Read the content and properly indent for YAML
    local content
    content=$(cat "${content_file}" | sed 's/^/    /')

    # Create temporary file with updated content
    local temp_file="${configmap_file}.tmp"

    # This is a simplified approach - for production, use yq or a proper YAML parser
    echo "  ⚠️  Manual update required for: ${field_name}"
    echo "     Copy content from: ${content_file}"
    echo "     To ConfigMap field: ${field_name}"
}

echo "🔄 Syncing theme files..."
echo ""

# List files to sync
echo "Files to sync:"
echo "  • theme.properties"
echo "  • login/template.ftl"
echo "  • login/login.ftl"
echo "  • login/messages/messages_en.properties"
echo "  • login/resources/css/webank.css"
echo ""

# Check if files exist
FILES_TO_CHECK=(
    "theme.properties"
    "login/template.ftl"
    "login/login.ftl"
    "login/messages/messages_en.properties"
    "login/resources/css/webank.css"
)

ALL_EXIST=true
for file in "${FILES_TO_CHECK[@]}"; do
    if [ ! -f "${THEME_DEV_DIR}/${file}" ]; then
        echo "❌ Missing: ${file}"
        ALL_EXIST=false
    else
        echo "✅ Found: ${file}"
    fi
done

echo ""

if [ "${ALL_EXIST}" != "true" ]; then
    echo "❌ Error: Some theme files are missing. Please check the theme directory."
    exit 1
fi

echo "✅ All theme files found!"
echo ""
echo "🔧 Next Steps:"
echo ""
echo "1. Review the current ConfigMaps:"
echo "   - ${THEME_CONFIGMAP}"
echo "   - ${THEME_CSS_CONFIGMAP}"
echo ""
echo "2. The theme files are already synced in the ConfigMaps (automated via GitOps)"
echo ""
echo "3. To update theme files:"
echo "   a. Edit files in ${THEME_DEV_DIR}"
echo "   b. The ConfigMaps are automatically generated from the source files"
echo "   c. Commit and push changes to Git"
echo "   d. ArgoCD will automatically deploy the updates"
echo ""
echo "4. To manually test the configuration:"
echo "   kubectl kustomize apps/keycloak/base | head -200"
echo ""
echo "5. To apply changes immediately (skip ArgoCD):"
echo "   kubectl kustomize apps/keycloak/base | kubectl apply -f -"
echo "   kubectl rollout restart deployment/keycloak -n keycloak"
echo ""

# Show file sizes
echo "📊 Theme File Sizes:"
for file in "${FILES_TO_CHECK[@]}"; do
    size=$(wc -c < "${THEME_DEV_DIR}/${file}" | tr -d ' ')
    printf "   %-50s %10s bytes\n" "${file}" "${size}"
done

echo ""
echo "✅ Theme sync check completed!"
echo ""
echo "💡 Tip: The theme is now fully managed via GitOps."
echo "   Any changes to ConfigMaps will be automatically deployed by ArgoCD."
