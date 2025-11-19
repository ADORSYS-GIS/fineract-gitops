#!/usr/bin/env python3
"""
System Foundation Consolidated Loader
Loads all system foundation entities (Waves 1-9) in sequence
"""
import sys
import argparse
import structlog
from pathlib import Path
import importlib.util

# Import structured logging configuration from base_loader
from base_loader import configure_logging

# Configure structured logging
configure_logging()
logger = structlog.get_logger(__name__)

# Entity loaders to run in order (matching wave sequence)
ENTITY_LOADERS = [
    ('code_values', 'CodeValuesLoader'),
    ('offices', 'OfficesLoader'),
    ('staff', 'StaffLoader'),
    ('roles', 'RolesLoader'),
    ('currency_config', 'CurrencyConfigLoader'),
    ('working_days', 'WorkingDaysLoader'),
    ('account_number_formats', 'AccountNumberFormatsLoader'),
    ('maker_checker', 'MakerCheckerLoader'),
    ('scheduler_jobs', 'SchedulerJobsLoader'),
]


def load_entity_loader(module_name: str, class_name: str):
    """Dynamically import and return loader class"""
    try:
        # Get the directory where this script is located
        script_dir = Path(__file__).parent
        module_path = script_dir / f"{module_name}.py"

        if not module_path.exists():
            logger.warning(f"Loader module not found: {module_path}")
            return None

        # Load the module
        spec = importlib.util.spec_from_file_location(module_name, module_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        # Get the loader class
        loader_class = getattr(module, class_name, None)
        if not loader_class:
            logger.warning(f"Class {class_name} not found in module {module_name}")
            return None

        return loader_class
    except Exception as e:
        logger.error(f"Error loading {module_name}.{class_name}: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(
        description='Load System Foundation entities into Fineract (Waves 1-9)'
    )
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
    logger.info("SYSTEM FOUNDATION LOADER")
    logger.info("=" * 80)
    logger.info(f"Data directory: {data_dir}")
    logger.info(f"Fineract URL: {args.fineract_url}")
    logger.info(f"Tenant: {args.tenant}")
    logger.info(f"Loading {len(ENTITY_LOADERS)} entity types from flat directory...")
    logger.info("=" * 80)

    total_loaded = 0
    total_failed = 0
    total_updated = 0
    total_skipped = 0
    failed_entities = []

    for module_name, class_name in ENTITY_LOADERS:
        entity_name = module_name.replace('_', ' ').title()

        # Bind entity context to logger
        entity_logger = logger.bind(entity_type=entity_name, module_name=module_name)

        entity_logger.info("loading_entity_type_start",
                          message=f"Loading {entity_name}",
                          separator="=" * 80)

        # Load the entity loader class
        loader_class = load_entity_loader(module_name, class_name)
        if not loader_class:
            entity_logger.error("loader_class_not_found",
                               class_name=class_name,
                               message=f"Failed to load {class_name}")
            failed_entities.append(entity_name)
            total_failed += 1
            continue

        try:
            # All loaders now use the same flat directory
            # They filter files by 'kind' field internally
            loader = loader_class(str(data_dir), args.fineract_url, args.tenant)
            summary = loader.load_all()

            # Accumulate totals
            total_loaded += summary.get('total_loaded', 0)
            total_failed += summary.get('total_failed', 0)
            total_updated += summary.get('total_updated', 0)
            total_skipped += summary.get('total_skipped', 0)

            if summary.get('total_failed', 0) > 0:
                failed_entities.append(entity_name)
                entity_logger.error("entity_type_completed_with_failures",
                                   failures=summary['total_failed'],
                                   created=summary.get('total_loaded', 0),
                                   updated=summary.get('total_updated', 0),
                                   skipped=summary.get('total_skipped', 0))
            else:
                entity_logger.info("entity_type_completed_successfully",
                                  created=summary.get('total_loaded', 0),
                                  updated=summary.get('total_updated', 0),
                                  skipped=summary.get('total_skipped', 0))

        except Exception as e:
            entity_logger.error("entity_type_exception",
                               error_message=str(e),
                               error_type=type(e).__name__,
                               exc_info=True)
            failed_entities.append(entity_name)
            total_failed += 1

    # Print final summary
    logger.info("\n" + "=" * 80)
    logger.info("SYSTEM FOUNDATION - FINAL SUMMARY")
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

    # Exit with error code if any failures
    if total_failed > 0 or failed_entities:
        logger.error(f"System Foundation loading completed with {total_failed} failures")
        sys.exit(1)
    else:
        logger.info("System Foundation loading completed successfully")
        sys.exit(0)


if __name__ == '__main__':
    main()
