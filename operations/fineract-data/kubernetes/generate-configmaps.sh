#!/bin/bash
# Generate ConfigMaps for Fineract Data Loader
# This script creates ConfigMaps from the scripts and data directories

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "Generating ConfigMaps for Fineract Data Loader"
echo "=============================================="

# Generate scripts ConfigMap
echo "Creating fineract-loader-scripts ConfigMap..."

kubectl create configmap fineract-loader-scripts \
  --from-file="$BASE_DIR/scripts/loaders/" \
  --from-file="$BASE_DIR/scripts/validate_yaml_data.py" \
  --dry-run=client -o yaml \
  -n fineract-dev > configmap-scripts-generated.yaml

echo "✓ Generated configmap-scripts-generated.yaml"

# Generate data ConfigMap (for small datasets)
echo ""
echo "Creating fineract-data-dev ConfigMap..."

# Create a temporary directory structure matching the expected paths
TEMP_DIR=$(mktemp -d)
cp -r "$BASE_DIR/data/dev/"* "$TEMP_DIR/"

kubectl create configmap fineract-data-dev \
  --from-file="$TEMP_DIR/" \
  --dry-run=client -o yaml \
  -n fineract-dev > configmap-data-generated.yaml

rm -rf "$TEMP_DIR"

echo "✓ Generated configmap-data-generated.yaml"

# Check sizes
SCRIPTS_SIZE=$(stat -f%z configmap-scripts-generated.yaml 2>/dev/null || stat -c%s configmap-scripts-generated.yaml)
DATA_SIZE=$(stat -f%z configmap-data-generated.yaml 2>/dev/null || stat -c%s configmap-data-generated.yaml)

echo ""
echo "ConfigMap sizes:"
echo "  Scripts: $(( SCRIPTS_SIZE / 1024 ))KB"
echo "  Data: $(( DATA_SIZE / 1024 ))KB"

if [ $DATA_SIZE -gt 1048576 ]; then
    echo ""
    echo "⚠️  WARNING: Data ConfigMap exceeds 1MB limit!"
    echo "    Consider using PersistentVolume for data instead"
fi

echo ""
echo "To apply the ConfigMaps:"
echo "  kubectl apply -f configmap-scripts-generated.yaml"
echo "  kubectl apply -f configmap-data-generated.yaml"
echo ""
echo "Or add them to kustomization.yaml resources:"
echo "  resources:"
echo "    - configmap-scripts-generated.yaml"
echo "    - configmap-data-generated.yaml"