#!/usr/bin/env python3
"""
Account Number Formats Loader
Creates or updates account number format preferences in Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class AccountNumberFormatsLoader(BaseLoader):
    """Loader for Fineract Account Number Formats"""

    def yaml_to_fineract_api(self, yaml_data: dict, is_update: bool = False) -> dict:
        """
        Convert Account Number Formats YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure
            is_update: Whether this is an update (excludes accountType)

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Map account types to Fineract entity IDs
        account_type_map = {
            'CLIENT': 1,
            'LOAN': 2,
            'SAVINGS': 3,
            'CENTERS': 4,
            'GROUPS': 5
        }

        # Map prefix types to Fineract IDs (from AccountNumberPrefixType enum)
        prefix_type_map = {
            'NONE': 1,
            'OFFICE NAME': 1,
            'CLIENT TYPE': 101,
            'LOAN PRODUCT SHORT NAME': 201,
            'SAVINGS PRODUCT SHORT NAME': 301,
            'PREFIX SHORT NAME': 401
        }

        account_type = spec.get('accountType', 'CLIENT').upper()
        prefix_type = spec.get('prefixType', 'NONE').upper()

        payload = {
            'prefixType': prefix_type_map.get(prefix_type, 1),
        }

        # accountType is only for CREATE, not UPDATE
        if not is_update:
            payload['accountType'] = account_type_map.get(account_type, 1)

        return payload

    def load_all(self) -> dict:
        """
        Load all account number format YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING ACCOUNT NUMBER FORMATS")
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
            if yaml_data.get('kind') != 'AccountNumberFormat':
                logger.debug(f"  Skipping (not AccountNumberFormat): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            # Use accountType as identifier since there's no 'name' field
            entity_name = spec.get('accountType')

            if not entity_name:
                logger.error(f"  Missing accountType in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists by accountType
            existing_id = self.entity_exists('accountnumberformats', entity_name, identifier_field='accountTypeName')

            if existing_id:
                logger.info(f"  Found existing format for {entity_name} (ID: {existing_id})")

                # Update existing format
                api_payload = self.yaml_to_fineract_api(yaml_data, is_update=True)
                response = self.put(f'accountnumberformats/{existing_id}', api_payload)

                if response:
                    logger.info(f"  ✓ Updated account number format: {entity_name} (ID: {existing_id})")
                    self.updated_entities[entity_name] = existing_id
                else:
                    logger.error(f"  ✗ Failed to update: {entity_name}")
                    self.failed_entities.append(yaml_file.name)
            else:
                # Create new format
                api_payload = self.yaml_to_fineract_api(yaml_data, is_update=False)
                response = self.post('accountnumberformats', api_payload)

                if response and 'resourceId' in response:
                    entity_id = response['resourceId']
                    logger.info(f"  ✓ Created account number format: {entity_name} (ID: {entity_id})")
                    self.loaded_entities[entity_name] = entity_id
                else:
                    logger.error(f"  ✗ Failed to create: {entity_name}")
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
        # Run pre-flight validation checks
        loader.validate_configuration()

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
