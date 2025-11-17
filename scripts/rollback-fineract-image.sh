#!/bin/bash

set -e

# This script automates the rollback of a Fineract image version in a specified environment.
# It can either revert the last commit that updated the image version or set a specific image tag.

# Usage: ./rollback-fineract-image.sh <environment> [target_image_tag]

ENVIRONMENT=$1
TARGET_IMAGE_TAG=$2

if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: $0 <environment> [target_image_tag]"
  echo "Environments: dev, uat, production"
  exit 1
fi

IMAGE_VERSION_FILE="environments/${ENVIRONMENT}/fineract-image-version.yaml"

if [ ! -f "$IMAGE_VERSION_FILE" ]; then
  echo "Error: Image version file not found for environment '${ENVIRONMENT}': ${IMAGE_VERSION_FILE}"
  exit 1
fi

echo "Initiating rollback for ${ENVIRONMENT} environment..."

# Ensure we are on the main branch and up to date
git checkout main
git pull origin main

# Create a new branch for the rollback
BRANCH_NAME="hotfix/rollback-fineract-${ENVIRONMENT}-$(date +%s)"
git checkout -b "$BRANCH_NAME"

if [ -n "$TARGET_IMAGE_TAG" ]; then
  # Option 1: Set a specific target image tag
  echo "Setting image tag to: ${TARGET_IMAGE_TAG}"
  if ! command -v yq &> /dev/null
  then
      echo "yq could not be found, please install it (e.g., brew install yq)"
      exit 1
  fi
  yq eval '.images[0].newTag = "'"$TARGET_IMAGE_TAG"'"' -i "$IMAGE_VERSION_FILE"
  COMMIT_MESSAGE="hotfix(${ENVIRONMENT}): Rollback Fineract to ${TARGET_IMAGE_TAG}"
else
  # Option 2: Revert the last commit that modified the image version file
  echo "Reverting the last commit that modified ${IMAGE_VERSION_FILE}"
  LAST_COMMIT_HASH=$(git log -1 --format=format:%H -- "$IMAGE_VERSION_FILE")
  if [ -z "$LAST_COMMIT_HASH" ]; then
    echo "Error: No previous commits found for ${IMAGE_VERSION_FILE}"
    exit 1
  fi
  git revert --no-edit "$LAST_COMMIT_HASH"
  COMMIT_MESSAGE="revert(${ENVIRONMENT}): Revert last Fineract image update for ${ENVIRONMENT}"
fi

# Commit the changes
git add "$IMAGE_VERSION_FILE"
git commit -m "$COMMIT_MESSAGE"

# Push the new branch
git push origin "$BRANCH_NAME"

# Create a pull request
if ! command -v gh &> /dev/null
then
    echo "GitHub CLI (gh) could not be found, please install it (https://cli.github.com/)"
    exit 1
fi

gh pr create \
  --base main \
  --head "$BRANCH_NAME" \
  --title "$COMMIT_MESSAGE" \
  --body "This PR performs a rollback for the ${ENVIRONMENT} environment. Please review and merge urgently."

echo "Pull request created for rollback in ${ENVIRONMENT} environment."

