#!/bin/bash
# Verify IRSA Credentials
# Runtime health checks for IAM Roles for Service Accounts (IRSA)
# Verifies that pods can assume IAM roles and access AWS services
#
# Usage: ./scripts/verify-irsa-credentials.sh [environment]
# Example: ./scripts/verify-irsa-credentials.sh dev
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. AWS CLI configured
# 3. Fineract applications deployed
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
ENV="${1:-dev}"
NAMESPACE="fineract-${ENV}"
AWS_REGION="${AWS_REGION:-us-east-2}"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

error_exit() {
    log_error "$1"
    exit 1
}

# Header
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}IRSA Credentials Verification${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}AWS Region: ${AWS_REGION}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    error_exit "kubectl not found"
fi

if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI not found"
fi

log "✓ Prerequisites met"
echo

# Verify cluster access
log_info "Verifying cluster access..."
if ! kubectl cluster-info &> /dev/null; then
    error_exit "Cannot access Kubernetes cluster"
fi

CURRENT_CONTEXT=$(kubectl config current-context)
log "✓ Connected to cluster: $CURRENT_CONTEXT"
echo

# Validation counters
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# Verify Service Account Configuration
# ============================================================================

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}1. Service Account Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if service account exists
SA_NAME="fineract-aws"
if kubectl get serviceaccount -n "$NAMESPACE" "$SA_NAME" &> /dev/null; then
    echo -e "${GREEN}✓ Service account exists: ${SA_NAME}${NC}"
    ((PASSED++))

    # Get IRSA role annotation
    IRSA_ROLE=$(kubectl get serviceaccount -n "$NAMESPACE" "$SA_NAME" \
        -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

    if [ -n "$IRSA_ROLE" ]; then
        echo -e "${GREEN}✓ IRSA role annotation found${NC}"
        echo -e "  ${BLUE}Role ARN:${NC} $IRSA_ROLE"
        ((PASSED++))

        # Verify IAM role exists
        ROLE_NAME=$(echo "$IRSA_ROLE" | awk -F'/' '{print $NF}')
        if aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" &> /dev/null; then
            echo -e "${GREEN}✓ IAM role exists in AWS: ${ROLE_NAME}${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ IAM role not found in AWS: ${ROLE_NAME}${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${RED}✗ IRSA role annotation not found${NC}"
        echo -e "${YELLOW}  Add annotation: eks.amazonaws.com/role-arn${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}✗ Service account not found: ${SA_NAME}${NC}"
    echo -e "${YELLOW}  Create with: kubectl apply -f secrets/${ENV}/service-account.yaml${NC}"
    ((FAILED++))
fi

echo

# ============================================================================
# Verify OIDC Provider
# ============================================================================

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}2. OIDC Provider Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Get EKS cluster name
EKS_CLUSTER=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' | sed 's/.*\///')

if [ -n "$EKS_CLUSTER" ]; then
    echo -e "${BLUE}EKS Cluster:${NC} $EKS_CLUSTER"

    # Get OIDC issuer
    OIDC_ISSUER=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
        --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || echo "")

    if [ -n "$OIDC_ISSUER" ]; then
        echo -e "${GREEN}✓ OIDC issuer found${NC}"
        echo -e "  ${BLUE}Issuer:${NC} $OIDC_ISSUER"
        ((PASSED++))

        # Extract OIDC provider ID
        OIDC_ID=$(echo "$OIDC_ISSUER" | awk -F'/id/' '{print $NF}')

        # Verify OIDC provider exists in IAM
        if aws iam list-open-id-connect-providers --region "$AWS_REGION" | grep -q "$OIDC_ID"; then
            echo -e "${GREEN}✓ OIDC provider registered in IAM${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ OIDC provider not found in IAM${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${RED}✗ Could not get OIDC issuer${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ Could not determine EKS cluster name${NC}"
    ((WARNINGS++))
fi

echo

