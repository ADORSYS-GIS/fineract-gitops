#!/usr/bin/env python3
"""
YAML Data Validation Script
Validates YAML files before running loaders to catch errors early
"""

import sys
import argparse
from pathlib import Path
import yaml
from typing import Dict, List, Tuple
import re

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

def validate_yaml_syntax(file_path: Path) -> Tuple[bool, str]:
    """
    Validate YAML file can be parsed

    Returns:
        (is_valid, error_message)
    """
    try:
        with open(file_path, 'r') as f:
            yaml.safe_load(f)
        return True, ""
    except yaml.YAMLError as e:
        return False, f"YAML syntax error: {e}"
    except Exception as e:
        return False, f"Error reading file: {e}"

def validate_fineract_structure(yaml_data: dict, file_path: Path) -> List[str]:
    """
    Validate Fineract YAML structure

    Returns:
        List of validation errors (empty if valid)
    """
    errors = []

    # Check required top-level fields
    if 'apiVersion' not in yaml_data:
        errors.append("Missing 'apiVersion' field")
    elif not yaml_data['apiVersion'].startswith('fineract.apache.org/'):
        errors.append(f"Invalid apiVersion: {yaml_data['apiVersion']}")

    if 'kind' not in yaml_data:
        errors.append("Missing 'kind' field")

    if 'metadata' not in yaml_data:
        errors.append("Missing 'metadata' field")
    else:
        metadata = yaml_data['metadata']
        if 'name' not in metadata:
            errors.append("Missing 'metadata.name' field")

    if 'spec' not in yaml_data:
        errors.append("Missing 'spec' field")

    return errors

def validate_gl_account(spec: dict) -> List[str]:
    """Validate GLAccount specific fields"""
    errors = []

    required_fields = ['name', 'glCode', 'type', 'usage']
    for field in required_fields:
        if field not in spec:
            errors.append(f"Missing required field: spec.{field}")

    # Validate type
    valid_types = ['Asset', 'Liability', 'Equity', 'Income', 'Expense']
    if 'type' in spec and spec['type'] not in valid_types:
        errors.append(f"Invalid type: {spec['type']}. Must be one of {valid_types}")

    # Validate usage
    valid_usage = ['Detail', 'Header']
    if 'usage' in spec and spec['usage'] not in valid_usage:
        errors.append(f"Invalid usage: {spec['usage']}. Must be one of {valid_usage}")

    # Validate glCode format (should be numeric string)
    if 'glCode' in spec:
        gl_code = str(spec['glCode'])
        if not re.match(r'^\d+$', gl_code):
            errors.append(f"Invalid glCode format: {gl_code}. Should be numeric")

    return errors

def validate_tax_group(spec: dict) -> List[str]:
    """Validate TaxGroup specific fields"""
    errors = []

    if 'name' not in spec:
        errors.append("Missing required field: spec.name")

    if 'taxComponents' not in spec:
        errors.append("Missing required field: spec.taxComponents")
    elif not isinstance(spec['taxComponents'], list):
        errors.append("spec.taxComponents must be an array")
    else:
        for i, component in enumerate(spec['taxComponents']):
            required = ['name', 'percentage', 'creditAccountType', 'creditGLCode', 'startDate']
            for field in required:
                if field not in component:
                    errors.append(f"Missing field in taxComponent[{i}]: {field}")

            # Validate percentage
            if 'percentage' in component:
                try:
                    pct = float(component['percentage'])
                    if pct < 0 or pct > 100:
                        errors.append(f"Invalid percentage in taxComponent[{i}]: {pct}. Must be 0-100")
                except (ValueError, TypeError):
                    errors.append(f"Invalid percentage format in taxComponent[{i}]")

            # Validate date format
            if 'startDate' in component:
                date_str = str(component['startDate'])
                if not re.match(r'^\d{4}-\d{2}-\d{2}$', date_str):
                    errors.append(f"Invalid date format in taxComponent[{i}]: {date_str}. Use YYYY-MM-DD")

    return errors

