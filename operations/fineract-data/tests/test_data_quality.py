"""
Data Quality Tests for Fineract YAML Files

These tests validate the integrity and consistency of YAML data files
before they are deployed to Fineract.
"""
import pytest
import yaml
from pathlib import Path
from typing import Dict, List, Set

# Base directory for test data
DATA_DIR = Path(__file__).parent.parent / "data" / "dev"


def load_yaml_file(filepath: Path) -> Dict:
    """Load and parse a YAML file"""
    with open(filepath, 'r') as f:
        return yaml.safe_load(f)


def get_all_yaml_files(subdir: str = "") -> List[Path]:
    """Get all YAML files in a subdirectory"""
    search_dir = DATA_DIR / subdir if subdir else DATA_DIR
    return [f for f in search_dir.rglob("*.yaml") if f.name != "kustomization.yaml"]


def get_entity_names(entity_type: str, name_field: str = "name") -> Set[str]:
    """Extract entity names from YAML files of a specific type"""
    names = set()
    for yaml_file in get_all_yaml_files():
        data = load_yaml_file(yaml_file)
        if data.get('kind') == entity_type:
            spec = data.get('spec', {})
            if name_field in spec:
                names.add(spec[name_field])
    return names


class TestOfficeReferences:
    """Test office reference integrity"""

    def test_all_offices_have_required_fields(self):
        """Verify all office YAMLs have required fields"""
        office_files = [f for f in get_all_yaml_files("offices")]

        for yaml_file in office_files:
            data = load_yaml_file(yaml_file)
            assert data.get('kind') == 'Office', f"Invalid kind in {yaml_file}"

            spec = data.get('spec', {})
            assert 'name' in spec, f"Missing name in {yaml_file}"
            assert 'externalId' in spec, f"Missing externalId in {yaml_file}"
            assert 'openingDate' in spec, f"Missing openingDate in {yaml_file}"

            # Validate openingDate format (YYYY-MM-DD)
            opening_date = spec['openingDate']
            assert len(opening_date) == 10, f"Invalid date format in {yaml_file}: {opening_date}"
            assert opening_date[4] == '-' and opening_date[7] == '-', \
                f"Invalid date format in {yaml_file}: {opening_date}"

    def test_office_parent_references_exist(self):
        """Verify parent office references are valid"""
        # Get all office names
        office_names = get_entity_names('Office', 'name')

        # Add Fineract's default office
        office_names.add('Head Office')  # Default office (ID 1) in Fineract

        # Check each office's parent reference
        for yaml_file in get_all_yaml_files("offices"):
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            parent = spec.get('parentOffice')

            if parent and parent not in ['head-office', None]:
                assert parent in office_names, \
                    f"Invalid parentOffice in {yaml_file.name}: '{parent}' not found. " \
                    f"Available offices: {sorted(office_names)}"

    def test_no_circular_office_hierarchy(self):
        """Verify there are no circular office hierarchies"""
        offices = {}
        for yaml_file in get_all_yaml_files("offices"):
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            name = spec.get('name')
            parent = spec.get('parentOffice')
            if name:
                offices[name] = parent

        # Check for circular references
        for office_name, parent in offices.items():
            visited = set()
            current = parent

            while current and current != 'head-office':
                if current in visited:
                    pytest.fail(f"Circular reference detected: {office_name} → {' → '.join(visited)}")
                visited.add(current)
                current = offices.get(current)


class TestStaffReferences:
    """Test staff reference integrity"""

    def test_all_staff_have_required_fields(self):
        """Verify all staff YAMLs have required fields"""
        staff_files = [f for f in get_all_yaml_files("staff")]

        for yaml_file in staff_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})

            assert 'firstName' in spec, f"Missing firstName in {yaml_file}"
            assert 'lastName' in spec, f"Missing lastName in {yaml_file}"
            assert 'officeId' in spec, f"Missing officeId in {yaml_file}"
            assert 'isLoanOfficer' in spec, f"Missing isLoanOfficer in {yaml_file}"

    def test_staff_office_references_valid(self):
        """Verify all staff members reference existing offices"""
        office_names = get_entity_names('Office', 'name')
        office_names.add('Head Office')  # Default Fineract office

        staff_files = [f for f in get_all_yaml_files("staff")]

        for yaml_file in staff_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            office_ref = spec.get('officeId')

            if office_ref:
                assert office_ref in office_names, \
                    f"Staff {yaml_file.name} references non-existent office: '{office_ref}'. " \
                    f"Available offices: {sorted(office_names)}"


class TestProductConfiguration:
    """Test product configuration integrity"""

    def test_loan_products_have_required_fields(self):
        """Verify loan products have required fields"""
        loan_product_files = [f for f in get_all_yaml_files("products/loan-products")]

        required_fields = [
            'name', 'shortName', 'currency', 'principal', 'interestRate',
            'numberOfRepayments', 'repaymentFrequency', 'amortizationType'
        ]

        for yaml_file in loan_product_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})

            for field in required_fields:
                assert field in spec, f"Missing {field} in {yaml_file.name}"

            # Validate principal structure
            principal = spec.get('principal', {})
            assert 'min' in principal, f"Missing principal.min in {yaml_file.name}"
            assert 'default' in principal, f"Missing principal.default in {yaml_file.name}"
            assert 'max' in principal, f"Missing principal.max in {yaml_file.name}"

    def test_savings_products_have_required_fields(self):
        """Verify savings products have required fields"""
        savings_product_files = [f for f in get_all_yaml_files("products/savings-products")]

        required_fields = [
            'name', 'shortName', 'currency', 'nominalAnnualInterestRate',
            'interestCompoundingPeriod', 'interestPostingPeriod', 'interestCalculationType'
        ]

        for yaml_file in savings_product_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})

            for field in required_fields:
                assert field in spec, f"Missing {field} in {yaml_file.name}"

    def test_product_currencies_valid(self):
        """Verify all products use valid currency codes"""
        valid_currencies = ['XAF', 'USD', 'EUR', 'GBP', 'XOF']  # Add more as needed

        product_files = get_all_yaml_files("products")

        for yaml_file in product_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            currency = spec.get('currency')

            if currency:
                assert currency in valid_currencies, \
                    f"Invalid currency in {yaml_file.name}: {currency}. " \
                    f"Valid currencies: {valid_currencies}"


