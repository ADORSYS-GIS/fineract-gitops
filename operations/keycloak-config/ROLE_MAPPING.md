# Fineract ↔ Keycloak Role Mapping

## Problem Statement

**Fineract uses role names with spaces** (e.g., "Super User", "Loan Officer")
**Keycloak uses kebab-case roles** (e.g., "loan-officer", "branch-manager")

This document defines the canonical mapping between the two systems.

---

## Standard Fineract Roles

Based on Fineract's default roles (from Fineract API `/roles`):

| Fineract Role (with spaces) | Description |
|------------------------------|-------------|
| Super user | Full administrative access to all functions |
| Loan Officer | Create and manage loans, clients |
| Teller | Cash transactions, deposits, withdrawals |
| Branch Manager | Manage branch operations, approve loans |
| Accountant | View financial reports, manage accounting |
| Field Officer | Field operations, client visits |
| Operations Manager | Operational oversight |
| Credit Committee | Loan approval authority |
| Checker | Maker-checker approval workflows |
| Read Only | View-only access |

**Note**: Fineract roles are case-sensitive and include spaces.

---

## Keycloak Roles (Normalized)

For Keycloak, we use **kebab-case** (lowercase with hyphens) for consistency and to avoid issues with:
- URLs
- LDAP/Active Directory integration
- Case-sensitive systems
- Special character handling

| Keycloak Role | Description |
|---------------|-------------|
| admin | System administrator (maps to Fineract "Super user") |
| loan-officer | Loan officer |
| teller | Teller/cashier |
| branch-manager | Branch manager |
| accountant | Accountant |
| field-officer | Field officer |
| operations-manager | Operations manager |
| credit-committee | Credit committee member |
| checker | Maker-checker approver |
| readonly | Read-only access |
| staff | Generic staff member |
| client | Client/customer |

---

## Role Mapping Table

### Complete Mapping

| Fineract Role (exact) | Keycloak Role | Priority | Notes |
|-----------------------|---------------|----------|-------|
| `Super user` | `admin` | 1 | Highest privilege |
| `superuser` | `admin` | 1 | Alternative format |
| `Super User` | `admin` | 1 | Alternative capitalization |
| `Loan Officer` | `loan-officer` | 2 | |
| `Teller` | `teller` | 3 | |
| `Cashier` | `teller` | 3 | Synonym for teller |
| `Branch Manager` | `branch-manager` | 2 | |
| `Accountant` | `accountant` | 3 | |
| `Field Officer` | `field-officer` | 3 | |
| `Operations Manager` | `operations-manager` | 2 | |
| `Credit Committee` | `credit-committee` | 2 | |
| `Checker` | `checker` | 3 | Maker-checker workflow |
| `Read Only` | `readonly` | 4 | Lowest privilege |
| `Staff` | `staff` | 3 | Generic staff |
| `Client` | `client` | 5 | Customer role |

### Default Mapping

If Fineract role is not found in the table, default to: **`staff`**

---

## Implementation

### User Sync Service

Update `sync_service.py` ROLE_MAPPING:

```python
ROLE_MAPPING = {
    # Exact matches (case-sensitive from Fineract)
    "Super user": "admin",
    "superuser": "admin",
    "Super User": "admin",

    "Loan Officer": "loan-officer",
    "loan officer": "loan-officer",

    "Teller": "teller",
    "teller": "teller",
    "Cashier": "teller",

    "Branch Manager": "branch-manager",
    "branch manager": "branch-manager",

    "Accountant": "accountant",
    "accountant": "accountant",

    "Field Officer": "field-officer",
    "field officer": "field-officer",

    "Operations Manager": "operations-manager",
    "operations manager": "operations-manager",

    "Credit Committee": "credit-committee",
    "credit committee": "credit-committee",

    "Checker": "checker",
    "checker": "checker",

    "Read Only": "readonly",
    "read only": "readonly",
    "ReadOnly": "readonly",

    "Staff": "staff",
    "staff": "staff",

    "Client": "client",
    "client": "client",
}

# Fallback
DEFAULT_ROLE = "staff"
```

### Mapping Function

```python
def map_fineract_role_to_keycloak(fineract_role: str) -> str:
    """
    Map Fineract role (with spaces) to Keycloak role (kebab-case)

    Handles:
    - Exact match (case-sensitive)
    - Lowercase fallback
    - Default to 'staff' if not found
    """
    # Try exact match first
    if fineract_role in ROLE_MAPPING:
        return ROLE_MAPPING[fineract_role]

    # Try lowercase
    lower_role = fineract_role.lower()
    if lower_role in ROLE_MAPPING:
        return ROLE_MAPPING[lower_role]

    # Try normalized (replace spaces with hyphens, lowercase)
    normalized = fineract_role.lower().replace(" ", "-")
    if normalized in ["admin", "loan-officer", "teller", "branch-manager",
                      "accountant", "field-officer", "operations-manager",
                      "credit-committee", "checker", "readonly", "staff", "client"]:
        return normalized

    # Default fallback
    logger.warning(f"Unknown Fineract role '{fineract_role}', defaulting to 'staff'")
    return DEFAULT_ROLE
```

