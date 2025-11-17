#!/bin/bash

set -e

# This script automates the promotion of a new release to the production environment.
# It updates the fineract-image-version.yaml file in the production environment
# with a specified release version, creates a new branch, commits the change,
# pushes the branch, and creates a pull request to merge into the main branch.

# Usage: ./promote-to-prod.sh <release_version>

if [ -z "$1" ]; then
  echo "Usage: $0 <release_version>"
  echo "Example: $0 1.12.1"
  exit 1
fi

RELEASE_VERSION=$1
PROD_IMAGE_VERSION_FILE="environments/production/fineract-image-version.yaml"

echo "Promoting release $RELEASE_VERSION to production..."

# Ensure we are on the main branch and up to date
git checkout main
git pull origin main

# Create a new branch for the update
BRANCH_NAME="release/promote-to-prod-${RELEASE_VERSION}"
git checkout -b "$BRANCH_NAME"

# Update the fineract-image-version.yaml file
if ! command -v yq &> /dev/null
then
    echo "yq could not be found, please install it (e.g., brew install yq)"
    exit 1
fi

yq eval '.images[0].newTag = "'"$RELEASE_VERSION"'"' -i "$PROD_IMAGE_VERSION_FILE"

echo "Updated $PROD_IMAGE_VERSION_FILE with newTag: $RELEASE_VERSION"

# Commit the changes
git add "$PROD_IMAGE_VERSION_FILE"
git commit -m "feat(prod): Promote Fineract to release $RELEASE_VERSION"

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
  --title "feat(prod): Promote Fineract to release $RELEASE_VERSION" \
  --body "This PR promotes Fineract to release $RELEASE_VERSION in the production environment. Please review and merge."

echo "Pull request created for production promotion of release $RELEASE_VERSION."
