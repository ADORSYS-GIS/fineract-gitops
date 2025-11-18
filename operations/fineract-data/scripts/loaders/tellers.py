#!/usr/bin/env python3
"""
Tellers Loader
Loads teller configuration into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class TellersLoader(BaseLoader):
    """Loader for Fineract Tellers"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Tellers YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Resolve office ID
        office_id = self._resolve_office(spec.get('officeName'))
        if not office_id:
            raise ValueError(f"Office not found: {spec.get('officeName')}")

        payload = {
            'officeId': office_id,
            'name': spec.get('name'),
            'description': spec.get('description', ''),
            'status': spec.get('status', 'ACTIVE'),
            'startDate': spec.get('startDate'),
            'dateFormat': 'yyyy-MM-dd',
            'locale': 'en'
        }

        # Add end date if specified
        if 'endDate' in spec:
            payload['endDate'] = spec['endDate']

        return payload

    def _resolve_office(self, office_name: str) -> int:
        """Resolve office name to ID"""
        if not office_name:
            return None

        try:
            offices = self.get('offices')
            for office in offices:
                if office.get('name') == office_name:
                    return office.get('id')
            logger.warning(f"  ⚠ Office not found: {office_name}")
            return None
        except Exception as e:
            logger.error(f"  Error resolving office '{office_name}': {e}")
            return None

    def load_all(self) -> dict:
        """
        Load all teller configuration YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING TELLERS")
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
            if yaml_data.get('kind') != 'Teller':
                logger.debug(f"  Skipping (not Teller): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if entity already exists
            existing_id = self.entity_exists('tellers', entity_name)

            if existing_id:
                logger.info(f"  Entity already exists: {entity_name} (ID: {existing_id})")
                self.loaded_entities[entity_name] = existing_id
                continue

            # Create entity
            api_payload = self.yaml_to_fineract_api(yaml_data)
            response = self.post('tellers', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created teller configuration: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create teller configuration: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Tellers into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = TellersLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
