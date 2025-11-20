#!/bin/bash
#
# Deployment Health Check - Simplified Wrapper
#
# This script is a backward-compatible wrapper around verify-deployment-health.sh
# It provides a simple interface for quick health checks.
#
# Usage:
#   ./scripts/deployment-health-check.sh [environment]
#
# For more comprehensive health checks with detailed phases, use:
#   ./scripts/verify-deployment-health.sh [environment] [--quick|--full]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${1:-dev}"

# Colors for output
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Running quick deployment health check for ${ENV}...${NC}"
echo ""

# Call the comprehensive health check script in quick mode
exec "$SCRIPT_DIR/verify-deployment-health.sh" "$ENV" --quick
