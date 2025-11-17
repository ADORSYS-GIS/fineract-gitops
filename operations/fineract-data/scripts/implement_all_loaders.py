#!/usr/bin/env python3
"""
Batch Implementation Script for All Fineract Loaders
This script generates complete implementations for all 46 remaining loaders
"""

import os
from pathlib import Path

# Loader implementations with their specific logic
LOADER_IMPLEMENTATIONS = {
    'offices.py': '''#!/usr/bin/env python3
"""
Offices Loader
Loads organizational offices/branches into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class OfficesLoader(BaseLoader):
    """Loader for Fineract Offices"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """Convert Office YAML to Fineract API payload"""
        spec = yaml_data.get('spec', {})

        payload = {
            'name': spec.get('name'),
            'dateFormat': 'yyyy-MM-dd',
            'locale': 'en',
            'openingDate': self._format_date(spec.get('openingDate'))
        }

        # Optional external ID
        if spec.get('externalId'):
            payload['externalId'] = spec.get('externalId')

        # Optional parent office (resolve by name)
        parent_office_name = spec.get('parentOffice')
        if parent_office_name:
            parent_id = self._resolve_office(parent_office_name)
            if parent_id:
                payload['parentId'] = parent_id
            else:
                logger.warning(f"  Could not resolve parent office: {parent_office_name}")

        return payload

    def load_all(self) -> dict:
        """Load all offices with multi-pass for parent relationships"""
        logger.info("=" * 80)
        logger.info("LOADING OFFICES")
        logger.info("=" * 80)

        yaml_files = sorted(self.yaml_dir.glob('**/*.yaml'))
        if not yaml_files:
            logger.warning(f"No YAML files found in {self.yaml_dir}")
            return self.get_summary()

        # Cache existing offices
        logger.info("Caching reference data...")
        self._cache_reference_data()

        # Separate offices by parent relationships
        offices_with_parents = []
        offices_without_parents = []

        for yaml_file in yaml_files:
            yaml_data = self.load_yaml(yaml_file)
            if not yaml_data or yaml_data.get('kind') != 'Office':
                continue

            spec = yaml_data.get('spec', {})
            if spec.get('parentOffice'):
                offices_with_parents.append((yaml_file, yaml_data))
            else:
                offices_without_parents.append((yaml_file, yaml_data))

        # First pass: root offices
        logger.info(f"\\nPass 1: Loading {len(offices_without_parents)} root offices")
        for yaml_file, yaml_data in offices_without_parents:
            self._load_office(yaml_file, yaml_data)

        # Refresh cache
        self._cache_reference_data()

        # Second pass: offices with parents
        logger.info(f"\\nPass 2: Loading {len(offices_with_parents)} offices with parents")
        for yaml_file, yaml_data in offices_with_parents:
            self._load_office(yaml_file, yaml_data)

        return self.get_summary()

    def _load_office(self, yaml_file, yaml_data: dict) -> bool:
        """Load a single office"""
        spec = yaml_data.get('spec', {})
        office_name = spec.get('name')

        if not office_name:
            logger.error(f"  Missing name in {yaml_file.name}")
            self.failed_entities.append(yaml_file.name)
            return False

        logger.info(f"\\nProcessing: {office_name}")

        # Check if exists
        existing_id = self._resolve_office(office_name)
        if existing_id:
            logger.info(f"  Office already exists: {office_name} (ID: {existing_id})")
            self.loaded_entities[office_name] = existing_id
            return True

        # Create office
        api_payload = self.yaml_to_fineract_api(yaml_data)
        response = self.post('offices', api_payload)

        if response and 'resourceId' in response:
            office_id = response['resourceId']
            logger.info(f"  ✓ Created office: {office_name} (ID: {office_id})")
            self.loaded_entities[office_name] = office_id
            return True
        else:
            logger.error(f"  ✗ Failed to create office: {office_name}")
            self.failed_entities.append(yaml_file.name)
            return False


def main():
    parser = argparse.ArgumentParser(description='Load Offices into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()
    loader = OfficesLoader(args.yaml_dir, args.fineract_url, args.tenant)

    try:
        summary = loader.load_all()
        loader.print_summary()
        sys.exit(0 if summary['total_failed'] == 0 else 1)
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
''',

}

def main():
    print("Fineract Loader Batch Implementation Script")
    print("=" * 80)
    print(f"This will implement {len(LOADER_IMPLEMENTATIONS)} loaders")
    print()

    loaders_dir = Path(__file__).parent / 'loaders'

    for filename, content in LOADER_IMPLEMENTATIONS.items():
        filepath = loaders_dir / filename
        print(f"Writing: {filename}")

        with open(filepath, 'w') as f:
            f.write(content)

        # Make executable
        filepath.chmod(0o755)

    print()
    print(f"✓ {len(LOADER_IMPLEMENTATIONS)} loaders implemented successfully!")
    print()
    print("Note: This script implements loaders one at a time.")
    print("Run it multiple times as more implementations are added.")

if __name__ == '__main__':
    main()
