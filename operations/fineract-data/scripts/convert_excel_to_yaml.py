#!/usr/bin/env python3
"""
Convert Fineract Excel data to YAML format for GitOps

This script reads Excel files and converts them into YAML files suitable for GitOps management.
Supports all 44 Fineract entity types (52 total converters + 5 sheet name aliases) and auto-generates
kustomization.yaml files. Automatically processes all sheets found in the Excel file.

Sheet Name Aliases:
    - "Codes and Values" -> "Code Values"
    - "Roles Permissions" -> "Roles"
    - "Maker Checker Config" -> "Maker Checker"
    - "Account Number Preferences" -> "Account Number Formats"
    - "Financial Activity Mapping" -> "Financial Activity Mappings"

Usage:
    python3 convert_excel_to_yaml.py <excel_file> <output_dir>

Example:
    python3 convert_excel_to_yaml.py \\
        /path/to/fineract_data.xlsx \\
        operations/fineract-data/data/dev
"""

import sys
import yaml
from pathlib import Path
from typing import Dict, Any, List, Tuple
import pandas as pd
from datetime import datetime


# Sheet name aliases - maps Excel sheet names to internal converter names
SHEET_ALIASES = {
    'Codes and Values': 'Code Values',
    'Roles Permissions': 'Roles',
    'Maker Checker Config': 'Maker Checker',
    'Account Number Preferences': 'Account Number Formats',
    'Financial Activity Mapping': 'Financial Activity Mappings',
}


def kebab_case(text: str) -> str:
    """Convert text to kebab-case for file names"""
    return text.lower().replace(' ', '-').replace('_', '-').replace('/', '-')


def get_column(row: pd.Series, *column_names, default=None):
    """
    Try multiple column name variations (Title Case, snake_case, lowercase, etc.)
    Returns the first non-null value found, or default if none found.

    Example: get_column(row, 'First Name', 'firstname', 'first_name', default='')
    """
    for name in column_names:
        if name in row.index and pd.notna(row[name]) and str(row[name]).strip():
            return str(row[name]).strip()
    return default


def generate_kustomization(output_path: Path, configmap_name: str, yaml_files: List[str]) -> None:
    """Generate kustomization.yaml with configMapGenerator for entity directory"""
    kustomization = {
        'apiVersion': 'kustomize.config.k8s.io/v1beta1',
        'kind': 'Kustomization',
        'configMapGenerator': [{
            'name': configmap_name,
            'files': sorted(yaml_files)
        }]
    }

    kustomization_path = output_path / 'kustomization.yaml'
    with open(kustomization_path, 'w') as f:
        yaml.dump(kustomization, f, default_flow_style=False, sort_keys=False)

    print(f"  ✓ Generated: {kustomization_path}")


# Entity type configuration: sheet_name -> (output_dir, configmap_name, kind, converter_func)
ENTITY_CONFIGS = {}


def register_converter(sheet_name: str, output_dir: str, configmap_name: str, kind: str):
    """Decorator to register entity converter functions"""
    def decorator(func):
        ENTITY_CONFIGS[sheet_name] = (output_dir, configmap_name, kind, func)
        return func
    return decorator


@register_converter('Code Values', 'codes-and-values', 'code-values-data', 'CodeValue')
def convert_code_values(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Code Values sheet to YAML data structures"""
    # Group by code name
    codes = {}
    for _, row in df.iterrows():
        code_name = get_column(row, 'Code Name', 'code_name', 'codename', default='unknown')
        value = get_column(row, 'Value', 'value', 'code_value', default='')
        position_str = get_column(row, 'Position', 'position', 'code_position')
        position = int(position_str) if position_str and position_str.isdigit() else None

        if code_name not in codes:
            codes[code_name] = []
        codes[code_name].append({'name': value, 'position': position if position else len(codes[code_name]) + 1})

    # Create one YAML file per code
    results = []
    for code_name, values in codes.items():
        print(f"  - Code: {code_name} ({len(values)} values)")
        results.append({
            'filename': f"{kebab_case(code_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'CodeValue',
                'metadata': {
                    'name': kebab_case(code_name),
                    'labels': {'category': 'code-value'}
                },
                'spec': {
                    'codeName': code_name,
                    'systemDefined': False,
                    'values': values
                }
            }
        })
    return results


@register_converter('Offices', 'offices', 'offices-data', 'Office')
def convert_offices(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Offices sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        office_name = get_column(row, 'Office Name', 'office_name', 'officename', 'name', default=f'office-{idx}')
        office_type = get_column(row, 'Type', 'type', 'office_type', default='branch')
        external_id = get_column(row, 'External ID', 'external_id', 'externalid', default=f'OFF-{idx:03d}')
        parent_office = get_column(row, 'Parent Office', 'parent_office', 'parentoffice')
        opening_date = get_column(row, 'Opening Date', 'opening_date', 'openingdate', default=datetime.now().strftime('%Y-%m-%d'))

        # Address fields
        street = get_column(row, 'Street Address', 'street_address', 'street', 'address', default='')
        city = get_column(row, 'City', 'city', default='')
        postal_code = get_column(row, 'Postal Code', 'postal_code', 'postalcode', 'zip', default='')
        country = get_column(row, 'Country', 'country', default='')

        # Contact fields
        phone = get_column(row, 'Phone', 'phone', 'phone_number', default='')
        email = get_column(row, 'Email', 'email', 'email_address', default='')
        manager = get_column(row, 'Manager', 'manager', default='')

        status = get_column(row, 'Status', 'status', default='ACTIVE')

        print(f"  - Office: {office_name} (Type: {office_type})")

        results.append({
            'filename': f"{kebab_case(office_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Office',
                'metadata': {
                    'name': kebab_case(office_name),
                    'labels': {'office-type': office_type}
                },
                'spec': {
                    'name': office_name,
                    'externalId': external_id,
                    'parentOffice': parent_office,
                    'openingDate': opening_date,
                    'address': {
                        'street': street,
                        'city': city,
                        'postalCode': postal_code,
                        'country': country
                    },
                    'contact': {
                        'phone': phone,
                        'email': email,
                        'manager': manager
                    },
                    'status': status
                }
            }
        })
    return results


@register_converter('Staff', 'staff', 'staff-data', 'Staff')
def convert_staff(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Staff sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        first_name = get_column(row, 'First Name', 'firstname', 'first_name', default='')
        last_name = get_column(row, 'Last Name', 'lastname', 'last_name', default='')
        staff_name = f"{first_name} {last_name}".strip() or f'staff-{idx}'

        staff_type = get_column(row, 'Type', 'type', 'staff_type', default='regular')
        office = get_column(row, 'Office', 'office', 'office_name', default='head-office')
        is_loan_officer_str = get_column(row, 'Is Loan Officer', 'is_loan_officer', 'loan_officer', default='True')
        is_loan_officer = is_loan_officer_str.lower() in ['true', '1', 'yes'] if isinstance(is_loan_officer_str, str) else bool(is_loan_officer_str)
        external_id = get_column(row, 'External ID', 'external_id', 'externalid', default=f'STAFF-{idx:03d}')
        mobile = get_column(row, 'Mobile', 'mobile', 'mobile_no', 'phone', default='')
        email = get_column(row, 'Email', 'email', 'email_address', default='')
        is_active_str = get_column(row, 'Active', 'active', 'is_active', default='True')
        is_active = is_active_str.lower() in ['true', '1', 'yes'] if isinstance(is_active_str, str) else bool(is_active_str)
        username = get_column(row, 'Username', 'username', 'user_name', default='')
        role = get_column(row, 'Role', 'role', default='')

        print(f"  - Staff: {staff_name} (Office: {office}, Role: {role})")

        results.append({
            'filename': f"{kebab_case(staff_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Staff',
                'metadata': {
                    'name': kebab_case(staff_name),
                    'labels': {'staff-type': staff_type}
                },
                'spec': {
                    'firstName': first_name,
                    'lastName': last_name,
                    'officeId': office,
                    'isLoanOfficer': is_loan_officer,
                    'externalId': external_id,
                    'mobileNo': mobile,
                    'emailAddress': email,
                    'isActive': is_active,
                    # User creation fields for Keycloak integration
                    'username': username,
                    'role': role
                }
            }
        })
    return results


@register_converter('Roles', 'roles', 'roles-data', 'Role')
def convert_roles(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Roles sheet to YAML data structures - aggregates permissions per role"""
    # Excel columns: role_name, permission_group, permission, description
    # Group by role_name and aggregate all permissions
    results = []
    roles_dict = {}

    for idx, row in df.iterrows():
        role_name = str(get_column(row, 'Role Name', 'role_name', default=f'role-{idx}'))
        permission_group = get_column(row, 'Permission Group', 'permission_group', default='')
        permission = get_column(row, 'Permission', 'permission', default='')

        # Initialize role if not seen before
        if role_name not in roles_dict:
            roles_dict[role_name] = {
                'permissions': [],
                'description': get_column(row, 'Description', 'description', default=f'Role: {role_name}')
            }

        # Add permission to role
        if permission_group and permission:
            roles_dict[role_name]['permissions'].append({
                'grouping': permission_group,
                'code': f'{permission_group}_{permission}'
            })

    # Convert aggregated roles to YAML format
    for role_name, role_data in roles_dict.items():
        print(f"  - Role: {role_name} ({len(role_data['permissions'])} permissions)")

        results.append({
            'filename': f"{kebab_case(role_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Role',
                'metadata': {
                    'name': kebab_case(role_name),
                    'labels': {'role-type': 'custom'}
                },
                'spec': {
                    'name': role_name,
                    'description': role_data['description'],
                    'disabled': False,
                    'permissions': role_data['permissions']
                }
            }
        })
    return results


