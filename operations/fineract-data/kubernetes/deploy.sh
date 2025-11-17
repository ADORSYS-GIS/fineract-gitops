#!/bin/bash
# Deploy Fineract Data Loader Jobs to Kubernetes

set -e

echo "====================================="
echo "Fineract Data Loader Deployment"
echo "====================================="

# Check if we're in the correct directory
if [ ! -f "kustomization.yaml" ]; then
    echo "Error: Please run this script from the kubernetes/ directory"
    exit 1
fi

# Set namespace
NAMESPACE=${NAMESPACE:-fineract-dev}
echo "Deploying to namespace: $NAMESPACE"

# Generate data ConfigMap (optional - for large datasets)
if [ "$GENERATE_DATA_CONFIGMAP" = "true" ]; then
    echo "Generating data ConfigMap..."
    ./generate-data-configmap.sh
fi

# Build kustomization
echo "Building kustomization..."
kubectl kustomize . > /tmp/fineract-data-loader.yaml

# Apply resources
echo "Applying resources..."
kubectl apply -f /tmp/fineract-data-loader.yaml

# Monitor jobs
echo ""
echo "Monitoring job progress..."
echo "====================================="

# Function to check job status
check_jobs() {
    local wave=$1
    local jobs=$2

    echo ""
    echo "Wave $wave jobs:"
    for job in $jobs; do
        status=$(kubectl get job $job -n $NAMESPACE -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "NotFound")
        if [ "$status" = "Complete" ]; then
            echo "  ✓ $job - Complete"
        elif [ "$status" = "Failed" ]; then
            echo "  ✗ $job - Failed"
            kubectl logs job/$job -n $NAMESPACE | tail -20
        else
            echo "  ⌛ $job - Running/Pending"
        fi
    done
}

# Monitor each wave
while true; do
    clear
    echo "Job Status Monitor (Ctrl+C to exit)"
    echo "====================================="

    # Wave 1-3: Foundation
    check_jobs "1-3 (Foundation)" "fineract-data-code-values fineract-data-offices fineract-data-staff fineract-data-roles fineract-data-currency-config fineract-data-working-days"

    # Wave 10-12: Accounting
    check_jobs "10-12 (Accounting)" "fineract-data-chart-of-accounts fineract-data-tax-groups fineract-data-floating-rates"

    # Wave 15: Charges
    check_jobs "15 (Charges)" "fineract-data-charges"

    # Wave 20-21: Products
    check_jobs "20-21 (Products)" "fineract-data-loan-products fineract-data-savings-products fineract-data-savings-product-accounting fineract-data-financial-activity-mappings"

    # Check if all jobs are complete
    completed=$(kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/name=fineract-data-loader -o jsonpath='{.items[?(@.status.conditions[0].type=="Complete")].metadata.name}' | wc -w)
    total=$(kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/name=fineract-data-loader -o name | wc -l)

    echo ""
    echo "Progress: $completed / $total jobs completed"

    if [ "$completed" -eq "$total" ] && [ "$total" -gt 0 ]; then
        echo ""
        echo "✅ All jobs completed successfully!"
        break
    fi

    sleep 5
done

echo ""
echo "Deployment complete!"
echo ""
echo "To check logs for a specific job:"
echo "  kubectl logs job/fineract-data-<loader-name> -n $NAMESPACE"
echo ""
echo "To re-run a failed job:"
echo "  kubectl delete job fineract-data-<loader-name> -n $NAMESPACE"
echo "  kubectl apply -f jobs/job-<loader-name>.yaml"