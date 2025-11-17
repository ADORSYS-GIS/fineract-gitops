#!/usr/bin/env python3
"""
Working Days Loader
Loads working days into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class WorkingDaysLoader(BaseLoader):
    """Loader for Fineract Working Days"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Working Days YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        payload = {
            'recurrence': spec.get('recurrence'),
            'repaymentRescheduleType': spec.get('repaymentReschedulingType'),
            'extendTermForDailyRepayments': spec.get('extendTermForDailyRepayments', False),
            'locale': 'en'
        }

        return payload

    def load_all(self) -> dict:
        """
        Load all working days YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING WORKING DAYS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('**/*.yaml'))

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
            if yaml_data.get('kind') != 'WorkingDays':
                logger.warning(f"  Skipping (not WorkingDays): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})

            # Working days is a singleton - always update
            entity_name = "Working Days Configuration"

            logger.info(f"  Updating working days configuration...")

            # Update working days configuration (PUT operation)
            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.put('workingdays', api_payload)

            if response and 'changes' in response:
                logger.info(f"  ✓ Updated working days configuration")
                self.loaded_entities[entity_name] = 1
            elif response:
                logger.info(f"  ✓ Working days configuration applied")
                self.loaded_entities[entity_name] = 1
            else:
                logger.error(f"  ✗ Failed to update working days configuration")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Working Days into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = WorkingDaysLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
