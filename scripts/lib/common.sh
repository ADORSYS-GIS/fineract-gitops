#!/bin/bash
#
# Common Utilities Library for Fineract GitOps Scripts
#
# This library provides shared functions used across deployment, secrets,
# and validation scripts to eliminate duplication and ensure consistency.
#
# Usage:
#   source "$(dirname "$0")/lib/common.sh"
#   or
#   source "$SCRIPT_DIR/lib/common.sh"
#

# =============================================================================
# Color Definitions
# =============================================================================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

# Log success message with green checkmark
log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

# Log info message with blue info icon
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

# Log warning message with yellow warning icon
log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

# Log error message with red X
log_error() {
    echo -e "${RED}✗${NC} $*"
}

# Log with timestamp
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

# Log error with timestamp
log_error_ts() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

# Log warning with timestamp
log_warn_ts() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"
}

# Log info with timestamp
log_info_ts() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

# Print section header
print_header() {
    local title="$1"
    local width=${2:-60}
    echo ""
    echo -e "${BLUE}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
}

# Print sub-header
print_subheader() {
    local title="$1"
    echo ""
    echo -e "${CYAN}─── $title ───${NC}"
    echo ""
}

# =============================================================================
# Error Handling Functions
# =============================================================================

# Exit with error message
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Check if command exists
require_command() {
    local cmd="$1"
    local install_msg="${2:-Install with your package manager}"

    if ! command -v "$cmd" &>/dev/null; then
        error_exit "Required command '$cmd' not found. $install_msg"
    fi
}

# Check if environment variable is set
require_env_var() {
    local var_name="$1"
    local help_msg="${2:-Please set this environment variable}"

    if [ -z "${!var_name}" ]; then
        error_exit "Required environment variable '$var_name' is not set. $help_msg"
    fi
}

# =============================================================================
# Kubernetes Helper Functions
# =============================================================================

# Check kubectl connectivity
check_kubectl_connection() {
    if ! kubectl cluster-info > /dev/null 2>&1; then
        error_exit "Cannot connect to Kubernetes cluster. Check your KUBECONFIG."
    fi
    log_success "Connected to Kubernetes cluster"
}

# Check if namespace exists
check_namespace_exists() {
    local namespace="$1"
    if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
        error_exit "Namespace '$namespace' does not exist"
    fi
}

# Wait for pod to be ready
wait_for_pod() {
    local namespace="$1"
    local label_selector="$2"
    local timeout="${3:-300}" # 5 minutes default

    log_info "Waiting for pod with label '$label_selector' in namespace '$namespace'..."

    if kubectl wait --for=condition=ready pod \
        -l "$label_selector" \
        -n "$namespace" \
        --timeout="${timeout}s" > /dev/null 2>&1; then
        log_success "Pod is ready"
        return 0
    else
        log_error "Pod did not become ready within ${timeout}s"
        return 1
    fi
}

# Get pod status
get_pod_status() {
    local namespace="$1"
    local label_selector="$2"

    kubectl get pods -n "$namespace" -l "$label_selector" \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown"
}

# =============================================================================
# File Operations
# =============================================================================

# Check if file exists
check_file_exists() {
    local file="$1"
    local error_msg="${2:-File '$file' does not exist}"

    if [ ! -f "$file" ]; then
        error_exit "$error_msg"
    fi
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error_exit "Failed to create directory: $dir"
        log_info "Created directory: $dir"
    fi
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up $file to $backup"
    fi
}

# =============================================================================
# User Interaction Functions
# =============================================================================

# Ask yes/no question (default: no)
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        read -p "$question [Y/n]: " response
        response=${response:-y}
    else
        read -p "$question [y/N]: " response
        response=${response:-n}
    fi

    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prompt for confirmation (exits if user declines)
confirm_or_exit() {
    local message="$1"
    if ! ask_yes_no "$message"; then
        echo ""
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate environment name
validate_environment() {
    local env="$1"
    if [[ ! "$env" =~ ^(dev|uat|production)$ ]]; then
        error_exit "Invalid environment '$env'. Must be: dev, uat, or production"
    fi
}

# Check if running in CI environment
is_ci_environment() {
    [ "${CI:-false}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GITLAB_CI:-}" ]
}

# =============================================================================
# Secrets Management Helpers
# =============================================================================

# Check if kubeseal is available
check_kubeseal() {
    require_command "kubeseal" "Install with: brew install kubeseal"
    log_success "kubeseal is available"
}

# Check if Sealed Secrets controller is running
check_sealed_secrets_controller() {
    local namespace="${1:-kube-system}"

    if ! kubectl get deployment sealed-secrets-controller -n "$namespace" > /dev/null 2>&1; then
        error_exit "Sealed Secrets controller not found in namespace '$namespace'"
    fi

    if ! kubectl wait --for=condition=available deployment/sealed-secrets-controller \
        -n "$namespace" --timeout=30s > /dev/null 2>&1; then
        error_exit "Sealed Secrets controller is not ready"
    fi

    log_success "Sealed Secrets controller is running"
}

# Generate random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# =============================================================================
# AWS Helpers
# =============================================================================

# Check AWS CLI is configured
check_aws_cli() {
    require_command "aws" "Install with: brew install awscli"

    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error_exit "AWS CLI not configured or credentials expired"
    fi

    log_success "AWS CLI is configured"
}

# =============================================================================
# Git Helpers
# =============================================================================

# Check if git repo is clean
is_git_clean() {
    [ -z "$(git status --porcelain)" ]
}

# Get current git branch
get_git_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

# Check if running in git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error_exit "Not in a git repository"
    fi
}

# =============================================================================
# Initialization
# =============================================================================

# This function should be called at the start of scripts using this library
init_common() {
    # Set strict error handling if not already set
    set -euo pipefail

    # Export functions for subshells
    export -f log_success log_info log_warn log_error
    export -f log log_error_ts log_warn_ts log_info_ts
    export -f print_header print_subheader error_exit
}

# =============================================================================
# Version Info
# =============================================================================

COMMON_LIB_VERSION="1.0.0"
export COMMON_LIB_VERSION

# Auto-initialize when sourced (can be disabled by setting SKIP_COMMON_INIT=1)
if [ "${SKIP_COMMON_INIT:-0}" != "1" ]; then
    init_common
fi