@register_converter('Loan Products', 'products/loan-products', 'loan-products-data', 'LoanProduct')
def convert_loan_products(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Products sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        product_name = get_column(row, 'Product Name', 'product_name', 'productname', 'name', default=f'product-{idx}')
        short_name = get_column(row, 'Short Name', 'short_name', 'shortname', default=product_name[:20])
        description = get_column(row, 'Description', 'description', default='')
        category = get_column(row, 'Category', 'category', default='general')
        currency = get_column(row, 'Currency', 'currency', 'currency_code', default='KES')
        decimal_places_str = get_column(row, 'Decimal Places', 'decimal_places', 'digits_after_decimal', default='2')

        # Principal fields
        min_principal_str = get_column(row, 'Min Principal', 'min_principal', 'principal_min', default='10000')
        default_principal_str = get_column(row, 'Default Principal', 'default_principal', 'principal_default', default='50000')
        max_principal_str = get_column(row, 'Max Principal', 'max_principal', 'principal_max', default='500000')

        # Interest rate fields
        min_rate_str = get_column(row, 'Min Interest Rate', 'min_interest_rate', 'interest_rate_min', default='10.0')
        default_rate_str = get_column(row, 'Default Interest Rate', 'default_interest_rate', 'interest_rate_default', default='15.0')
        max_rate_str = get_column(row, 'Max Interest Rate', 'max_interest_rate', 'interest_rate_max', default='20.0')
        interest_type = get_column(row, 'Interest Type', 'interest_type', default='DECLINING_BALANCE')

        # Repayment fields
        min_repayments_str = get_column(row, 'Min Repayments', 'min_repayments', 'repayments_min', default='6')
        default_repayments_str = get_column(row, 'Default Repayments', 'default_repayments', 'repayments_default', default='12')
        max_repayments_str = get_column(row, 'Max Repayments', 'max_repayments', 'repayments_max', default='36')
        repayment_every_str = get_column(row, 'Repayment Every', 'repayment_every', default='1')
        repayment_frequency = get_column(row, 'Repayment Frequency', 'repayment_frequency', default='MONTHS')
        amortization_type = get_column(row, 'Amortization Type', 'amortization_type', default='EQUAL_INSTALLMENTS')
        interest_calc_period = get_column(row, 'Interest Calculation Period', 'interest_calculation_period', default='SAME_AS_REPAYMENT')

        print(f"  - Loan Product: {product_name} ({currency})")

        results.append({
            'filename': f"{kebab_case(product_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'LoanProduct',
                'metadata': {
                    'name': kebab_case(product_name),
                    'labels': {
                        'product-type': 'loan',
                        'category': category
                    }
                },
                'spec': {
                    'name': product_name,
                    'shortName': short_name,
                    'description': description,
                    'currency': currency,
                    'digitsAfterDecimal': int(decimal_places_str) if decimal_places_str.isdigit() else 2,
                    'principal': {
                        'min': float(min_principal_str) if min_principal_str else 10000,
                        'default': float(default_principal_str) if default_principal_str else 50000,
                        'max': float(max_principal_str) if max_principal_str else 500000
                    },
                    'interestRate': {
                        'min': float(min_rate_str) if min_rate_str else 10.0,
                        'default': float(default_rate_str) if default_rate_str else 15.0,
                        'max': float(max_rate_str) if max_rate_str else 20.0,
                        'type': interest_type,
                        'perPeriod': True
                    },
                    'numberOfRepayments': {
                        'min': int(min_repayments_str) if min_repayments_str and min_repayments_str.isdigit() else 6,
                        'default': int(default_repayments_str) if default_repayments_str and default_repayments_str.isdigit() else 12,
                        'max': int(max_repayments_str) if max_repayments_str and max_repayments_str.isdigit() else 36
                    },
                    'repaymentEvery': int(repayment_every_str) if repayment_every_str and repayment_every_str.isdigit() else 1,
                    'repaymentFrequency': repayment_frequency,
                    'amortizationType': amortization_type,
                    'interestCalculationPeriod': interest_calc_period
                }
            }
        })
    return results


@register_converter('Savings Products', 'products/savings-products', 'savings-products-data', 'SavingsProduct')
def convert_savings_products(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Savings Products sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        product_name = get_column(row, 'Product Name', 'product_name', 'productname', 'name', default=f'savings-{idx}')
        short_name = get_column(row, 'Short Name', 'short_name', 'shortname', default=product_name[:20])
        description = get_column(row, 'Description', 'description', default='')
        category = get_column(row, 'Category', 'category', default='general')
        currency = get_column(row, 'Currency', 'currency', 'currency_code', default='KES')
        decimal_places_str = get_column(row, 'Decimal Places', 'decimal_places', 'digits_after_decimal', default='2')
        interest_rate_str = get_column(row, 'Interest Rate', 'interest_rate', 'nominal_annual_interest_rate', default='5.0')
        compounding_period = get_column(row, 'Compounding Period', 'compounding_period', 'interest_compounding_period', default='MONTHLY')
        posting_period = get_column(row, 'Posting Period', 'posting_period', 'interest_posting_period', default='MONTHLY')
        calculation_type = get_column(row, 'Calculation Type', 'calculation_type', 'interest_calculation_type', default='DAILY_BALANCE')
        min_balance_str = get_column(row, 'Min Opening Balance', 'min_opening_balance', 'min_required_opening_balance', default='0')
        withdrawal_fee_str = get_column(row, 'Withdrawal Fee', 'withdrawal_fee', 'withdrawal_fee_for_transfers', default='False')

        print(f"  - Savings Product: {product_name} ({currency}, {interest_rate_str}% p.a.)")

        results.append({
            'filename': f"{kebab_case(product_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SavingsProduct',
                'metadata': {
                    'name': kebab_case(product_name),
                    'labels': {
                        'product-type': 'savings',
                        'category': category
                    }
                },
                'spec': {
                    'name': product_name,
                    'shortName': short_name,
                    'description': description,
                    'currency': currency,
                    'digitsAfterDecimal': int(decimal_places_str) if decimal_places_str.isdigit() else 2,
                    'nominalAnnualInterestRate': float(interest_rate_str) if interest_rate_str else 5.0,
                    'interestCompoundingPeriod': compounding_period,
                    'interestPostingPeriod': posting_period,
                    'interestCalculationType': calculation_type,
                    'minRequiredOpeningBalance': float(min_balance_str) if min_balance_str else 0,
                    'withdrawalFeeForTransfers': withdrawal_fee_str.lower() in ['true', '1', 'yes'] if isinstance(withdrawal_fee_str, str) else bool(withdrawal_fee_str)
                }
            }
        })
    return results


@register_converter('Charges', 'charges', 'charges-data', 'Charge')
def convert_charges(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Charges sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        charge_name = get_column(row, 'Charge Name', 'charge_name', 'chargename', 'name', default=f'charge-{idx}')
        applies_to = get_column(row, 'Applies To', 'applies_to', 'charge_applies_to', default='LOAN')
        charge_type = get_column(row, 'Charge Type', 'charge_type', default='flat')
        currency = get_column(row, 'Currency', 'currency', default='KES')
        amount_str = get_column(row, 'Amount', 'amount', default='0')
        time_type = get_column(row, 'Time Type', 'time_type', 'charge_time_type', default='DISBURSEMENT')
        calc_type = get_column(row, 'Calculation Type', 'calculation_type', 'charge_calculation_type', default='FLAT')
        active_str = get_column(row, 'Active', 'active', 'is_active', default='True')
        penalty_str = get_column(row, 'Is Penalty', 'is_penalty', 'penalty', default='False')

        print(f"  - Charge: {charge_name} ({currency} {amount_str})")

        results.append({
            'filename': f"{kebab_case(charge_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Charge',
                'metadata': {
                    'name': kebab_case(charge_name),
                    'labels': {
                        'charge-applies-to': applies_to.lower(),
                        'charge-type': charge_type
                    }
                },
                'spec': {
                    'name': charge_name,
                    'currency': currency,
                    'amount': float(amount_str) if amount_str else 0,
                    'chargeAppliesTo': applies_to,
                    'chargeTimeType': time_type,
                    'chargeCalculationType': calc_type,
                    'active': active_str.lower() in ['true', '1', 'yes'] if isinstance(active_str, str) else bool(active_str),
                    'penalty': penalty_str.lower() in ['true', '1', 'yes'] if isinstance(penalty_str, str) else bool(penalty_str)
                }
            }
        })
    return results


