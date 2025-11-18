#!/usr/bin/env python3
"""
Roles Loader
Loads roles and permissions into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class RolesLoader(BaseLoader):
    """Loader for Fineract Roles"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Roles YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Build payload
        payload = {
            'name': spec.get('name'),
            'description': spec.get('description', ''),
            'disabled': spec.get('disabled', False)
        }

        # Build permissions array
        # Permissions in YAML are human-readable with grouping + code
        # Need to resolve to permission IDs from Fineract
        permissions_data = spec.get('permissions', [])

        if permissions_data:
            # Get all available permissions from Fineract
            all_permissions = self.get('permissions')
            permission_map = {}

            if all_permissions:
                for perm in all_permissions:
                    # Map by code for easy lookup
                    permission_map[perm.get('code')] = perm.get('id')

            # Resolve permission codes to IDs
            permission_ids = []
            for perm in permissions_data:
                perm_code = perm.get('code')
                if perm_code and perm_code in permission_map:
                    permission_ids.append(permission_map[perm_code])
                elif perm_code:
                    logger.warning(f"  Permission code not found: {perm_code}")

            if permission_ids:
                payload['permissions'] = permission_ids

        return payload

    def load_all(self) -> dict:
        """
        Load all roles and permissions YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING ROLES")
        logger.info("=" * 80)

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
            if yaml_data.get('kind') != 'Role':
                logger.debug(f"  Skipping (not Role): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Convert to API format
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Check if entity already exists
            existing_id = self.entity_exists('roles', entity_name)

            if existing_id:
                # Entity exists - check for changes
                if self.has_changes('/roles', existing_id, api_payload):
                    # Update entity
                    logger.info(f"  ↻ Updating: {entity_name}")
                    response = self.put(f'/roles/{existing_id}', api_payload)
                    if response:
                        logger.info(f"  ✓ Updated: {entity_name} (ID: {existing_id})")
                        self.updated_entities[entity_name] = existing_id
                    else:
                        logger.error(f"  ✗ Failed to update: {entity_name}")
                        self.failed_entities.append(yaml_file.name)
                else:
                    # No changes detected
                    logger.info(f"  ⊘ No changes: {entity_name} (ID: {existing_id})")
                    self.skipped_entities[entity_name] = existing_id
                continue

            # Create entity
            response = self.post('roles', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created roles and permissions: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create roles and permissions: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Roles into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = RolesLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