---

## Recommendation: **Keep the Spaces in Fineract**

### Why NOT normalize in Fineract:

❌ **Breaking Change**: Existing Fineract installations have roles with spaces
❌ **API Compatibility**: Fineract API expects exact role names
❌ **Database Changes**: Requires schema migration
❌ **Third-party Integrations**: Other systems may rely on current role names

### Why normalize in Keycloak:

✅ **Clean URLs**: `/admin/roles/loan-officer` vs `/admin/roles/Loan%20Officer`
✅ **LDAP/AD Compatibility**: Most LDAP systems prefer no spaces
✅ **Consistency**: Matches Keycloak naming conventions
✅ **Case-insensitive**: Lowercase avoids case-sensitivity issues
✅ **No Encoding**: Avoids URL encoding problems

---

## Solution: **Mapping Layer**

Keep roles as-is in Fineract, normalize in Keycloak, use mapping layer in between.

```
┌──────────────────┐        ┌──────────────────┐        ┌─────────────────┐
│   Fineract       │        │  User Sync       │        │   Keycloak      │
│                  │        │   Service        │        │                 │
│  "Loan Officer"  │  ────> │  ROLE_MAPPING    │  ────> │  loan-officer   │
│  "Super user"    │  ────> │  Dictionary      │  ────> │  admin          │
│  "Teller"        │  ────> │                  │  ────> │  teller         │
└──────────────────┘        └──────────────────┘        └─────────────────┘
```

---

## Testing

### Test Cases

```python
# Test exact match
assert map_fineract_role_to_keycloak("Super user") == "admin"

# Test case variations
assert map_fineract_role_to_keycloak("Super User") == "admin"
assert map_fineract_role_to_keycloak("Loan Officer") == "loan-officer"
assert map_fineract_role_to_keycloak("loan officer") == "loan-officer"

# Test synonyms
assert map_fineract_role_to_keycloak("Cashier") == "teller"

# Test fallback
assert map_fineract_role_to_keycloak("Unknown Role") == "staff"

# Test normalization
assert map_fineract_role_to_keycloak("Field Officer") == "field-officer"
```

---

## Migration Guide

### If You Need to Check Fineract Roles

```bash
# Get all roles from Fineract API
curl -X GET "http://fineract:8080/fineract-provider/api/v1/roles" \
  -H "Fineract-Platform-TenantId: default" \
  -H "Authorization: Basic $(echo -n 'mifos:password' | base64)"

# Response will show actual role names:
[
  {"id": 1, "name": "Super user", "description": "..."},
  {"id": 2, "name": "Loan Officer", "description": "..."},
  ...
]
```

### Update Mapping if Needed

1. Get actual role names from your Fineract instance
2. Update `ROLE_MAPPING` in `sync_service.py`
3. Update this document
4. Commit to Git
5. Redeploy user sync service

---

## FAQs

### Q: Should I remove spaces from Fineract roles?

**A: No.** Keep Fineract roles as-is. Use the mapping layer for Keycloak.

### Q: What if Fineract adds a new role?

**A: Add it to `ROLE_MAPPING` dictionary.** If role is similar to existing ones, it will default to `staff`.

### Q: Can I use custom Fineract roles?

**A: Yes.** Add them to `ROLE_MAPPING`. Example:
```python
"Regional Manager": "regional-manager",
"Auditor": "auditor",
```

Then add corresponding Keycloak role to `realm-fineract.yaml`:
```yaml
roles:
  realm:
    - name: regional-manager
      description: Regional manager role
```

### Q: What about hierarchical roles?

**A: Use composite roles in Keycloak.** Example:
```yaml
roles:
  realm:
    - name: branch-manager
      composite: true
      composites:
        realm:
          - loan-officer
          - staff
```

---

## Conclusion

✅ **Keep Fineract roles with spaces** (no breaking changes)
✅ **Normalize in Keycloak** (kebab-case, lowercase)
✅ **Use mapping layer** (user sync service)
✅ **Document all mappings** (this file)
✅ **Test thoroughly** (edge cases, synonyms)

This approach provides flexibility while maintaining compatibility with both systems.
