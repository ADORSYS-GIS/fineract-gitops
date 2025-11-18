#!/usr/bin/env python3
"""
Financial Activity Mappings Loader
Loads GL financial activity mappings into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class FinancialActivityMappingsLoader(BaseLoader):
    """Loader for Fineract Financial Activity Mappings"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Financial Activity Mappings YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Resolve financial activity ID from name
        activity_name = spec.get('financialActivityName')
        financial_activity_id = self._resolve_financial_activity(activity_name)

        if not financial_activity_id:
            logger.error(f"  Could not resolve financial activity: {activity_name}")
            return None

        # Resolve GL account
        gl_code = spec.get('glAccountCode')
        gl_account_id = self._resolve_gl_account(gl_code)

        if not gl_account_id:
            logger.error(f"  Could not resolve GL account: {gl_code}")
            return None

        # Build payload
        payload = {
            'financialActivityId': financial_activity_id,
            'glAccountId': gl_account_id
        }

        return payload

    def load_all(self) -> dict:
        """
        Load all GL financial activity mappings YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING FINANCIAL ACTIVITY MAPPINGS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Cache reference data
        logger.info("Caching reference data...")
        self._cache_reference_data()

        for yaml_file in yaml_files:
            logger.info(f"\nProcessing: {yaml_file.name}")

            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind
            if yaml_data.get('kind') != 'FinancialActivityMapping':
                logger.debug(f"  Skipping (not FinancialActivityMapping): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            activity_name = spec.get('financialActivityName')

            if not activity_name:
                logger.error(f"  Missing financialActivityName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if mapping already exists
            # Financial activity mappings are unique by financialActivityId
            financial_activity_id = self._resolve_financial_activity(activity_name)
            if financial_activity_id:
                # Check if this activity already has a mapping
                existing_mappings = self.get('financialactivityaccounts')
                if existing_mappings:
                    for mapping in existing_mappings:
                        if mapping.get('financialActivityData', {}).get('id') == financial_activity_id:
                            logger.info(f"  Mapping already exists for: {activity_name}")
                            self.loaded_entities[activity_name] = mapping.get('id')
                            continue

            # Create mapping
            api_payload = self.yaml_to_fineract_api(yaml_data)

            if not api_payload:
                logger.error(f"  Failed to build payload for: {activity_name}")
                self.failed_entities.append(yaml_file.name)
                continue

            response = self.post('financialactivityaccounts', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created financial activity mapping: {activity_name} (ID: {entity_id})")
                self.loaded_entities[activity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create financial activity mapping: {activity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Financial Activity Mappings into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = FinancialActivityMappingsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
