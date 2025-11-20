#!/usr/bin/env python3
"""
Global Configurations Loader
Loads global configuration settings into Fineract from YAML files

Handles both:
- kind: GlobalConfiguration (e.g., "maker-checker", "enable-business-date")
- kind: Configuration (e.g., "BASE_CURRENCY", "INSTITUTION_NAME")

Both kinds use the same Fineract API endpoint: /v1/configurations
Verified against Fineract source: GlobalConfigurationApiResource.java
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class GlobalConfigurationsLoader(BaseLoader):
    """Loader for Fineract Global Configuration Settings"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Global Configuration YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload

        Reference: /Users/guymoyo/dev/fineract/fineract-provider/src/main/java/
                   org/apache/fineract/infrastructure/configuration/api/GlobalConfigurationApiResource.java
        """
        spec = yaml_data.get('spec', {})

        payload = {}

        # Handle enabled field (boolean)
        if 'enabled' in spec:
            payload['enabled'] = spec['enabled']

        # Handle value field (can be string, number, or boolean - API expects it)
        if 'value' in spec:
            payload['value'] = spec['value']

        # Handle trapDoor field (only for GlobalConfiguration kind, not Configuration)
        # trapDoor prevents further modification of the configuration
        if 'trapDoor' in spec:
            payload['trapDoor'] = spec['trapDoor']

        return payload

    def load_all(self) -> dict:
        """
        Load all global configuration YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING GLOBAL CONFIGURATIONS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Get list of all existing configurations from Fineract
        logger.info("Fetching existing configurations from Fineract...")
        existing_configs = self.get('configurations')

        # Build lookup map: config_name -> config_id
        config_map = {}
        if existing_configs and 'globalConfiguration' in existing_configs:
            for config in existing_configs['globalConfiguration']:
                config_name = config.get('name')
                config_id = config.get('id')
                if config_name and config_id:
                    config_map[config_name] = config_id

        logger.info(f"Found {len(config_map)} existing configurations in Fineract")

        for yaml_file in yaml_files:
            logger.info(f"\nProcessing: {yaml_file.name}")

            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind (accept both GlobalConfiguration and Configuration)
            kind = yaml_data.get('kind')
            if kind not in ['GlobalConfiguration', 'Configuration']:
                logger.debug(f"  Skipping (not GlobalConfiguration/Configuration): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})

            # The configuration name is the identifier
            config_name = spec.get('name')
            if not config_name:
                logger.error(f"  Missing 'name' in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            logger.info(f"  Configuration: {config_name} (kind: {kind})")

            # Check if configuration exists
            config_id = config_map.get(config_name)

            if config_id:
                logger.info(f"  Found existing configuration (ID: {config_id})")

                # Update existing configuration using name-based endpoint
                # PUT /v1/configurations/name/{configName}
                api_payload = self.yaml_to_fineract_api(yaml_data)

                if not api_payload:
                    logger.warning(f"  No updates needed (payload empty)")
                    self.skipped_entities[config_name] = config_id
                    continue

                response = self.put(f'configurations/name/{config_name}', api_payload)

                if response:
                    # Fineract returns 'changes' object showing what was updated
                    changes = response.get('changes', {})
                    if changes:
                        logger.info(f"  ✓ Updated configuration: {config_name}")
                        logger.debug(f"    Changes: {changes}")
                        self.updated_entities[config_name] = config_id
                    else:
                        logger.info(f"  ✓ Configuration unchanged: {config_name}")
                        self.skipped_entities[config_name] = config_id
                else:
                    logger.error(f"  ✗ Failed to update: {config_name}")
                    self.failed_entities.append(yaml_file.name)
            else:
                # Configuration doesn't exist - this is unusual since configurations
                # are typically pre-seeded in Fineract database
                logger.warning(f"  Configuration '{config_name}' not found in Fineract")
                logger.warning(f"  Global configurations are typically pre-seeded in the database")
                logger.warning(f"  Verify the configuration name matches Fineract's expected name")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(
        description='Load Global Configurations into Fineract'
    )
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = GlobalConfigurationsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
