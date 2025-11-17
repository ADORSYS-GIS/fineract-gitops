#!/usr/bin/env python3
"""
Data Load Validation Script
Validates that data loading jobs completed successfully and expected entities exist
"""
import os
import sys
import requests
import logging
from typing import Dict, List, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DataLoadValidator:
    """Validates that Fineract data loading completed successfully"""

    def __init__(self, fineract_url: str, tenant: str = 'default'):
        """
        Initialize validator

        Args:
            fineract_url: Fineract API base URL
            tenant: Tenant identifier
        """
        self.fineract_url = fineract_url.rstrip('/')
        self.tenant = tenant

        # Get authentication configuration from environment
        self.client_id = os.getenv('FINERACT_CLIENT_ID')
        self.client_secret = os.getenv('FINERACT_CLIENT_SECRET')
        self.token_url = os.getenv('FINERACT_TOKEN_URL')
        self.username = os.getenv('FINERACT_USERNAME', 'mifos')
        self.password = os.getenv('FINERACT_PASSWORD', 'password')

        # Create session
        self.session = requests.Session()
        self.session.headers.update({
            'Fineract-Platform-TenantId': self.tenant,
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })

        # Set up authentication
        if self.client_id and self.client_secret and self.token_url:
            logger.info("Using OAuth2 client credentials authentication")
            self._obtain_oauth2_token()
        else:
            logger.info("Using Basic Authentication")
            self.session.auth = (self.username, self.password)

        # Validation results
        self.validation_results = {}
        self.errors = []
        self.warnings = []

    def _obtain_oauth2_token(self):
        """Obtain OAuth2 access token"""
        import time
        try:
            response = requests.post(
                self.token_url,
                data={
                    'grant_type': 'client_credentials',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret,
                    'scope': 'openid profile email'
                },
                timeout=30
            )
            response.raise_for_status()
            token_data = response.json()

            self.access_token = token_data.get('access_token')
            expires_in = token_data.get('expires_in', 3600)
            self.token_expiry = time.time() + expires_in

            self.session.headers.update({
                'Authorization': f'Bearer {self.access_token}'
            })
            logger.info("OAuth2 token obtained successfully")
        except Exception as e:
            logger.error(f"Failed to obtain OAuth2 token: {e}")
            raise

    def get(self, endpoint: str) -> Any:
        """Make GET request to Fineract API"""
        try:
            url = f"{self.fineract_url}{endpoint}"
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"GET {endpoint} failed: {e}")
            raise

    def validate_offices(self) -> bool:
        """Validate that offices were created"""
        logger.info("Validating offices...")
        try:
            offices = self.get('/fineract-provider/api/v1/offices')
            if not offices or len(offices) == 0:
                self.errors.append("No offices found - at least Head Office should exist")
                return False

            office_count = len(offices)
            logger.info(f"✓ Found {office_count} office(s)")
            self.validation_results['offices'] = {
                'status': 'PASS',
                'count': office_count,
                'names': [o.get('name') for o in offices]
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate offices: {e}")
            return False

    def validate_users(self) -> bool:
        """Validate that staff users were created"""
        logger.info("Validating users...")
        try:
            users = self.get('/fineract-provider/api/v1/users')
            if not users or len(users) == 0:
                self.errors.append("No users found - admin users should exist")
                return False

            user_count = len(users)
            logger.info(f"✓ Found {user_count} user(s)")
            self.validation_results['users'] = {
                'status': 'PASS',
                'count': user_count
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate users: {e}")
            return False

    def validate_roles(self) -> bool:
        """Validate that roles were created"""
        logger.info("Validating roles...")
        try:
            roles = self.get('/fineract-provider/api/v1/roles')
            if not roles or len(roles) == 0:
                self.warnings.append("No custom roles found - only using default roles")
                return True

            role_count = len(roles)
            logger.info(f"✓ Found {role_count} role(s)")
            self.validation_results['roles'] = {
                'status': 'PASS',
                'count': role_count
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate roles: {e}")
            return False

    def validate_code_values(self) -> bool:
        """Validate that code values were created"""
        logger.info("Validating code values...")
        try:
            codes = self.get('/fineract-provider/api/v1/codes')
            if not codes or len(codes) == 0:
                self.warnings.append("No code values found")
                return True

            code_count = len(codes)
            logger.info(f"✓ Found {code_count} code(s)")
            self.validation_results['codes'] = {
                'status': 'PASS',
                'count': code_count
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate codes: {e}")
            return False

    def validate_loan_products(self) -> bool:
        """Validate that loan products were created"""
        logger.info("Validating loan products...")
        try:
            products = self.get('/fineract-provider/api/v1/loanproducts')
            if not products or len(products) == 0:
                self.warnings.append("No loan products found - may be expected for fresh install")
                self.validation_results['loan_products'] = {
                    'status': 'WARN',
                    'count': 0
                }
                return True

            product_count = len(products)
            logger.info(f"✓ Found {product_count} loan product(s)")
            self.validation_results['loan_products'] = {
                'status': 'PASS',
                'count': product_count,
                'names': [p.get('name') for p in products]
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate loan products: {e}")
            return False

    def validate_savings_products(self) -> bool:
        """Validate that savings products were created"""
        logger.info("Validating savings products...")
        try:
            products = self.get('/fineract-provider/api/v1/savingsproducts')
            if not products or len(products) == 0:
                self.warnings.append("No savings products found - may be expected for fresh install")
                self.validation_results['savings_products'] = {
                    'status': 'WARN',
                    'count': 0
                }
                return True

            product_count = len(products)
            logger.info(f"✓ Found {product_count} savings product(s)")
            self.validation_results['savings_products'] = {
                'status': 'PASS',
                'count': product_count,
                'names': [p.get('name') for p in products]
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate savings products: {e}")
            return False

    def validate_gl_accounts(self) -> bool:
        """Validate that GL accounts were created"""
        logger.info("Validating GL accounts...")
        try:
            accounts = self.get('/fineract-provider/api/v1/glaccounts')
            if not accounts or len(accounts) == 0:
                self.warnings.append("No GL accounts found - may be expected for fresh install")
                return True

            account_count = len(accounts)
            logger.info(f"✓ Found {account_count} GL account(s)")
            self.validation_results['gl_accounts'] = {
                'status': 'PASS',
                'count': account_count
            }
            return True
        except Exception as e:
            self.errors.append(f"Failed to validate GL accounts: {e}")
            return False

    def run_all_validations(self) -> bool:
        """Run all validation checks"""
        logger.info("=" * 60)
        logger.info("Starting data load validation")
        logger.info("=" * 60)

        # Critical validations (must pass)
        critical_checks = [
            ('Offices', self.validate_offices),
            ('Users', self.validate_users),
            ('Roles', self.validate_roles),
        ]

        # Optional validations (warnings only)
        optional_checks = [
            ('Code Values', self.validate_code_values),
            ('Loan Products', self.validate_loan_products),
            ('Savings Products', self.validate_savings_products),
            ('GL Accounts', self.validate_gl_accounts),
        ]

        all_passed = True

        # Run critical checks
        for name, check_func in critical_checks:
            if not check_func():
                all_passed = False

        # Run optional checks
        for name, check_func in optional_checks:
            try:
                check_func()
            except Exception as e:
                logger.warning(f"Optional check '{name}' failed: {e}")

        # Print summary
        logger.info("=" * 60)
        logger.info("Validation Summary")
        logger.info("=" * 60)

        for entity_type, result in self.validation_results.items():
            status = result['status']
            count = result.get('count', 0)
            symbol = "✓" if status == "PASS" else "⚠"
            logger.info(f"{symbol} {entity_type}: {count} entities ({status})")

        if self.warnings:
            logger.info("")
            logger.info("Warnings:")
            for warning in self.warnings:
                logger.warning(f"  ⚠ {warning}")

        if self.errors:
            logger.info("")
            logger.info("Errors:")
            for error in self.errors:
                logger.error(f"  ✗ {error}")

        logger.info("=" * 60)

        if all_passed:
            logger.info("✓ Data load validation PASSED")
            return True
        else:
            logger.error("✗ Data load validation FAILED")
            return False


def main():
    """Main entry point"""
    fineract_url = os.getenv('FINERACT_URL', 'http://fineract-write-service:8443')
    tenant = os.getenv('FINERACT_TENANT', 'default')

    validator = DataLoadValidator(fineract_url, tenant)

    try:
        if validator.run_all_validations():
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        logger.error(f"Validation failed with error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
