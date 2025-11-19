#!/usr/bin/env python3
"""
Payment Type Accounting Loader
Loads payment type GL mappings into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class PaymentTypeAccountingLoader(BaseLoader):
    """Loader for Fineract Payment Type Accounting"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Payment Type Accounting YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Basic payload - customize based on Fineract API requirements
        payload = {
            'name': spec.get('name'),
            'description': spec.get('description', ''),
            'dateFormat': 'yyyy-MM-dd',
            'locale': 'en'
        }

        # Add entity-specific fields here

        return payload

    def load_all(self) -> dict:
        """
        Load all payment type GL mappings YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING PAYMENT TYPE ACCOUNTING")
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
            if yaml_data.get('kind') != 'PaymentTypeAccounting':
                logger.debug(f"  Skipping (not PaymentTypeAccounting): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists
            existing_id = self.entity_exists('paymenttypes', entity_name)

            if existing_id:
                logger.info(f"  Entity already exists: {entity_name} (ID: {existing_id})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity
            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.post('paymenttypes', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created payment type GL mappings: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create payment type GL mappings: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Payment Type Accounting into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = PaymentTypeAccountingLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
