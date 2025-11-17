#!/usr/bin/env python3
"""
Account Number Formats Loader
Loads account number preferences into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class AccountNumberFormatsLoader(BaseLoader):
    """Loader for Fineract Account Number Formats"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Account Number Formats YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Map account types
        account_type_map = {
            'CLIENT': 1,
            'LOAN': 2,
            'SAVINGS': 3,
            'CENTER': 4,
            'GROUP': 5
        }

        # Map prefix types
        prefix_type_map = {
            'NONE': 1,
            'OFFICE_NAME': 2,
            'CLIENT_TYPE': 3,
            'LOAN_PRODUCT_SHORT_NAME': 4
        }

        account_type = spec.get('accountType', 'CLIENT').upper()
        prefix_type = spec.get('prefixType', 'NONE').upper()

        payload = {
            'accountType': account_type_map.get(account_type, 1),
            'prefixType': prefix_type_map.get(prefix_type, 1),
            'locale': 'en'
        }

        # Add optional fields
        if 'startingValue' in spec:
            payload['startingValue'] = spec['startingValue']

        return payload

    def load_all(self) -> dict:
        """
        Load all account number preferences YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING ACCOUNT NUMBER FORMATS")
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
            if yaml_data.get('kind') != 'AccountNumberFormat':
                logger.warning(f"  Skipping (not AccountNumberFormat): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists
            existing_id = self.entity_exists('accountnumberformats', entity_name)

            if existing_id:
                logger.info(f"  Entity already exists: {entity_name} (ID: {existing_id})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity
            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.post('accountnumberformats', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created account number preferences: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create account number preferences: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Account Number Formats into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = AccountNumberFormatsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
