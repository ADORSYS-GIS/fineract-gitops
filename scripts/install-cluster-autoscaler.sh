#!/bin/bash
# Install Cluster Autoscaler
# Deploys Kubernetes Cluster Autoscaler with IRSA for EKS
#
# Usage: ./scripts/install-cluster-autoscaler.sh [environment]
# Example: ./scripts/install-cluster-autoscaler.sh dev
#
# Prerequisites:
# 1. kubectl configured to access the EKS cluster
# 2. Terraform outputs available (cluster name, IRSA role)
# 3. AWS CLI configured
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV="${1:-dev}"
NAMESPACE="kube-system"
CLUSTER_AUTOSCALER_VERSION="v1.31.0"  # Match with EKS version
AWS_REGION="${AWS_REGION:-us-east-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform/aws"

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
echo -e "${BLUE}Cluster Autoscaler Installation${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}Version: ${CLUSTER_AUTOSCALER_VERSION}${NC}"
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

# Get Terraform outputs
log_info "Fetching Terraform outputs..."

if [ ! -d "$TERRAFORM_DIR" ]; then
    error_exit "Terraform directory not found: $TERRAFORM_DIR"
fi

cd "$TERRAFORM_DIR"

# Get cluster name
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
if [ -z "$EKS_CLUSTER_NAME" ]; then
    error_exit "Could not get EKS cluster name from Terraform"
fi

# Get Cluster Autoscaler IRSA role
AUTOSCALER_ROLE_ARN=$(terraform output -raw cluster_autoscaler_role_arn 2>/dev/null || echo "")
if [ -z "$AUTOSCALER_ROLE_ARN" ]; then
    error_exit "Could not get Cluster Autoscaler IRSA role ARN from Terraform"
fi

cd "$SCRIPT_DIR/.."

log "✓ Terraform outputs retrieved"
echo -e "  ${BLUE}Cluster:${NC} $EKS_CLUSTER_NAME"
echo -e "  ${BLUE}IRSA Role:${NC} $AUTOSCALER_ROLE_ARN"
echo

# ============================================================================
# Create Service Account
# ============================================================================

log_info "Creating service account..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: ${NAMESPACE}
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  annotations:
    eks.amazonaws.com/role-arn: ${AUTOSCALER_ROLE_ARN}
EOF

log "✓ Service account created"
echo

# ============================================================================
# Create ClusterRole and ClusterRoleBinding
# ============================================================================

