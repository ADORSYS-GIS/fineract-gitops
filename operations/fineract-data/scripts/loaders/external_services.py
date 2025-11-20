#!/usr/bin/env python3
"""
External Services Loader
Loads external service configurations (SMTP/Email, SMS Gateway, Notifications) into Fineract from YAML files

Handles kind: SMSEmailConfig files that configure:
- Email SMTP (Gmail, etc.)
- SMS Gateway (Twilio, Infobip, etc.)
- System Notification Settings

Uses Fineract API endpoint: /v1/externalservice/{serviceName}
Verified against Fineract source: ExternalServicesConfigurationApiResource.java
"""
import sys
import argparse
from pathlib import Path
from collections import defaultdict
from base_loader import BaseLoader, logger


class ExternalServicesLoader(BaseLoader):
    """Loader for Fineract External Service Configurations"""

    # Map provider/config type to Fineract service name
    # Based on: /Users/guymoyo/dev/fineract/fineract-provider/src/main/java/
    #           org/apache/fineract/infrastructure/configuration/api/ExternalServicesConfigurationApiResource.java
    SERVICE_NAME_MAP = {
        'gmail': 'SMTP_Email_Account',
        'email': 'SMTP_Email_Account',
        'email smtp': 'SMTP_Email_Account',
        'twilio': 'twilio',
        'infobip': 'infobip',
        'notification': 'NOTIFICATION',
        'system': 'NOTIFICATION'
    }

    def get_service_name(self, yaml_data: dict) -> str:
        """
        Determine Fineract service name from YAML spec

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract service name (e.g., "SMTP_Email_Account", "twilio")
        """
        spec = yaml_data.get('spec', {})
        provider = spec.get('provider', '').lower()
        config_type = spec.get('configType', '').lower()

        # Try provider first
        if provider in self.SERVICE_NAME_MAP:
            return self.SERVICE_NAME_MAP[provider]

        # Fall back to config type
        if config_type in self.SERVICE_NAME_MAP:
            return self.SERVICE_NAME_MAP[config_type]

        # Default - use provider as-is
        logger.warning(f"Unknown provider/type: {provider}/{config_type}, using '{provider}' as service name")
        return provider

    def load_all(self) -> dict:
        """
        Load all external service configuration YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING EXTERNAL SERVICES CONFIGURATIONS")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Group config files by service name
        # service_configs = {
        #     'SMTP_Email_Account': [
        #         {'key': 'smtp_host', 'value': 'smtp.gmail.com'},
        #         {'key': 'smtp_port', 'value': '587'},
        #         ...
        #     ],
        #     'twilio': [...]
        # }
        service_configs = defaultdict(list)
        service_file_tracking = defaultdict(list)  # Track which files belong to which service

        # First pass: Group configurations by service
        logger.info("Grouping configurations by service...")
        for yaml_file in yaml_files:
            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if it's the correct kind
            if yaml_data.get('kind') != 'SMSEmailConfig':
                logger.debug(f"  Skipping (not SMSEmailConfig): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            config_key = spec.get('configKey')
            config_value = spec.get('configValue')

            if not config_key:
                logger.error(f"  Missing configKey in {yaml_file.name}")
                self.failed_entities.append(yaml_file.name)
                continue

            # Determine service name
            service_name = self.get_service_name(yaml_data)

            # Add to service group
            service_configs[service_name].append({
                'key': config_key,
                'value': config_value,
                'file': yaml_file.name
            })
            service_file_tracking[service_name].append(yaml_file.name)

        logger.info(f"Found {len(service_configs)} services to configure:")
        for service_name, configs in service_configs.items():
            logger.info(f"  - {service_name}: {len(configs)} properties")

        # Second pass: Update each service with its grouped configurations
        for service_name, configs in service_configs.items():
            logger.info(f"\n{'='*80}")
            logger.info(f"Configuring Service: {service_name}")
            logger.info(f"{'='*80}")

            # Build payload - Fineract expects key-value pairs
            # Example: {"smtp_host": "smtp.gmail.com", "smtp_port": "587", ...}
            api_payload = {}
            for config in configs:
                api_payload[config['key']] = config['value']
                logger.info(f"  {config['key']}: {config['value']}")

            # Update service configuration
            # PUT /v1/externalservice/{serviceName}
            endpoint = f'externalservice/{service_name}'
            response = self.put(endpoint, api_payload)

            if response:
                # Fineract may return 'changes' object or just success indicator
                changes = response.get('changes', {})
                if changes:
                    logger.info(f"  ✓ Updated service: {service_name}")
                    logger.debug(f"    Changes: {changes}")
                else:
                    logger.info(f"  ✓ Service configuration applied: {service_name}")

                # Mark all files in this service group as loaded
                for config in configs:
                    self.loaded_entities[f"{service_name}/{config['key']}"] = service_name
            else:
                logger.error(f"  ✗ Failed to configure service: {service_name}")
                # Mark all files in this service group as failed
                for file_name in service_file_tracking[service_name]:
                    if file_name not in self.failed_entities:
                        self.failed_entities.append(file_name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(
        description='Load External Services Configurations into Fineract'
    )
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = ExternalServicesLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