@register_converter('Currency Config', 'system-config', 'currency-config-data', 'CurrencyConfiguration')
def convert_currency_config(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Currency Config sheet to YAML data structures"""
    # Excel columns: currency_code, currency_name, decimal_places, in_multiples_of, display_symbol, name_code, description
    currencies = []
    for _, row in df.iterrows():
        code = get_column(row, 'Currency Code', 'currency_code', default='XAF')
        name = get_column(row, 'Currency Name', 'currency_name', default='Central African CFA Franc')
        symbol = get_column(row, 'Display Symbol', 'display_symbol', 'Symbol', 'symbol', default='FCFA')

        print(f"  - Currency: {code} ({name}) - {symbol}")

        currencies.append({
            'code': code,
            'name': name,
            'decimalPlaces': int(get_column(row, 'Decimal Places', 'decimal_places', default='0')),
            'inMultiplesOf': int(get_column(row, 'In Multiples Of', 'in_multiples_of', default='1')),
            'displaySymbol': symbol,
            'nameCode': get_column(row, 'Name Code', 'name_code', default=f'currency.{code}'),
            'displayLabel': f"{name} ({symbol})"
        })

    return [{
        'filename': 'currency-config.yaml',
        'data': {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'CurrencyConfiguration',
            'metadata': {
                'name': 'currency-config',
                'labels': {'config-type': 'currency'}
            },
            'spec': {
                'selectedCurrencies': currencies
            }
        }
    }]


@register_converter('Working Days', 'system-config', 'working-days-data', 'WorkingDays')
def convert_working_days(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Working Days sheet to YAML data structures"""
    row = df.iloc[0] if len(df) > 0 else {}
    return [{
        'filename': 'working-days.yaml',
        'data': {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'WorkingDays',
            'metadata': {
                'name': 'working-days',
                'labels': {'config-type': 'calendar'}
            },
            'spec': {
                'recurrence': get_column(row, 'Recurrence', 'recurrence', default='FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
                'repaymentReschedulingType': get_column(row, 'Rescheduling Type', 'rescheduling_type', default='MOVE_TO_NEXT_WORKING_DAY'),
                'extendTermForDailyRepayments': get_column(row, 'Extend Term Daily', 'extend_term_daily', default='False').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Extend Term Daily', 'extend_term_daily', default='False'), str) else bool(get_column(row, 'Extend Term Daily', 'extend_term_daily', default='False'))
            }
        }
    }]


@register_converter('Account Number Formats', 'system-config', 'account-number-formats-data', 'AccountNumberFormat')
def convert_account_number_formats(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Account Number Formats sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        # Excel columns: entity_type, prefix_type, account_number_length, example, description
        entity_type = str(get_column(row, 'Entity Type', 'entity_type', 'Format Name', 'format_name', default=f'format-{idx}'))
        format_name = f"{entity_type}-account-format"

        print(f"  - Account Number Format: {entity_type} (Length: {get_column(row, 'Account Number Length', 'account_number_length', 'Length', default='10')})")

        results.append({
            'filename': f"{kebab_case(format_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'AccountNumberFormat',
                'metadata': {
                    'name': kebab_case(format_name),
                    'labels': {'format-type': entity_type.lower()}
                },
                'spec': {
                    'accountType': entity_type.upper(),
                    'prefixType': get_column(row, 'Prefix Type', 'prefix_type', default='OFFICE_NAME').upper(),
                    'accountNumberLength': int(get_column(row, 'Account Number Length', 'account_number_length', 'Length', 'length', default='10'))
                }
            }
        })
    return results


@register_converter('Maker Checker', 'system-config', 'maker-checker-data', 'MakerChecker')
def convert_maker_checker(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Maker Checker sheet to YAML data structures"""
    # Excel columns: task_name, entity, action, threshold_amount, threshold_currency, maker_role, checker_role, description
    results = []
    for idx, row in df.iterrows():
        task_name = str(get_column(row, 'Task Name', 'task_name', default=f'task-{idx}'))
        entity = get_column(row, 'Entity', 'entity', default='Loan')
        action = get_column(row, 'Action', 'action', default='Approve')

        print(f"  - Maker Checker: {task_name} ({entity}.{action})")

        results.append({
            'filename': f"{kebab_case(task_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'MakerChecker',
                'metadata': {
                    'name': kebab_case(task_name),
                    'labels': {'entity': entity.lower()}
                },
                'spec': {
                    'taskName': task_name,
                    'entity': entity.upper(),
                    'action': action.upper(),
                    'thresholdAmount': float(get_column(row, 'Threshold Amount', 'threshold_amount', default='0')),
                    'thresholdCurrency': get_column(row, 'Threshold Currency', 'threshold_currency', default='XAF'),
                    'makerRole': get_column(row, 'Maker Role', 'maker_role', default='Loan Officer'),
                    'checkerRole': get_column(row, 'Checker Role', 'checker_role', default='Branch Manager'),
                    'enabled': True
                }
            }
        })
    return results


@register_converter('Scheduler Jobs', 'system-config', 'scheduler-jobs-data', 'SchedulerJob')
def convert_scheduler_jobs(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Scheduler Jobs sheet to YAML data structures"""
    # Excel columns: job_name, display_name, cron_expression, active, description
    results = []
    for idx, row in df.iterrows():
        job_name = str(get_column(row, 'Job Name', 'job_name', default=f'job-{idx}'))
        display_name = get_column(row, 'Display Name', 'display_name', default=job_name)
        active_val = get_column(row, 'Active', 'active', default='No')

        print(f"  - Scheduler Job: {job_name} (Active: {active_val})")

        results.append({
            'filename': f"{kebab_case(job_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SchedulerJob',
                'metadata': {
                    'name': kebab_case(job_name),
                    'labels': {'job-type': 'scheduled'}
                },
                'spec': {
                    'jobName': job_name,
                    'displayName': display_name,
                    'cronExpression': get_column(row, 'Cron Expression', 'cron_expression', default='0 0 * * * ?'),
                    'active': str(active_val).lower() in ['true', '1', 'yes'] if isinstance(active_val, str) else bool(active_val),
                    'description': get_column(row, 'Description', 'description', default='')
                }
            }
        })
    return results


@register_converter('Notification Templates', 'notification-templates', 'notification-templates-data', 'NotificationTemplate')
def convert_notification_templates(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Notification Templates sheet to YAML data structures"""
    # Excel columns: template_name, channel, event_trigger, subject, message_body, is_active, description
    results = []
    for idx, row in df.iterrows():
        template_name = str(get_column(row, 'Template Name', 'template_name', default=f'template-{idx}'))
        channel = str(get_column(row, 'Channel', 'channel', default='SMS'))
        event_trigger = str(get_column(row, 'Event Trigger', 'event_trigger', default=''))
        subject = str(get_column(row, 'Subject', 'subject', default=''))
        message_body = str(get_column(row, 'Message Body', 'message_body', default=''))
        is_active_str = str(get_column(row, 'Is Active', 'is_active', default='Yes')).lower()
        description = str(get_column(row, 'Description', 'description', default=''))

        print(f"  - Notification Template: {template_name} ({channel})")

        results.append({
            'filename': f"{kebab_case(template_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'NotificationTemplate',
                'metadata': {
                    'name': kebab_case(template_name),
                    'labels': {'channel': channel.lower()}
                },
                'spec': {
                    'name': template_name,
                    'channel': channel,
                    'eventTrigger': event_trigger,
                    'subject': subject,
                    'messageBody': message_body,
                    'isActive': is_active_str in ['yes', 'true', '1'],
                    'description': description
                }
            }
        })
    return results


@register_converter('Data Tables', 'data-tables', 'data-tables-data', 'DataTable')
def convert_data_tables(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Data Tables sheet to YAML data structures - aggregates columns per table"""
    # Excel columns: entity_type, table_name, field_name, field_type, mandatory, dropdown_values, description
    results = []
    tables_dict = {}

    for idx, row in df.iterrows():
        table_name = str(get_column(row, 'Table Name', 'table_name', default=f'table-{idx}'))
        field_name = get_column(row, 'Field Name', 'field_name', default='')

        # Initialize table if not seen before
        if table_name not in tables_dict:
            tables_dict[table_name] = {
                'entity_type': get_column(row, 'Entity Type', 'entity_type', default='Client'),
                'columns': []
            }

        # Add field to table
        if field_name:
            column_def = {
                'name': field_name,
                'type': get_column(row, 'Field Type', 'field_type', default='String'),
                'mandatory': str(get_column(row, 'Mandatory', 'mandatory', default='No')).lower() in ['yes', 'true', '1'],
                'length': 100 if get_column(row, 'Field Type', 'field_type', default='String') == 'String' else None
            }
            # Add dropdown values if present
            dropdown_vals = get_column(row, 'Dropdown Values', 'dropdown_values', default='')
            if dropdown_vals and str(dropdown_vals) != 'nan':
                column_def['code'] = f'{table_name}_{field_name}_options'

            tables_dict[table_name]['columns'].append(column_def)

    # Convert aggregated tables to YAML format
    for table_name, table_data in tables_dict.items():
        print(f"  - Data Table: {table_name} ({len(table_data['columns'])} fields)")

        results.append({
            'filename': f"{kebab_case(table_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'DataTable',
                'metadata': {
                    'name': kebab_case(table_name),
                    'labels': {'entity-type': table_data['entity_type'].lower()}
                },
                'spec': {
                    'datatableName': table_name,
                    'apptableName': table_data['entity_type'].upper(),
                    'multiRow': False,
                    'columns': table_data['columns']
                }
            }
        })
    return results


@register_converter('Tellers', 'tellers', 'tellers-data', 'Teller')
def convert_tellers(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Tellers sheet to YAML data structures"""
    # Excel columns: office_name, teller_name, description, start_date, end_date, status
    results = []
    for idx, row in df.iterrows():
        teller_name = str(get_column(row, 'Teller Name', 'teller_name', default=f'teller-{idx}'))
        office_name = get_column(row, 'Office Name', 'office_name', 'Office', 'office', default='Head Office')

        print(f"  - Teller: {teller_name} (Office: {office_name})")

        results.append({
            'filename': f"{kebab_case(teller_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Teller',
                'metadata': {
                    'name': kebab_case(teller_name),
                    'labels': {'office': kebab_case(office_name)}
                },
                'spec': {
                    'name': teller_name,
                    'officeId': office_name,
                    'description': get_column(row, 'Description', 'description', default=''),
                    'startDate': str(get_column(row, 'Start Date', 'start_date', default=datetime.now().strftime('%Y-%m-%d'))),
                    'endDate': str(get_column(row, 'End Date', 'end_date', default='2030-12-31')),
                    'status': get_column(row, 'Status', 'status', default='Active')
                }
            }
        })
    return results


@register_converter('Reports', 'reports', 'reports-data', 'Report')
def convert_reports(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Reports sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        report_name = str(get_column(row, 'Report Name', 'report_name', default=f'report-{idx}'))
        results.append({
            'filename': f"{kebab_case(report_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Report',
                'metadata': {
                    'name': kebab_case(report_name),
                    'labels': {'report-category': get_column(row, 'Category', 'category', default='general')}
                },
                'spec': {
                    'reportName': report_name,
                    'reportType': get_column(row, 'Type', 'type', default='Table'),
                    'reportCategory': get_column(row, 'Category', 'category', default='General'),
                    'useReport': get_column(row, 'Use Report', 'use_report', default='True').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Use Report', 'use_report', default='True'), str) else bool(get_column(row, 'Use Report', 'use_report', default='True')),
                    'reportSql': get_column(row, 'SQL Query', 'sql_query', default='')
                }
            }
        })
    return results


@register_converter('Collateral Types', 'collateral-types', 'collateral-types-data', 'CollateralType')
def convert_collateral_types(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Collateral Types sheet to YAML data structures"""
    # Excel columns: collateral_type, description, requires_valuation
    results = []
    for idx, row in df.iterrows():
        collateral_type = str(get_column(row, 'Collateral Type', 'collateral_type', default=f'collateral-{idx}'))
        description = str(get_column(row, 'Description', 'description', default=''))
        requires_valuation = str(get_column(row, 'Requires Valuation', 'requires_valuation', default='No'))

        print(f"  - Collateral Type: {collateral_type} (Valuation: {requires_valuation})")

        results.append({
            'filename': f"{kebab_case(collateral_type)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'CollateralType',
                'metadata': {
                    'name': kebab_case(collateral_type),
                    'labels': {'collateral-category': 'physical'}
                },
                'spec': {
                    'name': collateral_type,
                    'description': description,
                    'requiresValuation': requires_valuation.lower() in ['yes', 'true', '1']
                }
            }
        })
    return results


@register_converter('Guarantor Types', 'guarantor-types', 'guarantor-types-data', 'GuarantorType')
def convert_guarantor_types(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Guarantor Types sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        guarantor_name = str(get_column(row, 'Guarantor Type', 'guarantor_type', default=f'guarantor-{idx}'))
        results.append({
            'filename': f"{kebab_case(guarantor_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'GuarantorType',
                'metadata': {
                    'name': kebab_case(guarantor_name),
                    'labels': {'guarantor-category': get_column(row, 'Category', 'category', default='individual')}
                },
                'spec': {
                    'name': guarantor_name,
                    'description': get_column(row, 'Description', 'description', default=''),
                    'minGuarantorAmount': float(get_column(row, 'Min Amount', 'min_amount', default='0'))
                }
            }
        })
    return results


@register_converter('Floating Rates', 'floating-rates', 'floating-rates-data', 'FloatingRate')
def convert_floating_rates(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Floating Rates sheet to YAML data structures"""
    # Excel columns: rate_name, is_base_rate, is_active, rate_value, from_date, description
    results = []
    for idx, row in df.iterrows():
        rate_name = str(get_column(row, 'Rate Name', 'rate_name', default=f'rate-{idx}'))
        is_base_rate_str = str(get_column(row, 'Is Base Rate', 'is_base_rate', default='No')).lower()
        is_active_str = str(get_column(row, 'Is Active', 'is_active', 'Active', 'active', default='Yes')).lower()
        rate_value = float(get_column(row, 'Rate Value', 'rate_value', 'Interest Rate', 'interest_rate', default='0.0'))
        description = str(get_column(row, 'Description', 'description', default=''))

        print(f"  - Floating Rate: {rate_name} (Rate: {rate_value}%, Base: {is_base_rate_str}, Active: {is_active_str})")

        results.append({
            'filename': f"{kebab_case(rate_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'FloatingRate',
                'metadata': {
                    'name': kebab_case(rate_name),
                    'labels': {'rate-type': 'base' if is_base_rate_str in ['yes', 'true', '1'] else 'derived'}
                },
                'spec': {
                    'name': rate_name,
                    'description': description,
                    'isBaseLendingRate': is_base_rate_str in ['yes', 'true', '1'],
                    'isActive': is_active_str in ['yes', 'true', '1'],
                    'ratePeriods': [{
                        'fromDate': get_column(row, 'From Date', 'from_date', default=datetime.now().strftime('%Y-%m-%d')),
                        'interestRate': rate_value
                    }]
                }
            }
        })
    return results


@register_converter('Delinquency Buckets', 'delinquency/buckets', 'delinquency-buckets-data', 'DelinquencyBucket')
def convert_delinquency_buckets(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Delinquency Buckets sheet to YAML data structures"""
    # Excel columns: bucket_name, classification, min_days_overdue, max_days_overdue, color_code, description
    results = []
    for idx, row in df.iterrows():
        bucket_name = str(get_column(row, 'Bucket Name', 'bucket_name', default=f'bucket-{idx}'))
        classification = str(get_column(row, 'Classification', 'classification', default=''))
        min_days = str(get_column(row, 'Min Days Overdue', 'min_days_overdue', default='0'))
        max_days = str(get_column(row, 'Max Days Overdue', 'max_days_overdue', default='999'))
        color_code = str(get_column(row, 'Color Code', 'color_code', default=''))
        description = str(get_column(row, 'Description', 'description', default=''))

        print(f"  - Delinquency Bucket: {bucket_name} ({min_days}-{max_days} days)")

        results.append({
            'filename': f"{kebab_case(bucket_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'DelinquencyBucket',
                'metadata': {
                    'name': kebab_case(bucket_name),
                    'labels': {'bucket-type': 'age-based'}
                },
                'spec': {
                    'name': bucket_name,
                    'classification': classification,
                    'minimumAgeDays': int(min_days) if min_days.isdigit() else 0,
                    'maximumAgeDays': int(max_days) if max_days.isdigit() else 999,
                    'colorCode': color_code,
                    'description': description
                }
            }
        })
    return results


@register_converter('Chart of Accounts', 'accounting/chart-of-accounts', 'chart-of-accounts-data', 'GLAccount')
def convert_chart_of_accounts(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Chart of Accounts sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        account_name = get_column(row, 'Account Name', 'account_name', 'accountname', 'name', 'gl_name', default=f'account-{idx}')
        gl_code = get_column(row, 'GL Code', 'gl_code', 'glcode', 'account_code', 'code', default=f'{10000+idx}')
        account_type = get_column(row, 'Type', 'type', 'account_type', 'classification', default='ASSET')
        usage = get_column(row, 'Usage', 'usage', 'account_usage', default='DETAIL')
        manual_entries_str = get_column(row, 'Manual Entries', 'manual_entries', 'manual_entries_allowed', default='True')
        description = get_column(row, 'Description', 'description', default='')

        print(f"  - GL Account: {gl_code} - {account_name} ({account_type})")

        results.append({
            'filename': f"{kebab_case(account_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'GLAccount',
                'metadata': {
                    'name': kebab_case(account_name),
                    'labels': {
                        'account-type': account_type.lower(),
                        'usage': usage.lower()
                    }
                },
                'spec': {
                    'name': account_name,
                    'glCode': gl_code,
                    'type': account_type,
                    'usage': usage,
                    'manualEntriesAllowed': manual_entries_str.lower() in ['true', '1', 'yes'] if isinstance(manual_entries_str, str) else bool(manual_entries_str),
                    'description': description
                }
            }
        })
    return results


@register_converter('Fund Sources', 'accounting/fund-sources', 'fund-sources-data', 'Fund')
def convert_fund_sources(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Fund Sources sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        fund_name = str(get_column(row, 'Fund Name', 'fund_name', default=f'fund-{idx}'))
        results.append({
            'filename': f"{kebab_case(fund_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Fund',
                'metadata': {
                    'name': kebab_case(fund_name),
                    'labels': {'fund-type': get_column(row, 'Type', 'type', default='general')}
                },
                'spec': {
                    'name': fund_name,
                    'externalId': get_column(row, 'External ID', 'external_id', default=f'FUND-{idx:03d}')
                }
            }
        })
    return results


@register_converter('Payment Types', 'accounting/payment-types', 'payment-types-data', 'PaymentType')
def convert_payment_types(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Payment Types sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        payment_name = str(get_column(row, 'Payment Name', 'payment_name', default=f'payment-{idx}'))
        results.append({
            'filename': f"{kebab_case(payment_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'PaymentType',
                'metadata': {
                    'name': kebab_case(payment_name),
                    'labels': {'payment-category': get_column(row, 'Category', 'category', default='general')}
                },
                'spec': {
                    'name': payment_name,
                    'description': get_column(row, 'Description', 'description', default=''),
                    'isCashPayment': get_column(row, 'Is Cash', 'is_cash', default='False').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Is Cash', 'is_cash', default='False'), str) else bool(get_column(row, 'Is Cash', 'is_cash', default='False')),
                    'position': int(get_column(row, 'Position', 'position', default=str(idx + 1)))
                }
            }
        })
    return results


@register_converter('Tax Groups', 'accounting/tax-groups', 'tax-groups-data', 'TaxGroup')
def convert_tax_groups(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Tax Groups sheet to YAML data structures"""
    # Group by tax_group_name since each row is a component
    tax_groups = {}
    for idx, row in df.iterrows():
        tax_name = str(get_column(row, 'Tax Group Name', 'tax_group_name', default=f'tax-{idx}'))
        component_name = str(get_column(row, 'Tax Component Name', 'tax_component_name', default=''))
        tax_type = str(get_column(row, 'Tax Type', 'tax_type', default=''))
        tax_percentage = float(get_column(row, 'Tax Percentage', 'tax_percentage', default='0'))
        start_date = str(get_column(row, 'Start Date', 'start_date', default=datetime.now().strftime('%Y-%m-%d')))
        credit_account_type = str(get_column(row, 'Credit Account Type', 'credit_account_type', default=''))
        credit_gl_code = str(get_column(row, 'Credit GL Code', 'credit_gl_code', default=''))
        credit_gl_name = str(get_column(row, 'Credit GL Name', 'credit_gl_name', default=''))
        description = str(get_column(row, 'Description', 'description', default=''))

        print(f"  - Tax Component: {component_name} ({tax_type}, {tax_percentage}%)")

        if tax_name not in tax_groups:
            tax_groups[tax_name] = {'components': []}

        tax_groups[tax_name]['components'].append({
            'name': component_name,
            'taxType': tax_type,
            'percentage': tax_percentage,
            'startDate': start_date,
            'creditAccountType': credit_account_type,
            'creditGLCode': credit_gl_code,
            'creditGLName': credit_gl_name,
            'description': description
        })

    results = []
    for tax_name, data in tax_groups.items():
        results.append({
            'filename': f"{kebab_case(tax_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'TaxGroup',
                'metadata': {
                    'name': kebab_case(tax_name),
                    'labels': {'tax-type': 'withholding'}
                },
                'spec': {
                    'name': tax_name,
                    'taxComponents': data['components']
                }
            }
        })
    return results


@register_converter('Loan Provisioning', 'accounting/loan-provisioning', 'loan-provisioning-data', 'ProvisioningCriteria')
def convert_loan_provisioning(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Provisioning sheet to YAML data structures - aggregates criteria categories"""
    # Excel columns: category_name, category_id, min_days_overdue, max_days_overdue, provision_percentage, liability_gl_code, expense_gl_code
    results = []

    # Since each row is a category, create a single provisioning criteria with all categories
    definitions = []
    for idx, row in df.iterrows():
        category_name = get_column(row, 'Category Name', 'category_name', default='STANDARD')
        category_id = int(get_column(row, 'Category ID', 'category_id', default=str(idx+1)))
        min_days = int(get_column(row, 'Min Days Overdue', 'min_days_overdue', default='0'))
        max_days = int(get_column(row, 'Max Days Overdue', 'max_days_overdue', default='30'))
        provision_pct = float(get_column(row, 'Provision Percentage', 'provision_percentage', default='0'))

        print(f"  - Provisioning Category: {category_name} (Days: {min_days}-{max_days}, Provision: {provision_pct}%)")

        definitions.append({
            'categoryId': category_id,
            'categoryName': category_name,
            'minAge': min_days,
            'maxAge': max_days,
            'provisioningPercentage': provision_pct,
            'liabilityAccount': get_column(row, 'Liability GL Code', 'liability_gl_code', default=''),
            'expenseAccount': get_column(row, 'Expense GL Code', 'expense_gl_code', default='')
        })

    # Create single provisioning criteria with all categories
    results.append({
        'filename': 'loan-loss-provisioning.yaml',
        'data': {
            'apiVersion': 'fineract.apache.org/v1',
            'kind': 'ProvisioningCriteria',
            'metadata': {
                'name': 'loan-loss-provisioning',
                'labels': {'criteria-type': 'age-based'}
            },
            'spec': {
                'criteriaName': 'Loan Loss Provisioning',
                'loanProducts': [],  # Product IDs will be added later
                'definitions': definitions
            }
        }
    })
    return results


@register_converter('Financial Activity Mappings', 'accounting/financial-activity-mappings', 'financial-activity-mappings-data', 'FinancialActivityMapping')
def convert_financial_activity_mappings(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Financial Activity Mappings sheet to YAML data structures"""
    # Excel columns: financial_activity, gl_code, gl_name, description
    results = []
    for idx, row in df.iterrows():
        # Get the financial activity name from the correct column
        activity_name = str(get_column(row, 'Financial Activity', 'financial_activity', default=f'mapping-{idx}'))
        gl_code = str(get_column(row, 'GL Code', 'gl_code', default=''))
        gl_name = str(get_column(row, 'GL Name', 'gl_name', default=''))
        description = str(get_column(row, 'Description', 'description', default=''))

        print(f"  - Financial Activity: {activity_name} → GL {gl_code} ({gl_name})")

        results.append({
            'filename': f"{kebab_case(activity_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'FinancialActivityMapping',
                'metadata': {
                    'name': kebab_case(activity_name),
                    'labels': {'activity-type': 'financial-activity'}
                },
                'spec': {
                    'financialActivityName': activity_name,
                    'glAccountCode': gl_code,
                    'glAccountName': gl_name,
                    'description': description
                }
            }
        })
    return results


@register_converter('Holidays', 'calendar/holidays', 'holidays-data', 'Holiday')
def convert_holidays(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Holidays sheet to YAML data structures"""
    # Excel columns: holiday_name, date, rescheduled_to, description
    results = []
    for idx, row in df.iterrows():
        holiday_name = str(get_column(row, 'Holiday Name', 'holiday_name', default=f'holiday-{idx}'))
        date_str = str(get_column(row, 'Date', 'date', default=datetime.now().strftime('%Y-%m-%d')))
        rescheduled_str = str(get_column(row, 'Rescheduled To', 'rescheduled_to', default=date_str))

        # Extract year from date to make filename unique across years
        year = date_str.split('-')[0] if date_str else 'unknown'
        filename = f"{kebab_case(holiday_name)}-{year}.yaml"
        resource_name = f"{kebab_case(holiday_name)}-{year}"

        print(f"  - Holiday: {holiday_name} {year} (Date: {date_str})")

        results.append({
            'filename': filename,
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Holiday',
                'metadata': {
                    'name': resource_name,
                    'labels': {'holiday-type': 'public', 'year': year}
                },
                'spec': {
                    'name': holiday_name,
                    'fromDate': date_str,
                    'toDate': date_str,
                    'repaymentsRescheduledTo': rescheduled_str,
                    'offices': ['all'],
                    'description': get_column(row, 'Description', 'description', default='')
                }
            }
        })
    return results


# ==================== Demo/Transactional Data Converters ====================
# These converters support demo data and transactional entities (typically dev only)


@register_converter('Clients', 'clients', 'clients-data', 'Client')
def convert_clients(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Clients sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        first_name = get_column(row, 'First Name', 'firstname', 'first_name', default='')
        middle_name = get_column(row, 'Middle Name', 'middlename', 'middle_name', default='')
        last_name = get_column(row, 'Last Name', 'lastname', 'last_name', default='')
        client_name = f"{first_name} {last_name}".strip() or f'client-{idx}'

        client_type = get_column(row, 'Type', 'type', 'client_type', default='individual')
        office = get_column(row, 'Office', 'office', 'office_name', 'office_id', default='head-office')
        staff = get_column(row, 'Staff', 'staff', 'staff_name', 'staff_id', default='')
        external_id = get_column(row, 'External ID', 'external_id', 'externalid', default=f'CLI-{idx:03d}')
        mobile = get_column(row, 'Mobile', 'mobile', 'mobile_no', 'phone', default='')
        email = get_column(row, 'Email', 'email', 'email_address', default='')
        date_of_birth = get_column(row, 'Date of Birth', 'date_of_birth', 'dateofbirth', 'dob', default='')
        gender = get_column(row, 'Gender', 'gender', 'gender_id', default='Male')
        client_type_id = get_column(row, 'Client Type', 'client_type', 'clienttype', 'client_type_id', default='Individual')
        classification = get_column(row, 'Classification', 'classification', 'client_classification', 'client_classification_id', default='Standard')
        active_str = get_column(row, 'Active', 'active', 'is_active', default='True')
        activation_date = get_column(row, 'Activation Date', 'activation_date', 'activationdate', default=datetime.now().strftime('%Y-%m-%d'))

        print(f"  - Client: {client_name} (Office: {office})")

        results.append({
            'filename': f"{kebab_case(client_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Client',
                'metadata': {
                    'name': kebab_case(client_name),
                    'labels': {'client-type': client_type}
                },
                'spec': {
                    'firstName': first_name,
                    'middleName': middle_name,
                    'lastName': last_name,
                    'officeId': office,
                    'staffId': staff,
                    'externalId': external_id,
                    'mobileNo': mobile,
                    'emailAddress': email,
                    'dateOfBirth': date_of_birth,
                    'genderId': gender,
                    'clientTypeId': client_type_id,
                    'clientClassificationId': classification,
                    'active': active_str.lower() in ['true', '1', 'yes'] if isinstance(active_str, str) else bool(active_str),
                    'activationDate': activation_date
                }
            }
        })
    return results


@register_converter('Groups', 'groups', 'groups-data', 'Group')
def convert_groups(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Groups sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        group_name = str(get_column(row, 'Group Name', 'group_name', default=f'group-{idx}'))
        results.append({
            'filename': f"{kebab_case(group_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Group',
                'metadata': {
                    'name': kebab_case(group_name),
                    'labels': {'group-type': get_column(row, 'Type', 'type', default='standard')}
                },
                'spec': {
                    'name': group_name,
                    'officeId': get_column(row, 'Office', 'office', default='head-office'),
                    'staffId': get_column(row, 'Staff', 'staff', default=''),
                    'externalId': get_column(row, 'External ID', 'external_id', default=f'GRP-{idx:03d}'),
                    'active': get_column(row, 'Active', 'active', default='True').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Active', 'active', default='True'), str) else bool(get_column(row, 'Active', 'active', default='True')),
                    'activationDate': get_column(row, 'Activation Date', 'activation_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'clientMembers': []  # Will be populated from separate sheet or column
                }
            }
        })
    return results


@register_converter('Centers', 'centers', 'centers-data', 'Center')
def convert_centers(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Centers sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        center_name = str(get_column(row, 'Center Name', 'center_name', default=f'center-{idx}'))
        results.append({
            'filename': f"{kebab_case(center_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Center',
                'metadata': {
                    'name': kebab_case(center_name),
                    'labels': {'center-type': get_column(row, 'Type', 'type', default='standard')}
                },
                'spec': {
                    'name': center_name,
                    'officeId': get_column(row, 'Office', 'office', default='head-office'),
                    'staffId': get_column(row, 'Staff', 'staff', default=''),
                    'externalId': get_column(row, 'External ID', 'external_id', default=f'CTR-{idx:03d}'),
                    'active': get_column(row, 'Active', 'active', default='True').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Active', 'active', default='True'), str) else bool(get_column(row, 'Active', 'active', default='True')),
                    'activationDate': get_column(row, 'Activation Date', 'activation_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'meetingStartDate': get_column(row, 'Meeting Start Date', 'meeting_start_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'groupMembers': []  # Will be populated from separate sheet or column
                }
            }
        })
    return results


@register_converter('Loan Accounts', 'accounts/loan-accounts', 'loan-accounts-data', 'LoanAccount')
def convert_loan_accounts(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Accounts sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        # Excel columns: client_external_id, product, submitted_on, approved_on, disbursed_on, principal, loan_term, interest_rate, loan_officer, fund_source, external_id
        client_id = get_column(row, 'Client External ID', 'client_external_id', 'Client', 'client', default='unknown')
        account_name = f"{client_id}-loan-{idx}"

        # Parse loan_term (format: "12 months" or just "12")
        loan_term_str = str(get_column(row, 'Loan Term', 'loan_term', 'Term Frequency', 'term_frequency', default='12'))
        loan_term_parts = loan_term_str.lower().split()
        loan_term = int(loan_term_parts[0]) if loan_term_parts else 12
        loan_term_type = loan_term_parts[1].upper() if len(loan_term_parts) > 1 and 'month' in loan_term_parts[1] else 'MONTHS'

        print(f"  - Loan Account: {account_name} (Principal: {get_column(row, 'Principal', 'principal', default='50000')}, Product: {get_column(row, 'Product', 'product', 'Loan Product', default='')})")

        results.append({
            'filename': f"{kebab_case(account_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'LoanAccount',
                'metadata': {
                    'name': kebab_case(account_name),
                    'labels': {'account-type': 'loan'}
                },
                'spec': {
                    'clientId': client_id,
                    'productId': get_column(row, 'Product', 'product', 'Loan Product', 'loan_product', default=''),
                    'loanOfficerId': get_column(row, 'Loan Officer', 'loan_officer', default=''),
                    'externalId': get_column(row, 'External ID', 'external_id', default=f'LOAN-{idx:03d}'),
                    'fundId': get_column(row, 'Fund Source', 'fund_source', 'Fund', 'fund', default=''),
                    'principal': float(get_column(row, 'Principal', 'principal', default='50000')),
                    'loanTermFrequency': loan_term,
                    'loanTermFrequencyType': loan_term_type,
                    'numberOfRepayments': loan_term,  # Same as term for now
                    'repaymentEvery': 1,
                    'repaymentFrequencyType': loan_term_type,
                    'interestRatePerPeriod': float(get_column(row, 'Interest Rate', 'interest_rate', default='15.0')),
                    'expectedDisbursementDate': get_column(row, 'Disbursed On', 'disbursed_on', 'Disbursement Date', 'disbursement_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'submittedOnDate': get_column(row, 'Submitted On', 'submitted_on', 'Submitted Date', 'submitted_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'approvedOnDate': get_column(row, 'Approved On', 'approved_on', 'Approved Date', 'approved_date', default='')
                }
            }
        })
    return results


@register_converter('Savings Accounts', 'accounts/savings-accounts', 'savings-accounts-data', 'SavingsAccount')
def convert_savings_accounts(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Savings Accounts sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        # Excel columns: client_external_id, product, submitted_on, approved_on, activated_on, initial_deposit, field_officer, external_id
        client_id = get_column(row, 'Client External ID', 'client_external_id', 'Client', 'client', default='unknown')
        account_name = f"{client_id}-savings-{idx}"

        print(f"  - Savings Account: {account_name} (Product: {get_column(row, 'Product', 'product', 'Savings Product', default='')}, Deposit: {get_column(row, 'Initial Deposit', 'initial_deposit', default='0')})")

        results.append({
            'filename': f"{kebab_case(account_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SavingsAccount',
                'metadata': {
                    'name': kebab_case(account_name),
                    'labels': {'account-type': 'savings'}
                },
                'spec': {
                    'clientId': client_id,
                    'productId': get_column(row, 'Product', 'product', 'Savings Product', 'savings_product', default=''),
                    'fieldOfficerId': get_column(row, 'Field Officer', 'field_officer', default=''),
                    'externalId': get_column(row, 'External ID', 'external_id', default=f'SAV-{idx:03d}'),
                    'submittedOnDate': get_column(row, 'Submitted On', 'submitted_on', 'Submitted Date', 'submitted_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'approvedOnDate': get_column(row, 'Approved On', 'approved_on', 'Approved Date', default=''),
                    'activatedOnDate': get_column(row, 'Activated On', 'activated_on', 'Activated Date', default=''),
                    'nominalAnnualInterestRate': float(get_column(row, 'Interest Rate', 'interest_rate', 'nominal_annual_interest_rate', default='5.0')),
                    'minRequiredOpeningBalance': float(get_column(row, 'Initial Deposit', 'initial_deposit', 'Min Opening Balance', 'min_opening_balance', default='0'))
                }
            }
        })
    return results


@register_converter('Share Accounts', 'accounts/share-accounts', 'share-accounts-data', 'ShareAccount')
def convert_share_accounts(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Share Accounts sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        account_name = f"{get_column(row, 'Client', 'client', default='unknown')}-shares-{idx}"
        results.append({
            'filename': f"{kebab_case(account_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'ShareAccount',
                'metadata': {
                    'name': kebab_case(account_name),
                    'labels': {'account-type': 'shares'}
                },
                'spec': {
                    'clientId': get_column(row, 'Client', 'client', default=''),
                    'productId': get_column(row, 'Share Product', 'share_product', default=''),
                    'submittedDate': get_column(row, 'Submitted Date', 'submitted_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'requestedShares': int(get_column(row, 'Requested Shares', 'requested_shares', default='10')),
                    'savingsAccountId': get_column(row, 'Savings Account', 'savings_account', default='')
                }
            }
        })
    return results


@register_converter('Fixed Deposits', 'accounts/fixed-deposits', 'fixed-deposits-data', 'FixedDepositAccount')
def convert_fixed_deposits(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Fixed Deposits sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        account_name = f"{get_column(row, 'Client', 'client', default='unknown')}-fd-{idx}"
        results.append({
            'filename': f"{kebab_case(account_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'FixedDepositAccount',
                'metadata': {
                    'name': kebab_case(account_name),
                    'labels': {'account-type': 'fixed-deposit'}
                },
                'spec': {
                    'clientId': get_column(row, 'Client', 'client', default=''),
                    'productId': get_column(row, 'FD Product', 'fd_product', default=''),
                    'submittedOnDate': get_column(row, 'Submitted Date', 'submitted_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'depositAmount': float(get_column(row, 'Deposit Amount', 'deposit_amount', default='10000')),
                    'depositPeriod': int(get_column(row, 'Deposit Period', 'deposit_period', default='12')),
                    'depositPeriodFrequencyId': get_column(row, 'Period Frequency', 'period_frequency', default='MONTHS')
                }
            }
        })
    return results


@register_converter('Recurring Deposits', 'accounts/recurring-deposits', 'recurring-deposits-data', 'RecurringDepositAccount')
def convert_recurring_deposits(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Recurring Deposits sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        account_name = f"{get_column(row, 'Client', 'client', default='unknown')}-rd-{idx}"
        results.append({
            'filename': f"{kebab_case(account_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'RecurringDepositAccount',
                'metadata': {
                    'name': kebab_case(account_name),
                    'labels': {'account-type': 'recurring-deposit'}
                },
                'spec': {
                    'clientId': get_column(row, 'Client', 'client', default=''),
                    'productId': get_column(row, 'RD Product', 'rd_product', default=''),
                    'submittedOnDate': get_column(row, 'Submitted Date', 'submitted_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'recurringDepositAmount': float(get_column(row, 'Recurring Amount', 'recurring_amount', default='1000')),
                    'depositPeriod': int(get_column(row, 'Deposit Period', 'deposit_period', default='12')),
                    'depositPeriodFrequencyId': get_column(row, 'Period Frequency', 'period_frequency', default='MONTHS'),
                    'recurringDepositFrequency': int(get_column(row, 'Frequency', 'frequency', default='1')),
                    'recurringDepositFrequencyTypeId': get_column(row, 'Frequency Type', 'frequency_type', default='MONTHS')
                }
            }
        })
    return results


@register_converter('Journal Entries', 'accounting/journal-entries', 'journal-entries-data', 'JournalEntry')
def convert_journal_entries(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Journal Entries sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        entry_name = f"entry-{idx}"
        results.append({
            'filename': f"{kebab_case(entry_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'JournalEntry',
                'metadata': {
                    'name': kebab_case(entry_name),
                    'labels': {'entry-type': get_column(row, 'Type', 'type', default='manual')}
                },
                'spec': {
                    'officeId': get_column(row, 'Office', 'office', default='head-office'),
                    'transactionDate': get_column(row, 'Transaction Date', 'transaction_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'glAccountId': get_column(row, 'GL Account Code', 'gl_account_code', default=''),
                    'entryType': get_column(row, 'Entry Type', 'entry_type', default='DEBIT'),
                    'amount': float(get_column(row, 'Amount', 'amount', default='0')),
                    'comments': get_column(row, 'Comments', 'comments', default=''),
                    'referenceNumber': get_column(row, 'Reference Number', 'reference_number', default=f'REF-{idx:05d}')
                }
            }
        })
    return results


@register_converter('GL Closures', 'accounting/gl-closures', 'gl-closures-data', 'GLClosure')
def convert_gl_closures(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert GL Closures sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        closure_name = f"closure-{idx}"
        results.append({
            'filename': f"{kebab_case(closure_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'GLClosure',
                'metadata': {
                    'name': kebab_case(closure_name),
                    'labels': {'closure-type': get_column(row, 'Type', 'type', default='period-end')}
                },
                'spec': {
                    'officeId': get_column(row, 'Office', 'office', default='head-office'),
                    'closingDate': get_column(row, 'Closing Date', 'closing_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'comments': get_column(row, 'Comments', 'comments', default='')
                }
            }
        })
    return results


# ==================== New Converters for Additional Sheets ====================


@register_converter('Configuration', 'system-config', 'configuration-data', 'Configuration')
def convert_configuration(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Configuration sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        # Excel columns: config_key, config_value, category
        config_name = str(get_column(row, 'Config Key', 'config_key', 'Configuration Name', 'configuration_name', default=f'config-{idx}'))

        print(f"  - Configuration: {config_name} = {get_column(row, 'Config Value', 'config_value', 'Value', default='')}")

        results.append({
            'filename': f"{kebab_case(config_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'Configuration',
                'metadata': {
                    'name': kebab_case(config_name),
                    'labels': {'config-type': get_column(row, 'Category', 'category', default='system')}
                },
                'spec': {
                    'name': config_name,
                    'enabled': get_column(row, 'Enabled', 'enabled', default='True').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Enabled', 'enabled', default='True'), str) else bool(get_column(row, 'Enabled', 'enabled', default='True')),
                    'value': get_column(row, 'Config Value', 'config_value', 'Value', 'value', default=''),
                    'description': get_column(row, 'Description', 'description', default='')
                }
            }
        })
    return results


@register_converter('Loan Product Accounting', 'accounting/loan-product-accounting', 'loan-product-accounting-data', 'LoanProductAccounting')
def convert_loan_product_accounting(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Product Accounting sheet to YAML data structures"""
    # Excel columns: product_short_name, mapping_type, gl_code, gl_name, description
    # Excel format is LONG format: multiple rows per product with mapping_type indicating account type
    # We need to pivot this to create one YAML file per product with all account mappings

    results = []

    # Get unique products - find the column name first
    product_col = None
    for col in df.columns:
        if col.lower() in ['product short name', 'product_short_name', 'productshortname']:
            product_col = col
            break

    if product_col is None:
        print(f"  ⚠ Warning: Could not find product column. Available columns: {df.columns.tolist()}")
        return results

    products = df[product_col].unique()

    for product_name in products:
        product_name = str(product_name)
        # Filter rows for this product
        product_df = df[df[product_col] == product_name]

        # Create a mapping dict from mapping_type to gl_code
        account_mappings = []
        for _, row in product_df.iterrows():
            mapping_type = str(get_column(row, 'Mapping Type', 'mapping_type', default=''))
            gl_code = str(get_column(row, 'GL Code', 'gl_code', default=''))
            gl_name = str(get_column(row, 'GL Name', 'gl_name', default=''))
            description = str(get_column(row, 'Description', 'description', default=''))

            if mapping_type and gl_code:
                account_mappings.append({
                    'mappingType': mapping_type,
                    'glAccountCode': gl_code,
                    'glAccountName': gl_name,
                    'description': description
                })

        print(f"  - Loan Product: {product_name} ({len(account_mappings)} account mappings)")

        results.append({
            'filename': f"{kebab_case(product_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'LoanProductAccounting',
                'metadata': {
                    'name': kebab_case(product_name),
                    'labels': {'product-type': 'loan'}
                },
                'spec': {
                    'productName': product_name,
                    'accountMappings': account_mappings
                }
            }
        })

    return results


@register_converter('Savings Product Accounting', 'accounting/savings-product-accounting', 'savings-product-accounting-data', 'SavingsProductAccounting')
def convert_savings_product_accounting(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Savings Product Accounting sheet to YAML data structures"""
    # Excel columns: product_short_name, mapping_type, gl_code, gl_name, description
    # Excel format is LONG format: multiple rows per product with mapping_type indicating account type
    # We need to pivot this to create one YAML file per product with all account mappings

    results = []

    # Load Chart of Accounts for GL name lookup
    gl_lookup = {}
    try:
        # Get the excel file path from the dataframe's source (we'll pass it through global state)
        # For now, we'll check if gl_name looks like a placeholder and needs lookup
        pass
    except:
        pass

    # Get unique products - find the column name first
    product_col = None
    for col in df.columns:
        if col.lower() in ['product short name', 'product_short_name', 'productshortname']:
            product_col = col
            break

    if product_col is None:
        print(f"  ⚠ Warning: Could not find product column. Available columns: {df.columns.tolist()}")
        return results

    products = df[product_col].unique()

    for product_name in products:
        product_name = str(product_name)
        # Filter rows for this product
        product_df = df[df[product_col] == product_name]

        # Create a mapping list from mapping_type to gl_code
        account_mappings = []
        for _, row in product_df.iterrows():
            mapping_type = str(get_column(row, 'Mapping Type', 'mapping_type', default=''))
            gl_code = str(get_column(row, 'GL Code', 'gl_code', default=''))
            gl_name = str(get_column(row, 'GL Name', 'gl_name', default=''))
            description = str(get_column(row, 'Description', 'description', default=''))

            # Check if GL name is a placeholder like "GL Code 61" and needs to be looked up
            if gl_name.startswith('GL Code ') and gl_code:
                # Use a descriptive name based on common savings account GL codes
                code_int = int(gl_code) if gl_code.isdigit() else 0
                gl_name_map = {
                    61: 'Voluntary Savings Accounts',
                    62: 'Fixed Deposit Accounts',
                    63: 'Mandatory Group Savings',
                    64: 'Savings Interest Payable',
                    91: 'Interest Expense on Savings',
                    42: 'Cash on Hand',
                    82: 'Fee Income - Loan Processing',
                    84: 'Fee Income - Savings Accounts',
                    85: 'Mobile Money Transfer Fees'
                }
                if code_int in gl_name_map:
                    gl_name = gl_name_map[code_int]

            if mapping_type and gl_code:
                account_mappings.append({
                    'mappingType': mapping_type,
                    'glAccountCode': gl_code,
                    'glAccountName': gl_name,
                    'description': description
                })

        print(f"  - Savings Product: {product_name} ({len(account_mappings)} account mappings)")

        results.append({
            'filename': f"{kebab_case(product_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SavingsProductAccounting',
                'metadata': {
                    'name': kebab_case(product_name),
                    'labels': {'product-type': 'savings'}
                },
                'spec': {
                    'productName': product_name,
                    'accountMappings': account_mappings
                }
            }
        })

    return results


@register_converter('Payment Type Accounting', 'accounting/payment-type-accounting', 'payment-type-accounting-data', 'PaymentTypeAccounting')
def convert_payment_type_accounting(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Payment Type Accounting sheet to YAML data structures"""
    # Excel columns: payment_type, gl_code, gl_name, fund_source (Yes/No), description
    results = []
    for idx, row in df.iterrows():
        payment_type = str(get_column(row, 'Payment Type', 'payment_type', default=f'payment-type-{idx}'))
        gl_code = str(get_column(row, 'GL Code', 'gl_code', default=''))
        gl_name = str(get_column(row, 'GL Name', 'gl_name', default=''))
        fund_source_str = str(get_column(row, 'Fund Source', 'fund_source', default='No')).lower()
        description = str(get_column(row, 'Description', 'description', default=''))

        # If fund_source is Yes, use GL code as fund source account, otherwise as asset account
        is_fund_source = fund_source_str in ['yes', 'true', '1']

        print(f"  - Payment Type: {payment_type} → GL {gl_code} ({gl_name}) [Fund Source: {is_fund_source}]")

        results.append({
            'filename': f"{kebab_case(payment_type)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'PaymentTypeAccounting',
                'metadata': {
                    'name': kebab_case(payment_type),
                    'labels': {'payment-category': 'accounting'}
                },
                'spec': {
                    'paymentType': payment_type,
                    'glAccountCode': gl_code,
                    'glAccountName': gl_name,
                    'isFundSource': is_fund_source,
                    'description': description
                }
            }
        })
    return results


@register_converter('Teller Cashier Mapping', 'tellers/cashier-mappings', 'cashier-mappings-data', 'TellerCashierMapping')
def convert_teller_cashier_mapping(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Teller Cashier Mapping sheet to YAML data structures"""
    # Excel columns: office_name, teller_name, cash_gl_code, vault_gl_code, shortage_gl_code, overage_gl_code, description
    results = []
    for idx, row in df.iterrows():
        office_name = str(get_column(row, 'Office Name', 'office_name', default=''))
        teller_name = str(get_column(row, 'Teller Name', 'teller_name', default=''))
        cash_gl = str(get_column(row, 'Cash GL Code', 'cash_gl_code', default=''))
        vault_gl = str(get_column(row, 'Vault GL Code', 'vault_gl_code', default=''))
        shortage_gl = str(get_column(row, 'Shortage GL Code', 'shortage_gl_code', default=''))
        overage_gl = str(get_column(row, 'Overage GL Code', 'overage_gl_code', default=''))
        description = str(get_column(row, 'Description', 'description', default=''))

        mapping_name = f"cashier-{kebab_case(office_name)}"

        print(f"  - Cashier Mapping: {office_name} → Teller: {teller_name}, Cash GL: {cash_gl}")

        results.append({
            'filename': f"{kebab_case(mapping_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'TellerCashierMapping',
                'metadata': {
                    'name': kebab_case(mapping_name),
                    'labels': {'mapping-type': 'cashier', 'office': kebab_case(office_name)}
                },
                'spec': {
                    'officeName': office_name,
                    'tellerName': teller_name,
                    'cashGLCode': cash_gl,
                    'vaultGLCode': vault_gl,
                    'shortageGLCode': shortage_gl,
                    'overageGLCode': overage_gl,
                    'description': description,
                    'startDate': get_column(row, 'Start Date', 'start_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'endDate': get_column(row, 'End Date', 'end_date', default='') if pd.notna(get_column(row, 'End Date', 'end_date')) else None
                }
            }
        })
    return results


@register_converter('Global Configuration', 'system-config', 'global-configuration-data', 'GlobalConfiguration')
def convert_global_configuration(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Global Configuration sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        # Excel columns: config_name, enabled, value, description
        config_name = str(get_column(row, 'Config Name', 'config_name', 'Config Key', 'config_key', default=f'global-config-{idx}'))
        enabled_val = get_column(row, 'Enabled', 'enabled', default='No')
        value_val = get_column(row, 'Value', 'value', default='')

        print(f"  - Global Config: {config_name} (Enabled: {enabled_val}, Value: {value_val})")

        results.append({
            'filename': f"{kebab_case(config_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'GlobalConfiguration',
                'metadata': {
                    'name': kebab_case(config_name),
                    'labels': {'config-scope': 'global'}
                },
                'spec': {
                    'name': config_name,
                    'enabled': str(enabled_val).lower() in ['true', '1', 'yes'] if isinstance(enabled_val, str) else bool(enabled_val),
                    'value': value_val,
                    'trapDoor': False,  # Not in Excel, default to False
                    'description': get_column(row, 'Description', 'description', default='')
                }
            }
        })
    return results


@register_converter('SMS Email Config', 'system-config', 'sms-email-config-data', 'SMSEmailConfig')
def convert_sms_email_config(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert SMS Email Config sheet to YAML data structures"""
    # Excel columns: config_type, provider, config_key, config_value, is_active, description
    results = []
    for idx, row in df.iterrows():
        config_type = str(get_column(row, 'Config Type', 'config_type', default=''))
        provider = str(get_column(row, 'Provider', 'provider', default=''))
        config_key = str(get_column(row, 'Config Key', 'config_key', default=f'config-{idx}'))
        config_value = str(get_column(row, 'Config Value', 'config_value', default=''))
        is_active_str = str(get_column(row, 'Is Active', 'is_active', default='No'))
        description = str(get_column(row, 'Description', 'description', default=''))

        # Create a meaningful filename from provider and config_key
        config_name = f"{kebab_case(provider)}-{kebab_case(config_key)}" if provider else kebab_case(config_key)

        print(f"  - SMS/Email Config: {provider} - {config_key} (Active: {is_active_str})")

        results.append({
            'filename': f"{config_name}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SMSEmailConfig',
                'metadata': {
                    'name': config_name,
                    'labels': {'config-type': config_type.lower().replace(' ', '-'), 'provider': provider.lower()}
                },
                'spec': {
                    'configType': config_type,
                    'provider': provider,
                    'configKey': config_key,
                    'configValue': config_value,
                    'isActive': is_active_str.lower() in ['yes', 'true', '1'],
                    'description': description
                }
            }
        })
    return results


@register_converter('Savings Deposits', 'transactions/savings-deposits', 'savings-deposits-data', 'SavingsDeposit')
def convert_savings_deposits(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Savings Deposits sheet to YAML data structures"""
    # Excel columns: client_name, savings_account_number, transaction_date, transaction_amount, payment_type, receipt_number, note, office
    results = []
    for idx, row in df.iterrows():
        client_name = get_column(row, 'Client Name', 'client_name', default='unknown')
        savings_account = get_column(row, 'Savings Account Number', 'savings_account_number', 'Account Number', 'account_number', default='unknown')
        transaction_amount = float(get_column(row, 'Transaction Amount', 'transaction_amount', 'Amount', 'amount', default='0'))
        transaction_name = f"deposit-{kebab_case(client_name)}-{idx}"

        print(f"  - Savings Deposit: {transaction_name} (Account: {savings_account}, Amount: {transaction_amount})")

        results.append({
            'filename': f"{kebab_case(transaction_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SavingsDeposit',
                'metadata': {
                    'name': kebab_case(transaction_name),
                    'labels': {'transaction-type': 'deposit'}
                },
                'spec': {
                    'savingsAccountId': savings_account,
                    'transactionDate': get_column(row, 'Transaction Date', 'transaction_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'transactionAmount': transaction_amount,
                    'paymentTypeId': get_column(row, 'Payment Type', 'payment_type', default=''),
                    'receiptNumber': get_column(row, 'Receipt Number', 'receipt_number', default=''),
                    'note': get_column(row, 'Note', 'note', default='')
                }
            }
        })
    return results


@register_converter('Savings Withdrawals', 'transactions/savings-withdrawals', 'savings-withdrawals-data', 'SavingsWithdrawal')
def convert_savings_withdrawals(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Savings Withdrawals sheet to YAML data structures"""
    # Excel columns: client_name, savings_account_number, transaction_date, transaction_amount, payment_type, receipt_number, note, office
    results = []
    for idx, row in df.iterrows():
        client_name = get_column(row, 'Client Name', 'client_name', default='unknown')
        savings_account = get_column(row, 'Savings Account Number', 'savings_account_number', 'Account Number', 'account_number', default='unknown')
        transaction_amount = float(get_column(row, 'Transaction Amount', 'transaction_amount', 'Amount', 'amount', default='0'))
        transaction_name = f"withdrawal-{kebab_case(client_name)}-{idx}"

        print(f"  - Savings Withdrawal: {transaction_name} (Account: {savings_account}, Amount: {transaction_amount})")

        results.append({
            'filename': f"{kebab_case(transaction_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'SavingsWithdrawal',
                'metadata': {
                    'name': kebab_case(transaction_name),
                    'labels': {'transaction-type': 'withdrawal'}
                },
                'spec': {
                    'savingsAccountId': savings_account,
                    'transactionDate': get_column(row, 'Transaction Date', 'transaction_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'transactionAmount': transaction_amount,
                    'paymentTypeId': get_column(row, 'Payment Type', 'payment_type', default=''),
                    'receiptNumber': get_column(row, 'Receipt Number', 'receipt_number', default=''),
                    'note': get_column(row, 'Note', 'note', default='')
                }
            }
        })
    return results


@register_converter('Loan Repayments', 'transactions/loan-repayments', 'loan-repayments-data', 'LoanRepayment')
def convert_loan_repayments(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Repayments sheet to YAML data structures"""
    # Excel columns: client_name, loan_account_number, transaction_date, principal_amount, interest_amount, fee_amount, penalty_amount, payment_type, receipt_number, note, office
    results = []
    for idx, row in df.iterrows():
        client_name = get_column(row, 'Client Name', 'client_name', default='unknown')
        loan_account = get_column(row, 'Loan Account Number', 'loan_account_number', 'Loan Account', 'loan_account', default='unknown')
        principal_amount = float(get_column(row, 'Principal Amount', 'principal_amount', default='0'))
        interest_amount = float(get_column(row, 'Interest Amount', 'interest_amount', default='0'))
        transaction_amount = principal_amount + interest_amount
        transaction_name = f"repayment-{kebab_case(client_name)}-{idx}"

        print(f"  - Loan Repayment: {transaction_name} (Loan: {loan_account}, Amount: {transaction_amount})")

        results.append({
            'filename': f"{kebab_case(transaction_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'LoanRepayment',
                'metadata': {
                    'name': kebab_case(transaction_name),
                    'labels': {'transaction-type': 'repayment'}
                },
                'spec': {
                    'loanAccountId': loan_account,
                    'transactionDate': get_column(row, 'Transaction Date', 'transaction_date', default=datetime.now().strftime('%Y-%m-%d')),
                    'transactionAmount': transaction_amount,
                    'paymentTypeId': get_column(row, 'Payment Type', 'payment_type', default=''),
                    'receiptNumber': get_column(row, 'Receipt Number', 'receipt_number', default=''),
                    'note': get_column(row, 'Note', 'note', default='')
                }
            }
        })
    return results


@register_converter('Loan Collateral', 'loans/loan-collateral', 'loan-collateral-data', 'LoanCollateral')
def convert_loan_collateral(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Collateral sheet to YAML data structures"""
    # Excel columns: loan_account_number, client_name, collateral_type, collateral_value, description, location, condition, valuation_date, valuation_by, ownership_status, insurance
    results = []
    for idx, row in df.iterrows():
        loan_account = get_column(row, 'Loan Account Number', 'loan_account_number', 'Loan Account', 'loan_account', default='unknown')
        client_name = get_column(row, 'Client Name', 'client_name', default='unknown')
        collateral_type = get_column(row, 'Collateral Type', 'collateral_type', default='Unknown')
        collateral_value = float(get_column(row, 'Collateral Value', 'collateral_value', 'Value', 'value', default='0'))
        collateral_name = f"collateral-{kebab_case(loan_account)}-{idx}"

        print(f"  - Loan Collateral: {collateral_name} (Loan: {loan_account}, Type: {collateral_type}, Value: {collateral_value})")

        results.append({
            'filename': f"{kebab_case(collateral_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'LoanCollateral',
                'metadata': {
                    'name': kebab_case(collateral_name),
                    'labels': {'collateral-type': kebab_case(collateral_type)}
                },
                'spec': {
                    'loanAccountId': loan_account,
                    'collateralTypeId': collateral_type,
                    'value': collateral_value,
                    'description': get_column(row, 'Description', 'description', default=''),
                    'location': get_column(row, 'Location', 'location', default=''),
                    'condition': get_column(row, 'Condition', 'condition', default=''),
                    'valuationDate': get_column(row, 'Valuation Date', 'valuation_date', default=''),
                    'valuationBy': get_column(row, 'Valuation By', 'valuation_by', default='')
                }
            }
        })
    return results


@register_converter('Loan Guarantors', 'loans/loan-guarantors', 'loan-guarantors-data', 'LoanGuarantor')
def convert_loan_guarantors(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Loan Guarantors sheet to YAML data structures"""
    # Excel columns: loan_account_number, borrower_name, guarantor_type, guarantor_name, guarantor_id, guarantor_phone, guarantor_address, relationship, guaranteed_amount, guarantee_date, employment, employer_name, monthly_income
    results = []
    for idx, row in df.iterrows():
        loan_account = get_column(row, 'Loan Account Number', 'loan_account_number', 'Loan Account', 'loan_account', default='unknown')
        guarantor_name_full = get_column(row, 'Guarantor Name', 'guarantor_name', default='Unknown')
        guarantor_type = get_column(row, 'Guarantor Type', 'guarantor_type', default='Individual')
        guaranteed_amount = float(get_column(row, 'Guaranteed Amount', 'guaranteed_amount', 'Amount', 'amount', default='0'))
        guarantor_id = kebab_case(guarantor_name_full)

        print(f"  - Loan Guarantor: {guarantor_id} (Loan: {loan_account}, Name: {guarantor_name_full}, Amount: {guaranteed_amount})")

        results.append({
            'filename': f"guarantor-{guarantor_id}-{idx}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'LoanGuarantor',
                'metadata': {
                    'name': f"guarantor-{guarantor_id}-{idx}",
                    'labels': {'guarantor-type': kebab_case(guarantor_type)}
                },
                'spec': {
                    'loanAccountId': loan_account,
                    'guarantorTypeId': guarantor_type,
                    'fullName': guarantor_name_full,
                    'identificationNumber': get_column(row, 'Guarantor ID', 'guarantor_id', default=''),
                    'phone': get_column(row, 'Guarantor Phone', 'guarantor_phone', default=''),
                    'address': get_column(row, 'Guarantor Address', 'guarantor_address', default=''),
                    'relationship': get_column(row, 'Relationship', 'relationship', default=''),
                    'amount': guaranteed_amount,
                    'guaranteeDate': get_column(row, 'Guarantee Date', 'guarantee_date', default='')
                }
            }
        })
    return results


@register_converter('Inter-Branch Transfers', 'transactions/inter-branch-transfers', 'inter-branch-transfers-data', 'InterBranchTransfer')
def convert_inter_branch_transfers(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Inter-Branch Transfers sheet to YAML data structures"""
    # Excel columns: transfer_date, from_office, to_office, transfer_amount, currency, transfer_type, reference_number, initiated_by, description, status
    results = []
    for idx, row in df.iterrows():
        from_office = get_column(row, 'From Office', 'from_office', default='Unknown')
        to_office = get_column(row, 'To Office', 'to_office', default='Unknown')
        transfer_amount = float(get_column(row, 'Transfer Amount', 'transfer_amount', 'Amount', 'amount', default='0'))
        transfer_date = get_column(row, 'Transfer Date', 'transfer_date', 'Transaction Date', 'transaction_date', default=datetime.now().strftime('%Y-%m-%d'))
        transfer_name = f"transfer-{kebab_case(from_office)}-to-{kebab_case(to_office)}-{idx}"

        print(f"  - Inter-Branch Transfer: {transfer_name} ({from_office} -> {to_office}, Amount: {transfer_amount})")

        results.append({
            'filename': f"{kebab_case(transfer_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'InterBranchTransfer',
                'metadata': {
                    'name': kebab_case(transfer_name),
                    'labels': {'transfer-type': 'inter-branch'}
                },
                'spec': {
                    'fromOfficeId': from_office,
                    'toOfficeId': to_office,
                    'transactionDate': transfer_date,
                    'amount': transfer_amount,
                    'currency': get_column(row, 'Currency', 'currency', default='XAF'),
                    'transferType': get_column(row, 'Transfer Type', 'transfer_type', default='Cash Transfer'),
                    'referenceNumber': get_column(row, 'Reference Number', 'reference_number', default=''),
                    'initiatedBy': get_column(row, 'Initiated By', 'initiated_by', default=''),
                    'description': get_column(row, 'Description', 'description', default=''),
                    'status': get_column(row, 'Status', 'status', default='Completed')
                }
            }
        })
    return results


@register_converter('Financial Reports', 'reports/financial-reports', 'financial-reports-data', 'FinancialReport')
def convert_financial_reports(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert Financial Reports sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        report_name = str(get_column(row, 'Report Name', 'report_name', default=f'financial-report-{idx}'))
        results.append({
            'filename': f"{kebab_case(report_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'FinancialReport',
                'metadata': {
                    'name': kebab_case(report_name),
                    'labels': {'report-category': get_column(row, 'Category', 'category', default='financial')}
                },
                'spec': {
                    'reportName': report_name,
                    'reportType': get_column(row, 'Type', 'type', default='Balance Sheet'),
                    'useReport': get_column(row, 'Use Report', 'use_report', default='True').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Use Report', 'use_report', default='True'), str) else bool(get_column(row, 'Use Report', 'use_report', default='True')),
                    'reportSql': get_column(row, 'SQL Query', 'sql_query', default='')
                }
            }
        })
    return results


@register_converter('COBAC Reports', 'reports/cobac-reports', 'cobac-reports-data', 'COBACReport')
def convert_cobac_reports(df: pd.DataFrame) -> List[Dict[str, Any]]:
    """Convert COBAC Reports sheet to YAML data structures"""
    results = []
    for idx, row in df.iterrows():
        report_name = str(get_column(row, 'Report Name', 'report_name', default=f'cobac-report-{idx}'))
        results.append({
            'filename': f"{kebab_case(report_name)}.yaml",
            'data': {
                'apiVersion': 'fineract.apache.org/v1',
                'kind': 'COBACReport',
                'metadata': {
                    'name': kebab_case(report_name),
                    'labels': {'report-category': 'cobac'}
                },
                'spec': {
                    'reportName': report_name,
                    'reportCode': get_column(row, 'Report Code', 'report_code', default=''),
                    'reportType': get_column(row, 'Type', 'type', default='Regulatory'),
                    'useReport': get_column(row, 'Use Report', 'use_report', default='True').lower() in ['true', '1', 'yes'] if isinstance(get_column(row, 'Use Report', 'use_report', default='True'), str) else bool(get_column(row, 'Use Report', 'use_report', default='True')),
                    'reportSql': get_column(row, 'SQL Query', 'sql_query', default='')
                }
            }
        })
    return results


def convert_entity_type(excel_file: str, output_base_dir: str, sheet_name: str) -> Tuple[int, str]:
    """Convert a single entity type from Excel to YAML"""
    # Check if this sheet name has an alias
    converter_name = SHEET_ALIASES.get(sheet_name, sheet_name)

    if converter_name not in ENTITY_CONFIGS:
        return 0, None

    output_dir, configmap_name, kind, converter_func = ENTITY_CONFIGS[converter_name]

    print(f"Converting {sheet_name}...")

    try:
        df = pd.read_excel(excel_file, sheet_name=sheet_name)
    except Exception as e:
        print(f"  ⚠️  Could not read '{sheet_name}' sheet: {e}")
        return 0, None

    if len(df) == 0:
        print(f"  ⚠️  Sheet '{sheet_name}' is empty")
        return 0, None

    # Create output directory
    output_path = Path(output_base_dir) / output_dir
    output_path.mkdir(parents=True, exist_ok=True)

    # Convert rows to YAML files
    yaml_files = []
    try:
        results = converter_func(df)
        for result in results:
            file_path = output_path / result['filename']
            with open(file_path, 'w') as f:
                yaml.dump(result['data'], f, default_flow_style=False, sort_keys=False)
            yaml_files.append(result['filename'])
            print(f"  ✓ Created: {file_path}")

        # Generate kustomization.yaml
        if yaml_files:
            generate_kustomization(output_path, configmap_name, yaml_files)

        return len(yaml_files), output_dir

    except Exception as e:
        print(f"  ❌ Error converting {sheet_name}: {e}")
        import traceback
        traceback.print_exc()
        return 0, None


def create_main_kustomization(output_dir: str, entity_dirs: List[str]) -> None:
    """Create main kustomization.yaml that includes all entity subdirectories"""
    kustomization = {
        'apiVersion': 'kustomize.config.k8s.io/v1beta1',
        'kind': 'Kustomization',
        'resources': sorted(set(entity_dirs))  # Deduplicate and sort
    }

    kustomization_path = Path(output_dir) / 'kustomization.yaml'
    with open(kustomization_path, 'w') as f:
        yaml.dump(kustomization, f, default_flow_style=False, sort_keys=False)

    print(f"\n✓ Generated main kustomization: {kustomization_path}")


def main():
    """Main conversion function"""
    if len(sys.argv) != 3:
        print("Usage: python3 convert_excel_to_yaml.py <excel_file> <output_dir>")
        print("\nExample:")
        print("  python3 convert_excel_to_yaml.py \\")
        print("    /path/to/fineract_data.xlsx \\")
        print("    operations/fineract-data/data/dev")
        print("\nSupported Excel Sheets (44 entity types):")
        print("  System Config: Code Values, Offices, Staff, Roles, Currency Config,")
        print("                 Working Days, Account Number Formats, Maker Checker,")
        print("                 Scheduler Jobs, Configuration, Global Configuration,")
        print("                 SMS Email Config")
        print("  Products: Loan Products, Savings Products, Charges")
        print("  Features: Notification Templates, Data Tables, Tellers, Reports,")
        print("           Collateral Types, Guarantor Types, Floating Rates,")
        print("           Delinquency Buckets")
        print("  Accounting: Chart of Accounts, Fund Sources, Payment Types,")
        print("             Tax Groups, Loan Provisioning, Financial Activity Mappings,")
        print("             Loan Product Accounting, Savings Product Accounting,")
        print("             Payment Type Accounting")
        print("  Calendar: Holidays")
        print("  Tellers: Tellers, Teller Cashier Mapping")
        print("  Demo/Transactional (typically dev only): Clients, Groups, Centers,")
        print("                      Loan Accounts, Savings Accounts, Share Accounts,")
        print("                      Fixed Deposits, Recurring Deposits, Journal Entries,")
        print("                      GL Closures, Savings Deposits, Savings Withdrawals,")
        print("                      Loan Repayments, Loan Collateral, Loan Guarantors,")
        print("                      Inter-Branch Transfers")
        print("  Reports: Financial Reports, COBAC Reports")
        print("\nNote: Script processes all sheets found in Excel file. Unsupported sheets will be skipped.")
        sys.exit(1)

    excel_file = sys.argv[1]
    output_dir = sys.argv[2]

    if not Path(excel_file).exists():
        print(f"❌ Error: Excel file not found: {excel_file}")
        sys.exit(1)

    print(f"\n📊 Converting Excel to YAML")
    print(f"   Source: {excel_file}")
    print(f"   Target: {output_dir}\n")

    total = 0
    entity_dirs = []

    # Read all sheets from Excel file
    try:
        xls = pd.ExcelFile(excel_file)
        available_sheets = xls.sheet_names
        print(f"Found {len(available_sheets)} sheets in Excel file\n")
    except Exception as e:
        print(f"❌ Error: Could not read Excel file: {e}")
        sys.exit(1)

    # Process all sheets from the Excel file
    for sheet_name in available_sheets:
        count, entity_dir = convert_entity_type(excel_file, output_dir, sheet_name)
        total += count
        if entity_dir:
            entity_dirs.append(entity_dir)

    # Create main kustomization.yaml
    if entity_dirs:
        create_main_kustomization(output_dir, entity_dirs)

    print(f"\n✅ Conversion complete! Created {total} YAML files")
    print(f"\nGenerated kustomization.yaml files with configMapGenerator for:")
    for entity_dir in sorted(set(entity_dirs)):
        print(f"  - {entity_dir}")

    print(f"\nNext steps:")
    print(f"  1. Review generated YAML files: tree {output_dir}")
    print(f"  2. Test kustomize build: kustomize build {output_dir}")
    print(f"  3. Commit to Git: git add {output_dir} && git commit -m 'ops: add environment data'")


if __name__ == '__main__':
    main()
