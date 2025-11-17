#!/usr/bin/env python3
"""
Code Generator for Fineract Data Loaders and Kubernetes Jobs

This script generates Python loader scripts and Kubernetes Job manifests
for all 44 Fineract entity types.

Usage:
    python3 generate_loaders_and_jobs.py [--dry-run]
"""

import argparse
from pathlib import Path
from typing import Dict, List
import textwrap


# Entity type definitions
# Format: (name, api_endpoint, yaml_kind, sync_wave, description)
ENTITY_TYPES = [
    # System Configuration (Sync Waves 1-14)
    ('code-values', 'codes', 'CodeValue', 1, 'dropdown code values'),
    ('offices', 'offices', 'Office', 2, 'branch offices'),
    ('staff', 'staff', 'Staff', 3, 'staff members'),
    ('roles', 'roles', 'Role', 4, 'roles and permissions'),
    ('currency-config', 'currencies', 'CurrencyConfig', 5, 'currency configuration'),
    ('working-days', 'workingdays', 'WorkingDays', 6, 'working days'),
    ('account-number-formats', 'accountnumberformats', 'AccountNumberFormat', 7, 'account number preferences'),
    ('maker-checker', 'makercheckers', 'MakerChecker', 8, 'maker checker configuration'),
    ('scheduler-jobs', 'jobs', 'SchedulerJob', 9, 'scheduler job configuration'),

    # Products (Sync Waves 10-20)
    ('loan-products', 'loanproducts', 'LoanProduct', 10, 'loan products'),
    ('notification-templates', 'templates', 'NotificationTemplate', 11, 'notification templates'),
    ('data-tables', 'datatables', 'DataTable', 12, 'custom data tables'),
    ('tellers', 'tellers', 'Teller', 13, 'teller configuration'),
    ('reports', 'reports', 'Report', 14, 'financial reports'),
    ('savings-products', 'savingsproducts', 'SavingsProduct', 15, 'savings products'),
    ('charges', 'charges', 'Charge', 16, 'fees and charges'),
    ('collateral-types', 'collateral-management', 'CollateralType', 17, 'collateral types'),
    ('guarantor-types', 'guarantors', 'GuarantorType', 18, 'guarantor types'),
    ('floating-rates', 'floatingrates', 'FloatingRate', 19, 'floating interest rates'),
    ('delinquency-buckets', 'delinquency/buckets', 'DelinquencyBucket', 20, 'delinquency buckets'),

    # Accounting (Sync Waves 21-29)
    ('chart-of-accounts', 'glaccounts', 'GLAccount', 21, 'chart of accounts'),
    ('fund-sources', 'funds', 'FundSource', 22, 'fund sources'),
    ('payment-types', 'paymenttypes', 'PaymentType', 23, 'payment types'),
    ('tax-groups', 'taxes/group', 'TaxGroup', 24, 'tax groups'),
    ('loan-provisioning', 'provisioningcriteria', 'LoanProvisioning', 25, 'loan provisioning criteria'),
    ('financial-activity-mappings', 'financialactivityaccounts', 'FinancialActivityMapping', 26, 'GL financial activity mappings'),
    ('loan-product-accounting', 'loanproducts', 'LoanProductAccounting', 27, 'loan product GL mappings'),
    ('savings-product-accounting', 'savingsproducts', 'SavingsProductAccounting', 28, 'savings product GL mappings'),
    ('payment-type-accounting', 'paymenttypes', 'PaymentTypeAccounting', 29, 'payment type GL mappings'),

    # Demo Data - Entities (Sync Waves 30-34, dev/uat only)
    ('demo-clients', 'clients', 'Client', 30, 'demo client accounts'),
    ('demo-savings-accounts', 'savingsaccounts', 'SavingsAccount', 31, 'demo savings accounts'),
    ('demo-loan-accounts', 'loans', 'LoanAccount', 32, 'demo loan accounts'),
    ('demo-loan-collateral', 'loans', 'LoanCollateral', 33, 'demo loan collateral'),
    ('demo-loan-guarantors', 'loans', 'LoanGuarantor', 34, 'demo loan guarantors'),

    # Demo Data - Transactions (Sync Waves 35-39, dev/uat only)
    ('demo-savings-deposits', 'savingsaccounts', 'SavingsDeposit', 35, 'demo savings deposits'),
    ('demo-savings-withdrawals', 'savingsaccounts', 'SavingsWithdrawal', 36, 'demo savings withdrawals'),
    ('demo-loan-repayments', 'loans', 'LoanRepayment', 37, 'demo loan repayments'),
    ('demo-loan-disbursements', 'loans', 'LoanDisbursement', 38, 'demo loan disbursements'),
    ('demo-transfers', 'accounttransfers', 'AccountTransfer', 39, 'demo account transfers'),

    # Calendar (Sync Wave 40)
    ('holidays', 'holidays', 'Holiday', 40, 'holidays and non-working days'),
]


