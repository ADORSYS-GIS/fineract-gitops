#!/usr/bin/env python3
"""
Maker Checker Loader
Enables/disables maker-checker for specific permissions in Fineract from YAML files

Fineract's maker-checker works by enabling maker-checker on specific permission codes.
When enabled, operations require two-step approval: maker creates, checker approves.

NOTE: The YAML fields like thresholdAmount, makerRole, checkerRole are for documentation
purposes only. Fineract's permissions API only supports enabling/disabling maker-checker
on permission codes (e.g., ACTIVATE_CLIENT, APPROVE_LOAN).
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class MakerCheckerLoader(BaseLoader):
    """Loader for Fineract Maker Checker Permissions"""

    def yaml_to_permission_code(self, yaml_data: dict) -> str:
        """
        Convert YAML entity/action to Fineract permission code

        Args:
            yaml_data: YAML data structure

        Returns:
            Permission code (e.g., ACTIVATE_CLIENT, APPROVE_LOAN)
        """
        spec = yaml_data.get('spec', {})
        entity = spec.get('entity', '').upper()
        action = spec.get('action', '').upper()

        if not entity or not action:
            return None

        # Permission code format: {ACTION}_{ENTITY}
        # Examples: ACTIVATE_CLIENT, APPROVE_LOAN, DISBURSE_LOAN
        permission_code = f"{action}_{entity}"

        return permission_code

    def load_all(self) -> dict:
        """
        Load all maker checker configuration YAML files and enable maker-checker
        for the specified permissions via the /permissions API

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING MAKER CHECKER PERMISSIONS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Collect all permissions to enable in a single request
        permissions_to_enable = {}

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
            enabled = spec.get('enabled', True)

            if not task_name:
                logger.error(f"  Missing taskName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Get permission code from entity/action
            permission_code = self.yaml_to_permission_code(yaml_data)

            if not permission_code:
                logger.error(f"  Missing entity or action in spec for: {task_name}")
                self.failed_entities.append(yaml_file.name)
                continue

            logger.info(f"  Permission code: {permission_code}")
            logger.info(f"  Maker-checker: {'ENABLED' if enabled else 'DISABLED'}")

            # Add to batch update
            permissions_to_enable[permission_code] = enabled

        if permissions_to_enable:
            # Send single PUT request to /permissions to update all at once
            logger.info(f"\n{'=' * 80}")
            logger.info(f"Updating {len(permissions_to_enable)} maker-checker permissions")
            logger.info(f"{'=' * 80}")

            payload = {"permissions": permissions_to_enable}

            logger.info(f"Payload: {payload}")

            response = self.put('permissions', payload)

            if response:
                logger.info(f"  ✓ Successfully updated maker-checker permissions")
                # Mark all as loaded
                for permission_code in permissions_to_enable.keys():
                    self.loaded_entities[permission_code] = True
            else:
                logger.error(f"  ✗ Failed to update maker-checker permissions")
                # Mark all as failed
                for permission_code in permissions_to_enable.keys():
                    self.failed_entities.append(permission_code)
        else:
            logger.info("No maker-checker permissions to update")

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
