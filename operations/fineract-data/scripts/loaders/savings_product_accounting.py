#!/usr/bin/env python3
"""
Savings Product Accounting Loader
Loads savings product GL mappings into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class SavingsProductAccountingLoader(BaseLoader):
    """Loader for Fineract Savings Product Accounting"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        # Mapping from YAML mapping types to Fineract API field names
        self.mapping_field_map = {
            'Savings Reference': 'savingsReferenceAccountId',
            'Savings Control': 'savingsControlAccountId',
            'Interest on Savings': 'interestOnSavingsAccountId',
            'Income from Fees': 'incomeFromFeeAccountId',
            'Income from Penalties': 'incomeFromPenaltyAccountId',
            'Overdraft Portfolio Control': 'overdraftPortfolioControlId',
            'Income from Interest': 'incomeFromInterestId',
            'Losses Written Off': 'writeOffAccountId',
            'Escheat Liability': 'escheatLiabilityId',
            'Withholding Tax': 'savingsReferenceAccountId',  # May vary
            'Transfer in Suspense': 'transfersInSuspenseAccountId'
        }

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Savings Product Accounting YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload (for updating product accounting)
        """
        spec = yaml_data.get('spec', {})

        # Build accounting mappings from array
        accounting_mappings = {}
        for mapping in spec.get('accountMappings', []):
            mapping_type = mapping.get('mappingType')
            gl_code = mapping.get('glAccountCode')

            # Resolve GL account ID
            gl_account_id = self._resolve_gl_account(gl_code)
            if not gl_account_id:
                logger.warning(f"  Could not resolve GL code: {gl_code} for mapping: {mapping_type}")
                continue

            # Map to Fineract field name
            field_name = self.mapping_field_map.get(mapping_type)
            if field_name:
                accounting_mappings[field_name] = gl_account_id
            else:
                logger.warning(f"  Unknown mapping type: {mapping_type}")

        # Build update payload
        # Note: This assumes the product already exists and we're updating accounting only
        payload = {
            'accountingRule': 2,  # 2 = Cash-based accounting (adjust if needed)
            **accounting_mappings,
            'locale': 'en'
        }

        return payload

    def load_all(self) -> dict:
        """
        Load all savings product GL mappings YAML files
        Updates existing products with accounting mappings

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING SAVINGS PRODUCT ACCOUNTING")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('**/*.yaml'))

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
            if yaml_data.get('kind') != 'SavingsProductAccounting':
                logger.warning(f"  Skipping (not SavingsProductAccounting): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            product_name = spec.get('productName')

            if not product_name:
                logger.error(f"  Missing productName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Look up the savings product
            product_id = self._resolve_product(product_name, 'savings')

            if not product_id:
                logger.error(f"  Savings product not found: {product_name}")
                logger.error(f"  Please ensure the product exists before setting up accounting")
                self.failed_entities.append(yaml_file.name)
                continue

            logger.info(f"  Found product: {product_name} (ID: {product_id})")

            # Build accounting update payload
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Validate we have accounting mappings
            if len(api_payload) <= 2:  # Only locale and accountingRule
                logger.error(f"  No valid accounting mappings found for: {product_name}")
                self.failed_entities.append(yaml_file.name)
                continue

            # Update the product with accounting mappings
            response = self.put(f'savingsproducts/{product_id}', api_payload)

            if response and 'resourceId' in response:
                logger.info(f"  ✓ Updated accounting for: {product_name}")
                self.loaded_entities[product_name] = product_id
            else:
                logger.error(f"  ✗ Failed to update accounting for: {product_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Savings Product Accounting into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = SavingsProductAccountingLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