class TestAccountingReferences:
    """Test accounting reference integrity"""

    def test_gl_accounts_have_required_fields(self):
        """Verify GL accounts have required fields"""
        gl_account_files = [f for f in get_all_yaml_files("accounting/chart-of-accounts")]

        for yaml_file in gl_account_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})

            assert 'name' in spec, f"Missing name in {yaml_file}"
            assert 'glCode' in spec, f"Missing glCode in {yaml_file}"
            assert 'type' in spec, f"Missing type in {yaml_file}"
            assert 'usage' in spec, f"Missing usage in {yaml_file}"

    def test_gl_account_types_valid(self):
        """Verify GL account types are valid"""
        valid_types = ['Asset', 'Liability', 'Equity', 'Income', 'Expense']

        gl_account_files = [f for f in get_all_yaml_files("accounting/chart-of-accounts")]

        for yaml_file in gl_account_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            account_type = spec.get('type')

            if account_type:
                assert account_type in valid_types, \
                    f"Invalid GL account type in {yaml_file.name}: {account_type}. " \
                    f"Valid types: {valid_types}"

    def test_gl_account_usage_valid(self):
        """Verify GL account usage is valid"""
        valid_usages = ['Detail', 'Header']

        gl_account_files = [f for f in get_all_yaml_files("accounting/chart-of-accounts")]

        for yaml_file in gl_account_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            usage = spec.get('usage')

            if usage:
                assert usage in valid_usages, \
                    f"Invalid GL account usage in {yaml_file.name}: {usage}. " \
                    f"Valid usages: {valid_usages}"

    def test_gl_parent_references_exist(self):
        """Verify GL account parent references are valid"""
        # Get all GL account names
        gl_names = get_entity_names('GLAccount', 'name')
        gl_codes = set()

        for yaml_file in get_all_yaml_files("accounting/chart-of-accounts"):
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            if 'glCode' in spec:
                gl_codes.add(str(spec['glCode']))

        # Check parent references
        for yaml_file in get_all_yaml_files("accounting/chart-of-accounts"):
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            parent = spec.get('parentGLAccount')

            if parent:
                # Parent can be referenced by name or code
                assert parent in gl_names or str(parent) in gl_codes, \
                    f"Invalid parentGLAccount in {yaml_file.name}: '{parent}'"


class TestRolePermissions:
    """Test role permission integrity"""

    def test_roles_have_required_fields(self):
        """Verify roles have required fields"""
        role_files = [f for f in get_all_yaml_files("roles")]

        for yaml_file in role_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})

            assert 'name' in spec, f"Missing name in {yaml_file}"
            assert 'description' in spec, f"Missing description in {yaml_file}"
            assert 'disabled' in spec, f"Missing disabled in {yaml_file}"
            assert 'permissions' in spec, f"Missing permissions in {yaml_file}"

    def test_role_permissions_have_codes(self):
        """Verify all role permissions have permission codes"""
        role_files = [f for f in get_all_yaml_files("roles")]

        for yaml_file in role_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})
            permissions = spec.get('permissions', [])

            for i, perm in enumerate(permissions):
                assert 'code' in perm, \
                    f"Missing code in permission {i} of {yaml_file.name}"
                assert perm['code'], \
                    f"Empty permission code in permission {i} of {yaml_file.name}"


class TestYAMLStructure:
    """Test basic YAML structure and syntax"""

    def test_all_yaml_files_parseable(self):
        """Verify all YAML files can be parsed"""
        yaml_files = get_all_yaml_files()

        for yaml_file in yaml_files:
            try:
                data = load_yaml_file(yaml_file)
                assert data is not None, f"Empty YAML file: {yaml_file}"
            except yaml.YAMLError as e:
                pytest.fail(f"YAML parse error in {yaml_file}: {e}")

    def test_all_yaml_files_have_required_structure(self):
        """Verify all YAML files have required top-level structure"""
        yaml_files = get_all_yaml_files()

        for yaml_file in yaml_files:
            data = load_yaml_file(yaml_file)

            assert 'apiVersion' in data, f"Missing apiVersion in {yaml_file}"
            assert 'kind' in data, f"Missing kind in {yaml_file}"
            assert 'metadata' in data, f"Missing metadata in {yaml_file}"
            assert 'spec' in data, f"Missing spec in {yaml_file}"

            metadata = data.get('metadata', {})
            assert 'name' in metadata, f"Missing metadata.name in {yaml_file}"


class TestCodeValues:
    """Test code values configuration"""

    def test_code_values_have_required_fields(self):
        """Verify code values have required fields"""
        code_value_files = [f for f in get_all_yaml_files("codes-and-values")]

        for yaml_file in code_value_files:
            data = load_yaml_file(yaml_file)
            spec = data.get('spec', {})

            assert 'codeName' in spec, f"Missing codeName in {yaml_file}"
            assert 'values' in spec, f"Missing values in {yaml_file}"

            # Verify each value has required fields
            values = spec.get('values', [])
            for i, value in enumerate(values):
                assert 'name' in value, \
                    f"Missing name in value {i} of {yaml_file.name}"
                assert 'position' in value, \
                    f"Missing position in value {i} of {yaml_file.name}"


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v"])
