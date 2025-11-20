#!/usr/bin/env python3
"""
Scheduler Jobs Loader
Updates scheduler job configuration in Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class SchedulerJobsLoader(BaseLoader):
    """Loader for Fineract Scheduler Jobs"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Scheduler Jobs YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Build payload for updating scheduler job
        payload = {
            'displayName': spec.get('displayName', spec.get('jobName')),
            'cronExpression': spec.get('cronExpression'),
            'active': spec.get('active', True),
        }

        return payload

    def load_all(self) -> dict:
        """
        Update all scheduler job configurations from YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING SCHEDULER JOBS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        for yaml_file in yaml_files:
            logger.info(f"\nProcessing: {yaml_file.name}")

            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind
            if yaml_data.get('kind') != 'SchedulerJob':
                logger.debug(f"  Skipping (not SchedulerJob): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            job_name = spec.get('jobName')  # SchedulerJob uses 'jobName' not 'name'

            if not job_name:
                logger.error(f"  Missing jobName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Find existing scheduler job by name
            existing_id = self.entity_exists('jobs', job_name, identifier_field='displayName')

            if not existing_id:
                logger.warning(f"  Scheduler job not found in Fineract: {job_name}")
                logger.warning(f"  Skipping (scheduler jobs are pre-configured in Fineract)")
                self.skipped_entities.append(job_name)
                continue

            # Update the scheduler job configuration
            logger.info(f"  Found existing scheduler job: {job_name} (ID: {existing_id})")

            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.put(f'jobs/{existing_id}', api_payload)

            if response:
                logger.info(f"  ✓ Updated scheduler job: {job_name} (ID: {existing_id})")
                self.updated_entities[job_name] = existing_id
            else:
                logger.error(f"  ✗ Failed to update scheduler job: {job_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Scheduler Jobs into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = SchedulerJobsLoader(args.yaml_dir, args.fineract_url, args.tenant)

    try:
        summary = loader.load_all()
        loader.print_summary()

        # Exit with error code if any failures
        if summary['total_failed'] > 0:
            sys.exit(1)
        else:
            sys.exit(0)

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