def validate_floating_rate(spec: dict) -> List[str]:
    """Validate FloatingRate specific fields"""
    errors = []

    if 'name' not in spec:
        errors.append("Missing required field: spec.name")

    if 'ratePeriods' not in spec:
        errors.append("Missing required field: spec.ratePeriods")
    elif not isinstance(spec['ratePeriods'], list):
        errors.append("spec.ratePeriods must be an array")
    else:
        for i, period in enumerate(spec['ratePeriods']):
            required = ['fromDate', 'interestRate']
            for field in required:
                if field not in period:
                    errors.append(f"Missing field in ratePeriod[{i}]: {field}")

            # Validate interest rate
            if 'interestRate' in period:
                try:
                    rate = float(period['interestRate'])
                    if rate < 0:
                        errors.append(f"Invalid interestRate in ratePeriod[{i}]: {rate}. Must be non-negative")
                except (ValueError, TypeError):
                    errors.append(f"Invalid interestRate format in ratePeriod[{i}]")

            # Validate date format
            if 'fromDate' in period:
                date_str = str(period['fromDate'])
                if not re.match(r'^\d{4}-\d{2}-\d{2}$', date_str):
                    errors.append(f"Invalid date format in ratePeriod[{i}]: {date_str}. Use YYYY-MM-DD")

    return errors

def validate_savings_product_accounting(spec: dict) -> List[str]:
    """Validate SavingsProductAccounting specific fields"""
    errors = []

    if 'productName' not in spec:
        errors.append("Missing required field: spec.productName")

    if 'accountMappings' not in spec:
        errors.append("Missing required field: spec.accountMappings")
    elif not isinstance(spec['accountMappings'], list):
        errors.append("spec.accountMappings must be an array")
    else:
        if len(spec['accountMappings']) == 0:
            errors.append("spec.accountMappings must contain at least one mapping")

        for i, mapping in enumerate(spec['accountMappings']):
            required = ['mappingType', 'glAccountCode']
            for field in required:
                if field not in mapping:
                    errors.append(f"Missing field in accountMapping[{i}]: {field}")

    return errors

def validate_financial_activity_mapping(spec: dict) -> List[str]:
    """Validate FinancialActivityMapping specific fields"""
    errors = []

    required_fields = ['financialActivityName', 'glAccountCode']
    for field in required_fields:
        if field not in spec:
            errors.append(f"Missing required field: spec.{field}")

    return errors

def validate_client(spec: dict) -> List[str]:
    """Validate Client specific fields"""
    errors = []

    # Clients use firstName and lastName, not name
    if 'firstName' not in spec:
        errors.append("Missing required field: spec.firstName")
    if 'lastName' not in spec:
        errors.append("Missing required field: spec.lastName")
    if 'officeId' not in spec:
        errors.append("Missing required field: spec.officeId")

    return errors

def validate_staff(spec: dict) -> List[str]:
    """Validate Staff specific fields"""
    errors = []

    # Staff use firstName and lastName, not name
    if 'firstName' not in spec:
        errors.append("Missing required field: spec.firstName")
    if 'lastName' not in spec:
        errors.append("Missing required field: spec.lastName")
    if 'officeId' not in spec:
        errors.append("Missing required field: spec.officeId")

    return errors

def validate_group(spec: dict) -> List[str]:
    """Validate Group specific fields"""
    errors = []

    if 'name' not in spec:
        errors.append("Missing required field: spec.name")
    if 'officeId' not in spec:
        errors.append("Missing required field: spec.officeId")

    return errors

def validate_loan_account(spec: dict) -> List[str]:
    """Validate LoanAccount specific fields"""
    errors = []

    if 'clientId' not in spec and 'groupId' not in spec:
        errors.append("Missing required field: spec.clientId or spec.groupId")
    if 'productId' not in spec:
        errors.append("Missing required field: spec.productId")
    if 'principal' not in spec:
        errors.append("Missing required field: spec.principal")
    if 'loanTermFrequency' not in spec:
        errors.append("Missing required field: spec.loanTermFrequency")
    if 'submittedOnDate' not in spec:
        errors.append("Missing required field: spec.submittedOnDate")

    return errors

def validate_savings_account(spec: dict) -> List[str]:
    """Validate SavingsAccount specific fields"""
    errors = []

    if 'clientId' not in spec and 'groupId' not in spec:
        errors.append("Missing required field: spec.clientId or spec.groupId")
    if 'productId' not in spec:
        errors.append("Missing required field: spec.productId")
    if 'submittedOnDate' not in spec:
        errors.append("Missing required field: spec.submittedOnDate")

    return errors

