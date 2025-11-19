#!/usr/bin/env python3
"""
Fineract Staff Loader with Keycloak User Sync
Loads staff members into Fineract and creates corresponding Keycloak users
"""
import os
import sys
import argparse
import requests
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent))
from base_loader import BaseLoader, logger


class StaffLoader(BaseLoader):
    """Loader for Fineract Staff with Keycloak integration"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        super().__init__(yaml_dir, fineract_url, tenant)
        self.entity_type = 'Staff'
        self.api_endpoint = '/staff'

        # Keycloak user sync configuration
        self.user_sync_url = os.getenv('USER_SYNC_SERVICE_URL', 'http://user-sync-service:5000')
        self.default_password = os.getenv('DEFAULT_PASSWORD', 'ChangeMe123!')
        self.create_keycloak_users = os.getenv('CREATE_KEYCLOAK_USERS', 'true').lower() == 'true'

        # Track user creation results
        self.keycloak_success = []
        self.keycloak_failed = []

    def yaml_to_fineract_api(self, yaml_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert Staff YAML to Fineract API payload

        YAML format:
            spec:
              firstName: John
              lastName: Doe
              officeId: head-office
              isLoanOfficer: true
              emailAddress: john.doe@example.com
              mobileNo: "+254712345678"
              username: john.doe      # For Keycloak
              role: Loan Officer       # For Keycloak

        Fineract API format:
            {
              "firstname": "John",
              "lastname": "Doe",
              "officeId": 1,
              "isLoanOfficer": true,
              "dateFormat": "dd MMMM yyyy",
              "locale": "en"
            }
        """
        spec = yaml_data.get('spec', {})

        # Build API payload
        api_data = {
            'firstname': spec.get('firstName', ''),
            'lastname': spec.get('lastName', ''),
            'isLoanOfficer': spec.get('isLoanOfficer', False),
            'isActive': spec.get('isActive', True),
            'dateFormat': 'dd MMMM yyyy',
            'locale': 'en'
        }

        # Resolve office ID
        office_ref = spec.get('officeId', 'head-office')
        api_data['officeId'] = self._resolve_office_id(office_ref)

        # Optional fields
        if spec.get('externalId'):
            api_data['externalId'] = spec['externalId']
        # Fineract expects 'mobileNo', not 'mobileNumber'
        if spec.get('mobileNo'):
            api_data['mobileNo'] = spec['mobileNo']
        # Note: emailAddress is NOT a supported parameter for staff creation API
        # Email is typically stored in user accounts, not staff records

        # Joining date (if provided)
        if spec.get('joiningDate'):
            date_obj = datetime.strptime(spec['joiningDate'], '%Y-%m-%d')
            api_data['joiningDate'] = date_obj.strftime('%d %B %Y')

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

        return 1  # Default to head office (ID 1)

    def entity_exists(self, api_data: Dict[str, Any], yaml_data: Dict[str, Any]) -> Optional[int]:
        """Check if staff member already exists"""
        spec = yaml_data.get('spec', {})

        # Try to find by external ID first
        if spec.get('externalId'):
            try:
                response = self.get('/staff')
                if response:
                    for staff in response:
                        if staff.get('externalId') == spec['externalId']:
                            return staff['id']
            except:
                pass

        # Fallback to name matching
        try:
            firstname = spec.get('firstName', '')
            lastname = spec.get('lastName', '')
            response = self.get('/staff')
            if response:
                for staff in response:
                    if (staff.get('firstname') == firstname and
                        staff.get('lastname') == lastname):
                        return staff['id']
        except:
            pass

        return None

    def sync_to_keycloak(self, staff_id: int, yaml_data: Dict[str, Any]) -> bool:
        """
        Sync staff member to Keycloak as a user

        Args:
            staff_id: Fineract staff ID
            yaml_data: YAML data with username and role

        Returns:
            True if successful, False otherwise
        """
        if not self.create_keycloak_users:
            logger.info("  Keycloak user creation disabled (CREATE_KEYCLOAK_USERS=false)")
            return True

        spec = yaml_data.get('spec', {})

        # Check if username and role are provided
        username = spec.get('username', '').strip()
        role = spec.get('role', '').strip()

        if not username:
            logger.warning("  No username provided, skipping Keycloak user creation")
            return True  # Not an error, just skip

        if not role:
            logger.warning(f"  No role provided for user '{username}', skipping Keycloak user creation")
            return True  # Not an error, just skip

        # Prepare user sync payload
        payload = {
            'userId': staff_id,
            'username': username,
            'email': spec.get('emailAddress', f'{username}@example.com'),
            'firstName': spec.get('firstName', ''),
            'lastName': spec.get('lastName', ''),
            'role': role,
            'officeId': spec.get('officeId', 'head-office'),
            'employeeId': spec.get('externalId', f'STAFF-{staff_id}'),
            'mobileNumber': spec.get('mobileNo', '')
        }

        try:
            logger.info(f"  Creating Keycloak user: {username} (role: {role})")

            response = requests.post(
                f'{self.user_sync_url}/sync/user',
                json=payload,
                timeout=30,
                headers={'Content-Type': 'application/json'}
            )

            if response.status_code == 200:
                result = response.json()
                logger.info(f"  ✓ Keycloak user created: {username}")
                logger.info(f"    Temp password: {self.default_password}")
                logger.info(f"    Required actions: {result.get('required_actions', [])}")
                self.keycloak_success.append(username)
                return True
            else:
                error_msg = response.text
                logger.error(f"  ✗ Keycloak user creation failed: {error_msg}")
                self.keycloak_failed.append((username, error_msg))
                return False

        except requests.exceptions.ConnectionError:
            logger.error(f"  ✗ Cannot connect to user-sync-service at {self.user_sync_url}")
            self.keycloak_failed.append((username, "Connection error"))
            return False
        except Exception as e:
            logger.error(f"  ✗ Keycloak sync error: {e}")
            self.keycloak_failed.append((username, str(e)))
            return False

    def load_all(self) -> Dict[str, Any]:
        """Load all staff YAML files"""
        logger.info("=" * 80)
        logger.info("LOADING STAFF (with Keycloak user sync)")
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
            if yaml_data.get('kind') != 'Staff':
                logger.debug(f"  Skipping (not Staff): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            staff_name = f"{spec.get('firstName', '')} {spec.get('lastName', '')}".strip()

            if not staff_name:
                logger.error(f"  Missing firstName/lastName in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Convert to API format
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Check if entity already exists
            existing_id = self.entity_exists(api_payload, yaml_data)

            if existing_id:
                # Entity exists - check for changes
                if self.has_changes(self.api_endpoint, existing_id, api_payload):
                    # Update entity
                    logger.info(f"  ↻ Updating: {staff_name}")
                    response = self.put(f'{self.api_endpoint}/{existing_id}', api_payload)
                    if response:
                        logger.info(f"  ✓ Updated: {staff_name} (ID: {existing_id})")
                        self.updated_entities[staff_name] = existing_id

                        # Sync to Keycloak after update
                        # COMMENTED OUT: user-sync-service is optional and not available in this environment
                        # if spec.get('username'):
                        #     self.sync_to_keycloak(existing_id, yaml_data)
                    else:
                        logger.error(f"  ✗ Failed to update: {staff_name}")
                        self.failed_entities.append(yaml_file.name)
                else:
                    # No changes detected
                    logger.info(f"  ⊘ No changes: {staff_name} (ID: {existing_id})")
                    self.skipped_entities[staff_name] = existing_id

                    # Still try to sync to Keycloak if username provided
                    # COMMENTED OUT: user-sync-service is optional and not available in this environment
                    # if spec.get('username'):
                    #     self.sync_to_keycloak(existing_id, yaml_data)

                continue

            # Create staff in Fineract
            response = self.post('/staff', api_payload)

            if response and 'resourceId' in response:
                staff_id = response['resourceId']
                logger.info(f"  ✓ Created staff: {staff_name} (ID: {staff_id})")
                self.loaded_entities[staff_name] = staff_id

                # Sync to Keycloak
                # COMMENTED OUT: user-sync-service is optional and not available in this environment
                # self.sync_to_keycloak(staff_id, yaml_data)
            else:
                logger.error(f"  ✗ Failed to create staff: {staff_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()

    def print_summary(self):
        """Print loading summary with Keycloak stats"""
        super().print_summary()

        if self.create_keycloak_users:
            logger.info("\n" + "=" * 80)
            logger.info("KEYCLOAK USER SYNC SUMMARY")
            logger.info("=" * 80)
            logger.info(f"✓ Users created: {len(self.keycloak_success)}")
            logger.info(f"✗ Users failed: {len(self.keycloak_failed)}")

            if self.keycloak_success:
                logger.info(f"\nSuccessful user creations:")
                for username in self.keycloak_success:
                    logger.info(f"  - {username}")
                logger.info(f"\n  Default password: {self.default_password}")
                logger.info(f"  Users must change password on first login")

            if self.keycloak_failed:
                logger.info(f"\nFailed user creations:")
                for username, error in self.keycloak_failed:
                    logger.info(f"  - {username}: {error}")


def main():
    parser = argparse.ArgumentParser(description='Load Staff into Fineract with Keycloak user sync')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = StaffLoader(args.yaml_dir, args.fineract_url, args.tenant)

    try:
        summary = loader.load_all()
        loader.print_summary()

        # Exit with error code if any Fineract failures (Keycloak failures are logged but don't fail the job)
        if summary['total_failed'] > 0:
            sys.exit(1)
        else:
            sys.exit(0)

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