log_info "Creating RBAC resources..."

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["events", "endpoints"]
    verbs: ["create", "patch"]
  - apiGroups: [""]
    resources: ["pods/eviction"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["cluster-autoscaler"]
    verbs: ["get", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["watch", "list", "get", "update"]
  - apiGroups: [""]
    resources:
      - "namespaces"
      - "pods"
      - "services"
      - "replicationcontrollers"
      - "persistentvolumeclaims"
      - "persistentvolumes"
    verbs: ["watch", "list", "get"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes", "csidrivers", "csistoragecapacities"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["batch", "extensions"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create"]
  - apiGroups: ["coordination.k8s.io"]
    resourceNames: ["cluster-autoscaler"]
    resources: ["leases"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: ${NAMESPACE}
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create","list","watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    verbs: ["delete", "get", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: ${NAMESPACE}
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: ${NAMESPACE}
EOF

log "✓ RBAC resources created"
echo

# ============================================================================
# Create Deployment
# ============================================================================

log_info "Creating Cluster Autoscaler deployment..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: ${NAMESPACE}
  labels:
    app: cluster-autoscaler
    k8s-app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8085"
    spec:
      priorityClassName: system-cluster-critical
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
        seccompProfile:
          type: RuntimeDefault
      serviceAccountName: cluster-autoscaler
      containers:
        - image: registry.k8s.io/autoscaling/cluster-autoscaler:${CLUSTER_AUTOSCALER_VERSION}
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 600Mi
            requests:
              cpu: 100m
              memory: 600Mi
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --expander=least-waste
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${EKS_CLUSTER_NAME}
            - --balance-similar-node-groups
            - --skip-nodes-with-system-pods=false
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs/ca-certificates.crt
              readOnly: true
          imagePullPolicy: Always
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
      volumes:
        - name: ssl-certs
          hostPath:
            path: /etc/ssl/certs/ca-bundle.crt
      nodeSelector:
        kubernetes.io/os: linux
EOF

log "✓ Deployment created"
echo

# ============================================================================
# Wait for Deployment
# ============================================================================

log_info "Waiting for Cluster Autoscaler to be ready..."

if kubectl rollout status deployment/cluster-autoscaler -n "$NAMESPACE" --timeout=120s; then
    log "✓ Cluster Autoscaler is ready"
else
    log_warn "Deployment rollout timed out, but may still be starting"
fi

echo

# ============================================================================
# Verify Installation
# ============================================================================

log_info "Verifying installation..."
echo

# Check pod status
POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app=cluster-autoscaler \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")

if [ "$POD_STATUS" == "Running" ]; then
    echo -e "${GREEN}✓ Pod is running${NC}"
else
    echo -e "${YELLOW}⚠ Pod status: ${POD_STATUS}${NC}"
fi

# Check pod logs for errors
log_info "Checking logs for errors..."
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=cluster-autoscaler \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    LOGS=$(kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=20 2>&1 || echo "")

    if echo "$LOGS" | grep -qi "error"; then
        echo -e "${YELLOW}⚠ Errors found in logs:${NC}"
        echo "$LOGS" | grep -i "error" | tail -5 | sed 's/^/  /'
    else
        echo -e "${GREEN}✓ No errors in recent logs${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not find pod${NC}"
fi

echo

# ============================================================================
# Configuration Summary
# ============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configuration Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${BLUE}Cluster:${NC} $EKS_CLUSTER_NAME"
echo -e "${BLUE}AWS Region:${NC} $AWS_REGION"
echo -e "${BLUE}Namespace:${NC} $NAMESPACE"
echo -e "${BLUE}IRSA Role:${NC} $AUTOSCALER_ROLE_ARN"
echo -e "${BLUE}Version:${NC} $CLUSTER_AUTOSCALER_VERSION"
echo
echo -e "${BLUE}Auto-discovery Tag:${NC}"
echo "  k8s.io/cluster-autoscaler/enabled=true"
echo "  k8s.io/cluster-autoscaler/${EKS_CLUSTER_NAME}=owned"
echo
echo -e "${BLUE}Node Groups:${NC}"
echo "  Autoscaler will manage node groups tagged with the above"
echo

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cluster Autoscaler Installed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo

echo -e "${YELLOW}Next Steps:${NC}"
echo
echo "1. View Cluster Autoscaler logs:"
echo "   kubectl logs -f -n ${NAMESPACE} -l app=cluster-autoscaler"
echo
echo "2. Check autoscaler status:"
echo "   kubectl get deployment -n ${NAMESPACE} cluster-autoscaler"
echo
echo "3. View autoscaler events:"
echo "   kubectl get events -n ${NAMESPACE} --field-selector involvedObject.name=cluster-autoscaler"
echo
echo "4. Test scaling:"
echo "   kubectl scale deployment <name> --replicas=10"
echo "   # Watch nodes scale up"
echo "   kubectl get nodes -w"
echo
echo "5. Check node group auto-discovery:"
echo "   kubectl logs -n ${NAMESPACE} -l app=cluster-autoscaler | grep 'Discovered'"
echo

echo -e "${BLUE}Configuration Options:${NC}"
echo
echo "The autoscaler is configured with:"
echo "  • Auto-discovery based on ASG tags"
echo "  • Expander strategy: least-waste"
echo "  • Balance similar node groups: enabled"
echo "  • Skip nodes with local storage: false"
echo
echo "To modify configuration, edit the deployment:"
echo "  kubectl edit deployment -n ${NAMESPACE} cluster-autoscaler"
echo

echo -e "${BLUE}Monitoring:${NC}"
echo
echo "Cluster Autoscaler exposes metrics on port 8085"
echo "Prometheus scraping is enabled via annotations"
echo

echo -e "${GREEN}Done!${NC}"
