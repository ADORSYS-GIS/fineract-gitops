#!/bin/bash
# Script to generate data ConfigMap for Fineract data loader
# This creates a ConfigMap from all YAML files in the data directory

DATA_DIR="../data/dev"
OUTPUT_FILE="configmap-data-generated.yaml"

# Start the ConfigMap
cat > $OUTPUT_FILE <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fineract-data-dev
  namespace: fineract-dev
data:
EOF

# Process each YAML file
find $DATA_DIR -name "*.yaml" -type f | while read -r file; do
    # Get relative path from data/dev
    rel_path=${file#$DATA_DIR/}
    # Convert path to a valid ConfigMap key (replace / with -)
    key=$(echo "$rel_path" | sed 's/\//-/g')

    echo "  $key: |" >> $OUTPUT_FILE
    # Indent the file content
    sed 's/^/    /' "$file" >> $OUTPUT_FILE
done

echo "ConfigMap generated at $OUTPUT_FILE"
echo "Files included:"
find $DATA_DIR -name "*.yaml" -type f | wc -l