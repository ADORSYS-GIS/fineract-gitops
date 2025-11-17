#!/bin/bash
# Cleanup Cluster - Force remove stuck namespaces and resources
# This script handles stuck namespaces in "Terminating" state by removing finalizers

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Fineract GitOps - Cluster Cleanup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
    echo -e "${RED}✗ KUBECONFIG not set${NC}"
    echo "Please set KUBECONFIG environment variable"
    echo "Example: export KUBECONFIG=~/.kube/config-fineract-dev"
    exit 1
fi

# Check cluster connectivity (non-fatal if cluster doesn't exist)
echo -e "${BLUE}→ Checking cluster connectivity...${NC}"
CLUSTER_ACCESSIBLE=false
KUBECONFIG_UPDATED=false

# First try to connect
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓${NC} Connected to cluster"
    CLUSTER_ACCESSIBLE=true
else
    # Connection failed - check if it's a DNS resolution issue (stale kubeconfig)
    CLUSTER_ENDPOINT=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed 's|https://||' | cut -d: -f1 || echo "")

    if [ -n "$CLUSTER_ENDPOINT" ]; then
        echo -e "${YELLOW}⚠ Cannot connect to cluster${NC}"
        echo -e "${YELLOW}  Checking if kubeconfig is stale...${NC}"

        # Test DNS resolution
        if ! host "$CLUSTER_ENDPOINT" &>/dev/null && ! nslookup "$CLUSTER_ENDPOINT" &>/dev/null 2>&1; then
            echo -e "${YELLOW}  DNS resolution failed for: $CLUSTER_ENDPOINT${NC}"
            echo -e "${YELLOW}  This indicates a stale kubeconfig (cluster may have been recreated)${NC}"
            echo ""
            echo "Options:"
            echo "  1) Update kubeconfig and retry cleanup"
            echo "  2) Skip cleanup (cluster already gone)"
            echo "  3) Exit script"
            echo ""

            read -p "Choose option [1/2/3]: " -n 1 -r
            echo

            if [[ $REPLY =~ ^[1]$ ]]; then
                echo -e "${BLUE}→ Attempting to update kubeconfig...${NC}"

                # Try to update kubeconfig
                if cd "$SCRIPT_DIR/../terraform/aws" && make update-kubeconfig ENV="$ENV" 2>&1 | grep -q "updated\|configured"; then
                    echo -e "${GREEN}✓${NC} Kubeconfig updated successfully"
                    KUBECONFIG_UPDATED=true

                    # Retry connection
                    echo -e "${BLUE}→ Retrying cluster connection...${NC}"
                    if kubectl cluster-info &>/dev/null; then
                        echo -e "${GREEN}✓${NC} Connected to cluster"
                        CLUSTER_ACCESSIBLE=true
                    else
                        echo -e "${YELLOW}⚠ Still cannot connect after kubeconfig update${NC}"
                        echo -e "${YELLOW}  Cluster may not exist. Skipping Kubernetes cleanup.${NC}"
                    fi

                    cd "$SCRIPT_DIR" || exit 1
                else
                    echo -e "${RED}✗${NC} Failed to update kubeconfig"
                    echo -e "${YELLOW}  Cluster may not exist. Skipping Kubernetes cleanup.${NC}"
                fi
            elif [[ $REPLY =~ ^[2]$ ]]; then
                echo -e "${YELLOW}Skipping Kubernetes cleanup (cluster already gone)${NC}"
                echo -e "${BLUE}→ You may want to run: make destroy ENV=dev (to clean up AWS resources)${NC}"
                exit 0
            else
                echo -e "${YELLOW}Cleanup cancelled${NC}"
                exit 0
            fi
        else
            # DNS resolves but connection still fails
            echo -e "${YELLOW}  Cluster endpoint resolves but connection failed${NC}"
            echo ""
            echo "This could mean:"
            echo "  • Cluster is being destroyed"
            echo "  • Network connectivity issue"
            echo "  • Cluster is not accessible from this network"
            echo ""
            echo "Recommended action:"
            echo "  → Run: ${BLUE}make destroy ENV=dev${NC} (to clean up AWS resources)"
            echo ""

            read -p "Exit cleanup script? [Y/n] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo -e "${YELLOW}Cleanup cancelled${NC}"
                exit 0
            else
                echo -e "${YELLOW}Continuing anyway (Kubernetes cleanup will be skipped)...${NC}"
            fi
        fi
    else
        # Couldn't get cluster endpoint from kubeconfig
        echo -e "${YELLOW}⚠ Cannot connect to cluster${NC}"
        echo -e "${YELLOW}  Could not read cluster endpoint from kubeconfig${NC}"
        echo ""

        read -p "Exit cleanup script? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}Cleanup cancelled${NC}"
            exit 0
        else
            echo -e "${YELLOW}Continuing anyway (Kubernetes cleanup will be skipped)...${NC}"
        fi
    fi
