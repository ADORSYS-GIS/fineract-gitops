#!/usr/bin/env python3
"""
Entities Consolidated Loader
Loads all entity data (Waves 30-34) in sequence
"""
import sys
import argparse
import structlog
from pathlib import Path
import importlib.util

# Use structured logging (configured in base_loader.py)
logger = structlog.get_logger(__name__)

ENTITY_LOADERS = [
    ('demo_clients', 'DemoClientsLoader'),
    ('demo_savings_accounts', 'DemoSavingsAccountsLoader'),
    ('demo_loan_accounts', 'DemoLoanAccountsLoader'),
    ('demo_loan_collateral', 'DemoLoanCollateralLoader'),
    ('demo_loan_guarantors', 'DemoLoanGuarantorsLoader'),
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
    parser = argparse.ArgumentParser(description='Load Entities into Fineract (Waves 30-34)')
    parser.add_argument('--yaml-dir', required=True, help='Flat data directory with all YAML files (ConfigMap compatible)')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')
    args = parser.parse_args()

    # Use flat directory structure (ConfigMap compatible)
    # All YAML files are in a single directory, filtered by 'kind' field
    data_dir = Path(args.yaml_dir)

    if not data_dir.exists():
        logger.error(f"Data directory not found: {data_dir}")
        sys.exit(1)

    logger.info("=" * 80)
    logger.info("ENTITIES LOADER")
    logger.info("=" * 80)
    logger.info(f"Loading {len(ENTITY_LOADERS)} entity types from flat directory...")
    logger.info(f"Data directory: {data_dir}")
    logger.info("=" * 80)

    total_loaded = total_failed = total_updated = total_skipped = 0
    failed_entities = []

    for module_name, class_name in ENTITY_LOADERS:
        entity_name = module_name.replace('_', ' ').title()
        logger.info(f"\n{'=' * 80}")
        logger.info(f"LOADING: {entity_name}")
        logger.info(f"{'=' * 80}")

        loader_class = load_entity_loader(module_name, class_name)
        if not loader_class:
            failed_entities.append(entity_name)
            total_failed += 1
            continue

        try:
            # All loaders now use the same flat directory
            # They filter files by 'kind' field internally
            # All loaders now use the same flat directory
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
    logger.info("ENTITIES - FINAL SUMMARY")
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