# ============================================================================
# Test AWS Credentials in Pod
# ============================================================================

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}3. Pod AWS Credentials Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Find a running Fineract pod
FINERACT_POD=$(kubectl get pods -n "$NAMESPACE" -l app=fineract-write \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$FINERACT_POD" ]; then
    FINERACT_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=fineract \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -n "$FINERACT_POD" ]; then
    echo -e "${BLUE}Testing pod:${NC} $FINERACT_POD"
    echo

    # Check if pod is using the service account
    POD_SA=$(kubectl get pod -n "$NAMESPACE" "$FINERACT_POD" \
        -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null || echo "")

    if [ "$POD_SA" == "$SA_NAME" ]; then
        echo -e "${GREEN}✓ Pod is using service account: ${SA_NAME}${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠ Pod is using different service account: ${POD_SA}${NC}"
        echo -e "${YELLOW}  Expected: ${SA_NAME}${NC}"
        ((WARNINGS++))
    fi

    # Check for AWS environment variables
    log_info "Checking AWS environment variables in pod..."

    AWS_ROLE_ARN=$(kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
        sh -c 'echo $AWS_ROLE_ARN' 2>/dev/null || echo "")

    AWS_WEB_IDENTITY_TOKEN_FILE=$(kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
        sh -c 'echo $AWS_WEB_IDENTITY_TOKEN_FILE' 2>/dev/null || echo "")

    if [ -n "$AWS_ROLE_ARN" ]; then
        echo -e "${GREEN}✓ AWS_ROLE_ARN is set${NC}"
        echo -e "  ${BLUE}Value:${NC} $AWS_ROLE_ARN"
        ((PASSED++))
    else
        echo -e "${RED}✗ AWS_ROLE_ARN not set${NC}"
        ((FAILED++))
    fi

    if [ -n "$AWS_WEB_IDENTITY_TOKEN_FILE" ]; then
        echo -e "${GREEN}✓ AWS_WEB_IDENTITY_TOKEN_FILE is set${NC}"
        echo -e "  ${BLUE}Value:${NC} $AWS_WEB_IDENTITY_TOKEN_FILE"
        ((PASSED++))

        # Check if token file exists
        if kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
            test -f "$AWS_WEB_IDENTITY_TOKEN_FILE" 2>/dev/null; then
            echo -e "${GREEN}✓ Web identity token file exists${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ Web identity token file not found${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${RED}✗ AWS_WEB_IDENTITY_TOKEN_FILE not set${NC}"
        ((FAILED++))
    fi

    echo

    # Test AWS STS assume role
    log_info "Testing AWS STS GetCallerIdentity..."

    if kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
        sh -c 'command -v aws' &> /dev/null; then

        CALLER_IDENTITY=$(kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
            aws sts get-caller-identity --region "$AWS_REGION" 2>/dev/null || echo "")

        if [ -n "$CALLER_IDENTITY" ]; then
            echo -e "${GREEN}✓ Successfully called AWS STS${NC}"
            echo -e "${BLUE}Identity:${NC}"
            echo "$CALLER_IDENTITY" | sed 's/^/  /'
            ((PASSED++))
        else
            echo -e "${RED}✗ Failed to call AWS STS${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${YELLOW}⚠ AWS CLI not available in pod (expected for non-debug containers)${NC}"
        echo -e "${YELLOW}  Will test S3 access directly via application${NC}"
        ((WARNINGS++))
    fi

    echo

    # Test S3 access (if bucket name available)
    log_info "Testing S3 access..."

    S3_BUCKET=$(kubectl get secret -n "$NAMESPACE" s3-connection \
        -o jsonpath='{.data.bucket-name}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [ -n "$S3_BUCKET" ]; then
        echo -e "${BLUE}S3 Bucket:${NC} $S3_BUCKET"

        if kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
            sh -c 'command -v aws' &> /dev/null; then

            if kubectl exec -n "$NAMESPACE" "$FINERACT_POD" -- \
                aws s3 ls "s3://${S3_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
                echo -e "${GREEN}✓ Successfully accessed S3 bucket${NC}"
                ((PASSED++))
            else
                echo -e "${RED}✗ Failed to access S3 bucket${NC}"
                echo -e "${YELLOW}  Check IAM role permissions for S3${NC}"
                ((FAILED++))
            fi
        else
            echo -e "${YELLOW}⚠ Cannot test S3 access without AWS CLI in pod${NC}"
            echo -e "${YELLOW}  Monitor application logs for S3 errors${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠ S3 bucket name not found in secrets${NC}"
        ((WARNINGS++))
    fi

else
    echo -e "${YELLOW}⚠ No Fineract pods found${NC}"
    echo -e "${YELLOW}  Deploy applications first:${NC}"
    echo -e "${YELLOW}    kubectl apply -k argocd/applications/${ENV}/${NC}"
    ((WARNINGS++))
fi

echo

# ============================================================================
# Verify IAM Role Permissions
# ============================================================================

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}4. IAM Role Permissions${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

if [ -n "$IRSA_ROLE" ]; then
    ROLE_NAME=$(echo "$IRSA_ROLE" | awk -F'/' '{print $NF}')

    # Get attached policies
    log_info "Checking attached policies..."

    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --region "$AWS_REGION" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")

    if [ -n "$POLICIES" ]; then
        echo -e "${GREEN}✓ Policies attached to role:${NC}"
        for policy in $POLICIES; do
            POLICY_NAME=$(echo "$policy" | awk -F'/' '{print $NF}')
            echo -e "  ${BLUE}●${NC} $POLICY_NAME"
        done
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠ No managed policies attached${NC}"
        ((WARNINGS++))
    fi

    echo

    # Check inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --region "$AWS_REGION" \
        --query 'PolicyNames' --output text 2>/dev/null || echo "")

    if [ -n "$INLINE_POLICIES" ]; then
        echo -e "${GREEN}✓ Inline policies:${NC}"
        for policy in $INLINE_POLICIES; do
            echo -e "  ${BLUE}●${NC} $policy"
        done
        ((PASSED++))
    else
        echo -e "${BLUE}No inline policies${NC}"
    fi

    echo

    # Check trust relationship
    log_info "Checking trust relationship..."

    TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" \
        --query 'Role.AssumeRolePolicyDocument' 2>/dev/null || echo "")

    if echo "$TRUST_POLICY" | grep -q "sts:AssumeRoleWithWebIdentity"; then
        echo -e "${GREEN}✓ Trust policy allows AssumeRoleWithWebIdentity${NC}"
        ((PASSED++))

        if echo "$TRUST_POLICY" | grep -q "$NAMESPACE:serviceaccount:$SA_NAME"; then
            echo -e "${GREEN}✓ Trust policy includes correct service account${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠ Service account not explicitly in trust policy${NC}"
            echo -e "${YELLOW}  Might use wildcard or condition${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}✗ Trust policy does not allow AssumeRoleWithWebIdentity${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ Skipping (IRSA role not found)${NC}"
    ((WARNINGS++))
