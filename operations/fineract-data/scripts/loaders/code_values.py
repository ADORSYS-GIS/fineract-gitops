#!/usr/bin/env python3
"""
Code Values Loader
Loads dropdown code values into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class CodeValuesLoader(BaseLoader):
    """Loader for Fineract Code Values"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Code Value YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload for code
        """
        spec = yaml_data.get('spec', {})

        # Fineract API only supports 'name' parameter for code creation
        # 'systemDefined' is not a supported parameter (causes UnsupportedParameterException)
        return {
            'name': spec['codeName']
        }

    def create_code_values(self, code_id: int, values: list) -> bool:
        """
        Create code values for a code

        Args:
            code_id: Code ID
            values: List of code value dicts

        Returns:
            True if successful
        """
        success = True

        # Get existing code values
        existing_values = self.get(f'codes/{code_id}/codevalues')
        existing_names = set()
        if existing_values:
            existing_names = {v.get('name') for v in existing_values}

        for value_data in values:
            value_name = value_data['name']

            # Skip if already exists
            if value_name in existing_names:
                logger.info(f"    • Code value already exists: {value_name}")
                continue

            payload = {
                'name': value_name,
                'position': value_data.get('position', 0),
                'isActive': value_data.get('active', True),
                'description': value_data.get('description', '')
            }

            response = self.post(f'codes/{code_id}/codevalues', payload)
            if response:
                logger.info(f"    ✓ Created code value: {value_name}")
            else:
                logger.error(f"    ✗ Failed to create code value: {value_name}")
                success = False

        return success

    def load_all(self) -> dict:
        """
        Load all code value YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING CODE VALUES")
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

            # Check if it's a CodeValue kind
            if yaml_data.get('kind') != 'CodeValue':
                logger.debug(f"  Skipping (not CodeValue): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            code_name = spec.get('codeName')

            if not code_name:
                logger.error(f"  Missing codeName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Check if code already exists
            existing_codes = self.get('codes')
            code_id = None

            if existing_codes:
                for code in existing_codes:
                    if code.get('name') == code_name:
                        code_id = code.get('id')
                        logger.info(f"  Code already exists: {code_name} (ID: {code_id})")
                        break

            # Create code if it doesn't exist
            if not code_id:
                api_payload = self.yaml_to_fineract_api(yaml_data)
                response = self.post('codes', api_payload)

                if response and 'resourceId' in response:
                    code_id = response['resourceId']
                    logger.info(f"  ✓ Created code: {code_name} (ID: {code_id})")
                else:
                    logger.error(f"  ✗ Failed to create code: {code_name}")
                    self.failed_entities.append(yaml_file.name)
                    continue

            # Create code values
            values = spec.get('values', [])
            if values:
                logger.info(f"  Creating {len(values)} code values...")
                if self.create_code_values(code_id, values):
                    self.loaded_entities[code_name] = code_id
                else:
                    self.failed_entities.append(yaml_file.name)
            else:
                logger.warning(f"  No values defined for code: {code_name}")
                self.loaded_entities[code_name] = code_id

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Code Values into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = CodeValuesLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
