#!/usr/bin/env python3
"""
Charges Loader
Loads fees and charges into Fineract from YAML files
"""
import sys
import argparse
from pathlib import Path
from base_loader import BaseLoader, logger


class ChargesLoader(BaseLoader):
    """Loader for Fineract Charges"""

    def yaml_to_fineract_api(self, yaml_data: dict) -> dict:
        """
        Convert Charges YAML to Fineract API payload

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

        # Map charge applies to types
        charge_applies_to_map = {
            'LOAN': 1,
            'SAVINGS': 2,
            'CLIENT': 3,
            'SHARES': 4
        }

        # Map charge time types
        charge_time_type_map = {
            'DISBURSEMENT': 1,
            'SPECIFIED_DUE_DATE': 2,
            'SAVINGS_ACTIVATION': 3,
            'SAVINGS_CLOSURE': 4,
            'WITHDRAWAL_FEE': 5,
            'ANNUAL_FEE': 6,
            'MONTHLY_FEE': 7,
            'INSTALLMENT_FEE': 8,
            'OVERDUE_INSTALLMENT': 9,
            'OVERDRAFT_FEE': 10,
            'WEEKLY_FEE': 11,
            'TRANCHE_DISBURSEMENT': 12,
            'SHAREACCOUNT_ACTIVATION': 13,
            'SHARE_PURCHASE': 14,
            'SHARE_REDEEM': 15
        }

        # Map charge calculation types
        charge_calc_type_map = {
            'FLAT': 1,
            'PERCENTAGE_OF_AMOUNT': 2,
            'PERCENTAGE_OF_AMOUNT_AND_INTEREST': 3,
            'PERCENTAGE_OF_INTEREST': 4,
            'PERCENTAGE_OF_DISBURSEMENT_AMOUNT': 5
        }

        # Map charge payment modes
        charge_payment_mode_map = {
            'REGULAR': 0,
            'ACCOUNT_TRANSFER': 1
        }

        # Get normalized values
        applies_to = normalize(spec.get('chargeAppliesTo', 'LOAN'))
        time_type = normalize(spec.get('chargeTimeType', 'DISBURSEMENT'))
        calc_type = normalize(spec.get('chargeCalculationType', 'FLAT'))
        payment_mode = normalize(spec.get('chargePaymentMode', 'REGULAR'))

        payload = {
            'name': spec.get('name'),
            'currencyCode': spec.get('currency', 'XAF'),
            'amount': float(spec.get('amount', 0)),

            # Charge type configuration
            'chargeAppliesTo': charge_applies_to_map.get(applies_to, 1),
            'chargeTimeType': charge_time_type_map.get(time_type, 1),
            'chargeCalculationType': charge_calc_type_map.get(calc_type, 1),
            'chargePaymentMode': charge_payment_mode_map.get(payment_mode, 0),

            # Settings
            'active': spec.get('active', True),
            'penalty': spec.get('penalty', False),

            # Locale
            'locale': 'en',
            'monthDayFormat': 'dd MMM'
        }

        # Add optional fields
        if 'minCap' in spec:
            payload['minCap'] = float(spec['minCap'])
        if 'maxCap' in spec:
            payload['maxCap'] = float(spec['maxCap'])

        # Add fee frequency if it's a recurring charge
        if 'feeFrequency' in spec:
            payload['feeFrequency'] = spec['feeFrequency']
        if 'feeInterval' in spec:
            payload['feeInterval'] = int(spec['feeInterval'])

        # Add GL account for income if using accounting
        if 'incomeAccount' in spec:
            income_account_id = self._resolve_gl_account(spec['incomeAccount'])
            if income_account_id:
                payload['incomeAccountId'] = income_account_id

        # Add tax group if specified
        if 'taxGroup' in spec:
            tax_group_id = self._resolve_tax_group(spec['taxGroup'])
            if tax_group_id:
                payload['taxGroupId'] = tax_group_id

        return payload

    def _resolve_tax_group(self, tax_group_name: str) -> int:
        """
        Resolve tax group name to ID

        Args:
            tax_group_name: Tax group name

        Returns:
            Tax group ID or None
        """
        if not tax_group_name:
            return None

        try:
            tax_groups = self.get('taxes/group')
            for group in tax_groups:
                if group.get('name') == tax_group_name:
                    return group.get('id')
            logger.warning(f"  ⚠ Tax group not found: {tax_group_name}")
            return None
        except Exception as e:
            logger.error(f"  Error resolving tax group '{tax_group_name}': {e}")
            return None

    def load_all(self) -> dict:
        """
        Load all fees and charges YAML files

        Returns:
            Summary dict
        """
        logger.info("=" * 80)
        logger.info("LOADING CHARGES")
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

            # Check if it's the correct kind
            if yaml_data.get('kind') != 'Charge':
                logger.warning(f"  Skipping (not Charge): {yaml_file.name}")
                continue

            spec = yaml_data.get('spec', {})
            entity_name = spec.get('name')

            if not entity_name:
                logger.error(f"  Missing name in spec")
                self.failed_entities.append(yaml_file.name)
                continue

            # Convert to API format
            api_payload = self.yaml_to_fineract_api(yaml_data)

            # Check if entity already exists
            existing_id = self.entity_exists('charges', entity_name)

            if existing_id:
                # Entity exists - check for changes
                if self.has_changes('/charges', existing_id, api_payload):
                    # Update entity
                    logger.info(f"  ↻ Updating: {entity_name}")
                    response = self.put(f'/charges/{existing_id}', api_payload)
                    if response:
                        logger.info(f"  ✓ Updated: {entity_name} (ID: {existing_id})")
                        self.updated_entities[entity_name] = existing_id
                    else:
                        logger.error(f"  ✗ Failed to update: {entity_name}")
                        self.failed_entities.append(yaml_file.name)
                else:
                    # No changes detected
                    logger.info(f"  ⊘ No changes: {entity_name} (ID: {existing_id})")
                    self.skipped_entities[entity_name] = existing_id
                continue

            # Create entity
            response = self.post('charges', api_payload)

            if response and 'resourceId' in response:
                entity_id = response['resourceId']
                logger.info(f"  ✓ Created fees and charges: {entity_name} (ID: {entity_id})")
                self.loaded_entities[entity_name] = entity_id
            else:
                logger.error(f"  ✗ Failed to create fees and charges: {entity_name}")
                self.failed_entities.append(yaml_file.name)

        return self.get_summary()


def main():
    parser = argparse.ArgumentParser(description='Load Charges into Fineract')
    parser.add_argument('--yaml-dir', required=True, help='Directory containing YAML files')
    parser.add_argument('--fineract-url', required=True, help='Fineract API base URL')
    parser.add_argument('--tenant', default='default', help='Tenant identifier')

    args = parser.parse_args()

    loader = ChargesLoader(args.yaml_dir, args.fineract_url, args.tenant)

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
