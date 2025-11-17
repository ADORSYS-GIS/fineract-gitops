#!/usr/bin/env python3
"""
Fineract Clients Loader
Loads client (individual/corporate) data from YAML files into Fineract
"""
import os
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

from base_loader import BaseLoader

class ClientsLoader(BaseLoader):
    """Loader for Fineract Client entities"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        self.entity_type = 'Client'
        self.api_endpoint = '/clients'
        self._cache_reference_data()

    def yaml_to_fineract_api(self, yaml_data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert YAML format to Fineract API format for clients"""
        spec = yaml_data.get('spec', {})
        
        api_data = {
            'firstname': spec.get('firstName', ''),
            'lastname': spec.get('lastName', ''),
            'officeId': self._resolve_office(spec.get('officeId', 'head-office')),
            'active': spec.get('active', True),
            'dateFormat': 'dd MMMM yyyy',
            'locale': 'en'
        }

        # Optional fields
        if spec.get('middleName'):
            api_data['middlename'] = spec['middleName']
        if spec.get('externalId'):
            api_data['externalId'] = spec['externalId']
        if spec.get('mobileNo'):
            api_data['mobileNo'] = spec['mobileNo']
        if spec.get('emailAddress'):
            api_data['emailAddress'] = spec['emailAddress']
        if spec.get('staffId'):
            api_data['staffId'] = self._resolve_staff(spec['staffId'])

        # Activation date
        if spec.get('activationDate'):
            date_obj = datetime.strptime(spec['activationDate'], '%Y-%m-%d')
            api_data['activationDate'] = date_obj.strftime('%d %B %Y')

        # Date of birth
        if spec.get('dateOfBirth'):
            date_obj = datetime.strptime(spec['dateOfBirth'], '%Y-%m-%d')
            api_data['dateOfBirth'] = date_obj.strftime('%d %B %Y')

        return api_data

    def load_all(self) -> Dict[str, Any]:
        """Load all client YAML files"""
        from base_loader import logger

        logger.info("=" * 80)
        logger.info(f"LOADING {self.entity_type.upper()}S")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('**/*.yaml'))

        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        for yaml_file in yaml_files:
            logger.info(f"\nProcessing: {yaml_file.name}")

            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data:
                self.failed_entities.append(yaml_file.name)
                continue

            if yaml_data.get('kind') != self.entity_type:
                logger.warning(f"  Skipping (not {self.entity_type}): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            client_name = f"{spec.get('firstName', '')} {spec.get('lastName', '')}".strip()

            if not client_name:
                logger.error(f"  Missing firstName/lastName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            api_payload = self.yaml_to_fineract_api(yaml_data)
            existing_id = self.entity_exists(self.api_endpoint, spec.get('externalId'), 'externalId')

            if existing_id:
                if self.has_changes(self.api_endpoint, existing_id, api_payload):
                    logger.info(f"  {self.entity_type} already exists, but has changes: {client_name} (ID: {existing_id})")
                    # Update logic here if needed
                    self.updated_entities[client_name] = existing_id
                else:
                    logger.info(f"  {self.entity_type} already exists and has no changes: {client_name} (ID: {existing_id})")
                    self.skipped_entities[client_name] = existing_id
                continue

            response = self.post(self.api_endpoint, api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created {self.entity_type.lower()}: {client_name} (ID: {entity_id})")
                self.loaded_entities[client_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create {self.entity_type.lower()}: {client_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Load Fineract clients from YAML')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing client YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant ID')
    args = parser.parse_args()

    loader = ClientsLoader(args.yaml_dir, args.fineract_url, args.tenant)
    summary = loader.load_all()
    loader.print_summary()
    import sys
    sys.exit(0 if summary['total_failed'] == 0 else 1)

if __name__ == '__main__':
    main()
