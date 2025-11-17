#!/bin/bash
# Local validation script - runs the same checks as GitHub Actions

set -e

echo "======================================="
echo "Local Kubernetes Manifest Validation"
echo "======================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if required tools are installed
echo "Checking required tools..."

if ! command -v kubeconform &> /dev/null; then
    echo -e "${YELLOW}⚠ kubeconform not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install kubeconform
    else
        curl -sSLo kubeconform.tar.gz https://github.com/yannh/kubeconform/releases/download/v0.6.4/kubeconform-linux-amd64.tar.gz
        tar xf kubeconform.tar.gz
        sudo mv kubeconform /usr/local/bin/
        rm kubeconform.tar.gz
    fi
fi

if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}⚠ kustomize not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install kustomize
    else
        curl -sSLo kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz
        tar xf kustomize.tar.gz
        sudo mv kustomize /usr/local/bin/
        rm kustomize.tar.gz
    fi
fi

if ! command -v yamllint &> /dev/null; then
    echo -e "${YELLOW}⚠ yamllint not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install yamllint
    else
        pip3 install yamllint
    fi
fi

echo -e "${GREEN}✓ All tools installed${NC}"
echo ""

# Step 1: Kubeconform validation (non-strict)
echo "======================================="
echo "Step 1: Kubeconform Validation (Summary)"
echo "======================================="
kubeconform \
  -summary \
  -output json \
  -ignore-missing-schemas \
  -kubernetes-version 1.28.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  apps/ environments/ argocd/ || true

echo ""

# Step 2: Strict validation
echo "======================================="
echo "Step 2: Strict Validation"
echo "======================================="
echo "Validating apps/ and argocd/ directories..."
find apps/ argocd/ -name '*.yaml' -o -name '*.yml' | \
  grep -v '\.template$' | \
  xargs kubeconform \
    -strict \
    -ignore-missing-schemas \
    -kubernetes-version 1.28.0 \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

echo ""
echo "Validating environment manifests (namespace and kustomization only)..."
find environments/*/. -maxdepth 1 \( -name 'namespace.yaml' -o -name 'kustomization.yaml' \) | \
  xargs kubeconform \
    -strict \
    -ignore-missing-schemas \
    -kubernetes-version 1.28.0 \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

echo ""

# Step 3: Kustomize build validation
echo "======================================="
echo "Step 3: Kustomize Build Validation"
echo "======================================="

for env in dev uat production; do
    echo "Building and validating $env environment..."
    kustomize build environments/$env | kubeconform \
      -strict \
      -ignore-missing-schemas \
      -kubernetes-version 1.28.0 \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
    echo -e "${GREEN}✓ $env environment build validated${NC}"
done

echo ""

# Step 4: YAML Lint (warnings only, not failing)
echo "======================================="
echo "Step 4: YAML Lint Check"
echo "======================================="
cat > /tmp/yamllint-config.yaml <<EOF
extends: default
rules:
  line-length:
    max: 250
    level: warning
  indentation:
    spaces: 2
    indent-sequences: whatever
  comments:
    min-spaces-from-content: 1
  comments-indentation: disable
  document-start: disable
  brackets:
    max-spaces-inside: 1
  braces:
    max-spaces-inside: 1
  truthy: disable
  trailing-spaces: disable
  new-line-at-end-of-file: disable
  empty-lines:
    max: 3
EOF

echo "Running yamllint..."
yamllint -c /tmp/yamllint-config.yaml apps/ environments/ argocd/

echo ""

# Step 5: Check for placeholders
echo "======================================="
echo "Step 5: Placeholder Value Check"
echo "======================================="

if grep -r "github.com/\*" apps/ argocd/ environments/ 2>/dev/null; then
  echo -e "${RED}❌ ERROR: Found placeholder GitHub URLs (github.com/*)${NC}"
  exit 1
fi

# Check for REPLACE placeholders, excluding secret template files
if grep -r "REPLACE" apps/ argocd/ environments/ 2>/dev/null | \
   grep -v "# REPLACE" | \
   grep -v "secret.yaml" | \
   grep -v "secret-template.yaml"; then
  echo -e "${RED}❌ ERROR: Found REPLACE placeholders${NC}"
  exit 1
fi

# Check for CHANGE_ME placeholders, excluding secret template files
if grep -r "CHANGE_ME" apps/ argocd/ environments/ 2>/dev/null | \
   grep -v "# CHANGE_ME" | \
   grep -v "# TODO" | \
   grep -v "secret.yaml" | \
   grep -v "secret-template.yaml" | \
   grep -v "secret-admin.yaml"; then
  echo -e "${RED}❌ ERROR: Found CHANGE_ME placeholders${NC}"
  exit 1
fi

echo -e "${GREEN}✓ No placeholder values found (secret templates excluded)${NC}"
echo ""

# Step 6: Pod Security Standards
echo "======================================="
echo "Step 6: Pod Security Standards Check"
echo "======================================="

if ls apps/*/base/deployment*.yaml 2>/dev/null; then
  for file in apps/*/base/deployment*.yaml; do
    if ! grep -q "runAsNonRoot: true" "$file" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  WARNING: $file missing runAsNonRoot: true${NC}"
    fi
    if ! grep -q "allowPrivilegeEscalation: false" "$file" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  WARNING: $file missing allowPrivilegeEscalation: false${NC}"
    fi
  done
fi

echo -e "${GREEN}✓ Pod Security Standards check complete${NC}"
echo ""

# Summary
echo "======================================="
echo "Validation Summary"
echo "======================================="
echo -e "${GREEN}✅ Kubernetes manifest validation complete${NC}"
echo -e "${GREEN}✅ Kustomize build validation complete${NC}"
echo -e "${GREEN}✅ Placeholder value check complete${NC}"
echo -e "${GREEN}✅ Pod Security Standards check complete${NC}"
echo ""
echo -e "${GREEN}All validations passed! Safe to push.${NC}"
