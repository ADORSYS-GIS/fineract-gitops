#!/bin/bash
# Cleanup Cluster - Force remove stuck namespaces and resources
# This script handles stuck namespaces in "Terminating" state by removing finalizers
#
# Usage: ./cleanup-cluster.sh [--env dev|uat|prod] [--force] [--stuck-only]

set -e
set -o pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default environment
ENV="${ENV:-dev}"
FORCE_MODE=false
STUCK_ONLY=false
SKIP_DB_CLEANUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env|-e)
            ENV="$2"
            shift 2
            ;;
        --force|-f)
            FORCE_MODE=true
            shift
            ;;
        --stuck-only)
            STUCK_ONLY=true
            FORCE_MODE=true  # stuck-only implies force mode
            shift
            ;;
        --skip-db)
            SKIP_DB_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--env dev|uat|prod] [--force] [--stuck-only]"
            echo ""
            echo "Options:"
            echo "  --env, -e      Environment to clean (dev, uat, prod). Default: dev"
            echo "  --force, -f    Non-interactive mode (skip all confirmations)"
            echo "  --stuck-only   Only clean stuck (Terminating) namespaces, then exit"
            echo "  --skip-db      Skip database cleanup prompt"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Validate and set namespace based on environment
case "$ENV" in
    dev)
        FINERACT_NAMESPACE="fineract-dev"
        ;;
    uat)
        FINERACT_NAMESPACE="fineract-uat"
        ;;
    prod|production)
        FINERACT_NAMESPACE="fineract-production"
        ENV="prod"
        ;;
    *)
        echo "Invalid environment: $ENV"
        echo "Valid values: dev, uat, prod"
        exit 1
        ;;