fi

# Check for jq (optional but helpful for nuclear option)
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}⚠ jq not found (optional, some advanced cleanup features won't work)${NC}"
    echo -e "${YELLOW}  Install with: brew install jq${NC}"
fi

echo ""

# Function to check if namespace exists and is stuck
check_namespace_stuck() {
    local ns=$1
    local phase=$(kubectl get namespace $ns -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [ "$phase" = "Terminating" ]; then
        echo "stuck"
    elif [ "$phase" = "Active" ]; then
        echo "active"
    else
        echo "notfound"
    fi
}

# Function to aggressively clean all resources in a namespace
clean_namespace_resources() {
    local ns=$1
    echo -e "${YELLOW}  → Cleaning all resources in namespace: $ns${NC}"

    # Delete all resources with finalizers
    local resource_types=(
        # ArgoCD Resources (must be first)
        "applications.argoproj.io"
        "applicationsets.argoproj.io"
        "appprojects.argoproj.io"

        # Workload Resources (CRITICAL - often have hook finalizers)
        "jobs"
        "cronjobs"
        "deployments"
        "statefulsets"
        "replicasets"
        "daemonsets"
        "pods"

        # Storage Resources
        "persistentvolumeclaims"

        # Network Resources
        "services"
        "ingresses"
        "endpoints"
        "endpointslices"
        "networkpolicies"

        # Configuration Resources
        "configmaps"
        "secrets"

        # RBAC Resources
        "serviceaccounts"
        "roles"
        "rolebindings"
    )

    for resource in "${resource_types[@]}"; do
        # Check if resource type exists in cluster
        if kubectl api-resources --verbs=list -o name 2>/dev/null | grep -q "^${resource}$"; then
            local count=$(kubectl get $resource -n $ns --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$count" -gt 0 ]; then
                echo -e "${BLUE}    Removing finalizers from $resource...${NC}"

                # Specifically target ArgoCD hook finalizers for jobs (don't hide errors)
                if [[ "$resource" == "jobs" ]]; then
                    echo -e "${BLUE}      Removing ArgoCD hook finalizers from jobs...${NC}"
                    kubectl get jobs -n $ns -o name 2>/dev/null | while read job; do
                        # Remove all finalizers including argocd.argoproj.io/hook-finalizer
                        echo -e "${BLUE}        Patching $job...${NC}"
                        kubectl patch $job -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
                        # Also try with empty array
                        kubectl patch $job -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                        # Give each patch a moment to apply
                        sleep 1
                    done
                    # Give all patches time to fully apply
                    sleep 3
                    # Force delete jobs
                    echo -e "${BLUE}      Force deleting jobs...${NC}"
                    kubectl delete jobs --all -n $ns --force --grace-period=0 2>/dev/null || true
                    # Wait a bit more for deletion to complete
                    sleep 2
                else
                    # Remove finalizers from all resources of this type
                    kubectl get $resource -n $ns -o name 2>/dev/null | while read obj; do
                        kubectl patch $obj -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    done
                    # Force delete
                    kubectl delete $resource --all -n $ns --force --grace-period=0 2>/dev/null || true
                fi
            fi
        fi
    done

    echo -e "${GREEN}  ✓${NC} Namespace resources cleaned"
}

# Function to force delete namespace by removing finalizers
force_delete_namespace() {
    local ns=$1
    echo -e "${YELLOW}  → Force-deleting namespace: $ns${NC}"

    # Step 1: Clean all resources in the namespace first
    clean_namespace_resources $ns

    # Step 2: Delete the namespace if it still exists
    # Use timeout to prevent hanging if cluster is unreachable
    if timeout 10 kubectl get namespace $ns &>/dev/null; then
        timeout 30 kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || true
    fi

    # Step 3: Remove finalizers from namespace itself
    timeout 10 kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

    # Step 4: Use JSON patch to forcibly remove finalizers (more aggressive)
    timeout 10 kubectl patch namespace $ns --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true

    # Step 5: Try to replace the namespace spec (nuclear option)
    timeout 10 kubectl get namespace $ns -o json 2>/dev/null | \
        jq '.spec.finalizers=[]' | \
        timeout 10 kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true

    # Wait for deletion with longer timeout
    echo -e "${BLUE}    Waiting for namespace deletion...${NC}"
    local count=0
    while timeout 5 kubectl get namespace $ns &>/dev/null && [ $count -lt 60 ]; do
        if [ $((count % 10)) -eq 0 ]; then
            # Every 10 seconds, try patching again
            kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
        echo -ne "${BLUE}    Progress: $count/60 seconds...${NC}\r"
        sleep 1
        count=$((count + 1))
    done
    echo ""

    if kubectl get namespace $ns &>/dev/null; then
        echo -e "${YELLOW}  ⚠ Namespace still exists after 60s${NC}"
        echo -e "${YELLOW}  → Diagnosing issue...${NC}"

        # Show what's blocking deletion
        echo -e "${BLUE}    Resources still in namespace:${NC}"
        kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | \
            xargs -n 1 kubectl get --show-kind --ignore-not-found -n $ns 2>/dev/null | head -20

        return 1
    else
        echo -e "${GREEN}  ✓${NC} Namespace deleted"
        return 0
    fi
}

# Function to delete all ArgoCD Applications (removes finalizers)
delete_argocd_applications() {
    echo -e "${BLUE}→ Checking for ArgoCD Applications...${NC}"

    local app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$app_count" -gt 0 ]; then
        echo -e "${YELLOW}  Found $app_count ArgoCD Application(s)${NC}"
        echo -e "${YELLOW}  → Removing finalizers and deleting...${NC}"

        # Remove finalizers from all applications
        kubectl get applications -n argocd -o name 2>/dev/null | while read app; do
            kubectl patch $app -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done

        # Delete all applications
        kubectl delete applications --all -n argocd --timeout=30s 2>/dev/null || true

        echo -e "${GREEN}  ✓${NC} ArgoCD Applications removed"
    else
        echo -e "${GREEN}  ✓${NC} No ArgoCD Applications found"
    fi
}

# Function to delete CRDs
delete_crds() {
    echo -e "${BLUE}→ Deleting Custom Resource Definitions...${NC}"

    local crds=(
        "applications.argoproj.io"
        "applicationsets.argoproj.io"
        "appprojects.argoproj.io"
        "sealedsecrets.bitnami.com"
    )

    for crd in "${crds[@]}"; do
        if kubectl get crd $crd &>/dev/null; then
            echo -e "${YELLOW}  → Deleting CRD: $crd${NC}"
            kubectl delete crd $crd --timeout=30s 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}  ✓${NC} CRDs deleted"
}

# Function to delete webhook configurations (cluster-scoped)
delete_webhooks() {
    echo -e "${BLUE}→ Deleting Webhook Configurations...${NC}"

    # Validating Webhooks
    local validating_webhooks=(
        "cert-manager-webhook"
        "ingress-nginx-admission"
    )

    for webhook in "${validating_webhooks[@]}"; do
        if kubectl get validatingwebhookconfiguration $webhook &>/dev/null; then
            echo -e "${YELLOW}  → Deleting ValidatingWebhookConfiguration: $webhook${NC}"
            kubectl delete validatingwebhookconfiguration $webhook --timeout=30s 2>/dev/null || true
        fi
    done

    # Mutating Webhooks
    local mutating_webhooks=(
        "cert-manager-webhook"
        "ingress-nginx-admission"
    )

    for webhook in "${mutating_webhooks[@]}"; do
        if kubectl get mutatingwebhookconfiguration $webhook &>/dev/null; then
            echo -e "${YELLOW}  → Deleting MutatingWebhookConfiguration: $webhook${NC}"
            kubectl delete mutatingwebhookconfiguration $webhook --timeout=30s 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}  ✓${NC} Webhook configurations deleted"
}

# Function to cleanup Sealed Secrets from kube-system
cleanup_sealed_secrets() {
    echo -e "${BLUE}→ Checking for Sealed Secrets Controller in kube-system...${NC}"

    # Check if Sealed Secrets Controller exists
    if kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
        echo -e "${YELLOW}  Found Sealed Secrets Controller${NC}"
        echo -e "${YELLOW}  → Deleting deployment...${NC}"
        kubectl delete deployment sealed-secrets-controller -n kube-system --force --grace-period=0 2>/dev/null || true
        echo -e "${GREEN}  ✓${NC} Deployment deleted"
    else
        echo -e "${GREEN}  ✓${NC} No Sealed Secrets Controller found"
    fi

    # Check for Sealed Secrets keys
    local key_count=$(kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$key_count" -gt 0 ]; then
        echo -e "${YELLOW}  Found $key_count Sealed Secrets key(s)${NC}"
        echo -e "${YELLOW}  → Deleting encryption keys...${NC}"
        kubectl delete secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key --force --grace-period=0 2>/dev/null || true
        echo -e "${GREEN}  ✓${NC} Encryption keys deleted"
    else
        echo -e "${GREEN}  ✓${NC} No Sealed Secrets keys found"
    fi

    # Clean up service and other resources
    if kubectl get service sealed-secrets-controller -n kube-system &>/dev/null; then
        kubectl delete service sealed-secrets-controller -n kube-system --force --grace-period=0 2>/dev/null || true
        echo -e "${GREEN}  ✓${NC} Service deleted"
    fi

    if kubectl get service sealed-secrets-controller-metrics -n kube-system &>/dev/null; then
        kubectl delete service sealed-secrets-controller-metrics -n kube-system --force --grace-period=0 2>/dev/null || true
        echo -e "${GREEN}  ✓${NC} Metrics service deleted"
    fi

    echo -e "${GREEN}  ✓${NC} Sealed Secrets cleanup complete"
}

# Main cleanup process
if [ "$CLUSTER_ACCESSIBLE" = true ]; then
    echo -e "${YELLOW}This will remove all ArgoCD applications and force-delete stuck namespaces:${NC}"
    echo "  - argocd"
    echo "  - fineract-dev"
    echo "  - ingress-nginx"
    echo "  - cert-manager"
    echo "  - monitoring"
    echo ""
    echo -e "${YELLOW}It will also remove from kube-system:${NC}"
    echo "  - Sealed Secrets Controller"
    echo "  - Sealed Secrets encryption keys"
    echo ""

    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleanup cancelled${NC}"
        exit 0
    fi

    echo ""

    # Step 1: Delete ArgoCD Applications first (removes finalizers)
    delete_argocd_applications
    echo ""

    # Step 1.5: Cleanup Sealed Secrets from kube-system
    cleanup_sealed_secrets
    echo ""

    # Step 2: Check and cleanup each namespace
    NAMESPACES=("argocd" "fineract-dev" "ingress-nginx" "cert-manager" "monitoring")

for ns in "${NAMESPACES[@]}"; do
    status=$(check_namespace_stuck $ns)

    if [ "$status" = "stuck" ]; then
        echo -e "${YELLOW}→ Namespace '$ns' is stuck in Terminating state${NC}"
        force_delete_namespace $ns
    elif [ "$status" = "active" ]; then
        echo -e "${BLUE}→ Deleting active namespace: $ns${NC}"
        kubectl delete namespace $ns --timeout=30s 2>/dev/null || force_delete_namespace $ns
    else
        echo -e "${GREEN}✓${NC} Namespace '$ns' not found (already deleted)"
    fi
done

echo ""

# Step 3: Delete CRDs
delete_crds
echo ""

# Step 3.5: Delete Webhook Configurations
delete_webhooks
echo ""

# Step 4: Wait for all namespaces to be fully deleted
echo -e "${BLUE}→ Verifying cleanup...${NC}"
sleep 5

ALL_CLEAN=true
STUCK_NS=()

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace $ns &>/dev/null; then
        ns_status=$(kubectl get namespace $ns -o jsonpath='{.status.phase}' 2>/dev/null)
        echo -e "${YELLOW}  ⚠ Namespace '$ns' still exists (status: $ns_status)${NC}"
        STUCK_NS+=($ns)
        ALL_CLEAN=false
    else
        echo -e "${GREEN}  ✓ Namespace '$ns' fully deleted${NC}"
    fi
done

echo ""
if [ "$ALL_CLEAN" = true ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Cluster cleanup completed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  Run: make deploy-gitops"
    echo "  Or:  make deploy-step-2"
    exit 0
else
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}⚠ Cleanup partially completed${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Some namespaces are still stuck: ${STUCK_NS[@]}${NC}"
    echo ""

    # Try one more aggressive cleanup for stuck namespaces
    echo -e "${BLUE}→ Attempting final aggressive cleanup...${NC}"
    for ns in "${STUCK_NS[@]}"; do
        echo -e "${YELLOW}  Final attempt for: $ns${NC}"

        # Ultra-aggressive: patch via API directly
        kubectl get namespace $ns -o json 2>/dev/null | \
            sed 's/"finalizers": \[[^]]*\]/"finalizers": []/' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true

        # Give it a moment
        sleep 2

        if kubectl get namespace $ns &>/dev/null; then
            echo -e "${RED}  ✗ Still stuck${NC}"
        else
            echo -e "${GREEN}  ✓ Deleted!${NC}"
        fi
    done

    echo ""
    echo -e "${BLUE}Options if namespaces are still stuck:${NC}"
    echo ""
    echo "  1. ${YELLOW}Wait 1-2 minutes${NC} and run this script again:"
    echo "     make cleanup-cluster"
    echo ""
    echo "  2. ${YELLOW}Manual diagnosis${NC} - check what's blocking deletion:"
    for ns in "${STUCK_NS[@]}"; do
        echo "     kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n $ns"
    done
    echo ""
    echo "  3. ${YELLOW}Restart kubelet${NC} on nodes (if on-premise):"
    echo "     # This forces Kubernetes to re-sync namespace state"
    echo ""
    echo "  4. ${RED}Last resort${NC} - Recreate the cluster:"
    echo "     make destroy ENV=dev"
    echo "     cd terraform/aws && terraform apply"
    echo ""

    # Final check
    sleep 3
    FINAL_CHECK=true
    for ns in "${STUCK_NS[@]}"; do
        if kubectl get namespace $ns &>/dev/null; then
            FINAL_CHECK=false
            break
        fi
    done

    if [ "$FINAL_CHECK" = true ]; then
        echo -e "${GREEN}✓ Success! All namespaces deleted on final check${NC}"
        exit 0
    else
        echo -e "${YELLOW}Some namespaces remain stuck. Follow options above.${NC}"
        exit 1
    fi
fi
else
    # Cluster not accessible - provide guidance
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW} Cluster Not Accessible - Skipping K8s Cleanup${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Since the cluster is not accessible, Kubernetes resources cannot be cleaned."
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Clean up AWS infrastructure:"
    echo "     ${BLUE}make destroy ENV=dev${NC}"
    echo ""
    echo "  2. Deploy fresh infrastructure:"
    echo "     ${BLUE}make deploy-infrastructure-dev${NC}"
    echo "     ${BLUE}aws eks update-kubeconfig --region us-east-2 --name fineract-dev-eks${NC}"
    echo "     ${BLUE}make deploy-k8s-with-loadbalancer-dns-dev${NC}"
    echo "     ${BLUE}make deploy-gitops ENV=dev${NC}"
    echo ""
    exit 0
fi
