#!/usr/bin/env python3
"""
Chart Of Accounts Loader
Loads chart of accounts into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class ChartOfAccountsLoader(BaseLoader):
    """Loader for Fineract Chart Of Accounts"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        self.gl_account_type_map = {
            'Asset': 1,
            'Liability': 2,
            'Equity': 3,
            'Income': 4,
            'Expense': 5
        }
        self.usage_map = {
            'Detail': 1,
            'Header': 2
        }

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Chart Of Accounts YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Build payload
        payload = {
            'name': spec.get('name'),
            'glCode': spec.get('glCode'),
            'type': self.gl_account_type_map.get(spec.get('type')),
            'usage': self.usage_map.get(spec.get('usage')),
            'manualEntriesAllowed': spec.get('manualEntriesAllowed', True),
            'description': spec.get('description', '')
        }

        # Optional: parent account (by GL code)
        parent_gl_code = spec.get('parentGLCode')
        if parent_gl_code:
            parent_id = self._resolve_gl_account(parent_gl_code)
            if parent_id:
                payload['parentId'] = parent_id
            else:
                logger.warning(f"  Could not resolve parent GL code: {parent_gl_code}")

        # Optional: tag
        tag_name = spec.get('tag')
        if tag_name:
            # Tags are usually numeric IDs in Fineract
            # For now, skip tags as they need separate resolution
            pass

        return payload

    def load_all(self) -> dict:
        """
        Load all chart of accounts YAML files
        Uses multi-pass loading to handle hierarchical relationships

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING CHART OF ACCOUNTS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Cache existing GL accounts for reference resolution
        logger.info("Caching reference data...")
        self._cache_reference_data()

        # Load all YAML files and separate by parent relationships
        accounts_with_parents = []
        accounts_without_parents = []

        for yaml_file in yaml_files:
            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind
            if yaml_data.get('kind') != 'GLAccount':
                continue

            spec = yaml_data.get('spec', {})
            if spec.get('parentGLCode'):
                accounts_with_parents.append((yaml_file, yaml_data))
            else:
                accounts_without_parents.append((yaml_file, yaml_data))

        # First pass: Load accounts without parents
        logger.info("\n" + "=" * 80)
        logger.info("PASS 1: Loading accounts without parent relationships")
        logger.info("=" * 80)

        for yaml_file, yaml_data in accounts_without_parents:
            self._load_account(yaml_file, yaml_data)

        # Refresh cache after first pass
        self._cache_reference_data()

        # Second pass: Load accounts with parents (may need multiple passes)
        logger.info("\n" + "=" * 80)
        logger.info("PASS 2: Loading accounts with parent relationships")
        logger.info("=" * 80)

        max_passes = 5
        remaining_accounts = accounts_with_parents

        for pass_num in range(2, max_passes + 2):
            if not remaining_accounts:
                break

            logger.info(f"\n--- Pass {pass_num}: {len(remaining_accounts)} accounts remaining ---")
            still_pending = []

            for yaml_file, yaml_data in remaining_accounts:
                spec = yaml_data.get('spec', {})
                parent_gl_code = spec.get('parentGLCode')

                # Check if parent exists now
                parent_id = self._resolve_gl_account(parent_gl_code)
                if not parent_id:
                    logger.debug(f"  Parent {parent_gl_code} not yet available for {spec.get('name')}, deferring...")
                    still_pending.append((yaml_file, yaml_data))
                    continue

                self._load_account(yaml_file, yaml_data)

            # Update remaining and refresh cache
            remaining_accounts = still_pending
            if remaining_accounts and pass_num < max_passes + 1:
                self._cache_reference_data()

        # Report any accounts that couldn't be loaded
        if remaining_accounts:
            logger.warning(f"\n{len(remaining_accounts)} accounts could not be loaded due to missing parent references:")
            for yaml_file, yaml_data in remaining_accounts:
                spec = yaml_data.get('spec', {})
                logger.warning(f"  - {spec.get('name')} (parent: {spec.get('parentGLCode')})")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()

    def _load_account(self, yaml_file, yaml_data: dict) -> bool:
        """
        Load a single GL account

        Args:
            yaml_file: Path to YAML file
            yaml_data: Parsed YAML data

        Returns:
            True if successful, False otherwise
        """
        spec = yaml_data.get('spec', {})
        entity_name = spec.get('name')
        gl_code = spec.get('glCode')

        if not entity_name or not gl_code:
            logger.error(f"  Missing name or glCode in {yaml_file.name}")
            self.failed_entities.append(yaml_file.name)
            return False

        logger.info(f"\nProcessing: {entity_name} ({gl_code})")

        # Check if entity already exists (by name or GL code)
        existing_id = self.entity_exists('glaccounts', entity_name)
        if not existing_id:
            existing_id = self._resolve_gl_account(gl_code)

        if existing_id:
            logger.info(f"  Entity already exists: {entity_name} (ID: {existing_id})")
            self.loaded_entities[entity_name] = existing_id
            return True

        # Create entity
        api_payload = self.yaml_to_fineract_api(yaml_data)
        response = self.post('glaccounts', api_payload)

        if response and 'resourceId' in response:
            entity_id = response['resourceId']
            logger.info(f"  ✓ Created GL account: {entity_name} (ID: {entity_id})")
            self.loaded_entities[entity_name] = entity_id
            return True
        else:
            logger.error(f"  ✗ Failed to create GL account: {entity_name}")
            self.failed_entities.append(yaml_file.name)
            return False


def main():
    parser = argparse.ArgumentParser(description='Load Chart Of Accounts into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = ChartOfAccountsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