LOADER_TEMPLATE = '''#!/usr/bin/env python3
"""
{title} Loader
Loads {description} into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class {class_name}Loader(BaseLoader):
    """Loader for Fineract {title}"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert {title} YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {{}})

        # Basic payload - customize based on Fineract API requirements
        payload = {{
            'name': spec.get('name'),
            'description': spec.get('description', ''),
            'dateFormat': 'yyyy-MM-dd',
            'locale': 'en'
        }}

        # Add entity-specific fields here as needed

        return payload

    def load_all(self) -> dict:
        """
        Load all {description} YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING {upper_title}")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('**/*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {{self.yaml_dir}}")
            return self.get_summary()

        for yaml_file in yaml_files:
            logger.info(f"\\nProcessing: {{yaml_file.name}}")

            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind
            if yaml_data.get('kind') != '{yaml_kind}':
                logger.warning(f"  Skipping (not {yaml_kind}): {{yaml_file.name}}")
                continue

            spec = yaml_data.get('spec', {{}})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists
            existing_id = self.entity_exists('{api_endpoint}', entity_name)

            if existing_id:
                logger.info(f"  Entity already exists: {{entity_name}} (ID: {{existing_id}})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity
            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.post('{api_endpoint}', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created {description}: {{entity_name}} (ID: {{entity_id}})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create {description}: {{entity_name}}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load {title} into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = {class_name}Loader(args.yaml_dir, args.fineract_url, args.tenant)

    try:
        summary = loader.load_all()
        loader.print_summary()

        # Exit with error code if any failures
        if summary['total_failed'] > 0:
            sys.exit(1)
        else:
            sys.exit(0)

    except Exception as e:
        logger.error(f"Fatal error: {{e}}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
'''


JOB_TEMPLATE = '''apiVersion: batch/v1
kind: Job
metadata:
  name: load-{name}
  labels:
    app: fineract-data-loader
    job-type: {job_type}
    load-order: "{sync_wave:02d}"
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "{sync_wave}"
spec:
  ttlSecondsAfterFinished: 3600  # Keep for 1 hour for debugging
  backoffLimit: 3
  template:
    metadata:
      labels:
        app: fineract-data-loader
    spec:
      restartPolicy: OnFailure

      initContainers:
      # Wait for Fineract to be ready
      - name: wait-for-fineract
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          echo "Waiting for Fineract write instance to be ready..."
          until wget -q -O- http://fineract-write-service:8080/fineract-provider/actuator/health/readiness | grep -q UP; do
            echo "Fineract not ready yet, waiting 10s..."
            sleep 10
          done
          echo "Fineract is ready!"

      containers:
      - name: {name}-loader
        image: python:3.11-slim
        command:
        - python3
        - /scripts/loaders/{loader_file}
        - --yaml-dir
        - /data/{name}
        - --fineract-url
        - http://fineract-write-service:8080/fineract-provider/api/v1
        - --tenant
        - default

        env:
        # OAuth2 Client Credentials (preferred authentication method)
        - name: FINERACT_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: fineract-admin-credentials
              key: client-id
        - name: FINERACT_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: fineract-admin-credentials
              key: client-secret
        - name: FINERACT_TOKEN_URL
          valueFrom:
            secretKeyRef:
              name: fineract-admin-credentials
              key: token-url

        volumeMounts:
        - name: loader-scripts
          mountPath: /scripts
        - name: {name}-data
          mountPath: /data/{name}

        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"

      volumes:
      - name: loader-scripts
        configMap:
          name: fineract-loader-scripts
      - name: {name}-data
        configMap:
          name: {name}-data
'''


def to_class_name(name: str) -> str:
    """Convert kebab-case to PascalCase"""
    return ''.join(word.capitalize() for word in name.split('-'))


def generate_loader(name: str, api_endpoint: str, yaml_kind: str, description: str, output_dir: Path) -> Path:
    """Generate a Python loader script"""
    class_name = to_class_name(name)
    title = name.replace('-', ' ').title()
    upper_title = name.upper().replace('-', ' ')

    content = LOADER_TEMPLATE.format(
        title=title,
        description=description,
        class_name=class_name,
        upper_title=upper_title,
        yaml_kind=yaml_kind,
        api_endpoint=api_endpoint,
        name=name
    )

    loader_file = output_dir / f"{name.replace('-', '_')}.py"
    loader_file.write_text(content)
    loader_file.chmod(0o755)  # Make executable

    return loader_file


