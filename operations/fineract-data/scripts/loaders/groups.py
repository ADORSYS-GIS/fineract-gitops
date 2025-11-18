#!/usr/bin/env python3
"""Fineract Groups Loader"""
import sys
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent))
from base_loader import BaseLoader, logger

class GroupsLoader(BaseLoader):
    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        self.entity_type = 'Group'
        self.api_endpoint = '/groups'

    def yaml_to_fineract_api(self, yaml_data: Dict[str, Any]) -> Dict[str, Any]:
        spec = yaml_data.get('spec', {})

        # Build API payload
        api_data = {
            'name': spec.get('name', ''),
            'officeId': self._resolve_office_id(spec.get('officeId', 'head-office')),
            'active': spec.get('active', True),
            'dateFormat': 'dd MMMM yyyy',
            'locale': 'en'
        }

        # Optional fields
        if spec.get('externalId'):
            api_data['externalId'] = spec['externalId']
        if spec.get('staffId'):
            api_data['staffId'] = spec['staffId']
        if spec.get('activationDate'):
            date_obj = datetime.strptime(spec['activationDate'], '%Y-%m-%d')
            api_data['activationDate'] = date_obj.strftime('%d %B %Y')
        if spec.get('submittedOnDate'):
            date_obj = datetime.strptime(spec['submittedOnDate'], '%Y-%m-%d')
            api_data['submittedOnDate'] = date_obj.strftime('%d %B %Y')

        return api_data

    def _resolve_office_id(self, office_ref: str) -> int:
        """Resolve office reference to ID"""
        try:
            response = self.get('/offices')
            if response:
                for office in response:
                    if office.get('name') == office_ref or office.get('externalId') == office_ref:
                        return office['id']
        except Exception as e:
            logger.warning(f"Error resolving office '{office_ref}': {e}")
        return 1  # Default to head office

    def entity_exists(self, api_data: Dict[str, Any], yaml_data: Dict[str, Any]) -> Optional[int]:
        spec = yaml_data.get('spec', {})

        # Try external ID first
        if spec.get('externalId'):
            try:
                response = self.get(self.api_endpoint)
                items = response if isinstance(response, list) else response.get('pageItems', [])
                for item in items:
                    if item.get('externalId') == spec['externalId']:
                        return item['id']
            except Exception as e:
                logger.warning(f"Error checking existing groups: {e}")

        # Fallback to name matching
        try:
            response = self.get(self.api_endpoint)
            items = response if isinstance(response, list) else response.get('pageItems', [])
            for item in items:
                if item.get('name') == spec.get('name'):
                    return item['id']
        except Exception as e:
            logger.warning(f"Error checking existing groups by name: {e}")

        return None

    def load_all(self) -> Dict[str, Any]:
        """Load all group YAML files"""
        logger.info("=" * 80)
        logger.info(f"LOADING {self.entity_type.upper()}S")
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
            if yaml_data.get('kind') != self.entity_type:
                logger.debug(f"  Skipping (not {self.entity_type}): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name', yaml_file.stem)

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Convert to API format
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Check if entity already exists
            existing_id = self.entity_exists(api_payload, yaml_data)

            if existing_id:
                logger.info(f"  {self.entity_type} already exists: {entity_name} (ID: {existing_id})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity in Fineract
            response = self.post(self.api_endpoint, api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created {self.entity_type.lower()}: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create {self.entity_type.lower()}: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--yaml-dir', required=True)
    parser.add_argument('--fineract-url', required=True)
    parser.add_argument('--tenant', default='default')
    args = parser.parse_args()

    loader = GroupsLoader(args.yaml_dir, args.fineract_url, args.tenant)
    summary = loader.load_all()
    loader.print_summary()
    sys.exit(0 if summary['total_failed'] == 0 else 1)

if __name__ == '__main__':
    main()
