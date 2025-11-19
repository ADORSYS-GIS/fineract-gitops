#!/usr/bin/env python3
"""
Run fineract-data loader jobs sequentially to avoid resource exhaustion.
"""

import subprocess
import time
import sys
import yaml
from pathlib import Path

KUBECONFIG = "/Users/guymoyo/.kube/config-fineract-dev"
NAMESPACE = "fineract-dev"
KUSTOMIZE_DIR = "/Users/guymoyo/dev/fineract-gitops/operations/fineract-data"

# Jobs in order of sync wave
JOBS = [
    ("fineract-data-system-foundation", 5),
    ("fineract-data-products", 10),
    ("fineract-data-accounting", 21),
    ("fineract-data-entities", 30),
    ("fineract-data-transactions", 35),
    ("fineract-data-calendar", 40),
]

def run_cmd(cmd, check=True):
    """Run a shell command and return the output."""
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True,
        env={"KUBECONFIG": KUBECONFIG}
    )
    if check and result.returncode != 0:
        print(f"Error running command: {cmd}")
        print(f"stdout: {result.stdout}")
        print(f"stderr: {result.stderr}")
        sys.exit(1)
    return result.stdout, result.stderr

def wait_for_job(job_name, timeout=600):
    """Wait for a job to complete (success or failure)."""
    print(f"Waiting for job {job_name} to complete (timeout {timeout}s)...")
    start_time = time.time()

    while time.time() - start_time < timeout:
        # Get job status
        stdout, _ = run_cmd(
            f"kubectl get job {job_name} -n {NAMESPACE} -o jsonpath='{{.status.conditions[0].type}}{{\"\\n\"}}{{.status.succeeded}}{{\"\\n\"}}{{.status.failed}}'",
            check=False
        )

        lines = stdout.strip().split("\n")
        if len(lines) >= 3:
            condition = lines[0]
            succeeded = lines[1]
            failed = lines[2]

            if succeeded == "1":
                print(f"✓ Job {job_name} completed successfully")
                return True
            elif failed and failed != "":
                print(f"✗ Job {job_name} failed")
                # Show logs
                stdout, _ = run_cmd(
                    f"kubectl logs -n {NAMESPACE} -l job-name={job_name} --tail=50",
                    check=False
                )
                print(f"Logs:\n{stdout}")
                return False

        time.sleep(10)

    print(f"✗ Job {job_name} timed out after {timeout}s")
    return False

def apply_configmaps():
    """Apply ConfigMaps first using kustomize."""
    print("Applying ConfigMaps...")
    stdout, _ = run_cmd(
        f"cd {KUSTOMIZE_DIR} && kustomize build . | kubectl apply -f - --dry-run=client -o yaml | grep 'kind: ConfigMap' -A 100"
    )
    # Apply only configmaps
    run_cmd(
        f"cd {KUSTOMIZE_DIR} && kustomize build . | kubectl apply -f - --selector='!batch.kubernetes.io/job-name'"
    )
    print("ConfigMaps applied")

def apply_job(job_name):
    """Apply a single job using kustomize and filtering."""
    print(f"\nApplying job {job_name}...")

    # Build kustomize and filter for specific job
    build_cmd = f"cd {KUSTOMIZE_DIR} && kustomize build ."
    stdout, _ = run_cmd(build_cmd)

    # Parse YAML and find the specific job
    docs = yaml.safe_load_all(stdout)
    for doc in docs:
        if doc and doc.get("kind") == "Job" and doc.get("metadata", {}).get("name") == job_name:
            # Apply this job
            job_yaml = yaml.dump(doc)
            apply_cmd = f"echo '{job_yaml}' | kubectl apply -f -"
            run_cmd(apply_cmd)
            print(f"Job {job_name} applied")
            return True

    print(f"Job {job_name} not found in kustomize output")
    return False

def main():
    print("Starting sequential fineract-data job execution...")
    print(f"Kustomize directory: {KUSTOMIZE_DIR}")
    print(f"Namespace: {NAMESPACE}")
    print()

    # First, apply ConfigMaps and RBAC
    print("Step 1: Applying ConfigMaps and RBAC...")
    run_cmd(f"cd {KUSTOMIZE_DIR} && kustomize build . | kubectl apply -f -")

    # Wait a bit for configmaps to be ready
    time.sleep(5)

    # Delete any existing jobs
    print("\nStep 2: Cleaning up existing jobs...")
    for job_name, _ in JOBS:
        run_cmd(f"kubectl delete job {job_name} -n {NAMESPACE} --ignore-not-found=true")

    time.sleep(5)

    # Run jobs sequentially
    print("\nStep 3: Running jobs sequentially...")
    for job_name, wave in JOBS:
        print(f"\n{'='*60}")
        print(f"Wave {wave}: {job_name}")
        print('='*60)

        if not apply_job(job_name):
            print(f"Failed to apply job {job_name}")
            sys.exit(1)

        if not wait_for_job(job_name, timeout=600):
            print(f"Job {job_name} did not complete successfully")
            sys.exit(1)

        # Wait a bit between jobs
        time.sleep(5)

    print("\n" + "="*60)
    print("All jobs completed successfully!")
    print("="*60)

if __name__ == "__main__":
    main()
