#!/usr/bin/env python3
"""
Webank User Sync Service
Syncs users from Fineract to Keycloak

This service acts as a bridge between Fineract (source of truth for users)
and Keycloak (identity provider). It creates matching Keycloak users when
users are created in Fineract.
"""

import os
import sys
import logging
import secrets
import string
from typing import Dict, List, Optional
from flask import Flask, request, jsonify
from keycloak import KeycloakAdmin, KeycloakError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Keycloak configuration
KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://keycloak-service:8080")
KEYCLOAK_REALM = os.getenv("KEYCLOAK_REALM", "fineract")
ADMIN_CLI_CLIENT_ID = os.getenv("ADMIN_CLI_CLIENT_ID", "admin-cli")
ADMIN_CLI_SECRET = os.getenv("ADMIN_CLI_SECRET")

# Keycloak Admin credentials (for password reset and user management)
KEYCLOAK_ADMIN_USERNAME = os.getenv("KEYCLOAK_ADMIN_USERNAME")
KEYCLOAK_ADMIN_PASSWORD = os.getenv("KEYCLOAK_ADMIN_PASSWORD")

# Fineract role → Keycloak role mapping
# Handles Fineract roles with spaces → Keycloak kebab-case roles
# See: operations/keycloak-config/ROLE_MAPPING.md for full documentation
ROLE_MAPPING = {
    # Admin roles (highest privilege)
    "Super user": "admin",         # Fineract default (lowercase 'user')
    "Super User": "admin",         # Alternative capitalization
    "superuser": "admin",          # No space variant
    "Admin": "admin",

    # Loan Officer
    "Loan Officer": "loan-officer",
    "loan officer": "loan-officer",

    # Teller/Cashier
    "Teller": "teller",
    "teller": "teller",
    "Cashier": "teller",           # Synonym
    "cashier": "teller",

    # Branch Manager
    "Branch Manager": "branch-manager",
    "branch manager": "branch-manager",

    # Accountant
    "Accountant": "accountant",
    "accountant": "accountant",

    # Field Officer
    "Field Officer": "field-officer",
    "field officer": "field-officer",

    # Operations Manager
    "Operations Manager": "operations-manager",
    "operations manager": "operations-manager",

    # Credit Committee
    "Credit Committee": "credit-committee",
    "credit committee": "credit-committee",

    # Maker-Checker
    "Checker": "checker",
    "checker": "checker",
    "Maker": "checker",            # Maker uses same role

    # Read-only
    "Read Only": "readonly",
    "read only": "readonly",
    "ReadOnly": "readonly",

    # Generic Staff
    "Staff": "staff",
    "staff": "staff",

    # Client/Customer
    "Client": "client",
    "client": "client",
    "Customer": "client",
}

# Default role for unmapped Fineract roles
DEFAULT_ROLE = "staff"

# Initialize Keycloak Admin Client
def get_keycloak_admin():
    """Get Keycloak Admin client with admin credentials or service account"""
    try:
        # Prefer admin username/password if available (required for admin operations)
        if KEYCLOAK_ADMIN_USERNAME and KEYCLOAK_ADMIN_PASSWORD:
            admin = KeycloakAdmin(
                server_url=KEYCLOAK_URL,
                username=KEYCLOAK_ADMIN_USERNAME,
                password=KEYCLOAK_ADMIN_PASSWORD,
                realm_name="master",  # Admin user is in master realm
                user_realm_name=KEYCLOAK_REALM,  # But operates on fineract realm
                verify=True
            )
            logger.info("Successfully connected to Keycloak with admin credentials")
        else:
            # Fall back to admin-cli service account
            admin = KeycloakAdmin(
                server_url=KEYCLOAK_URL,
                client_id=ADMIN_CLI_CLIENT_ID,
                client_secret_key=ADMIN_CLI_SECRET,
                realm_name=KEYCLOAK_REALM,
                verify=True
            )
            logger.info("Successfully connected to Keycloak with admin-cli service account")
        return admin
    except Exception as e:
        logger.error(f"Failed to connect to Keycloak: {str(e)}")
        raise


