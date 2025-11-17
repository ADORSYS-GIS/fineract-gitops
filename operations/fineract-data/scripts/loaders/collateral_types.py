#!/usr/bin/env python3
"""
Collateral Types Loader
Loads collateral types into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class CollateralTypesLoader(BaseLoader):
    """Loader for Fineract Collateral Types"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Collateral Types YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Map quality standards
        quality_map = {
            'GOOD': 1,
            'FAIR': 2,
            'POOR': 3
        }

        # Map unit types
        unit_type_map = {
            'SINGLE': 1,
            'MULTIPLE': 2,
            'PER_UNIT': 3
        }

        quality = spec.get('quality', 'GOOD').upper()
        unit_type = spec.get('unitType', 'SINGLE').upper()

        payload = {
            'name': spec.get('name'),
            'description': spec.get('description', ''),
            'currency': spec.get('currency', 'XAF'),
            'quality': quality_map.get(quality, 1),
            'unitType': unit_type_map.get(unit_type, 1),
            'locale': 'en'
        }

        # Add value limits if specified
        if 'basePrice' in spec:
            payload['basePrice'] = float(spec['basePrice'])
        if 'pctToBase' in spec:
            payload['pctToBase'] = float(spec['pctToBase'])

        return payload

    def load_all(self) -> dict:
        """
        Load all collateral types YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING COLLATERAL TYPES")
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
            if yaml_data.get('kind') != 'CollateralType':
                logger.warning(f"  Skipping (not CollateralType): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists
            existing_id = self.entity_exists('collateral-management', entity_name)

            if existing_id:
                logger.info(f"  Entity already exists: {entity_name} (ID: {existing_id})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity
            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.post('collateral-management', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created collateral types: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create collateral types: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Collateral Types into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = CollateralTypesLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
