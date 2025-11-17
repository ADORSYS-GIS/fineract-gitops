#!/usr/bin/env python3
"""
Accounting Consolidated Loader
Loads all accounting entities (Waves 21-29) in sequence
"""
import sys
import argparse
import logging
from pathlib import Path
import importlib.util

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

ENTITY_LOADERS = [
    ('chart_of_accounts', 'ChartOfAccountsLoader'),
    ('fund_sources', 'FundSourcesLoader'),
    ('payment_types', 'PaymentTypesLoader'),
    ('tax_groups', 'TaxGroupsLoader'),
    ('loan_provisioning', 'LoanProvisioningLoader'),
    ('financial_activity_mappings', 'FinancialActivityMappingsLoader'),
    ('loan_product_accounting', 'LoanProductAccountingLoader'),
    ('savings_product_accounting', 'SavingsProductAccountingLoader'),
    ('payment_type_accounting', 'PaymentTypeAccountingLoader'),
]

def load_entity_loader(module_name: str, class_name: str):
    try:
        script_dir = Path(__file__).parent
        module_path = script_dir / f"{module_name}.py"
        if not module_path.exists():
            logger.warning(f"Loader module not found: {module_path}")
            return None
        spec = importlib.util.spec_from_file_location(module_name, module_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return getattr(module, class_name, None)
    except Exception as e:
        logger.error(f"Error loading {module_name}.{class_name}: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description='Load Accounting into Fineract (Waves 21-29)')
    parser.add_argument('--yaml-dir', required=True, help='Base data directory')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')
    args = parser.parse_args()

    base_data_dir = Path(args.yaml_dir)
    entity_data_dirs = {
        'chart_of_accounts': base_data_dir / 'accounting' / 'chart-of-accounts',
        'fund_sources': base_data_dir / 'accounting' / 'fund-sources',
        'payment_types': base_data_dir / 'accounting' / 'payment-types',
        'tax_groups': base_data_dir / 'accounting' / 'tax-groups',
        'loan_provisioning': base_data_dir / 'accounting' / 'loan-provisioning',
        'financial_activity_mappings': base_data_dir / 'accounting' / 'financial-activity-mappings',
        'loan_product_accounting': base_data_dir / 'accounting' / 'loan-product-accounting',
        'savings_product_accounting': base_data_dir / 'accounting' / 'savings-product-accounting',
        'payment_type_accounting': base_data_dir / 'accounting' / 'payment-type-accounting',
    }

    logger.info("=" * 80)
    logger.info("ACCOUNTING LOADER")
    logger.info("=" * 80)
    logger.info(f"Loading {len(ENTITY_LOADERS)} entity types...")
    logger.info("=" * 80)

    total_loaded = total_failed = total_updated = total_skipped = 0
    failed_entities = []

    for module_name, class_name in ENTITY_LOADERS:
        entity_name = module_name.replace('_', ' ').title()
        logger.info(f"\n{'=' * 80}")
        logger.info(f"LOADING: {entity_name}")
        logger.info(f"{'=' * 80}")

        data_dir = entity_data_dirs.get(module_name)
        if not data_dir or not data_dir.exists():
            logger.warning(f"Data directory not found: {data_dir}")
            continue

        loader_class = load_entity_loader(module_name, class_name)
        if not loader_class:
            failed_entities.append(entity_name)
            total_failed += 1
            continue

        try:
            loader = loader_class(str(data_dir), args.fineract_url, args.tenant)
            summary = loader.load_all()
            total_loaded += summary.get('total_loaded', 0)
            total_failed += summary.get('total_failed', 0)
            total_updated += summary.get('total_updated', 0)
            total_skipped += summary.get('total_skipped', 0)
            if summary.get('total_failed', 0) > 0:
                failed_entities.append(entity_name)
        except Exception as e:
            logger.error(f"✗ Error loading {entity_name}: {e}", exc_info=True)
            failed_entities.append(entity_name)
            total_failed += 1

    logger.info("\n" + "=" * 80)
    logger.info("ACCOUNTING - FINAL SUMMARY")
    logger.info("=" * 80)
    logger.info(f"Total Created: {total_loaded}")
    logger.info(f"Total Updated: {total_updated}")
    logger.info(f"Total Skipped: {total_skipped}")
    logger.info(f"Total Failed: {total_failed}")
    if failed_entities:
        logger.info(f"\nFailed Entity Types:")
        for entity in failed_entities:
            logger.info(f"  ✗ {entity}")
    logger.info("=" * 80)

    sys.exit(1 if total_failed > 0 or failed_entities else 0)

if __name__ == '__main__':
    main()