fi

echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${GREEN}  Passed: $PASSED${NC}"
echo -e "${RED}  Failed: $FAILED${NC}"
echo -e "${YELLOW}  Warnings: $WARNINGS${NC}"
echo

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ IRSA is properly configured!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo "Pods using service account '${SA_NAME}' can:"
    echo "  ✓ Assume IAM role: ${IRSA_ROLE}"
    echo "  ✓ Access AWS services (S3, SES, etc.)"
    echo "  ✓ No static credentials needed"
    echo
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}⚠ IRSA configured with warnings${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo
    echo "Review warnings above and ensure:"
    echo "  1. Applications are deployed"
    echo "  2. Pods are using the correct service account"
    echo "  3. AWS CLI is available if needed for testing"
    echo
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ IRSA configuration issues detected!${NC}"
    echo -e "${RED}========================================${NC}"
    echo
    echo "Common fixes:"
    echo
    echo "1. Create/update service account:"
    echo "   kubectl apply -f secrets/${ENV}/service-account.yaml"
    echo
    echo "2. Ensure IAM role has trust policy for OIDC:"
    echo "   Check terraform/aws/modules/eks/irsa.tf"
    echo
    echo "3. Verify OIDC provider is registered:"
    echo "   aws iam list-open-id-connect-providers"
    echo
    echo "4. Check IAM role permissions:"
    echo "   aws iam get-role --role-name <role-name>"
    echo
    echo "5. Restart pods to pick up service account changes:"
    echo "   kubectl rollout restart deployment -n ${NAMESPACE}"
    echo
    echo "For detailed troubleshooting, see:"
    echo "  docs/TROUBLESHOOTING_EKS.md"
    echo
    exit 1
fi