def validate_guarantor(spec: dict) -> List[str]:
    """Validate Guarantor specific fields"""
    errors = []

    # Guarantors can have various types (internal client, external, etc.)
    if 'loanId' not in spec and 'loanAccountId' not in spec:
        errors.append("Missing required field: spec.loanId or spec.loanAccountId")
    if 'guarantorTypeId' not in spec:
        errors.append("Missing required field: spec.guarantorTypeId")

    # Check for at least one form of identification
    has_identification = (
        'clientRelationshipId' in spec or
        'firstName' in spec or
        'fullName' in spec or
        'entityId' in spec
    )
    if not has_identification:
        errors.append("Missing guarantor identification (clientRelationshipId, firstName, fullName, or entityId)")

    return errors

def validate_loan_collateral(spec: dict) -> List[str]:
    """Validate LoanCollateral specific fields"""
    errors = []

    if 'loanAccountId' not in spec and 'loanId' not in spec:
        errors.append("Missing required field: spec.loanAccountId or spec.loanId")
    if 'collateralTypeId' not in spec:
        errors.append("Missing required field: spec.collateralTypeId")
    if 'value' not in spec:
        errors.append("Missing required field: spec.value")

    return errors

def validate_data_table(spec: dict) -> List[str]:
    """Validate DataTable specific fields"""
    errors = []

    if 'datatableName' not in spec:
        errors.append("Missing required field: spec.datatableName")
    if 'apptableName' not in spec:
        errors.append("Missing required field: spec.apptableName")
    if 'columns' not in spec:
        errors.append("Missing required field: spec.columns")
    elif not isinstance(spec['columns'], list):
        errors.append("spec.columns must be an array")

    return errors

def validate_currency_configuration(spec: dict) -> List[str]:
    """Validate CurrencyConfiguration specific fields"""
    errors = []

    if 'selectedCurrencies' not in spec:
        errors.append("Missing required field: spec.selectedCurrencies")
    elif not isinstance(spec['selectedCurrencies'], list):
        errors.append("spec.selectedCurrencies must be an array")

    return errors

def validate_payment_type_accounting(spec: dict) -> List[str]:
    """Validate PaymentTypeAccounting specific fields"""
    errors = []

    if 'paymentType' not in spec:
        errors.append("Missing required field: spec.paymentType")
    if 'glAccountCode' not in spec:
        errors.append("Missing required field: spec.glAccountCode")

    return errors

def validate_provisioning_criteria(spec: dict) -> List[str]:
    """Validate ProvisioningCriteria specific fields"""
    errors = []

    if 'criteriaName' not in spec:
        errors.append("Missing required field: spec.criteriaName")
    if 'definitions' not in spec:
        errors.append("Missing required field: spec.definitions")
    elif not isinstance(spec['definitions'], list):
        errors.append("spec.definitions must be an array")

    return errors

def validate_global_configuration(spec: dict) -> List[str]:
    """Validate GlobalConfiguration specific fields"""
    errors = []

    # Global configs have various formats, just check they have some content
    if not spec:
        errors.append("spec cannot be empty")

    return errors

def validate_entity(yaml_data: dict, file_path: Path) -> List[str]:
    """
    Validate entity based on kind

    Returns:
        List of validation errors
    """
    kind = yaml_data.get('kind', '')
    spec = yaml_data.get('spec', {})

    validators = {
        'GLAccount': validate_gl_account,
        'TaxGroup': validate_tax_group,
        'FloatingRate': validate_floating_rate,
        'SavingsProductAccounting': validate_savings_product_accounting,
        'FinancialActivityMapping': validate_financial_activity_mapping,
        'Client': validate_client,
        'Staff': validate_staff,
        'Group': validate_group,
        'LoanAccount': validate_loan_account,
        'SavingsAccount': validate_savings_account,
        'Guarantor': validate_guarantor,
        'LoanGuarantor': validate_guarantor,  # Same as Guarantor
        'LoanCollateral': validate_loan_collateral,
        'DataTable': validate_data_table,
        'CurrencyConfiguration': validate_currency_configuration,
        'PaymentTypeAccounting': validate_payment_type_accounting,
        'ProvisioningCriteria': validate_provisioning_criteria,
        'GlobalConfiguration': validate_global_configuration,
        'Permission': validate_global_configuration,  # Permissions are like global configs
        'MakerCheckerPermission': validate_global_configuration,  # Same pattern
    }

    if kind in validators:
        return validators[kind](spec)
    else:
        # For unknown kinds, just check spec has some identifying field
        # Different entities use different identification patterns
        has_identifier = (
            'name' in spec or
            'productName' in spec or
            'financialActivityName' in spec or
            'firstName' in spec or
            'fullName' in spec or
            'codeName' in spec or
            'accountNo' in spec or
            'loanId' in spec or
            'loanAccountId' in spec or
            'clientId' in spec or
            'groupId' in spec or
            'officeId' in spec or
            'value' in spec or
            'templateName' in spec or
            'scheduledJob' in spec or
            'reportName' in spec or
            'datatableName' in spec or
            'paymentType' in spec or
            'criteriaName' in spec or
            'selectedCurrencies' in spec or
            'enabled' in spec or  # Global configs often have enabled field
            'configName' in spec or
            'permission' in spec or
            len(spec) > 0  # As last resort, accept any non-empty spec
        )
        if not has_identifier:
            return [f"spec must contain an identifying field for kind: {kind}"]
        return []

