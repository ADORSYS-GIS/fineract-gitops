# Script Utilities Library Guide

Complete guide to using the shared utilities library (`scripts/lib/common.sh`) for consistent, maintainable bash scripts.

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Available Functions](#available-functions)
- [Color Definitions](#color-definitions)
- [Logging Functions](#logging-functions)
- [Error Handling](#error-handling)
- [Kubernetes Helpers](#kubernetes-helpers)
- [File Operations](#file-operations)
- [User Interaction](#user-interaction)
- [Validation Functions](#validation-functions)
- [Secrets Management](#secrets-management)
- [AWS Helpers](#aws-helpers)
- [Git Helpers](#git-helpers)
- [Best Practices](#best-practices)
- [Examples](#examples)

---

## Overview

The `scripts/lib/common.sh` library provides **400+ lines of reusable functions** for bash scripts in the fineract-gitops repository.

### Benefits

- ✅ **Consistent error handling** across all scripts
- ✅ **Standardized logging** with colors and icons
- ✅ **Reduced duplication** - write once, use everywhere
- ✅ **Easier maintenance** - fix bugs in one place
- ✅ **Better user experience** - consistent output formatting

### Library Version

Current version: **v1.0.0**

---

## Quick Start

### Basic Usage

```bash
#!/bin/bash
#
# Example script using common utilities
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common library
source "$SCRIPT_DIR/lib/common.sh"

# Now use the functions
print_header "My Script"

log_info "Starting operation..."
check_kubectl_connection

if ask_yes_no "Continue with deployment?"; then
    log_success "User confirmed - proceeding"
else
    error_exit "User cancelled operation"
fi
```

### Minimal Example

```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

log_info "Hello, World!"
log_success "Operation complete"
```

---

## Available Functions

### Color Definitions

Pre-defined color variables for consistent formatting:

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'  # No Color
```

**Usage**:
```bash
echo -e "${GREEN}Success!${NC}"
echo -e "${RED}Error occurred${NC}"
```

---

## Logging Functions

### `log_success`

Display success message with green checkmark.

```bash
log_success "Deployment completed"
# Output: ✓ Deployment completed (in green)
```

### `log_info`

Display informational message with blue info icon.

```bash
log_info "Connecting to cluster..."
# Output: ℹ Connecting to cluster... (in blue)
```

### `log_warn`

Display warning message with yellow warning icon.

```bash
log_warn "Using deprecated configuration"
# Output: ⚠ Using deprecated configuration (in yellow)
```

### `log_error`

Display error message with red X.

```bash
log_error "Connection failed"
# Output: ✗ Connection failed (in red)
```

### `log` / `log_info_ts` / `log_warn_ts` / `log_error_ts`

Log messages with timestamps.

```bash
log "Starting deployment"
# Output: [2025-11-20 10:30:45] Starting deployment

log_error_ts "Failed to connect"
# Output: [2025-11-20 10:30:50] ERROR: Failed to connect (in red)
```

### `print_header`

Print section header with box decoration.

```bash
print_header "Phase 1: Prerequisites"
# Output:
# ════════════════════════════════════════════════════════════
#   Phase 1: Prerequisites
# ════════════════════════════════════════════════════════════

print_header "Deployment" 40
# Use custom width (default: 60)
```

### `print_subheader`

Print sub-section header.

```bash
print_subheader "Checking Tools"
# Output:
# ─── Checking Tools ───
```

---

## Error Handling

### `error_exit`

Exit script with error message.

```bash
error_exit "Configuration file not found"
# Prints error and exits with code 1

error_exit "Custom error" 2
# Prints error and exits with code 2
```

### `require_command`

Check if command exists, exit if not found.

```bash
require_command "kubectl"
# Exits if kubectl not found

require_command "aws" "Install with: brew install awscli"
# Custom installation message
```

### `require_env_var`

Check if environment variable is set, exit if not.

```bash
require_env_var "KUBECONFIG"
# Exits if KUBECONFIG not set

require_env_var "AWS_REGION" "Set with: export AWS_REGION=us-east-1"
# Custom help message
```

---

## Kubernetes Helpers

### `check_kubectl_connection`

Verify kubectl can connect to cluster.

```bash
check_kubectl_connection
# Exits if cannot connect
# Prints success message if connected
```

### `check_namespace_exists`

Verify namespace exists in cluster.

```bash
check_namespace_exists "fineract-dev"
# Exits if namespace doesn't exist
```

### `wait_for_pod`

Wait for pod to be ready.

```bash
wait_for_pod "argocd" "app.kubernetes.io/name=argocd-server"
# Wait up to 5 minutes (default)

wait_for_pod "fineract-dev" "app=fineract" 600
# Wait up to 10 minutes
```

### `get_pod_status`

Get pod status phase.

```bash
status=$(get_pod_status "argocd" "app=argocd-server")
echo "Pod status: $status"
# Output: Pod status: Running
```

---

## File Operations

### `check_file_exists`

Verify file exists, exit if not.

```bash
check_file_exists "/path/to/config.yaml"
# Exits if file doesn't exist

check_file_exists "$CONFIG_FILE" "Config file missing. Run setup first."
# Custom error message
```

### `ensure_directory`

Create directory if it doesn't exist.

```bash
ensure_directory "/tmp/backups"
# Creates directory if needed
# Prints info message when creating
```

### `backup_file`

Backup file with timestamp.

```bash
backup_file "/etc/config.yaml"
# Creates: /etc/config.yaml.backup.20251120-103045
# Prints info message with backup location
```

---

## User Interaction

### `ask_yes_no`

Ask yes/no question, return 0 for yes, 1 for no.

```bash
if ask_yes_no "Continue with deployment?"; then
    echo "User said yes"
else
    echo "User said no"
fi

# Default to yes
if ask_yes_no "Enable autoscaling?" "y"; then
    echo "Autoscaling enabled"
fi
```

### `confirm_or_exit`

Ask for confirmation, exit if user declines.

```bash
confirm_or_exit "This will delete all resources. Continue?"
# Exits if user says no
# Continues if user says yes
```

---

## Validation Functions

### `validate_environment`

Validate environment name.

```bash
validate_environment "dev"      # OK
validate_environment "staging"  # Exits with error
# Only accepts: dev, uat, production
```

### `is_ci_environment`

Check if running in CI environment.

```bash
if is_ci_environment; then
    echo "Running in CI"
    # Skip interactive prompts
else
    echo "Running locally"
fi
```

---

## Secrets Management

### `check_kubeseal`

Verify kubeseal is installed.

```bash
check_kubeseal
# Exits if kubeseal not found
# Prints success message if available
```

### `check_sealed_secrets_controller`

Verify Sealed Secrets controller is running.

```bash
check_sealed_secrets_controller
# Default: checks kube-system namespace

check_sealed_secrets_controller "sealed-secrets"
# Check custom namespace
```

### `generate_password`

Generate random password.

```bash
password=$(generate_password)
# Generates 32-character password

password=$(generate_password 16)
# Generates 16-character password
```

---

## AWS Helpers

### `check_aws_cli`

Verify AWS CLI is installed and configured.

```bash
check_aws_cli
# Exits if AWS CLI not configured or credentials expired
# Prints success message if OK
```

---

## Git Helpers

### `is_git_clean`

Check if git working directory is clean.

```bash
if is_git_clean; then
    echo "No uncommitted changes"
else
    echo "Uncommitted changes exist"
fi
```

### `get_git_branch`

Get current git branch name.

```bash
branch=$(get_git_branch)
echo "Current branch: $branch"
```

### `check_git_repo`

Verify running in git repository.

```bash
check_git_repo
# Exits if not in git repo
```

---

## Best Practices

### DO ✅

1. **Always source the library** at the start of your script
2. **Use log functions** for all output (not echo)
3. **Use error_exit** for fatal errors (not exit directly)
4. **Check prerequisites** with require_* functions
5. **Ask for confirmation** before destructive operations
6. **Use consistent colors** from the library

### DON'T ❌

1. **Don't bypass error handling** - use the provided functions
2. **Don't use plain echo** - use log functions instead
3. **Don't ignore return codes** from helper functions
4. **Don't hardcode colors** - use the library variables
5. **Don't duplicate code** - check if library has what you need

---

## Examples

### Example 1: Deployment Script

```bash
#!/bin/bash
#
# Deploy application to Kubernetes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Validate inputs
ENV="${1:-dev}"
validate_environment "$ENV"

print_header "Fineract Deployment - ${ENV}"

# Check prerequisites
log_info "Checking prerequisites..."
require_command "kubectl"
require_command "kustomize"
require_env_var "KUBECONFIG"
check_kubectl_connection

# Confirm with user
confirm_or_exit "Deploy to ${ENV} environment?"

# Deploy
print_subheader "Deploying application"
log_info "Building kustomize configuration..."
if kustomize build "environments/${ENV}" | kubectl apply -f -; then
    log_success "Deployment successful"
else
    error_exit "Deployment failed"
fi

# Wait for pods
print_subheader "Waiting for pods"
if wait_for_pod "fineract-${ENV}" "app=fineract" 300; then
    log_success "Application is ready"
else
    log_warn "Pods not ready within timeout"
fi

print_header "Deployment Complete"
log_success "Application deployed to ${ENV}"
```

### Example 2: Validation Script

```bash
#!/bin/bash
#
# Validate cluster prerequisites
#

source "$(dirname "$0")/lib/common.sh"

print_header "Prerequisites Validation"

# Check commands
log_info "Checking required commands..."
require_command "kubectl" "Install with: brew install kubectl"
require_command "terraform" "Install with: brew install terraform"
require_command "aws" "Install with: brew install awscli"
log_success "All required commands found"

# Check environment variables
log_info "Checking environment variables..."
require_env_var "KUBECONFIG" "Set with: export KUBECONFIG=~/.kube/config"
require_env_var "AWS_REGION" "Set with: export AWS_REGION=us-east-1"
log_success "All required environment variables set"

# Check connections
log_info "Checking connections..."
check_kubectl_connection
check_aws_cli
log_success "All connections verified"

print_header "Validation Complete"
log_success "All prerequisites met!"
```

### Example 3: Secrets Management Script

```bash
#!/bin/bash
#
# Create sealed secrets
#

source "$(dirname "$0")/lib/common.sh"

ENV="${1:-dev}"
validate_environment "$ENV"

print_header "Sealed Secrets Creation - ${ENV}"

# Check prerequisites
check_kubeseal
check_sealed_secrets_controller

# Generate secrets
print_subheader "Generating Secrets"

log_info "Generating Redis password..."
redis_password=$(generate_password 32)
log_success "Redis password generated"

log_info "Generating admin password..."
admin_password=$(generate_password 32)
log_success "Admin password generated"

# Create sealed secrets
print_subheader "Creating Sealed Secrets"

if ask_yes_no "Create secrets in cluster?"; then
    # Create and seal secrets here
    log_success "Sealed secrets created"
else
    log_warn "Skipped secret creation"
fi

print_header "Complete"
log_success "All secrets processed"
```

### Example 4: Backup Script

```bash
#!/bin/bash
#
# Backup configuration files
#

source "$(dirname "$0")/lib/common.sh"

BACKUP_DIR="/tmp/backups/$(date +%Y%m%d)"

print_header "Configuration Backup"

# Ensure backup directory exists
ensure_directory "$BACKUP_DIR"

# Backup files
log_info "Backing up configuration files..."

backup_file "terraform/aws/terraform.tfvars"
backup_file "kubernetes/sealed-secrets/controller-key.yaml"
backup_file "environments/dev/kustomization.yaml"

log_success "Backup complete: $BACKUP_DIR"
```

---

## Migration Guide

### Converting Existing Scripts

**Before** (without library):
```bash
#!/bin/bash
set -e

echo "Starting deployment..."

if [ ! -f "config.yaml" ]; then
    echo "ERROR: Config file not found"
    exit 1
fi

kubectl apply -f config.yaml
echo "Deployment complete"
```

**After** (with library):
```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

print_header "Deployment"
log_info "Starting deployment..."

check_file_exists "config.yaml"

kubectl apply -f config.yaml
log_success "Deployment complete"
```

### Benefits of Migration

- ✅ Consistent error handling
- ✅ Better visual output
- ✅ Reusable validation logic
- ✅ Easier to maintain

---

## Extending the Library

### Adding New Functions

1. **Add function** to `scripts/lib/common.sh`
2. **Document** in this file
3. **Export function** for subshells if needed:
   ```bash
   export -f my_new_function
   ```
4. **Update version** in library
5. **Test thoroughly**

### Contributing

When adding new utility functions:
- Follow existing naming conventions
- Add comprehensive comments
- Include usage examples
- Update this documentation
- Test with various scenarios

---

## Troubleshooting

### Issue: "common.sh: No such file or directory"

**Solution**: Check script directory detection
```bash
# Use this pattern
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
```

### Issue: Functions not available in subshell

**Solution**: Export functions or re-source in subshell
```bash
export -f log_success
export -f log_error

# Or in subshell
(
    source "$SCRIPT_DIR/lib/common.sh"
    log_success "In subshell"
)
```

### Issue: Colors not displaying

**Solution**: Ensure terminal supports colors
```bash
# Check if terminal supports colors
if [ -t 1 ]; then
    # Colors supported
fi
```

---

## Related Documentation

- [Deployment Guide](../DEPLOYMENT.md) - Main deployment documentation
- [Script Examples](../scripts/) - Example scripts using the library
- [Bash Best Practices](https://google.github.io/styleguide/shellguide.html) - Google shell style guide

---

**Library Location**: `scripts/lib/common.sh`
**Library Version**: v1.0.0
**Last Updated**: 2025-11-20
**Created**: 2025-11-20 (Phase 4 of maintenance cleanup)
