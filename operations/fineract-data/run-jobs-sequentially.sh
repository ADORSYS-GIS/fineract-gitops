#!/bin/bash
#
# Run fineract-data loader jobs sequentially to avoid resource exhaustion.
#

set -e

KUBECONFIG="/Users/guymoyo/.kube/config-fineract-dev"
NAMESPACE="fineract-dev"
KUSTOMIZE_DIR="/Users/guymoyo/dev/fineract-gitops/operations/fineract-data"

export KUBECONFIG

# Jobs in order of sync wave
declare -a JOBS=(
    "fineract-data-system-foundation:5"
    "fineract-data-products:10"
    "fineract-data-accounting:21"
    "fineract-data-entities:30"
    "fineract-data-transactions:35"
    "fineract-data-calendar:40"
)

wait_for_job() {
    local job_name=$1
    local timeout=${2:-600}
    local start_time=$(date +%s)

    echo "Waiting for job $job_name to complete (timeout ${timeout}s)..."

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -gt $timeout ]; then
            echo "✗ Job $job_name timed out after ${timeout}s"
            return 1
        fi

        # Check job status
        local status=$(kubectl get job $job_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        local failed=$(kubectl get job $job_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")

        if [ "$status" == "True" ]; then
            echo "✓ Job $job_name completed successfully"
            return 0
        elif [ "$failed" == "True" ]; then
            echo "✗ Job $job_name failed"
            echo "Logs:"
            kubectl logs -n $NAMESPACE -l job-name=$job_name --tail=50
            return 1
        fi

        sleep 10
    done
}

echo "Starting sequential fineract-data job execution..."
echo "Kustomize directory: $KUSTOMIZE_DIR"
echo "Namespace: $NAMESPACE"
echo

# Step 1: Apply everything first (ConfigMaps, RBAC, Jobs)
echo "Step 1: Applying all resources..."
cd "$KUSTOMIZE_DIR"
kustomize build . | kubectl apply -f -
echo

# Wait for ConfigMaps to be ready
sleep 5

# Step 2: Delete all jobs
echo "Step 2: Deleting all existing jobs..."
for job_entry in "${JOBS[@]}"; do
    job_name="${job_entry%%:*}"
    kubectl delete job $job_name -n $NAMESPACE --ignore-not-found=true
done
echo

sleep 5

# Step 3: Run jobs sequentially
echo "Step 3: Running jobs sequentially..."
for job_entry in "${JOBS[@]}"; do
    job_name="${job_entry%%:*}"
    wave="${job_entry##*:}"

    echo
    echo "============================================================"
    echo "Wave $wave: $job_name"
    echo "============================================================"

    # Extract just this job from the kustomize build and apply it
    cd "$KUSTOMIZE_DIR"
    kustomize build . | kubectl apply -f - --selector="batch.kubernetes.io/job-name=$job_name" 2>/dev/null || true

    # Alternative: Apply using resource name
    kubectl get job $job_name -n $NAMESPACE >/dev/null 2>&1 || {
        # Job doesn't exist, create it
        kustomize build . | \
            python3 -c "import yaml; import sys; docs = list(yaml.safe_load_all(sys.stdin)); [print(yaml.dump(d)) for d in docs if d and d.get('kind') == 'Job' and d.get('metadata', {}).get('name') == '$job_name']" | \
            kubectl apply -f -
    }

    if ! wait_for_job "$job_name" 600; then
        echo "Job $job_name did not complete successfully"
        exit 1
    fi

    # Wait a bit between jobs
    sleep 5
done

echo
echo "============================================================"
echo "All jobs completed successfully!"
echo "============================================================"
