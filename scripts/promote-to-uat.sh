#!/bin/bash

set -e

# This script automates the promotion of a tested commit to the UAT environment.
# It updates the fineract-image-version.yaml file in the UAT environment
# with a specified commit SHA, creates a new branch, commits the change,
# pushes the branch, and creates a pull request to merge into the main branch.

# Usage: ./promote-to-uat.sh <commit_sha>

if [ -z "$1" ]; then
  echo "Usage: $0 <commit_sha>"
  exit 1
fi

COMMIT_SHA=$1
UAT_IMAGE_VERSION_FILE="environments/uat/fineract-image-version.yaml"

echo "Promoting commit $COMMIT_SHA to UAT..."

# Ensure we are on the main branch and up to date
git checkout main
git pull origin main

# Create a new branch for the update
BRANCH_NAME="feature/uat-promote-${COMMIT_SHA}"
git checkout -b "$BRANCH_NAME"

# Update the fineract-image-version.yaml file
# Using yq to safely update the YAML file
if ! command -v yq &> /dev/null
then
    echo "yq could not be found, please install it (e.g., brew install yq)"
    exit 1
fi

yq eval '.images[0].newTag = "'"$COMMIT_SHA"'"' -i "$UAT_IMAGE_VERSION_FILE"

echo "Updated $UAT_IMAGE_VERSION_FILE with newTag: $COMMIT_SHA"

# Commit the changes
git add "$UAT_IMAGE_VERSION_FILE"
git commit -m "chore(uat): Promote Fineract to commit $COMMIT_SHA"

# Push the new branch
git push origin "$BRANCH_NAME"

# Create a pull request
# Assuming gh CLI is installed and authenticated
if ! command -v gh &> /dev/null
then
    echo "GitHub CLI (gh) could not be found, please install it (https://cli.github.com/)"
    exit 1
fi

gh pr create \
  --base main \
  --head "$BRANCH_NAME" \
  --title "chore(uat): Promote Fineract to commit $COMMIT_SHA" \
  --body "This PR promotes Fineract to commit $COMMIT_SHA in the UAT environment. Please review and merge."

echo "Pull request created for UAT promotion of commit $COMMIT_SHA."