def generate_temp_password(length=16) -> str:
    """Generate cryptographically secure temporary password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    password = ''.join(secrets.choice(alphabet) for i in range(length))

    # Ensure password meets requirements
    has_upper = any(c.isupper() for c in password)
    has_lower = any(c.islower() for c in password)
    has_digit = sum(c.isdigit() for c in password) >= 2
    has_special = any(c in "!@#$%^&*" for c in password)

    if not (has_upper and has_lower and has_digit and has_special):
        # Regenerate if requirements not met
        return generate_temp_password(length)

    return password


def map_fineract_role_to_keycloak(fineract_role: str) -> str:
    """
    Map Fineract role (with spaces) to Keycloak role (kebab-case)

    Handles:
    - Exact match (case-sensitive)
    - Lowercase fallback
    - Normalized format (spaces → hyphens)
    - Default to DEFAULT_ROLE if not found

    Args:
        fineract_role: Role name from Fineract (e.g., "Loan Officer", "Super user")

    Returns:
        Keycloak role name (e.g., "loan-officer", "admin")

    Examples:
        >>> map_fineract_role_to_keycloak("Super user")
        "admin"
        >>> map_fineract_role_to_keycloak("Loan Officer")
        "loan-officer"
        >>> map_fineract_role_to_keycloak("Unknown Role")
        "staff"
    """
    if not fineract_role:
        logger.warning("Empty Fineract role provided, defaulting to DEFAULT_ROLE")
        return DEFAULT_ROLE

    # Try exact match first (most common case)
    if fineract_role in ROLE_MAPPING:
        return ROLE_MAPPING[fineract_role]

    # Try lowercase version
    lower_role = fineract_role.lower()
    if lower_role in ROLE_MAPPING:
        return ROLE_MAPPING[lower_role]

    # Try normalized (spaces → hyphens, lowercase)
    normalized = lower_role.replace(" ", "-")

    # Check if normalized version matches a Keycloak role directly
    valid_keycloak_roles = [
        "admin", "loan-officer", "teller", "branch-manager",
        "accountant", "field-officer", "operations-manager",
        "credit-committee", "checker", "readonly", "staff", "client"
    ]

    if normalized in valid_keycloak_roles:
        logger.info(f"Normalized Fineract role '{fineract_role}' to Keycloak role '{normalized}'")
        return normalized

    # If still not found, log warning and use default
    logger.warning(f"Unknown Fineract role '{fineract_role}', defaulting to '{DEFAULT_ROLE}'")
    return DEFAULT_ROLE


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        admin = get_keycloak_admin()
        realm_info = admin.get_realm(KEYCLOAK_REALM)
        return jsonify({
            "status": "healthy",
            "service": "fineract-keycloak-sync",
            "keycloak_connected": True,
            "realm": realm_info.get("realm")
        }), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 503


@app.route('/sync/user', methods=['POST'])
def sync_user():
    """
    Sync a single user from Fineract to Keycloak

    Expected payload:
    {
        "userId": 123,
        "username": "john.doe",
        "email": "john.doe@webank.com",
        "firstName": "John",
        "lastName": "Doe",
        "role": "Loan Officer",
        "officeId": 1,
        "officeName": "Head Office",
        "employeeId": "EMP001",
        "mobileNumber": "+254712345678"
    }
    """
    try:
        data = request.get_json()

        # Validate required fields
        required_fields = ['userId', 'username', 'email']
        for field in required_fields:
            if field not in data:
                return jsonify({
                    "status": "error",
                    "message": f"Missing required field: {field}"
                }), 400

        # Extract user data
        fineract_user_id = str(data['userId'])
        username = data['username']
        email = data['email']
        first_name = data.get('firstName', '')
        last_name = data.get('lastName', '')
        fineract_role = data.get('role', 'Staff')
        office_id = str(data.get('officeId', ''))
        office_name = data.get('officeName', '')
        employee_id = data.get('employeeId', '')
        mobile_number = data.get('mobileNumber', '')

        logger.info(f"Syncing user: {username} (Fineract ID: {fineract_user_id})")

        # Get Keycloak admin client
        admin = get_keycloak_admin()

        # Check if user already exists
        existing_users = admin.get_users({"username": username})
        if existing_users:
            logger.warning(f"User {username} already exists in Keycloak")
            return jsonify({
                "status": "exists",
                "message": f"User {username} already exists in Keycloak",
                "keycloak_user_id": existing_users[0]['id']
            }), 200

        # Generate temporary password
        temp_password = generate_temp_password()

        # Map role
        keycloak_role = map_fineract_role_to_keycloak(fineract_role)

        # Prepare user data for Keycloak
        user_data = {
            "username": username,
            "email": email,
            "firstName": first_name,
            "lastName": last_name,
            "enabled": True,
            "emailVerified": False,  # User must verify email
            "attributes": {
                "fineract_user_id": [fineract_user_id],
                "office_id": [office_id],
                "office_name": [office_name],
                "employee_id": [employee_id],
                "mobile_number": [mobile_number],
                "fineract_role": [fineract_role]
            },
            "credentials": [{
                "type": "password",
                "value": temp_password,
                "temporary": True  # Force password change on first login
            }],
            "requiredActions": [
                "UPDATE_PASSWORD",      # Must change password
                "VERIFY_EMAIL",         # Must verify email
                "webauthn-register"     # Must register device
            ]
        }

        # Create user in Keycloak
        user_id = admin.create_user(user_data)
        logger.info(f"Created user in Keycloak: {username} (ID: {user_id})")

        # Assign role
        try:
            realm_roles = admin.get_realm_roles()
            role_obj = next((r for r in realm_roles if r['name'] == keycloak_role), None)

            if role_obj:
                admin.assign_realm_roles(user_id, [role_obj])
                logger.info(f"Assigned role '{keycloak_role}' to user {username}")
            else:
                logger.warning(f"Role '{keycloak_role}' not found in Keycloak")
        except Exception as e:
            logger.error(f"Failed to assign role: {str(e)}")

        # Add to appropriate group (based on office)
        try:
            if keycloak_role == "admin":
                group_name = "head-office"
            elif keycloak_role == "branch-manager":
                group_name = "branch-managers"
            elif keycloak_role == "loan-officer":
                group_name = "loan-officers"
            elif keycloak_role == "teller":
                group_name = "tellers"
            elif keycloak_role == "client":
                group_name = "clients"
            else:
                group_name = None

            if group_name:
                groups = admin.get_groups({"search": group_name})
                if groups:
                    admin.group_user_add(user_id, groups[0]['id'])
                    logger.info(f"Added user {username} to group '{group_name}'")
        except Exception as e:
            logger.error(f"Failed to add to group: {str(e)}")

        # Return success with temporary password
        return jsonify({
            "status": "success",
            "message": f"User {username} synced to Keycloak successfully",
            "keycloak_user_id": user_id,
            "temporary_password": temp_password,
            "required_actions": user_data["requiredActions"]
        }), 201

    except KeycloakError as e:
        logger.error(f"Keycloak error: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Keycloak error: {str(e)}"
        }), 500
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Unexpected error: {str(e)}"
        }), 500


@app.route('/sync/bulk', methods=['POST'])
def bulk_sync():
    """
    Bulk sync multiple users from Fineract to Keycloak

    Expected payload:
    {
        "users": [
            { "userId": 1, "username": "user1", ... },
            { "userId": 2, "username": "user2", ... }
        ]
    }
    """
    try:
        data = request.get_json()
        users = data.get('users', [])

        if not users:
            return jsonify({
                "status": "error",
                "message": "No users provided"
            }), 400

        logger.info(f"Bulk sync initiated for {len(users)} users")

        results = {
            "total": len(users),
            "created": 0,
            "existed": 0,
            "failed": 0,
            "details": []
        }

        for user_data in users:
            try:
                # Call sync_user endpoint internally
                with app.test_client() as client:
                    response = client.post('/sync/user', json=user_data)
                    result = response.get_json()

                    if response.status_code == 201:
                        results["created"] += 1
                        results["details"].append({
                            "username": user_data.get('username'),
                            "status": "created",
                            "temp_password": result.get('temporary_password')
                        })
                    elif response.status_code == 200 and result.get('status') == 'exists':
                        results["existed"] += 1
                        results["details"].append({
                            "username": user_data.get('username'),
                            "status": "existed"
                        })
                    else:
                        results["failed"] += 1
                        results["details"].append({
                            "username": user_data.get('username'),
                            "status": "failed",
                            "error": result.get('message')
                        })
            except Exception as e:
                results["failed"] += 1
                results["details"].append({
                    "username": user_data.get('username'),
                    "status": "failed",
                    "error": str(e)
                })

        logger.info(f"Bulk sync completed: {results['created']} created, {results['existed']} existed, {results['failed']} failed")

        return jsonify(results), 200

    except Exception as e:
        logger.error(f"Bulk sync error: {str(e)}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/user/<username>', methods=['GET'])
def get_user(username):
    """Get user details from Keycloak"""
    try:
        admin = get_keycloak_admin()
        users = admin.get_users({"username": username})

        if not users:
            return jsonify({
                "status": "not_found",
                "message": f"User {username} not found"
            }), 404

        user = users[0]
        return jsonify({
            "status": "success",
            "user": {
                "id": user.get('id'),
                "username": user.get('username'),
                "email": user.get('email'),
                "firstName": user.get('firstName'),
                "lastName": user.get('lastName'),
                "enabled": user.get('enabled'),
                "emailVerified": user.get('emailVerified'),
                "attributes": user.get('attributes', {})
            }
        }), 200

    except Exception as e:
        logger.error(f"Error getting user: {str(e)}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/api/users/<username>/reset-password', methods=['POST'])
def reset_password(username):
    """
    Trigger password reset email for a user via Keycloak

    This sends a password reset email to the user with a time-limited link.
    The link expires after 24 hours.

    Admin only endpoint - requires proper authentication via Apache Gateway.
    """
    try:
        admin = get_keycloak_admin()

        # Find user by username
        users = admin.get_users({"username": username})
        if not users:
            logger.warning(f"Password reset failed: User {username} not found in Keycloak")
            return jsonify({
                "status": "error",
                "message": f"User {username} not found"
            }), 404

        user = users[0]
        user_id = user['id']
        user_email = user.get('email')

        # Check if user has email
        if not user_email:
            logger.warning(f"Password reset failed: User {username} has no email")
            return jsonify({
                "status": "error",
                "message": "User has no email address configured"
            }), 400

        # Send password reset email via Keycloak
        # This triggers the UPDATE_PASSWORD required action
        admin.send_update_account(
            user_id=user_id,
            payload=['UPDATE_PASSWORD'],  # Required action
            lifespan=86400  # Link valid for 24 hours (in seconds)
        )

        logger.info(f"Password reset email sent to {username} ({user_email})")

        return jsonify({
            "status": "success",
            "message": f"Password reset email sent to {user_email}",
            "username": username,
            "email": user_email
        }), 200

    except KeycloakError as e:
        logger.error(f"Keycloak error during password reset for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Keycloak error: {str(e)}"
        }), 500
    except Exception as e:
        logger.error(f"Unexpected error during password reset for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Unexpected error: {str(e)}"
        }), 500


@app.route('/api/users/<username>/status', methods=['PUT'])
def update_user_status(username):
    """
    Enable or disable a user in Keycloak

    Expected payload:
    {
        "enabled": true  // or false
    }

    When a user is disabled:
    - They cannot log in
    - Existing sessions are NOT automatically terminated (depends on Keycloak config)
    - User remains in the system

    Admin only endpoint - requires proper authentication via Apache Gateway.
    """
    try:
        data = request.get_json()

        if 'enabled' not in data:
            return jsonify({
                "status": "error",
                "message": "Missing 'enabled' field in request body"
            }), 400

        enabled = data['enabled']

        if not isinstance(enabled, bool):
            return jsonify({
                "status": "error",
                "message": "'enabled' must be a boolean value"
            }), 400

        admin = get_keycloak_admin()

        # Find user by username
        users = admin.get_users({"username": username})
        if not users:
            logger.warning(f"Status update failed: User {username} not found in Keycloak")
            return jsonify({
                "status": "error",
                "message": f"User {username} not found"
            }), 404

        user = users[0]
        user_id = user['id']

        # Update user enabled status
        admin.update_user(
            user_id=user_id,
            payload={
                'enabled': enabled
            }
        )

        action = "enabled" if enabled else "disabled"
        logger.info(f"User {username} (ID: {user_id}) {action} in Keycloak")

        return jsonify({
            "status": "success",
            "message": f"User {username} {action} successfully",
            "username": username,
            "enabled": enabled
        }), 200

    except KeycloakError as e:
        logger.error(f"Keycloak error during status update for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Keycloak error: {str(e)}"
        }), 500
    except Exception as e:
        logger.error(f"Unexpected error during status update for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Unexpected error: {str(e)}"
        }), 500


@app.route('/api/users/<username>/force-password-change', methods=['POST'])
def force_password_change(username):
    """
    Force user to change password on next login

    This adds the UPDATE_PASSWORD required action to the user.
    User will be prompted to change password on next login.

    Admin only endpoint - requires proper authentication via Apache Gateway.
    """
    try:
        admin = get_keycloak_admin()

        # Find user by username
        users = admin.get_users({"username": username})
        if not users:
            logger.warning(f"Force password change failed: User {username} not found in Keycloak")
            return jsonify({
                "status": "error",
                "message": f"User {username} not found"
            }), 404

        user = users[0]
        user_id = user['id']

        # Get current required actions
        current_actions = user.get('requiredActions', [])

        # Add UPDATE_PASSWORD if not already present
        if 'UPDATE_PASSWORD' not in current_actions:
            current_actions.append('UPDATE_PASSWORD')

            admin.update_user(
                user_id=user_id,
                payload={
                    'requiredActions': current_actions
                }
            )

            logger.info(f"User {username} will be required to change password on next login")

            return jsonify({
                "status": "success",
                "message": f"User {username} will be required to change password on next login",
                "username": username
            }), 200
        else:
            logger.info(f"User {username} already has UPDATE_PASSWORD required action")
            return jsonify({
                "status": "success",
                "message": f"User {username} already has password change required",
                "username": username
            }), 200

    except KeycloakError as e:
        logger.error(f"Keycloak error during force password change for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Keycloak error: {str(e)}"
        }), 500
    except Exception as e:
        logger.error(f"Unexpected error during force password change for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": f"Unexpected error: {str(e)}"
        }), 500


@app.route('/api/users/<username>/keycloak-status', methods=['GET'])
def get_keycloak_status(username):
    """
    Get user's Keycloak sync status and details

    Returns information about the user in Keycloak including:
    - Enabled status
    - Required actions
    - Email verification status
    - Roles and groups
    """
    try:
        admin = get_keycloak_admin()

        # Find user by username
        users = admin.get_users({"username": username})
        if not users:
            return jsonify({
                "status": "not_found",
                "message": f"User {username} not found in Keycloak"
            }), 404

        user = users[0]
        user_id = user['id']

        # Get user roles
        try:
            user_roles = admin.get_realm_roles_of_user(user_id)
            role_names = [role['name'] for role in user_roles]
        except:
            role_names = []

        # Get user groups
        try:
            user_groups = admin.get_user_groups(user_id)
            group_names = [group['name'] for group in user_groups]
        except:
            group_names = []

        return jsonify({
            "status": "success",
            "keycloak_user": {
                "id": user.get('id'),
                "username": user.get('username'),
                "email": user.get('email'),
                "firstName": user.get('firstName'),
                "lastName": user.get('lastName'),
                "enabled": user.get('enabled', False),
                "emailVerified": user.get('emailVerified', False),
                "requiredActions": user.get('requiredActions', []),
                "roles": role_names,
                "groups": group_names,
                "attributes": user.get('attributes', {})
            }
        }), 200

    except Exception as e:
        logger.error(f"Error getting Keycloak status for {username}: {str(e)}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


if __name__ == '__main__':
    # Validate environment variables
    if not ADMIN_CLI_SECRET:
        logger.error("ADMIN_CLI_SECRET environment variable not set")
        sys.exit(1)

    # Start Flask app
    port = int(os.getenv("PORT", 5000))
    logger.info(f"Starting Fineract-Keycloak User Sync Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
