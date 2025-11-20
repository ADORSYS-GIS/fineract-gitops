#!/usr/bin/env python3
"""
Maker Checker Loader
Configures maker-checker permissions in Fineract from YAML files
NOTE: This is a stub implementation - MakerChecker configuration may not be fully supported via API
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class MakerCheckerLoader(BaseLoader):
    """Loader for Fineract Maker Checker"""

    def load_all(self) -> dict:
        """
        Load all maker checker configuration YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING MAKER CHECKER")
        logger.info("=" * 80)
        logger.warning("MakerChecker loader is not fully implemented - skipping all configurations")
        logger.warning("Maker-checker permissions may need to be configured manually in Fineract UI")

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
            if yaml_data.get('kind') != 'MakerChecker':
                logger.debug(f"  Skipping (not MakerChecker): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            task_name = spec.get('taskName')  # MakerChecker uses 'taskName' not 'name'

            if not task_name:
                logger.error(f"  Missing taskName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Skip - not implemented yet
            logger.info(f"  Skipping MakerChecker config: {task_name} (not implemented)")
            self.skipped_entities.append(task_name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Maker Checker into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = MakerCheckerLoader(args.yaml_dir, args.fineract_url, args.tenant)

    try:
        summary = loader.load_all()
        loader.print_summary()

        # Don't exit with error for skipped entities
        if summary['total_failed'] > 0:
            sys.exit(1)
        else:
            sys.exit(0)

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