esac

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Fineract GitOps - Cluster Cleanup${NC}"
echo -e "${BLUE} Environment: ${ENV}${NC}"
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
HAVE_JQ=true
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}⚠ jq not found (optional, some advanced cleanup features won't work)${NC}"
    echo -e "${YELLOW}  Install with: brew install jq${NC}"
    HAVE_JQ=false
fi

echo ""

# Function to diagnose blocking resources in a namespace
check_blocking_resources() {
    local ns=$1
    echo -e "${BLUE}  → Diagnostic check for namespace: $ns${NC}"

    # Check for resources with finalizers
    echo -e "${BLUE}    Checking for finalizers...${NC}"
    local found_finalizers=false

    if [ "$HAVE_JQ" = true ]; then
        # Use jq for detailed finalizer analysis
        kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | while read resource; do
            local count=$(kubectl get $resource -n $ns -o json 2>/dev/null | \
                jq '[.items[] | select(.metadata.finalizers)] | length' 2>/dev/null || echo "0")
            if [ "$count" -gt 0 ]; then
                echo -e "${YELLOW}      Found $count $resource(s) with finalizers${NC}"
                # Show specific resources with finalizers
                kubectl get $resource -n $ns -o json 2>/dev/null | \
                    jq -r '.items[] | select(.metadata.finalizers) | "        - " + .metadata.name + ": " + (.metadata.finalizers | join(", "))' 2>/dev/null | head -5
                found_finalizers=true
            fi
        done
    else
        # Fallback without jq - check common resource types
        for resource in pods jobs deployments statefulsets services pvc; do
            local resources_with_finalizers=$(kubectl get $resource -n $ns -o custom-columns=NAME:.metadata.name,FINALIZERS:.metadata.finalizers --no-headers 2>/dev/null | grep -v '<none>' | wc -l)
            if [ "$resources_with_finalizers" -gt 0 ]; then
                echo -e "${YELLOW}      Found $resources_with_finalizers $resource(s) with finalizers${NC}"
                kubectl get $resource -n $ns -o custom-columns=NAME:.metadata.name,FINALIZERS:.metadata.finalizers --no-headers 2>/dev/null | grep -v '<none>' | head -3 | sed 's/^/        - /'
                found_finalizers=true
            fi
        done
    fi

    if [ "$found_finalizers" = false ]; then
        echo -e "${GREEN}      No resources with finalizers found${NC}"
    fi

    # Check for pods in bad states
    local failed_pods=$(kubectl get pods -n $ns --field-selector=status.phase=Failed 2>/dev/null | tail -n +2 | wc -l)
    local evicted_pods=$(kubectl get pods -n $ns --field-selector=status.reason=Evicted 2>/dev/null | tail -n +2 | wc -l)
    local terminating_pods=$(kubectl get pods -n $ns --field-selector=metadata.deletionTimestamp!=null 2>/dev/null | tail -n +2 | wc -l)

    if [ "$failed_pods" -gt 0 ]; then
        echo -e "${YELLOW}      Found $failed_pods failed pod(s)${NC}"
    fi
    if [ "$evicted_pods" -gt 0 ]; then
        echo -e "${YELLOW}      Found $evicted_pods evicted pod(s)${NC}"
    fi
    if [ "$terminating_pods" -gt 0 ]; then
        echo -e "${YELLOW}      Found $terminating_pods terminating pod(s)${NC}"
    fi

    # Check for PVCs
    local pvc_count=$(kubectl get pvc -n $ns --no-headers 2>/dev/null | wc -l)
    if [ "$pvc_count" -gt 0 ]; then
        echo -e "${YELLOW}      Found $pvc_count PVC(s)${NC}"
        kubectl get pvc -n $ns --no-headers 2>/dev/null | awk '{print "        - " $1 " (" $2 ")"}'
    fi

    # Check for jobs
    local job_count=$(kubectl get jobs -n $ns --no-headers 2>/dev/null | wc -l)
    if [ "$job_count" -gt 0 ]; then
        echo -e "${YELLOW}      Found $job_count job(s)${NC}"
        kubectl get jobs -n $ns -o custom-columns=NAME:.metadata.name,COMPLETIONS:.status.succeeded,ACTIVE:.status.active --no-headers 2>/dev/null | head -5 | sed 's/^/        - /'
    fi

    echo ""
}

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

        # Workload Resources (CRITICAL - delete pods before jobs to avoid blocking)
        "pods"
        "jobs"
        "cronjobs"
        "deployments"
        "statefulsets"
        "replicasets"
        "daemonsets"

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

                # Enhanced job cleanup with proper pod deletion and finalizer handling
                if [[ "$resource" == "jobs" ]]; then
                    echo -e "${BLUE}      Enhanced job cleanup (identify & fix all finalizer types)...${NC}"

                    # Step 1: Get total job count for verification
                    local job_count=$(kubectl get jobs -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
                    echo -e "${BLUE}        Total jobs in namespace: $job_count${NC}"

                    if [ "$job_count" -gt 0 ]; then
                        # Step 2: Identify jobs and their finalizers
                        echo -e "${BLUE}        Analyzing job finalizers...${NC}"
                        if [ "$HAVE_JQ" = true ]; then
                            kubectl get jobs -n $ns -o json 2>/dev/null | jq -r '.items[] |
                                "\(.metadata.name):\(.metadata.finalizers | join(",") // "none")"' 2>/dev/null | \
                            while IFS=: read job_name finalizers; do
                                if [ -n "$job_name" ]; then
                                    if [ "$finalizers" != "none" ] && [ -n "$finalizers" ]; then
                                        echo -e "${YELLOW}          Job '$job_name' has finalizers: $finalizers${NC}"
                                    fi
                                fi
                            done
                        else
                            echo -e "${YELLOW}          (jq not available - skipping detailed finalizer analysis)${NC}"
                        fi

                        # Step 3: Remove ALL finalizers from jobs (do this BEFORE deleting pods)
                        echo -e "${BLUE}        Removing finalizers from all jobs...${NC}"
                        kubectl get jobs -n $ns -o name 2>/dev/null | while read job; do
                            # Strategy 1: Set finalizers to empty array (most compatible)
                            kubectl patch "$job" -n $ns -p '{"metadata":{"finalizers":[]}}' \
                                --type=merge 2>/dev/null || true
                        done

                        # Step 4: If jq available, use ultra-aggressive removal for persistent finalizers
                        if [ "$HAVE_JQ" = true ]; then
                            echo -e "${BLUE}        Ultra-aggressive finalizer removal for stuck jobs...${NC}"
                            kubectl get jobs -n $ns -o json 2>/dev/null | \
                                jq -r '.items[] | select(.metadata.finalizers) | .metadata.name' 2>/dev/null | \
                                while read job_name; do
                                    if [ -n "$job_name" ]; then
                                        # Get the job, remove finalizers, and replace
                                        kubectl get "job/$job_name" -n $ns -o json 2>/dev/null | \
                                            jq 'del(.metadata.finalizers)' | \
                                            kubectl replace -f - 2>/dev/null || \
                                            kubectl patch "job/$job_name" -n $ns -p '{"metadata":{"finalizers":null}}' \
                                                --type=merge 2>/dev/null || true
                                    fi
                                done
                        fi

                        # Step 5: Wait for API server to process finalizer removal
                        echo -e "${BLUE}        Waiting for API server to process finalizer removal...${NC}"
                        sleep 5

                        # Step 6: Now delete job pods (AFTER finalizer removal)
                        echo -e "${BLUE}        Deleting job pods...${NC}"
                        kubectl delete pods -n $ns -l job-name --force --grace-period=0 2>/dev/null || true
                        sleep 2

                        # Step 7: Force delete jobs
                        echo -e "${BLUE}        Force deleting all jobs...${NC}"
                        kubectl delete jobs --all -n $ns --force --grace-period=0 --timeout=30s 2>/dev/null || true
                        sleep 5

                        # Step 8: Verify completion and handle stuck jobs
                        local remaining=$(kubectl get jobs -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
                        if [ "$remaining" -gt 0 ]; then
                            echo -e "${YELLOW}        Warning: $remaining job(s) still remain after initial cleanup${NC}"

                            # Show what's remaining
                            if [ "$HAVE_JQ" = true ]; then
                                kubectl get jobs -n $ns -o json 2>/dev/null | \
                                    jq -r '.items[] | "          - " + .metadata.name + " (finalizers: " + (.metadata.finalizers | join(", ") // "none") + ", deletionTimestamp: " + (.metadata.deletionTimestamp // "none") + ")"' 2>/dev/null
                            else
                                kubectl get jobs -n $ns -o custom-columns=NAME:.metadata.name,FINALIZERS:.metadata.finalizers 2>/dev/null | sed 's/^/          /'
                            fi

                            # Nuclear option: Use kubectl replace --raw to force delete stuck jobs
                            echo -e "${YELLOW}        Applying nuclear option for stuck jobs...${NC}"
                            kubectl get jobs -n $ns -o name 2>/dev/null | while read job; do
                                job_name=$(echo "$job" | sed 's|.*/||')

                                # Method 1: Patch with null finalizers via API
                                kubectl patch "$job" -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

                                # Method 2: Direct API manipulation to remove finalizers and deletionTimestamp
                                if [ "$HAVE_JQ" = true ]; then
                                    kubectl get "$job" -n $ns -o json 2>/dev/null | \
                                        jq 'del(.metadata.finalizers) | del(.metadata.deletionTimestamp)' | \
                                        kubectl replace --raw "/apis/batch/v1/namespaces/$ns/jobs/$job_name" -f - 2>/dev/null || true
                                fi
                            done

                            sleep 3

                            # Final force delete attempt
                            kubectl delete jobs --all -n $ns --force --grace-period=0 2>/dev/null || true
                            sleep 3

                            # Final verification
                            remaining=$(kubectl get jobs -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
                            if [ "$remaining" -gt 0 ]; then
                                echo -e "${RED}        ✗ $remaining job(s) still stuck - may need manual intervention${NC}"
                            else
                                echo -e "${GREEN}        ✓ All jobs deleted successfully (after nuclear option)${NC}"
                            fi
                        else
                            echo -e "${GREEN}        ✓ All jobs deleted successfully${NC}"
                        fi
                    else
                        echo -e "${GREEN}        ✓ No jobs found${NC}"
                    fi
                elif [[ "$resource" == "statefulsets" ]]; then
                    # Enhanced StatefulSet cleanup - must delete PVCs explicitly
                    echo -e "${BLUE}      Cleaning StatefulSets and their PVCs...${NC}"

                    # Step 1: Remove finalizers from StatefulSets
                    kubectl get statefulsets -n $ns -o name 2>/dev/null | while read sts; do
                        kubectl patch "$sts" -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    done

                    # Step 2: Delete StatefulSets
                    kubectl delete statefulsets --all -n $ns --force --grace-period=0 2>/dev/null || true
                    sleep 2

                    # Step 3: Explicitly clean up StatefulSet PVCs (they don't auto-delete)
                    echo -e "${BLUE}        Cleaning StatefulSet PVCs...${NC}"
                    if [ "$HAVE_JQ" = true ]; then
                        # Use jq to find PVCs owned by StatefulSets
                        kubectl get pvc -n $ns -o json 2>/dev/null | \
                            jq -r '.items[] | select(.metadata.ownerReferences[]? | select(.kind=="StatefulSet")) | .metadata.name' 2>/dev/null | \
                            while read pvc_name; do
                                if [ -n "$pvc_name" ]; then
                                    echo -e "${BLUE}          Deleting StatefulSet PVC: $pvc_name${NC}"
                                    kubectl patch pvc "$pvc_name" -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                                    kubectl delete pvc "$pvc_name" -n $ns --force --grace-period=0 2>/dev/null || true
                                fi
                            done
                    else
                        # Fallback: Delete all PVCs with redis/stateful pattern in name
                        kubectl get pvc -n $ns -o name 2>/dev/null | grep -E '(redis|data)' | while read pvc; do
                            echo -e "${BLUE}          Deleting PVC: $pvc${NC}"
                            kubectl patch "$pvc" -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                            kubectl delete "$pvc" -n $ns --force --grace-period=0 2>/dev/null || true
                        done
                    fi
                    echo -e "${GREEN}        ✓ StatefulSets and PVCs cleaned${NC}"
                elif [[ "$resource" == "services" ]]; then
                    # Enhanced service cleanup - remove AWS LoadBalancer finalizers first
                    echo -e "${BLUE}      Cleaning services (remove finalizers first)...${NC}"

                    # Step 1: Remove finalizers from services (especially AWS ELB finalizers)
                    kubectl get services -n $ns -o name 2>/dev/null | while read svc; do
                        # Remove common service finalizers (service.kubernetes.io/load-balancer-cleanup, etc.)
                        kubectl patch "$svc" -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    done

                    sleep 2

                    # Step 2: Now safe to delete
                    kubectl delete services --all -n $ns --force --grace-period=0 2>/dev/null || true
                    echo -e "${GREEN}        ✓ Services cleaned${NC}"
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

        # Check specifically for stuck jobs
        local stuck_jobs=$(kubectl get jobs -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$stuck_jobs" -gt 0 ]; then
            echo -e "${YELLOW}    Found $stuck_jobs stuck job(s) - applying final nuclear cleanup...${NC}"

            # Ultra-nuclear: Delete jobs via raw API with force
            kubectl get jobs -n $ns -o name 2>/dev/null | while read job; do
                job_name=$(echo "$job" | sed 's|.*/||')
                echo -e "${YELLOW}      Forcing deletion of job: $job_name${NC}"

                # Remove finalizers via raw API
                kubectl get "$job" -n $ns -o json 2>/dev/null | \
                    jq 'del(.metadata.finalizers) | del(.metadata.deletionTimestamp) | del(.metadata.deletionGracePeriodSeconds)' 2>/dev/null | \
                    kubectl replace --raw "/apis/batch/v1/namespaces/$ns/jobs/$job_name" -f - 2>/dev/null || true

                # Also try direct deletion via raw API
                kubectl delete --raw "/apis/batch/v1/namespaces/$ns/jobs/$job_name" 2>/dev/null || true
            done

            # Delete job pods via raw API as well
            kubectl get pods -n $ns -l job-name -o name 2>/dev/null | while read pod; do
                pod_name=$(echo "$pod" | sed 's|.*/||')
                kubectl delete --raw "/api/v1/namespaces/$ns/pods/$pod_name?gracePeriodSeconds=0&force=true" 2>/dev/null || true
            done

            sleep 5

            # Try namespace deletion one more time
            kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || true

            sleep 5

            # Final check
            if kubectl get namespace $ns &>/dev/null; then
                echo -e "${RED}    ✗ Namespace still stuck after nuclear cleanup${NC}"
                return 1
            else
                echo -e "${GREEN}    ✓ Namespace deleted after nuclear cleanup!${NC}"
                return 0
            fi
        fi

        return 1
    else
        echo -e "${GREEN}  ✓${NC} Namespace deleted"
        return 0
    fi
}

# Function to delete all ArgoCD Applications and AppProjects (removes finalizers)
delete_argocd_applications() {
    echo -e "${BLUE}→ Checking for ArgoCD resources...${NC}"

    # Delete Applications
    local app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$app_count" -gt 0 ]; then
        echo -e "${YELLOW}  Found $app_count ArgoCD Application(s)${NC}"
        echo -e "${YELLOW}  → Removing finalizers and deleting...${NC}"

        # Remove finalizers from all applications
        kubectl get applications -n argocd -o name 2>/dev/null | while read app; do
            kubectl patch $app -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done

        # Delete all applications
        kubectl delete applications --all -n argocd --force --grace-period=0 2>/dev/null || true

        echo -e "${GREEN}  ✓${NC} ArgoCD Applications removed"
    else
        echo -e "${GREEN}  ✓${NC} No ArgoCD Applications found"
    fi

    # Delete ApplicationSets
    local appset_count=$(kubectl get applicationsets -n argocd --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$appset_count" -gt 0 ]; then
        echo -e "${YELLOW}  Found $appset_count ArgoCD ApplicationSet(s)${NC}"

        kubectl get applicationsets -n argocd -o name 2>/dev/null | while read appset; do
            kubectl patch $appset -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done

        kubectl delete applicationsets --all -n argocd --force --grace-period=0 2>/dev/null || true
        echo -e "${GREEN}  ✓${NC} ArgoCD ApplicationSets removed"
    fi

    # Delete AppProjects (IMPORTANT - these can block namespace deletion)
    local project_count=$(kubectl get appprojects -n argocd --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$project_count" -gt 0 ]; then
        echo -e "${YELLOW}  Found $project_count ArgoCD AppProject(s)${NC}"
        echo -e "${YELLOW}  → Removing finalizers and deleting...${NC}"

        # Remove finalizers from all appprojects
        kubectl get appprojects -n argocd -o name 2>/dev/null | while read proj; do
            kubectl patch $proj -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done

        # Delete all appprojects (except 'default' which is protected)
        kubectl delete appprojects --all -n argocd --force --grace-period=0 2>/dev/null || true

        echo -e "${GREEN}  ✓${NC} ArgoCD AppProjects removed"
    else
        echo -e "${GREEN}  ✓${NC} No ArgoCD AppProjects found"
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

# Function to cleanup Reloader from kube-system
cleanup_reloader() {
    echo -e "${BLUE}→ Checking for Reloader in kube-system...${NC}"

    local found=false

    # Check by label
    if kubectl get deployment -n kube-system -l app.kubernetes.io/name=reloader --no-headers 2>/dev/null | grep -q .; then
        found=true
    fi

    # Also check by name pattern
    if kubectl get deployment -n kube-system reloader-reloader --no-headers 2>/dev/null | grep -q .; then
        found=true
    fi

    if [ "$found" = true ]; then
        echo -e "${YELLOW}  Found Reloader deployment${NC}"
        echo -e "${YELLOW}  → Deleting Reloader resources...${NC}"

        # Delete by label
        kubectl delete deployment -n kube-system -l app.kubernetes.io/name=reloader --force --grace-period=0 2>/dev/null || true
        kubectl delete serviceaccount -n kube-system -l app.kubernetes.io/name=reloader --force --grace-period=0 2>/dev/null || true

        # Delete by name (fallback)
        kubectl delete deployment -n kube-system reloader-reloader --force --grace-period=0 2>/dev/null || true
        kubectl delete serviceaccount -n kube-system reloader-reloader --force --grace-period=0 2>/dev/null || true

        # Delete ClusterRole and ClusterRoleBinding
        kubectl delete clusterrole reloader-reloader-role --force --grace-period=0 2>/dev/null || true
        kubectl delete clusterrolebinding reloader-reloader-role-binding --force --grace-period=0 2>/dev/null || true

        echo -e "${GREEN}  ✓${NC} Reloader deleted"
    else
        echo -e "${GREEN}  ✓${NC} No Reloader found"
    fi
}

# Function to cleanup cluster-scoped resources
cleanup_cluster_scoped_resources() {
    echo -e "${BLUE}→ Cleaning up cluster-scoped resources...${NC}"

    # ClusterRoles - delete by name pattern (grep for our components)
    echo -e "${BLUE}  → Deleting ClusterRoles...${NC}"

    # Delete all ArgoCD cluster roles
    kubectl get clusterroles -o name 2>/dev/null | grep -E 'argocd' | while read role; do
        kubectl delete "$role" --force --grace-period=0 2>/dev/null || true
    done

    # Delete all cert-manager cluster roles
    kubectl get clusterroles -o name 2>/dev/null | grep -E 'cert-manager' | while read role; do
        kubectl delete "$role" --force --grace-period=0 2>/dev/null || true
    done

    # Delete all ingress-nginx cluster roles
    kubectl get clusterroles -o name 2>/dev/null | grep -E 'ingress-nginx' | while read role; do
        kubectl delete "$role" --force --grace-period=0 2>/dev/null || true
    done

    # Delete reloader cluster role
    kubectl delete clusterrole reloader-reloader-role --force --grace-period=0 2>/dev/null || true

    # Also delete by label (in case name doesn't match)
    kubectl delete clusterroles -l app.kubernetes.io/part-of=argocd --force --grace-period=0 2>/dev/null || true
    kubectl delete clusterroles -l app.kubernetes.io/name=ingress-nginx --force --grace-period=0 2>/dev/null || true
    kubectl delete clusterroles -l app.kubernetes.io/instance=cert-manager --force --grace-period=0 2>/dev/null || true
    kubectl delete clusterroles -l app.kubernetes.io/name=reloader --force --grace-period=0 2>/dev/null || true

    # ClusterRoleBindings - delete by name pattern
    echo -e "${BLUE}  → Deleting ClusterRoleBindings...${NC}"

    kubectl get clusterrolebindings -o name 2>/dev/null | grep -E 'argocd' | while read binding; do
        kubectl delete "$binding" --force --grace-period=0 2>/dev/null || true
    done

    kubectl get clusterrolebindings -o name 2>/dev/null | grep -E 'cert-manager' | while read binding; do
        kubectl delete "$binding" --force --grace-period=0 2>/dev/null || true
    done

    kubectl get clusterrolebindings -o name 2>/dev/null | grep -E 'ingress-nginx' | while read binding; do
        kubectl delete "$binding" --force --grace-period=0 2>/dev/null || true
    done

    kubectl delete clusterrolebinding reloader-reloader-role-binding --force --grace-period=0 2>/dev/null || true

    # Also delete by label
    kubectl delete clusterrolebindings -l app.kubernetes.io/part-of=argocd --force --grace-period=0 2>/dev/null || true
    kubectl delete clusterrolebindings -l app.kubernetes.io/name=ingress-nginx --force --grace-period=0 2>/dev/null || true
    kubectl delete clusterrolebindings -l app.kubernetes.io/instance=cert-manager --force --grace-period=0 2>/dev/null || true
    kubectl delete clusterrolebindings -l app.kubernetes.io/name=reloader --force --grace-period=0 2>/dev/null || true

    # IngressClass
    echo -e "${BLUE}  → Deleting IngressClass...${NC}"
    kubectl delete ingressclass nginx --force --grace-period=0 2>/dev/null || true

    # PersistentVolumes (all - since we're doing a full cleanup)
    echo -e "${BLUE}  → Deleting PersistentVolumes...${NC}"
    kubectl get pv -o name 2>/dev/null | while read pv; do
        echo "    Deleting $pv..."
        kubectl patch "$pv" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete "$pv" --force --grace-period=0 2>/dev/null || true
    done

    echo -e "${GREEN}  ✓${NC} Cluster-scoped resources cleaned"
}

# Function to cleanup RDS databases (drop and recreate)
cleanup_rds_databases() {
    echo -e "${BLUE}→ Cleaning up RDS databases...${NC}"

    # Check if fineract-db-credentials secret exists (needed for DB access)
    if ! kubectl get secret -n "$FINERACT_NAMESPACE" fineract-db-credentials &>/dev/null; then
        echo -e "${YELLOW}  ⚠ fineract-db-credentials secret not found${NC}"
        echo -e "${YELLOW}  → Skipping database cleanup (cluster may not be fully deployed)${NC}"
        return 0
    fi

    echo -e "${YELLOW}  This will drop and recreate the following databases:${NC}"
    echo "    - keycloak (Keycloak identity management)"
    echo "    - fineract_tenants (Fineract tenant store - contains tenant credentials)"
    echo "    - fineract_default (Fineract core banking)"
    echo ""
    echo -e "${YELLOW}  This ensures a clean state for the next deployment.${NC}"
    echo ""

    if [ "$FORCE_MODE" = false ]; then
        read -p "  Drop and recreate RDS databases? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}  → Skipping database cleanup${NC}"
            return 0
        fi
    else
        echo -e "${BLUE}  [Force mode] Proceeding with database cleanup...${NC}"
    fi

    # Create a temporary job to drop and recreate databases
    echo -e "${BLUE}  → Creating database cleanup job...${NC}"

    cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: batch/v1
kind: Job
metadata:
  name: cleanup-rds-databases
  namespace: $FINERACT_NAMESPACE
  labels:
    app: database-cleanup
spec:
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      name: cleanup-databases
    spec:
      restartPolicy: Never
      containers:
      - name: cleanup-db
        image: postgres:15-alpine
        command:
        - /bin/sh
        - -c
        - |
          set -e
          echo "========================================="
          echo "RDS Database Cleanup"
          echo "========================================="

          export PGHOST="\${RDS_HOST}"
          export PGPORT="5432"
          export PGUSER="\${FINERACT_USER}"
          export PGPASSWORD="\${FINERACT_PASSWORD}"
          export PGDATABASE="postgres"

          echo "Connecting to RDS: \${PGHOST}"
          echo ""

          # Terminate connections to keycloak database
          echo "1/6: Terminating connections to keycloak database..."
          psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'keycloak' AND pid <> pg_backend_pid();" || true

          # Drop keycloak database
          echo "2/6: Dropping keycloak database..."
          psql -c "DROP DATABASE IF EXISTS keycloak;" || echo "  (database may not exist)"

          # Terminate connections to fineract_tenants database (tenant store with credentials)
          echo "3/6: Terminating connections to fineract_tenants database..."
          psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'fineract_tenants' AND pid <> pg_backend_pid();" || true

          # Drop fineract_tenants database (contains tenant credentials that must match secrets)
          echo "4/6: Dropping fineract_tenants database..."
          psql -c "DROP DATABASE IF EXISTS fineract_tenants;" || echo "  (database may not exist)"

          # Terminate connections to fineract_default database
          echo "5/6: Terminating connections to fineract_default database..."
          psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'fineract_default' AND pid <> pg_backend_pid();" || true

          # Drop fineract_default database
          echo "6/6: Dropping fineract_default database..."
          psql -c "DROP DATABASE IF EXISTS fineract_default;" || echo "  (database may not exist)"

          echo ""
          echo "========================================="
          echo "✅ RDS databases dropped successfully"
          echo "   Databases will be recreated on next deployment"
          echo "========================================="
        env:
        - name: RDS_HOST
          valueFrom:
            secretKeyRef:
              name: fineract-db-credentials
              key: host
        - name: FINERACT_USER
          valueFrom:
            secretKeyRef:
              name: fineract-db-credentials
              key: username
        - name: FINERACT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: fineract-db-credentials
              key: password
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 999
          capabilities:
            drop:
            - ALL
EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓${NC} Database cleanup job created"

        # Wait for job to complete
        echo -e "${BLUE}  → Waiting for database cleanup to complete...${NC}"
        if kubectl wait --for=condition=complete --timeout=60s job/cleanup-rds-databases -n "$FINERACT_NAMESPACE" 2>/dev/null; then
            echo -e "${GREEN}  ✓${NC} Databases cleaned successfully"

            # Show job logs
            echo -e "${BLUE}  → Cleanup job output:${NC}"
            kubectl logs job/cleanup-rds-databases -n "$FINERACT_NAMESPACE" 2>/dev/null | sed 's/^/    /'
        else
            echo -e "${YELLOW}  ⚠ Database cleanup job did not complete within 60s${NC}"
            echo -e "${YELLOW}  → Checking job logs...${NC}"
            kubectl logs job/cleanup-rds-databases -n "$FINERACT_NAMESPACE" 2>/dev/null | sed 's/^/    /' || echo "    (no logs available)"
        fi

        # Clean up the job
        kubectl delete job cleanup-rds-databases -n "$FINERACT_NAMESPACE" --force --grace-period=0 2>/dev/null || true
    else
        echo -e "${YELLOW}  ⚠ Failed to create database cleanup job${NC}"
        echo -e "${YELLOW}  → Continuing with namespace cleanup...${NC}"
    fi

    echo -e "${GREEN}  ✓${NC} Database cleanup complete"

    # After database cleanup, delete ALL deployments in the namespace
    # This ensures:
    # 1. No stale database connections (Keycloak, Fineract services)
    # 2. No resource exhaustion from old pods
    # 3. ArgoCD recreates everything in correct order (migrations first)
    echo -e "${BLUE}  → Deleting all deployments in $FINERACT_NAMESPACE (will restart fresh)...${NC}"
    kubectl delete deployments --all -n "$FINERACT_NAMESPACE" --ignore-not-found 2>/dev/null || true
    echo -e "${GREEN}  ✓${NC} All deployments deleted - ArgoCD will recreate them on next sync"
}

# Main cleanup process
if [ "$CLUSTER_ACCESSIBLE" = true ]; then

    # ===========================================================================
    # STUCK-ONLY MODE: Quick fix for stuck namespaces before deployment
    # ===========================================================================
    if [ "$STUCK_ONLY" = true ]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE} Quick Fix: Cleaning Stuck Namespaces${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""

        # Find all stuck namespaces
        STUCK_NAMESPACES=$(kubectl get namespaces -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase=="Terminating") | .metadata.name' 2>/dev/null || echo "")

        if [ -z "$STUCK_NAMESPACES" ]; then
            echo -e "${GREEN}✓ No stuck namespaces found${NC}"
            exit 0
        fi

        echo -e "${YELLOW}Found stuck namespaces:${NC}"
        echo "$STUCK_NAMESPACES" | while read ns; do
            echo "  - $ns"
        done
        echo ""

        # Clean each stuck namespace
        echo "$STUCK_NAMESPACES" | while read ns; do
            if [ -n "$ns" ]; then
                echo -e "${YELLOW}→ Fixing stuck namespace: $ns${NC}"

                # Step 1: Remove finalizers from all resources in namespace
                echo -e "${BLUE}  Removing resource finalizers...${NC}"
                for resource in applications.argoproj.io appprojects.argoproj.io pods jobs deployments statefulsets services pvc configmaps secrets; do
                    kubectl get $resource -n $ns -o name 2>/dev/null | while read obj; do
                        kubectl patch $obj -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    done
                done

                # Step 2: Force delete remaining resources
                echo -e "${BLUE}  Force deleting resources...${NC}"
                kubectl delete all --all -n $ns --force --grace-period=0 2>/dev/null || true

                # Step 3: Remove namespace finalizers
                echo -e "${BLUE}  Removing namespace finalizers...${NC}"
                kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

                # Step 4: Use finalize API endpoint
                echo -e "${BLUE}  Calling finalize API...${NC}"
                kubectl get namespace $ns -o json 2>/dev/null | \
                    jq '.spec.finalizers=[]' | \
                    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true

                sleep 2

                # Check result
                if kubectl get namespace $ns &>/dev/null; then
                    echo -e "${YELLOW}  ⚠ Namespace still exists (may need more time)${NC}"
                else
                    echo -e "${GREEN}  ✓ Namespace deleted${NC}"
                fi
            fi
        done

        echo ""

        # Final verification
        sleep 3
        REMAINING=$(kubectl get namespaces -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase=="Terminating") | .metadata.name' 2>/dev/null || echo "")

        if [ -z "$REMAINING" ]; then
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}✓ All stuck namespaces cleaned!${NC}"
            echo -e "${GREEN}========================================${NC}"
            exit 0
        else
            echo -e "${YELLOW}========================================${NC}"
            echo -e "${YELLOW}⚠ Some namespaces still stuck:${NC}"
            echo "$REMAINING" | sed 's/^/   - /'
            echo -e "${YELLOW}========================================${NC}"
            echo ""
            echo "Try running again or wait a few seconds."
            exit 1
        fi
    fi
    # ===========================================================================
    # END STUCK-ONLY MODE
    # ===========================================================================

    echo -e "${YELLOW}This will clean up the '${ENV}' environment:${NC}"
    echo ""
    echo -e "${YELLOW}Namespaces to be removed:${NC}"
    echo "  - argocd"
    echo "  - $FINERACT_NAMESPACE"
    echo "  - ingress-nginx"
    echo "  - cert-manager"
    echo "  - monitoring"
    echo "  - logging"
    echo ""
    echo -e "${YELLOW}It will also remove from kube-system:${NC}"
    echo "  - Sealed Secrets Controller"
    echo "  - Sealed Secrets encryption keys"
    echo ""
    echo -e "${YELLOW}Optional: Clean RDS databases for fresh deployment${NC}"
    echo "  - keycloak database (if prompted)"
    echo "  - fineract_default database (if prompted)"
    echo ""

    if [ "$FORCE_MODE" = false ]; then
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Cleanup cancelled${NC}"
            exit 0
        fi
    else
        echo -e "${BLUE}[Force mode] Proceeding with cleanup...${NC}"
    fi

    echo ""

    # Step 0.5: Cleanup RDS databases (optional, before deleting namespaces)
    if [ "$SKIP_DB_CLEANUP" = false ]; then
        cleanup_rds_databases
    else
        echo -e "${BLUE}→ Skipping database cleanup (--skip-db flag)${NC}"
    fi
    echo ""

    # Step 1: Delete ArgoCD Applications first (removes finalizers)
    delete_argocd_applications
    echo ""

    # Step 1.5: Cleanup Sealed Secrets from kube-system
    cleanup_sealed_secrets
    echo ""

    # Step 1.6: Cleanup Reloader from kube-system
    cleanup_reloader
    echo ""

    # Step 1.7: Cleanup cluster-scoped resources
    cleanup_cluster_scoped_resources
    echo ""

    # Step 1.75: Run pre-cleanup diagnostics for all target namespaces
    echo -e "${BLUE}→ Pre-cleanup diagnostics for target namespaces...${NC}"
    echo ""
    NAMESPACES=("argocd" "$FINERACT_NAMESPACE" "ingress-nginx" "cert-manager" "monitoring" "logging")
    for ns in "${NAMESPACES[@]}"; do
        status=$(check_namespace_stuck $ns)
        if [ "$status" != "notfound" ]; then
            echo -e "${BLUE}  Namespace: $ns (status: $status)${NC}"
            check_blocking_resources "$ns"
        fi
    done
    echo ""

    # Step 2: Check and cleanup each namespace
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
    echo "     ${BLUE}make destroy ENV=${ENV}${NC}"
    echo ""
    echo "  2. Deploy fresh infrastructure:"
    echo "     ${BLUE}make deploy-infrastructure-${ENV}${NC}"
    echo "     ${BLUE}aws eks update-kubeconfig --region eu-central-1 --name fineract-${ENV}-eks${NC}"
    echo "     ${BLUE}make deploy-k8s-with-loadbalancer-dns-${ENV}${NC}"
    echo "     ${BLUE}make deploy-gitops ENV=${ENV}${NC}"
    echo ""
    exit 0
fi
