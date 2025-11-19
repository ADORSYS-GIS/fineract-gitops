#!/usr/bin/env python3
"""
Fineract Offices Loader

Loads office configuration from YAML files into Fineract via API.
Offices represent branches and organizational units in the MFI hierarchy.

Usage:
    python3 offices.py

Environment Variables:
    FINERACT_URL      - Fineract API URL (default: http://localhost:8080/fineract-provider)
    FINERACT_TENANT   - Tenant ID (default: default)
    FINERACT_USERNAME - Admin username (default: mifos)
    FINERACT_PASSWORD - Admin password (default: password)
    YAML_DIR          - Directory with YAML files (default: ../../data/dev/offices)
"""

import os
import sys
from pathlib import Path
from typing import Dict, Any, Optional, List

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))
from base_loader import BaseLoader


class OfficesLoader(BaseLoader):
    """Loader for Fineract Office entities"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        self.entity_type = 'Office'
        self.api_endpoint = '/offices'

    def yaml_to_fineract_api(self, yaml_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert YAML format to Fineract API format for offices.

        YAML format:
            spec:
              name: Nairobi Branch
              externalId: BR-NAI-001
              parentOffice: head-office
              openingDate: "2024-01-01"
              address:
                street: Kimathi Street
                city: Nairobi
              contact:
                phone: "+254-20-1234567"

        Fineract API format:
            {
              "name": "Nairobi Branch",
              "externalId": "BR-NAI-001",
              "parentId": 1,
              "openingDate": "01 January 2024",
              "dateFormat": "dd MMMM yyyy",
              "locale": "en"
            }
        """
        spec = yaml_data.get('spec', {})

        # Base office data
        api_data = {
            'name': spec['name'],
            'dateFormat': 'dd MMMM yyyy',
            'locale': 'en'
        }

        # Optional fields
        if 'externalId' in spec:
            api_data['externalId'] = spec['externalId']

        # Opening date
        if 'openingDate' in spec:
            # Convert from YYYY-MM-DD to dd MMMM yyyy
            from datetime import datetime
            date_obj = datetime.strptime(spec['openingDate'], '%Y-%m-%d')
            api_data['openingDate'] = date_obj.strftime('%d %B %Y')

        # Parent office - need to resolve name to ID
        if spec.get('parentOffice') and spec['parentOffice'] != 'head-office':
            parent_name = spec['parentOffice']
            parent_office = self._find_office_by_name(parent_name)
            if parent_office:
                api_data['parentId'] = parent_office['id']
            else:
                self.logger.warning(f"Parent office '{parent_name}' not found, creating without parent")

        # Note: Address and contact info are stored separately or in custom fields
        # For now, we'll add them as metadata in the payload if needed
        # Fineract core doesn't have direct address fields in office API

        return api_data

    def _find_office_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        """Find office by name"""
        try:
            response = self.get('/offices')
            if response:
                for office in response:
                    if office.get('name') == name:
                        return office
        except Exception as e:
            self.logger.error(f"Error finding office by name '{name}': {e}")
        return None

    def _find_office_by_external_id(self, external_id: str) -> Optional[Dict[str, Any]]:
        """Find office by external ID"""
        try:
            response = self.get('/offices')
            if response:
                for office in response:
                    if office.get('externalId') == external_id:
                        return office
        except Exception as e:
            self.logger.error(f"Error finding office by external ID '{external_id}': {e}")
        return None

    def entity_exists(self, api_data: Dict[str, Any], yaml_data: Dict[str, Any]) -> Optional[int]:
        """
        Check if office already exists.
        Returns office ID if exists, None otherwise.
        """
        spec = yaml_data.get('spec', {})

        # Try to find by external ID first (most reliable)
        if 'externalId' in spec:
            office = self._find_office_by_external_id(spec['externalId'])
            if office:
                return office['id']

        # Fallback to name
        office = self._find_office_by_name(spec['name'])
        if office:
            return office['id']

        return None

    def discover_yaml_files(self) -> List[Path]:
        """Find all YAML files with kind: Office in the configured directory"""
        import logging
        logger = logging.getLogger(__name__)

        if not self.yaml_dir.exists():
            logger.warning(f"YAML directory does not exist: {self.yaml_dir}")
            return []

        # Get all YAML files
        all_yaml_files = list(self.yaml_dir.glob('*.yaml')) + list(self.yaml_dir.glob('*.yml'))

        # Filter by kind: Office
        filtered_files = []
        for yaml_file in all_yaml_files:
            try:
                yaml_data = self.load_yaml(yaml_file)
                if yaml_data and yaml_data.get('kind') == 'Office':
                    filtered_files.append(yaml_file)
            except Exception as e:
                logger.debug(f"Skipping {yaml_file.name}: {e}")

        logger.info(f"Found {len(filtered_files)} Office YAML files (filtered from {len(all_yaml_files)} total)")
        return sorted(filtered_files)

    def load_single(self, file_path: Path) -> str:
        """
        Load a single office from YAML file.
        Returns: 'success', 'updated', 'skipped', or error message
        """
        import logging
        logger = logging.getLogger(__name__)

        try:
            # Load YAML
            yaml_data = self.load_yaml(file_path)
            if not yaml_data:
                return "Failed to load YAML"

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name', file_path.stem)

            # Convert to API format
            api_data = self.yaml_to_fineract_api(yaml_data)
            if not api_data:
                return "Failed to convert YAML to API format"

            # Check if entity exists
            existing_id = self.entity_exists(api_data, yaml_data)

            if existing_id:
                # Entity exists - check for changes
                if self.has_changes(self.api_endpoint, existing_id, api_data):
                    # Update entity
                    logger.info(f"  ↻ Updating: {entity_name}")
                    response = self.put(f'{self.api_endpoint}/{existing_id}', api_data)
                    if response:
                        logger.info(f"  ✓ Updated: {entity_name}")
                        self.updated_entities[entity_name] = existing_id
                        return 'updated'
                    else:
                        logger.error(f"  ✗ Failed to update: {entity_name}")
                        self.failed_entities.append(file_path.name)
                        return f"Failed to update entity: {entity_name}"
                else:
                    # No changes detected
                    logger.info(f"  ⊘ No changes: {entity_name}")
                    self.skipped_entities[entity_name] = existing_id
                    return 'skipped'
            else:
                # Create new entity
                logger.info(f"  + Creating: {entity_name}")
                response = self.post(self.api_endpoint, api_data)
                if response and 'resourceId' in response:
                    entity_id = response['resourceId']
                    logger.info(f"  ✓ Created: {entity_name} (ID: {entity_id})")
                    self.loaded_entities[entity_name] = entity_id
                    return 'success'
                else:
                    logger.error(f"  ✗ Failed to create: {entity_name}")
                    self.failed_entities.append(file_path.name)
                    return f"Failed to create entity: {entity_name}"

        except Exception as e:
            logger.error(f"Error loading {file_path}: {e}")
            self.failed_entities.append(file_path.name)
            return str(e)

    def load_all(self) -> Dict[str, Any]:
        """
        Load all office YAML files.

        Offices must be loaded in hierarchy order (head office first, then branches).
        We'll do multiple passes to handle the hierarchy.
        """
        import logging
        logger = logging.getLogger(__name__)

        yaml_files = self.discover_yaml_files()
        if not yaml_files:
            return {'success': 0, 'updated': 0, 'failed': 0, 'skipped': 0, 'errors': []}

        logger.info(f"Found {len(yaml_files)} office files to process")

        # Separate head office from branches
        head_office_files = []
        branch_files = []

        for file_path in yaml_files:
            yaml_data = self.load_yaml(file_path)
            if not yaml_data:
                continue

            spec = yaml_data.get('spec', {})
            parent = spec.get('parentOffice')

            if not parent or parent == 'head-office':
                head_office_files.append(file_path)
            else:
                branch_files.append(file_path)

        # Load head office first
        logger.info("Loading head office(s)...")
        results = {'success': 0, 'updated': 0, 'failed': 0, 'skipped': 0, 'errors': []}

        for file_path in head_office_files:
            result = self.load_single(file_path)
            if result == 'success':
                results['success'] += 1
            elif result == 'updated':
                results['updated'] += 1
            elif result == 'skipped':
                results['skipped'] += 1
            else:
                results['failed'] += 1
                results['errors'].append(f"{file_path}: {result}")

        # Then load branches (may need multiple passes for nested hierarchy)
        logger.info("Loading branch offices...")
        max_passes = 5  # Prevent infinite loops
        remaining_files = branch_files.copy()

        for pass_num in range(max_passes):
            if not remaining_files:
                break

            logger.info(f"Branch loading pass {pass_num + 1}...")
            still_remaining = []

            for file_path in remaining_files:
                result = self.load_single(file_path)
                if result == 'success':
                    results['success'] += 1
                elif result == 'updated':
                    results['updated'] += 1
                elif result == 'skipped':
                    results['skipped'] += 1
                elif 'Parent office' in str(result) and 'not found' in str(result):
                    # Parent not ready yet, try again in next pass
                    still_remaining.append(file_path)
                else:
                    results['failed'] += 1
                    results['errors'].append(f"{file_path}: {result}")

            if len(still_remaining) == len(remaining_files):
                # No progress made, break to avoid infinite loop
                logger.warning(f"{len(still_remaining)} offices could not be loaded due to missing parents")
                for file_path in still_remaining:
                    results['failed'] += 1
                    results['errors'].append(f"{file_path}: Parent office not found after {pass_num + 1} passes")
                break

            remaining_files = still_remaining

        # Print summary using base class method
        self.print_summary()

        return results


def main():
    """Main entry point"""
    import logging

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    # Configuration from environment variables
    yaml_dir = os.environ.get('YAML_DIR', '../../data/dev/offices')
    fineract_url = os.environ.get('FINERACT_URL', 'http://localhost:8080/fineract-provider')
    tenant = os.environ.get('FINERACT_TENANT', 'default')

    loader = OfficesLoader(yaml_dir, fineract_url, tenant)
    results = loader.load_all()

    print(f"\n{'='*60}")
    print(f"Offices Loading Summary")
    print(f"{'='*60}")
    print(f"✓ Successfully loaded: {results['success']}")
    print(f"⊘ Skipped (already exist): {results['skipped']}")
    print(f"✗ Failed: {results['failed']}")

    if results['errors']:
        print(f"\nErrors:")
        for error in results['errors']:
            print(f"  - {error}")

    sys.exit(0 if results['failed'] == 0 else 1)


if __name__ == '__main__':
    main()
