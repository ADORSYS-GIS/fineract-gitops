#!/usr/bin/env python3
"""
Loan Products Loader
Loads loan products into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class LoanProductsLoader(BaseLoader):
    """Loader for Fineract Loan Products"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Loan Product YAML to Fineract API payload

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

        # Map frequency types
        frequency_map = {
            'DAYS': 0,
            'WEEKS': 1,
            'MONTHS': 2,
            'MONTHLY': 2,
            'YEARS': 3
        }

        # Map interest types
        interest_type_map = {
            'FLAT': 0,
            'DECLINING_BALANCE': 1
        }

        # Map amortization types
        amortization_map = {
            'EQUAL_INSTALLMENTS': 1,
            'EQUAL_PRINCIPAL': 0
        }

        # Map interest calculation period types
        interest_calc_period_map = {
            'DAILY': 0,
            'SAME_AS_REPAYMENT_PERIOD': 1
        }

        # Map accounting types
        accounting_map = {
            'NONE': 1,
            'CASH': 2,
            'ACCRUAL_PERIODIC': 3,
            'ACCRUAL_UPFRONT': 4
        }

        # Get normalized values
        repayment_freq = normalize(spec.get('repaymentFrequency', 'MONTHS'))
        interest_type = normalize(spec.get('interestRate', {}).get('type', 'DECLINING_BALANCE'))
        amortization = normalize(spec.get('amortizationType', 'EQUAL_INSTALLMENTS'))
        interest_calc = normalize(spec.get('interestCalculationPeriod', 'SAME_AS_REPAYMENT_PERIOD'))
        accounting_type = normalize(spec.get('accounting', {}).get('type', 'NONE'))

        payload = {
            'name': spec['name'],
            'shortName': spec.get('shortName', spec['name'][:20]),
            'description': spec.get('description', ''),

            # Currency
            'currencyCode': spec['currency'],
            'digitsAfterDecimal': spec.get('digitsAfterDecimal', 2),
            'inMultiplesOf': spec.get('inMultiplesOf', 0),

            # Principal
            'principal': float(spec['principal']['default']),
            'minPrincipal': float(spec['principal']['min']),
            'maxPrincipal': float(spec['principal']['max']),

            # Interest Rate
            'interestRatePerPeriod': float(spec['interestRate']['default']),
            'minInterestRatePerPeriod': float(spec['interestRate']['min']),
            'maxInterestRatePerPeriod': float(spec['interestRate']['max']),
            'interestType': interest_type_map.get(interest_type, 1),
            'interestCalculationPeriodType': interest_calc_period_map.get(interest_calc, 1),

            # Repayments
            'numberOfRepayments': int(spec['numberOfRepayments']['default']),
            'minNumberOfRepayments': int(spec['numberOfRepayments']['min']),
            'maxNumberOfRepayments': int(spec['numberOfRepayments']['max']),
            'repaymentEvery': int(spec.get('repaymentEvery', 1)),
            'repaymentFrequencyType': frequency_map.get(repayment_freq, 2),

            # Amortization
            'amortizationType': amortization_map.get(amortization, 1),

            # Grace periods
            'graceOnPrincipalPayment': spec.get('gracePeriods', {}).get('principal', 0),
            'graceOnInterestPayment': spec.get('gracePeriods', {}).get('interest', 0),
            'graceOnInterestCharged': spec.get('gracePeriods', {}).get('interestCharged', 0),

            # Settings
            'allowPartialPeriodInterestCalcualtion': spec.get('allowPartialPeriodInterestCalculation', True),
            'canDefineInstallmentAmount': spec.get('canDefineInstallmentAmount', False),
            'isInterestRecalculationEnabled': spec.get('interestRecalculation', {}).get('enabled', False),
            'holdGuaranteeFunds': spec.get('holdGuaranteeFunds', False),
            'multiDisburseLoan': spec.get('multiDisburseLoan', False),
            'canUseForTopup': spec.get('canUseForTopup', False),

            # Transaction processing strategy
            'transactionProcessingStrategyId': spec.get('transactionProcessingStrategyId', 1),

            # Accounting
            'accountingRule': accounting_map.get(accounting_type, 1),

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
        if accounting_type in ['CASH', 'ACCRUAL_PERIODIC', 'ACCRUAL_UPFRONT']:
            # Resolve GL account references
            fund_source_id = self._resolve_gl_account(accounting.get('fundSource'))
            loan_portfolio_id = self._resolve_gl_account(accounting.get('loanPortfolio'))
            transfer_suspense_id = self._resolve_gl_account(accounting.get('transferInSuspense'))
            interest_income_id = self._resolve_gl_account(accounting.get('interestOnLoans'))
            fee_income_id = self._resolve_gl_account(accounting.get('incomeFromFees'))
            penalty_income_id = self._resolve_gl_account(accounting.get('incomeFromPenalties'))
            overpayment_id = self._resolve_gl_account(accounting.get('overpaymentLiability'))

            if fund_source_id:
                payload['fundSourceAccountId'] = fund_source_id
            if loan_portfolio_id:
                payload['loanPortfolioAccountId'] = loan_portfolio_id
            if transfer_suspense_id:
                payload['transfersInSuspenseAccountId'] = transfer_suspense_id
            if interest_income_id:
                payload['interestOnLoanAccountId'] = interest_income_id
            if fee_income_id:
                payload['incomeFromFeeAccountId'] = fee_income_id
            if penalty_income_id:
                payload['incomeFromPenaltyAccountId'] = penalty_income_id
            if overpayment_id:
                payload['overpaymentLiabilityAccountId'] = overpayment_id

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
        Load all loan product YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING LOAN PRODUCTS")
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

            # Check if it's a LoanProduct kind
            if yaml_data.get('kind') != 'LoanProduct':
                logger.debug(f"  Skipping (not LoanProduct): {yaml_file.name}")
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
            existing_id = self.entity_exists('loanproducts', product_name)

            if existing_id:
                # Entity exists - check for changes
                if self.has_changes('/loanproducts', existing_id, api_payload):
                    # Update entity
                    logger.info(f"  ↻ Updating: {product_name}")
                    response = self.put(f'/loanproducts/{existing_id}', api_payload)
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
            response = self.post('loanproducts', api_payload)

            if response and 'resourceId' in response:
                product_id = response['resourceId']
                logger.info(f"  ✓ Created loan product: {product_name} (ID: {product_id})")
                self.loaded_entities[product_name] = product_id
            else:
                logger.error(f"  ✗ Failed to create loan product: {product_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Loan Products into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = LoanProductsLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