def validate_file(file_path: Path, verbose: bool = False) -> Tuple[bool, List[str]]:
    """
    Validate a single YAML file

    Returns:
        (is_valid, list_of_errors)
    """
    # Skip kustomization files
    if file_path.name == 'kustomization.yaml':
        return True, []

    # Check YAML syntax
    is_valid, error = validate_yaml_syntax(file_path)
    if not is_valid:
        return False, [error]

    # Load and validate structure
    with open(file_path, 'r') as f:
        yaml_data = yaml.safe_load(f)

    errors = []

    # Basic structure validation
    structure_errors = validate_fineract_structure(yaml_data, file_path)
    errors.extend(structure_errors)

    # Entity-specific validation
    if not structure_errors:  # Only validate entity if structure is valid
        entity_errors = validate_entity(yaml_data, file_path)
        errors.extend(entity_errors)

    return len(errors) == 0, errors

def validate_directory(directory: Path, verbose: bool = False) -> Dict:
    """
    Validate all YAML files in directory

    Returns:
        Summary dict
    """
    yaml_files = list(directory.glob('**/*.yaml'))

    total = 0
    valid = 0
    invalid = 0
    skipped = 0

    invalid_files = []

    for yaml_file in yaml_files:
        if yaml_file.name == 'kustomization.yaml':
            skipped += 1
            continue

        total += 1
        is_valid, errors = validate_file(yaml_file, verbose)

        if is_valid:
            valid += 1
            if verbose:
                print(f"{Colors.GREEN}✓{Colors.NC} {yaml_file.relative_to(directory)}")
        else:
            invalid += 1
            invalid_files.append((yaml_file, errors))
            print(f"{Colors.RED}✗{Colors.NC} {yaml_file.relative_to(directory)}")
            for error in errors:
                print(f"    {Colors.RED}•{Colors.NC} {error}")

    return {
        'total': total,
        'valid': valid,
        'invalid': invalid,
        'skipped': skipped,
        'invalid_files': invalid_files
    }

def main():
    parser = argparse.ArgumentParser(description='Validate Fineract YAML data files')
    parser.add_argument('directory', help='Directory containing YAML files')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output (show valid files)')
    parser.add_argument('--kind', help='Only validate specific kind (GLAccount, TaxGroup, etc.)')

    args = parser.parse_args()

    directory = Path(args.directory)

    if not directory.exists():
        print(f"{Colors.RED}Error: Directory not found: {directory}{Colors.NC}")
        sys.exit(1)

    if not directory.is_dir():
        print(f"{Colors.RED}Error: Not a directory: {directory}{Colors.NC}")
        sys.exit(1)

    print("=" * 80)
    print("Fineract YAML Data Validation")
    print("=" * 80)
    print(f"Directory: {directory}")
    if args.kind:
        print(f"Filter: kind={args.kind}")
    print("=" * 80)
    print()

    summary = validate_directory(directory, args.verbose)

    print()
    print("=" * 80)
    print("VALIDATION SUMMARY")
    print("=" * 80)
    print(f"Total files processed: {summary['total']}")
    print(f"{Colors.GREEN}Valid: {summary['valid']}{Colors.NC}")
    print(f"{Colors.RED}Invalid: {summary['invalid']}{Colors.NC}")
    print(f"{Colors.YELLOW}Skipped: {summary['skipped']}{Colors.NC}")
    print("=" * 80)

    if summary['invalid'] > 0:
        print()
        print(f"{Colors.RED}Validation failed with {summary['invalid']} errors{Colors.NC}")
        sys.exit(1)
    else:
        print()
        print(f"{Colors.GREEN}All files are valid!{Colors.NC}")
        sys.exit(0)

if __name__ == '__main__':
    main()
