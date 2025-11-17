#!/bin/bash

# Build User Sync Service Docker Image
# Helper script for manual Docker image builds

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_DIR="${PROJECT_ROOT}/apps/user-sync-service"

# Default values
IMAGE_NAME="fineract-keycloak-sync"
IMAGE_TAG="latest"
REGISTRY=""
PUSH=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "User Sync Service - Docker Build Script"
echo "======================================"
echo ""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -t, --tag TAG        Image tag (default: latest)"
            echo "  -r, --registry REG   Registry prefix (e.g., gcr.io/project)"
            echo "  -p, --push           Push image to registry after build"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Build with :latest tag"
            echo "  $0 -t v1.0.0                          # Build with custom tag"
            echo "  $0 -r gcr.io/webank -t v1.0.0 -p     # Build, tag for GCR, and push"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Construct full image name
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo "📦 Build Configuration:"
echo "   Service Directory: ${SERVICE_DIR}"
echo "   Image Name: ${IMAGE_NAME}"
echo "   Image Tag: ${IMAGE_TAG}"
if [ -n "$REGISTRY" ]; then
    echo "   Registry: ${REGISTRY}"
fi
echo "   Full Image: ${FULL_IMAGE_NAME}"
echo "   Push after build: ${PUSH}"
echo ""

# Check if Dockerfile exists
if [ ! -f "${SERVICE_DIR}/Dockerfile" ]; then
    echo -e "${RED}❌ Error: Dockerfile not found at ${SERVICE_DIR}/Dockerfile${NC}"
    exit 1
fi

# Check if requirements.txt exists
if [ ! -f "${SERVICE_DIR}/requirements.txt" ]; then
    echo -e "${YELLOW}⚠️  Warning: requirements.txt not found${NC}"
fi

# Check if app directory exists
if [ ! -d "${SERVICE_DIR}/app" ]; then
    echo -e "${RED}❌ Error: app directory not found at ${SERVICE_DIR}/app${NC}"
    exit 1
fi

echo "🔨 Building Docker image..."
echo ""

# Build the image
cd "${SERVICE_DIR}"
docker build -t "${FULL_IMAGE_NAME}" .

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Docker image built successfully!${NC}"
    echo ""

    # Show image details
    echo "📊 Image Details:"
    docker images "${FULL_IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    echo ""

    # Tag with :latest if using a version tag
    if [ "$IMAGE_TAG" != "latest" ]; then
        LOCAL_LATEST="${IMAGE_NAME}:latest"
        echo "🏷️  Tagging as ${LOCAL_LATEST}..."
        docker tag "${FULL_IMAGE_NAME}" "${LOCAL_LATEST}"
        echo -e "${GREEN}✅ Tagged as ${LOCAL_LATEST}${NC}"
        echo ""
    fi

    # Push to registry if requested
    if [ "$PUSH" = true ]; then
        if [ -z "$REGISTRY" ]; then
            echo -e "${RED}❌ Error: Cannot push without --registry option${NC}"
            exit 1
        fi

        echo "📤 Pushing image to registry..."
        docker push "${FULL_IMAGE_NAME}"

        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✅ Image pushed successfully to ${REGISTRY}${NC}"
            echo ""
        else
            echo ""
            echo -e "${RED}❌ Failed to push image${NC}"
            exit 1
        fi
    fi

    echo "🎯 Next Steps:"
    echo ""

    if [ "$PUSH" = false ] && [ -n "$REGISTRY" ]; then
        echo "1. Push the image to registry:"
        echo "   docker push ${FULL_IMAGE_NAME}"
        echo ""
    fi

    if [ -n "$REGISTRY" ]; then
        echo "2. Update kustomization overlay to use this image:"
        echo "   Edit: operations/keycloak-config/user-sync-service/overlays/dev/kustomization.yaml"
        echo "   Change image to: ${FULL_IMAGE_NAME}"
        echo ""
    fi

    echo "3. Deploy via GitOps:"
    echo "   git add operations/keycloak-config/user-sync-service/"
    echo "   git commit -m \"build: update user-sync-service image to ${IMAGE_TAG}\""
    echo "   git push origin develop"
    echo ""

    echo "4. Sync with ArgoCD (optional, auto-syncs in 3 min):"
    echo "   argocd app sync user-sync-service"
    echo ""

    echo -e "${GREEN}✅ Build complete!${NC}"
else
    echo ""
    echo -e "${RED}❌ Docker build failed${NC}"
    exit 1
fi
