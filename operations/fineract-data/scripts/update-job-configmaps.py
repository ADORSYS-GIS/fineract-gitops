#!/usr/bin/env python3
"""
Update Job ConfigMap References

This script updates all job YAML files to reference their specific ConfigMaps
instead of the monolithic fineract-data-dev ConfigMap.

Usage:
    python3 update-job-configmaps.py [--dry-run]
"""

import argparse
from pathlib import Path
import sys
import re


# Mapping: job-file-name -> configmap-name
JOB_CONFIGMAP_MAPPING = {
    'job-code-values.yaml': 'fineract-data-code-values',
    'job-offices.yaml': 'fineract-data-offices',
    'job-staff.yaml': 'fineract-data-staff',
    'job-roles.yaml': 'fineract-data-roles',
    'job-currency-config.yaml': 'fineract-data-currency-config',
    'job-working-days.yaml': 'fineract-data-working-days',
    'job-account-number-formats.yaml': 'fineract-data-account-number-formats',
    'job-maker-checker.yaml': 'fineract-data-maker-checker',
    'job-scheduler-jobs.yaml': 'fineract-data-scheduler-jobs',
    'job-loan-products.yaml': 'fineract-data-loan-products',
    'job-notification-templates.yaml': 'fineract-data-notification-templates',
    'job-data-tables.yaml': 'fineract-data-data-tables',
    'job-tellers.yaml': 'fineract-data-tellers',
    'job-reports.yaml': 'fineract-data-reports',
    'job-savings-products.yaml': 'fineract-data-savings-products',
    'job-charges.yaml': 'fineract-data-charges',
    'job-collateral-types.yaml': 'fineract-data-collateral-types',
    'job-guarantor-types.yaml': 'fineract-data-guarantor-types',
    'job-floating-rates.yaml': 'fineract-data-floating-rates',
    'job-delinquency-buckets.yaml': 'fineract-data-delinquency-buckets',
    'job-chart-of-accounts.yaml': 'fineract-data-chart-of-accounts',
    'job-fund-sources.yaml': 'fineract-data-fund-sources',
    'job-payment-types.yaml': 'fineract-data-payment-types',
    'job-tax-groups.yaml': 'fineract-data-tax-groups',
    'job-loan-provisioning.yaml': 'fineract-data-loan-provisioning',
    'job-financial-activity-mappings.yaml': 'fineract-data-financial-activity-mappings',
    'job-loan-product-accounting.yaml': 'fineract-data-loan-product-accounting',
    'job-savings-product-accounting.yaml': 'fineract-data-savings-product-accounting',
    'job-payment-type-accounting.yaml': 'fineract-data-payment-type-accounting',
    'job-clients.yaml': 'fineract-data-clients',
    'job-savings-accounts.yaml': 'fineract-data-savings-accounts',
    'job-loan-accounts.yaml': 'fineract-data-loan-accounts',
    'job-loan-collateral.yaml': 'fineract-data-loan-collateral',
    'job-loan-guarantors.yaml': 'fineract-data-loan-guarantors',
    'job-savings-deposits.yaml': 'fineract-data-savings-deposits',
    'job-savings-withdrawals.yaml': 'fineract-data-savings-withdrawals',
    'job-loan-repayments.yaml': 'fineract-data-loan-repayments',
    'job-inter-branch-transfers.yaml': 'fineract-data-inter-branch-transfers',
    'job-holidays.yaml': 'fineract-data-holidays',
}


def update_job_configmap(job_file: Path, new_configmap_name: str, dry_run: bool = False) -> bool:
    """
    Update a job file to reference the new ConfigMap name

    Args:
        job_file: Path to the job YAML file
        new_configmap_name: New ConfigMap name to use
        dry_run: If True, don't write changes

    Returns:
        True if file was updated, False otherwise
    """
    content = job_file.read_text()

    # Pattern to match the data ConfigMap reference
    # Looking for:
    #       - name: data
    #         configMap:
    #           name: fineract-data-dev
    pattern = r'(      - name: data\n        configMap:\n          name: )fineract-data-dev'
    replacement = rf'\g<1>{new_configmap_name}'

    new_content, count = re.subn(pattern, replacement, content)

    if count == 0:
        return False

    if not dry_run:
        job_file.write_text(new_content)

    return True


def main():
    parser = argparse.ArgumentParser(
        description='Update job ConfigMap references to use separate ConfigMaps'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be changed without making changes'
    )

    args = parser.parse_args()

    # Determine paths
    script_dir = Path(__file__).parent
    fineract_data_dir = script_dir.parent
    jobs_dir = fineract_data_dir / 'kubernetes' / 'base' / 'jobs'

    print("=" * 80)
    print("JOB CONFIGMAP UPDATER")
    print("=" * 80)
    print(f"\nJobs directory: {jobs_dir}")
    print(f"Dry run: {args.dry_run}\n")

    if not jobs_dir.exists():
        print(f"ERROR: Jobs directory not found: {jobs_dir}")
        sys.exit(1)

    updated_jobs = []
    skipped_jobs = []
    not_found_jobs = []

    for job_filename, configmap_name in sorted(JOB_CONFIGMAP_MAPPING.items()):
        job_file = jobs_dir / job_filename

        if not job_file.exists():
            print(f"⚠️  {job_filename}: File not found")
            not_found_jobs.append(job_filename)
            continue

        was_updated = update_job_configmap(job_file, configmap_name, args.dry_run)

        if was_updated:
            action = "Would update" if args.dry_run else "✓ Updated"
            print(f"{action}: {job_filename}")
            print(f"           ConfigMap: fineract-data-dev → {configmap_name}")
            updated_jobs.append(job_filename)
        else:
            print(f"⏭️  {job_filename}: Already using separate ConfigMap or no match found")
            skipped_jobs.append(job_filename)

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Jobs updated: {len(updated_jobs)}")
    print(f"Jobs skipped: {len(skipped_jobs)}")
    print(f"Jobs not found: {len(not_found_jobs)}")

    if not args.dry_run and updated_jobs:
        print("\n" + "=" * 80)
        print("NEXT STEPS")
        print("=" * 80)
        print("\n1. Review the changes:")
        print(f"   git diff {jobs_dir}")
        print("\n2. Test with kustomize build:")
        print(f"   cd {fineract_data_dir} && kustomize build . | grep -A 5 'kind: ConfigMap'")
        print("\n3. Apply the new kustomization.yaml:")
        print(f"   mv {fineract_data_dir}/kustomization-new.yaml {fineract_data_dir}/kustomization.yaml")
        print("\n4. Verify the configuration:")
        print(f"   cd {fineract_data_dir} && kustomize build . | grep 'kind: ConfigMap' | wc -l")
        print("   (Should show ~35 ConfigMaps)")
        print("\n5. Commit the changes:")
        print("   git add operations/fineract-data/")
        print("   git commit -m 'feat: split fineract-data into separate ConfigMaps per entity'")


if __name__ == '__main__':
    main()
