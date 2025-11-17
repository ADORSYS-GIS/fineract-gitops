#!/usr/bin/env python3
"""
Tax Groups Loader
Loads tax groups into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class TaxGroupsLoader(BaseLoader):
    """Loader for Fineract Tax Groups"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        self.account_type_map = {
            'Asset': 1,
            'Liability': 2,
            'Equity': 3,
            'Income': 4,
            'Expense': 5
        }

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Tax Groups YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Build tax components array
        tax_components = []
        for component in spec.get('taxComponents', []):
            # Resolve GL account
            gl_code = component.get('creditGLCode')
            gl_account_id = self._resolve_gl_account(gl_code)

            if not gl_account_id:
                logger.warning(f"  Could not resolve GL code: {gl_code}")
                continue

            tax_component = {
                'name': component.get('name'),
                'percentage': component.get('percentage'),
                'creditAccountType': self.account_type_map.get(component.get('creditAccountType')),
                'creditAcountId': gl_account_id,  # Note: Fineract API has typo "Acount"
                'startDate': self._format_date(component.get('startDate')),
                'dateFormat': 'yyyy-MM-dd',
                'locale': 'en'
            }

            tax_components.append(tax_component)

        # Build payload
        payload = {
            'name': spec.get('name'),
            'taxComponents': tax_components,
            'dateFormat': 'yyyy-MM-dd',
            'locale': 'en'
        }

        return payload

    def load_all(self) -> dict:
        """
        Load all tax groups YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING TAX GROUPS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('**/*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Cache GL accounts for reference resolution
        logger.info("Caching reference data...")
        self._cache_reference_data()

        for yaml_file in yaml_files:
            logger.info(f"\nProcessing: {yaml_file.name}")

            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind
            if yaml_data.get('kind') != 'TaxGroup':
                logger.warning(f"  Skipping (not TaxGroup): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists
            existing_id = self.entity_exists('taxes/group', entity_name)

            if existing_id:
                logger.info(f"  Entity already exists: {entity_name} (ID: {existing_id})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Validate we have tax components
            if not api_payload.get('taxComponents'):
                logger.error(f"  No valid tax components found for: {entity_name}")
                self.failed_entities.append(yaml_file.name)
                continue

            response = self.post('taxes/group', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created tax group: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create tax group: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Tax Groups into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = TaxGroupsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