def generate_job(name: str, sync_wave: int, output_dir: Path) -> Path:
    """Generate a Kubernetes Job manifest"""
    # Determine job type based on sync wave
    if sync_wave <= 14:
        job_type = "system-config"
    elif sync_wave <= 29:
        job_type = "configuration"
    elif sync_wave <= 39:
        job_type = "demo-data"
    else:
        job_type = "calendar"

    loader_file = name.replace('-', '_') + '.py'

    content = JOB_TEMPLATE.format(
        name=name,
        sync_wave=sync_wave,
        job_type=job_type,
        loader_file=loader_file
    )

    job_file = output_dir / f"{sync_wave:02d}-load-{name}.yaml"
    job_file.write_text(content)

    return job_file


def main():
    parser = argparse.ArgumentParser(description='Generate Fineract data loaders and jobs')
    parser.add_argument('--dry-run', action='store_true', help='Print what would be generated without creating files')
    parser.add_argument('--loaders-dir', default='loaders', help='Output directory for loader scripts')
    parser.add_argument('--jobs-dir', default='../jobs/base', help='Output directory for job manifests')

    args = parser.parse_args()

    # Get absolute paths
    script_dir = Path(__file__).parent
    loaders_dir = (script_dir / args.loaders_dir).resolve()
    jobs_dir = (script_dir / args.jobs_dir).resolve()

    print("=" * 80)
    print("FINERACT DATA OPERATIONS CODE GENERATOR")
    print("=" * 80)
    print(f"\\nLoaders output: {loaders_dir}")
    print(f"Jobs output: {jobs_dir}")
    print(f"Total entity types: {len(ENTITY_TYPES)}")
    print(f"Dry run: {args.dry_run}\\n")

    if not args.dry_run:
        loaders_dir.mkdir(parents=True, exist_ok=True)
        jobs_dir.mkdir(parents=True, exist_ok=True)

    generated_loaders = []
    generated_jobs = []
    skipped = []

    for name, api_endpoint, yaml_kind, sync_wave, description in ENTITY_TYPES:
        print(f"\\n[{sync_wave:02d}] {name}")
        print(f"    API: {api_endpoint}, Kind: {yaml_kind}")
        print(f"    Description: {description}")

        loader_file = loaders_dir / f"{name.replace('-', '_')}.py"
        job_file = jobs_dir / f"{sync_wave:02d}-load-{name}.yaml"

        # Skip if files already exist
        if loader_file.exists() and job_file.exists():
            print(f"    ⏭️  Skipped (files already exist)")
            skipped.append(name)
            continue

        if args.dry_run:
            print(f"    Would create:")
            print(f"      - {loader_file.name}")
            print(f"      - {job_file.name}")
        else:
            # Generate loader
            if not loader_file.exists():
                generated_loader = generate_loader(name, api_endpoint, yaml_kind, description, loaders_dir)
                print(f"    ✓ Created loader: {generated_loader.name}")
                generated_loaders.append(generated_loader)

            # Generate job
            if not job_file.exists():
                generated_job = generate_job(name, sync_wave, jobs_dir)
                print(f"    ✓ Created job: {generated_job.name}")
                generated_jobs.append(generated_job)

    # Summary
    print("\\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Loaders generated: {len(generated_loaders)}")
    print(f"Jobs generated: {len(generated_jobs)}")
    print(f"Skipped (already exist): {len(skipped)}")
    print(f"\\nTotal entity types: {len(ENTITY_TYPES)}")

    if not args.dry_run and (generated_loaders or generated_jobs):
        print("\\n" + "=" * 80)
        print("NEXT STEPS")
        print("=" * 80)
        print("\\n1. Review generated files:")
        print(f"   ls -lh {loaders_dir}")
        print(f"   ls -lh {jobs_dir}")
        print("\\n2. Customize yaml_to_fineract_api() in each loader based on Fineract API docs")
        print("\\n3. Create sample YAML data files for each entity type")
        print("\\n4. Test loaders locally:")
        print("   python3 loaders/<entity>_loader.py --yaml-dir=../data/dev/<entity> --fineract-url=http://localhost:8080/fineract-provider/api/v1")
        print("\\n5. Update jobs/base/kustomization.yaml to include new jobs")
        print("\\n6. Commit to Git:")
        print("   git add loaders/ jobs/")
        print("   git commit -m 'feat: add complete data operations for all 44 entity types'")


if __name__ == '__main__':
    main()
