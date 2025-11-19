#!/usr/bin/env python3
"""
Savings Products Loader
Loads savings products into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class SavingsProductsLoader(BaseLoader):
    """Loader for Fineract Savings Products"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Savings Product YAML to Fineract API payload

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        spec = yaml_data.get('spec', {})

        # Normalize string values for mapping (handle spaces, case variations)
        def normalize(value: str) -> str:
            if not value:
                return ''
            return value.upper().replace(' ', '_')

        # Map interest compounding period types
        compounding_map = {
            'DAILY': 1,
            'MONTHLY': 4,
            'QUARTERLY': 5,
            'SEMIANNUAL': 6,
            'ANNUAL': 7
        }

        # Map interest posting period types
        posting_map = {
            'MONTHLY': 4,
            'QUARTERLY': 5,
            'ANNUAL': 7
        }

        # Map interest calculation types
        calculation_map = {
            'DAILY_BALANCE': 1,
            'AVERAGE_DAILY_BALANCE': 2
        }

        # Map days in year types
        days_in_year_map = {
            '360': 360,
            '365': 365,
            '364': 364,
            'ACTUAL': 360
        }

        # Map accounting types
        accounting_map = {
            'NONE': 1,
            'CASH': 2
        }

        # Get normalized values
        compounding = normalize(spec.get('interestCompoundingPeriod', 'MONTHLY'))
        posting = normalize(spec.get('interestPostingPeriod', 'MONTHLY'))
        calculation = normalize(spec.get('interestCalculationType', 'DAILY_BALANCE'))
        accounting_type = normalize(spec.get('accounting', {}).get('type', 'NONE'))

        payload = {
            'name': spec['name'],
            'shortName': spec.get('shortName', spec['name'][:20]),
            'description': spec.get('description', ''),

            # Currency
            'currencyCode': spec['currency'],
            'digitsAfterDecimal': spec.get('digitsAfterDecimal', 2),
            'inMultiplesOf': spec.get('inMultiplesOf', 0),

            # Interest Rate
            'nominalAnnualInterestRate': float(spec.get('nominalAnnualInterestRate', 0)),
            'minRequiredOpeningBalance': float(spec.get('minRequiredOpeningBalance', 0)),
            'minBalanceForInterestCalculation': float(spec.get('minBalanceForInterestCalculation', 0)),
            'withdrawalFeeForTransfers': spec.get('withdrawalFeeForTransfers', False),
            'allowOverdraft': spec.get('allowOverdraft', False),

            # Interest Calculation
            'interestCompoundingPeriodType': compounding_map.get(compounding, 4),
            'interestPostingPeriodType': posting_map.get(posting, 4),
            'interestCalculationType': calculation_map.get(calculation, 1),
            'interestCalculationDaysInYearType': days_in_year_map.get(
                str(spec.get('daysInYear', 365)), 365
            ),

            # Accounting
            'accountingRule': accounting_map.get(accounting_type, 1),

            # Settings
            'withdrawalFeeApplicableForTransfer': spec.get('withdrawalFeeForTransfers', False),
            'isDormancyTrackingActive': spec.get('dormancyTracking', {}).get('enabled', False),
            'enforceMinRequiredBalance': spec.get('enforceMinRequiredBalance', False),
            'withHoldTax': spec.get('withHoldTax', False),

            # Dates
            'dateFormat': 'yyyy-MM-dd',
            'locale': 'en'
        }

        # Add charges if present
        if 'charges' in spec:
            charge_ids = []
            for charge_ref in spec['charges']:
                charge_id = self._resolve_charge(charge_ref)
                if charge_id:
                    charge_ids.append(charge_id)
            if charge_ids:
                payload['charges'] = charge_ids

        # Add accounting mappings if using accounting
        accounting = spec.get('accounting', {})
        if accounting_type == 'CASH':
            # Resolve GL account references
            savings_ref_id = self._resolve_gl_account(accounting.get('savingsReference'))
            savings_control_id = self._resolve_gl_account(accounting.get('savingsControl'))
            transfer_suspense_id = self._resolve_gl_account(accounting.get('transferInSuspense'))
            interest_payable_id = self._resolve_gl_account(accounting.get('interestOnSavings'))
            fee_income_id = self._resolve_gl_account(accounting.get('incomeFromFees'))
            penalty_income_id = self._resolve_gl_account(accounting.get('incomeFromPenalties'))
            overdraft_control_id = self._resolve_gl_account(accounting.get('overdraftControl'))

            if savings_ref_id:
                payload['savingsReferenceAccountId'] = savings_ref_id
            if savings_control_id:
                payload['savingsControlAccountId'] = savings_control_id
            if transfer_suspense_id:
                payload['transfersInSuspenseAccountId'] = transfer_suspense_id
            if interest_payable_id:
                payload['interestOnSavingsAccountId'] = interest_payable_id
            if fee_income_id:
                payload['incomeFromFeeAccountId'] = fee_income_id
            if penalty_income_id:
                payload['incomeFromPenaltyAccountId'] = penalty_income_id
            if overdraft_control_id:
                payload['overdraftPortfolioControlId'] = overdraft_control_id

        return payload

    def _resolve_charge(self, charge_ref: str) -> int:
        """
        Resolve charge name to ID

        Args:
            charge_ref: Charge name

        Returns:
            Charge ID or None
        """
        if not charge_ref:
            return None

        try:
            charges = self.get('charges')
            for charge in charges:
                if charge.get('name') == charge_ref:
                    return charge.get('id')
            logger.warning(f"  ⚠ Charge not found: {charge_ref}")
            return None
        except Exception as e:
            logger.error(f"  Error resolving charge '{charge_ref}': {e}")
            return None

    def load_all(self) -> dict:
        """
        Load all savings product YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING SAVINGS PRODUCTS")
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

            # Check if it's a SavingsProduct kind
            if yaml_data.get('kind') != 'SavingsProduct':
                logger.debug(f"  Skipping (not SavingsProduct): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            product_name = spec.get('name')

            if not product_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Convert to API format
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Check if product already exists
            existing_id = self.entity_exists('savingsproducts', product_name)

            if existing_id:
                # Entity exists - check for changes
                if self.has_changes('/savingsproducts', existing_id, api_payload):
                    # Update entity
                    logger.info(f"  ↻ Updating: {product_name}")
                    response = self.put(f'/savingsproducts/{existing_id}', api_payload)
                    if response:
                        logger.info(f"  ✓ Updated: {product_name} (ID: {existing_id})")
                        self.updated_entities[product_name] = existing_id
                    else:
                        logger.error(f"  ✗ Failed to update: {product_name}")
                        self.failed_entities.append(yaml_file.name)
                else:
                    # No changes detected
                    logger.info(f"  ⊘ No changes: {product_name} (ID: {existing_id})")
                    self.skipped_entities[product_name] = existing_id
                continue

            # Create product
            response = self.post('savingsproducts', api_payload)

            if response and 'resourceId' in response:
                product_id = response['resourceId']
                logger.info(f"  ✓ Created savings product: {product_name} (ID: {product_id})")
                self.loaded_entities[product_name] = product_id
            else:
                logger.error(f"  ✗ Failed to create savings product: {product_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Savings Products into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = SavingsProductsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
