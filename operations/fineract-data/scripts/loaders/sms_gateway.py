#!/usr/bin/env python3
"""
SMS Gateway Configuration Loader

This script loads SMS gateway configuration data into the message-gateway service:
1. Creates tenants and retrieves unique app keys
2. Configures SMS providers (Twilio, Infobip, AWS SNS, etc.)
3. Sets up SMS bridges for each tenant

The message-gateway service must be running and accessible before running this loader.
"""

import os
import sys
import logging
import requests
import yaml
from typing import Dict, List, Optional
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SMSGatewayLoader:
    """Loader for SMS Gateway configuration"""

    def __init__(self, base_url: str, data_dir: Path):
        """
        Initialize the SMS Gateway loader

        Args:
            base_url: Base URL of message-gateway service (e.g., http://message-gateway-service:9191)
            data_dir: Path to directory containing YAML configuration files
        """
        self.base_url = base_url.rstrip('/')
        self.data_dir = data_dir
        self.tenant_keys: Dict[str, str] = {}  # Store generated app keys
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })

    def load_yaml_file(self, filename: str) -> dict:
        """Load and parse YAML file"""
        file_path = self.data_dir / filename
        if not file_path.exists():
            logger.warning(f"File not found: {file_path}")
            return {}

        with open(file_path, 'r') as f:
            data = yaml.safe_load(f)
            logger.info(f"Loaded {filename}")
            return data or {}

    def substitute_env_vars(self, value: str) -> str:
        """Substitute environment variables in configuration values"""
        if isinstance(value, str) and value.startswith('${') and value.endswith('}'):
            env_var = value[2:-1]
            return os.getenv(env_var, value)
        return value

    def substitute_config_vars(self, config: dict) -> dict:
        """Recursively substitute environment variables in configuration"""
        result = {}
        for key, value in config.items():
            if isinstance(value, dict):
                result[key] = self.substitute_config_vars(value)
            elif isinstance(value, str):
                result[key] = self.substitute_env_vars(value)
            else:
                result[key] = value
        return result

    def create_tenant(self, tenant_id: str, description: str) -> Optional[str]:
        """
        Create a tenant in message-gateway and retrieve the app key

        Args:
            tenant_id: Unique tenant identifier
            description: Human-readable description

        Returns:
            Generated app key for the tenant, or None if creation failed
        """
        url = f"{self.base_url}/tenants/"
        payload = {
            "tenantId": tenant_id,
            "description": description
        }

        try:
            logger.info(f"Creating tenant: {tenant_id}")
            response = self.session.post(url, json=payload)

            if response.status_code == 201:
                # Extract app key from response
                response_data = response.json()
                app_key = response_data.get('appKey')
                logger.info(f"✓ Tenant '{tenant_id}' created successfully")
                logger.info(f"  App Key: {app_key}")
                logger.warning(f"  IMPORTANT: Store this app key securely! It will be needed for API calls.")
                return app_key
            elif response.status_code == 409:
                logger.warning(f"Tenant '{tenant_id}' already exists")
                return None
            else:
                logger.error(f"Failed to create tenant '{tenant_id}': {response.status_code} - {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.error(f"Error creating tenant '{tenant_id}': {str(e)}")
            return None

    def create_sms_bridge(self, tenant_id: str, app_key: str, provider_config: dict) -> bool:
        """
        Create an SMS bridge (provider configuration) for a tenant

        Args:
            tenant_id: Tenant identifier
            app_key: Tenant's app key for authentication
            provider_config: SMS provider configuration

        Returns:
            True if successful, False otherwise
        """
        url = f"{self.base_url}/smsbridges"

        # Set tenant headers
        headers = {
            'Fineract-Platform-TenantId': tenant_id,
            'Fineract-Tenant-App-Key': app_key,
            'Content-Type': 'application/json'
        }

        # Substitute environment variables in configuration
        config = self.substitute_config_vars(provider_config.get('configuration', {}))

        # Build SMS bridge payload based on provider
        provider_name = provider_config.get('provider_name', '').lower()

        if 'twilio' in provider_name:
            payload = {
                "providerName": "Twilio",
                "accountId": config.get('account_id'),
                "authToken": config.get('auth_token'),
                "phoneNumber": config.get('phone_number'),
                "countryCode": config.get('country_code')
            }
        elif 'infobip' in provider_name:
            payload = {
                "providerName": "Infobip",
                "accountId": config.get('account_id'),
                "authToken": config.get('auth_token'),
                "phoneNumber": config.get('phone_number'),
                "countryCode": config.get('country_code')
            }
        else:
            logger.warning(f"Unsupported provider: {provider_name}")
            return False

        try:
            provider_id = provider_config.get('provider_id', 'unknown')
            logger.info(f"Creating SMS bridge for tenant '{tenant_id}': {provider_name} ({provider_id})")

            response = self.session.post(url, json=payload, headers=headers)

            if response.status_code in [200, 201]:
                response_data = response.json()
                bridge_id = response_data.get('bridgeId') or response_data.get('id')
                logger.info(f"✓ SMS bridge created successfully")
                logger.info(f"  Provider: {provider_name}")
                logger.info(f"  Bridge ID: {bridge_id}")
                return True
            elif response.status_code == 409:
                logger.warning(f"SMS bridge already exists for tenant '{tenant_id}'")
                return True
            else:
                logger.error(f"Failed to create SMS bridge: {response.status_code} - {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.error(f"Error creating SMS bridge: {str(e)}")
            return False

    def load_tenants(self):
        """Load and create tenants from tenants.yaml"""
        logger.info("=" * 60)
        logger.info("Loading Tenants")
        logger.info("=" * 60)

        data = self.load_yaml_file('tenants.yaml')
        tenants = data.get('tenants', [])

        if not tenants:
            logger.warning("No tenants found in tenants.yaml")
            return

        for tenant in tenants:
            tenant_id = tenant.get('tenant_id')
            description = tenant.get('description', '')
            active = tenant.get('active', True)

            if not active:
                logger.info(f"Skipping inactive tenant: {tenant_id}")
                continue

            if not tenant_id:
                logger.warning("Tenant missing tenant_id, skipping")
                continue

            # Create tenant and get app key
            app_key = self.create_tenant(tenant_id, description)

            if app_key:
                self.tenant_keys[tenant_id] = app_key
            elif tenant.get('app_key') and tenant['app_key'] != 'GENERATED_ON_FIRST_SETUP':
                # Use existing app key from config
                self.tenant_keys[tenant_id] = tenant['app_key']
                logger.info(f"Using existing app key for tenant '{tenant_id}'")

        logger.info("")

    def load_sms_providers(self):
        """Load and create SMS providers from sms-providers.yaml"""
        logger.info("=" * 60)
        logger.info("Loading SMS Providers")
        logger.info("=" * 60)

        data = self.load_yaml_file('sms-providers.yaml')
        providers = data.get('sms_providers', [])

        if not providers:
            logger.warning("No SMS providers found in sms-providers.yaml")
            return

        for provider in providers:
            tenant_id = provider.get('tenant_id')
            active = provider.get('active', True)
            provider_id = provider.get('provider_id', 'unknown')

            if not active:
                logger.info(f"Skipping inactive provider: {provider_id}")
                continue

            if not tenant_id:
                logger.warning(f"Provider '{provider_id}' missing tenant_id, skipping")
                continue

            # Get tenant app key
            app_key = self.tenant_keys.get(tenant_id)
            if not app_key:
                logger.error(f"No app key found for tenant '{tenant_id}', cannot create SMS bridge")
                continue

            # Create SMS bridge
            self.create_sms_bridge(tenant_id, app_key, provider)

        logger.info("")

    def load_all(self):
        """Load all SMS gateway configuration"""
        logger.info("Starting SMS Gateway configuration load...")
        logger.info("")

        try:
            # Step 1: Create tenants
            self.load_tenants()

            # Step 2: Create SMS providers (bridges)
            self.load_sms_providers()

            logger.info("=" * 60)
            logger.info("SMS Gateway configuration completed successfully!")
            logger.info("=" * 60)

            # Print summary of tenant keys
            if self.tenant_keys:
                logger.info("")
                logger.info("IMPORTANT: Tenant App Keys (store these securely!):")
                for tenant_id, app_key in self.tenant_keys.items():
                    logger.info(f"  {tenant_id}: {app_key}")

        except Exception as e:
            logger.error(f"Error during SMS gateway configuration: {str(e)}")
            raise


def main():
    """Main entry point"""
    # Get message-gateway URL from environment or use default
    base_url = os.getenv('MESSAGE_GATEWAY_URL', 'http://message-gateway-service:9191')

    # Get data directory
    script_dir = Path(__file__).parent.parent
    data_dir = script_dir / 'data' / 'sms-gateway'

    if not data_dir.exists():
        logger.error(f"Data directory not found: {data_dir}")
        sys.exit(1)

    # Initialize loader
    loader = SMSGatewayLoader(base_url, data_dir)

    # Load all configuration
    try:
        loader.load_all()
    except Exception as e:
        logger.error(f"Failed to load SMS gateway configuration: {str(e)}")
        sys.exit(1)


if __name__ == '__main__':
    main()
