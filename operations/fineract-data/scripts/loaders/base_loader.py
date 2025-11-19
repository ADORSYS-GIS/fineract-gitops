"""
Base Loader Class for Fineract Data
Provides common functionality for all entity loaders
"""
import os
import sys
import yaml
import requests
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class BaseLoader:
    """Base class for Fineract data loaders"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default', dry_run: bool = False):
        """
        Initialize loader

        Args:
            yaml_dir: Directory containing YAML files
            fineract_url: Fineract API base URL
            tenant: Tenant identifier
            dry_run: If True, preview changes without applying them
        """
        self.yaml_dir = Path(yaml_dir)
        self.fineract_url = fineract_url.rstrip('/')
        self.tenant = tenant
        self.dry_run = dry_run

        # ====================================================================
        # SENSITIVE DATA IN ENVIRONMENT VARIABLES
        # ====================================================================
        # CURRENT APPROACH: Read credentials from environment variables
        #
        # SECURITY TRADE-OFFS:
        # - Environment variables visible in process listing (ps aux)
        # - Can be scraped from /proc/<pid>/environ
        # - Logged in error messages if not careful
        # - Available to all code in the same process
        #
        # RATIONALE FOR CURRENT APPROACH:
        # - Standard pattern for 12-factor apps and containerized workloads
        # - Kubernetes native: Secrets injected as env vars
        # - Simple: No file I/O, no path management
        # - Portable: Works across different execution environments
        # - Job context: Short-lived jobs (run once, then terminate)
        # - RBAC protection: Only users with pod describe/exec can view
        #
        # MORE SECURE ALTERNATIVES:
        # 1. Mounted secret files (RECOMMENDED for production):
        #    volumes:
        #    - name: credentials
        #      secret:
        #        secretName: fineract-loader-credentials
        #    volumeMounts:
        #    - name: credentials
        #      mountPath: /secrets
        #      readOnly: true
        #    Code change:
        #      with open('/secrets/client_id') as f:
        #          self.client_id = f.read().strip()
        #    Pros:
        #    - Not visible in environment (kubectl describe)
        #    - File permissions can restrict access (chmod 0400)
        #    - Secrets never in process environment
        #    Cons:
        #    - Slightly more code complexity
        #    - Requires volume mount setup
        #    - File path management
        #
        # 2. Sealed Secrets (RECOMMENDED for production):
        #    Encrypt secrets with cluster public key before committing to Git
        #    Sealed Secrets controller unseals them in the cluster
        #    Example:
        #      apiVersion: bitnami.com/v1alpha1
        #      kind: SealedSecret
        #      metadata:
        #        name: fineract-loader-credentials
        #      spec:
        #        encryptedData:
        #          client_id: AgA... # encrypted
        #          client_secret: AgB... # encrypted
        #    Pros:
        #    - True GitOps (everything in Git, encrypted)
        #    - No external dependencies
        #    - Works across cloud providers
        #    Cons:
        #    - Manual rotation (reseal and commit)
        #    - Cluster coupling (sealed for specific cluster)
        #    - Network dependency during pod startup
        #    - More complex setup
        #
        # 3. Service Account Token Volume Projection:
        #    Use Kubernetes ServiceAccount tokens for authentication
        #    No secrets needed in environment or files
        #    Example:
        #      volumes:
        #      - name: token
        #        projected:
        #          sources:
        #          - serviceAccountToken:
        #              path: token
        #              expirationSeconds: 600
        #              audience: fineract-api
        #    Pros:
        #    - No secret management needed
        #    - Auto-rotating tokens
        #    - Kubernetes-native
        #    Cons:
        #    - Requires Fineract to support ServiceAccount token authentication
        #    - Not applicable for Basic Auth
        #
        # 4. HashiCorp Vault Agent Injector:
        #    Sidecar container injects secrets into pod
        #    Secrets written to shared volume at runtime
        #    Example:
        #      annotations:
        #        vault.hashicorp.com/agent-inject: "true"
        #        vault.hashicorp.com/role: "fineract-loader"
        #        vault.hashicorp.com/agent-inject-secret-credentials: "secret/fineract/loader"
        #    Pros:
        #    - Secrets never in env vars
        #    - Dynamic secret generation
        #    - Vault audit trail
        #    Cons:
        #    - Requires Vault infrastructure
        #    - Sidecar overhead
        #    - More complex
        #
        # INPUT VALIDATION:
        # The code does NOT validate credentials before use, which could lead to:
        # - Late failure (after data processing starts)
        # - Unclear error messages
        # - Retry storms on invalid credentials
        #
        # RECOMMENDED ADDITIONS (for production):
        # - Fail fast if required env vars are missing:
        #   if not self.client_id or not self.client_secret:
        #       raise ValueError("FINERACT_CLIENT_ID and FINERACT_CLIENT_SECRET required")
        # - Validate credential format (length, character set)
        # - Test authentication during __init__ (fail early)
        # - Never log credential values (even in debug mode)
        #
        # CURRENT APPROACH JUSTIFICATION:
        # - Acceptable for: Dev, staging, short-lived jobs
        # - Consider mounted files for: Production, long-running pods
        # - Consider ESO/Vault for: Multi-cluster, compliance requirements
        # - Risk mitigation: RBAC, network policies, short job lifetime
        #
        # Get authentication configuration from environment
        # Support both OAuth2 (preferred) and Basic Auth (legacy)
        self.client_id = os.getenv('FINERACT_CLIENT_ID')
        self.client_secret = os.getenv('FINERACT_CLIENT_SECRET')
        self.token_url = os.getenv('FINERACT_TOKEN_URL')

        # Fallback to Basic Auth if OAuth2 not configured
        self.username = os.getenv('FINERACT_USERNAME', 'mifos')
        self.password = os.getenv('FINERACT_PASSWORD', 'password')

        # OAuth2 token management
        self.access_token = None
        self.token_expiry = None

        # Create session with authentication
        self.session = requests.Session()

        # SSL Verification Configuration
        # Allow disabling SSL verification for development/testing environments with self-signed certificates
        verify_ssl = os.getenv('FINERACT_VERIFY_SSL', 'true').lower() in ('true', '1', 'yes')
        self.session.verify = verify_ssl

        if not verify_ssl:
            # Suppress InsecureRequestWarning when SSL verification is disabled
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
            logger.warning("SSL certificate verification is DISABLED - not recommended for production")

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
            logger.info("Using Basic Authentication (consider upgrading to OAuth2)")
            self.session.auth = (self.username, self.password)

        # Configure retry strategy for transient failures
        retry_strategy = Retry(
            total=3,  # Maximum number of retries
            backoff_factor=1,  # Wait 1s, 2s, 4s between retries
            status_forcelist=[429, 500, 502, 503, 504],  # Retry on these HTTP status codes
            allowed_methods=["GET", "POST", "PUT", "DELETE"]  # Retry all methods (idempotent operations)
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
        logger.info("HTTP retry strategy configured: 3 retries with exponential backoff")

        # Track loaded entities
        self.loaded_entities = {}
        self.failed_entities = []
        self.updated_entities = {}
        self.skipped_entities = {}

    def _obtain_oauth2_token(self):
        """
        Obtain OAuth2 access token using client credentials flow
        """
        import time
        try:
            response = requests.post(
                self.token_url,
                data={
                    'grant_type': 'client_credentials',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret
                },
                headers={'Content-Type': 'application/x-www-form-urlencoded'}
            )
            response.raise_for_status()

            token_data = response.json()
            self.access_token = token_data['access_token']
            expires_in = token_data.get('expires_in', 300)  # Default 5 minutes if not specified
            self.token_expiry = time.time() + expires_in - 30  # Refresh 30 seconds before expiry

            # Set Bearer token in session headers
            self.session.headers.update({
                'Authorization': f'Bearer {self.access_token}'
            })

            logger.info("Successfully obtained OAuth2 access token")
        except Exception as e:
            logger.error(f"Failed to obtain OAuth2 token: {e}")
            raise

    def _ensure_valid_token(self):
        """
        Ensure OAuth2 token is valid, refresh if necessary
        """
        import time
        if self.access_token and self.token_expiry:
            if time.time() >= self.token_expiry:
                logger.info("OAuth2 token expired, refreshing...")
                self._obtain_oauth2_token()

    def load_yaml(self, filepath: Path) -> Optional[Dict[str, Any]]:
        """
        Load and parse YAML file

        Args:
            filepath: Path to YAML file

        Returns:
            Parsed YAML data or None if error

        ====================================================================
        LACK OF INPUT VALIDATION
        ====================================================================
        CURRENT APPROACH: Load YAML with yaml.safe_load() only

        SECURITY/QUALITY ISSUES:
        - No schema validation (any YAML structure accepted)
        - No type checking (fields can be wrong type)
        - No required field validation (missing fields caught late)
        - No value range/format validation
        - Errors surface during API calls, not during loading
        - Unclear error messages for users

        IMPACT:
        - Late failure (after processing starts)
        - Poor user experience (cryptic API errors)
        - Potential data corruption from malformed input
        - Debugging difficulty
        - No protection against typos in YAML files

        MORE ROBUST ALTERNATIVES:

        1. Pydantic Models (RECOMMENDED):
           from pydantic import BaseModel, Field, validator

           class ClientData(BaseModel):
               firstname: str = Field(..., min_length=1, max_length=50)
               lastname: str = Field(..., min_length=1, max_length=50)
               externalId: str
               officeId: Optional[int]
               activationDate: str  # Format validated by custom validator

               @validator('activationDate')
               def validate_date(cls, v):
                   from datetime import datetime
                   try:
                       datetime.strptime(v, '%Y-%m-%d')
                       return v
                   except ValueError:
                       raise ValueError('Date must be in YYYY-MM-DD format')

           Usage:
               data = yaml.safe_load(f)
               validated = ClientData(**data)  # Raises ValidationError if invalid

           Pros:
           - Type safety
           - Clear validation errors with field names
           - Runtime and IDE autocomplete
           - Fail fast (errors during load, not during API call)
           - Self-documenting schemas
           Cons:
           - Additional dependency (pydantic)
           - Schema maintenance overhead
           - Learning curve

        2. JSON Schema Validation:
           import jsonschema

           client_schema = {
               "type": "object",
               "required": ["firstname", "lastname", "officeId"],
               "properties": {
                   "firstname": {"type": "string", "minLength": 1},
                   "lastname": {"type": "string", "minLength": 1},
                   "officeId": {"type": "integer", "minimum": 1},
                   "activationDate": {
                       "type": "string",
                       "pattern": "^\\d{4}-\\d{2}-\\d{2}$"
                   }
               }
           }

           Usage:
               data = yaml.safe_load(f)
               jsonschema.validate(data, client_schema)  # Raises ValidationError

           Pros:
           - Industry standard (JSON Schema spec)
           - Language-agnostic (can reuse schemas)
           - Rich validation primitives (pattern, range, etc.)
           - Clear error messages
           Cons:
           - Verbose schema definitions
           - Separate schema files to maintain
           - Less Pythonic than Pydantic

        3. Cerberus Validation:
           from cerberus import Validator

           client_schema = {
               'firstname': {'type': 'string', 'required': True, 'minlength': 1},
               'lastname': {'type': 'string', 'required': True, 'minlength': 1},
               'officeId': {'type': 'integer', 'required': True, 'min': 1},
               'activationDate': {'type': 'string', 'regex': '\\d{4}-\\d{2}-\\d{2}'}
           }

           Usage:
               data = yaml.safe_load(f)
               v = Validator(client_schema)
               if not v.validate(data):
                   raise ValueError(v.errors)

           Pros:
           - Lightweight
           - Easy to learn
           - Good error messages
           Cons:
           - Less feature-rich than Pydantic
           - Smaller community

        4. Manual Validation (Minimal improvement):
           def validate_client_data(data: dict):
               required_fields = ['firstname', 'lastname', 'officeId']
               for field in required_fields:
                   if field not in data:
                       raise ValueError(f"Missing required field: {field}")

               if not isinstance(data['officeId'], int):
                   raise ValueError("officeId must be an integer")

           Pros:
           - No dependencies
           - Simple for basic validation
           Cons:
           - Boilerplate code
           - Hard to maintain as schemas grow
           - Lacks advanced validation (patterns, ranges)

        RECOMMENDED APPROACH:
        For production use, implement Pydantic models:
        1. Create schema classes for each entity type
        2. Validate data immediately after YAML load
        3. Provide clear error messages to users
        4. Fail fast before API calls

        Example implementation:
            try:
                with open(filepath, 'r') as f:
                    raw_data = yaml.safe_load(f)

                # Validate based on entity type (determined by subclass)
                validated_data = self.schema_class(**raw_data)
                return validated_data.dict()

            except pydantic.ValidationError as e:
                logger.error(f"Validation failed for {filepath}:")
                for error in e.errors():
                    logger.error(f"  - {error['loc'][0]}: {error['msg']}")
                return None

        CURRENT APPROACH JUSTIFICATION:
        - Acceptable for: Dev/testing with known-good data
        - Not recommended for: Production, user-facing tools
        - Risk: Late failures, poor UX, debugging difficulty
        - Mitigation: Document expected YAML structure, example files
        """
        try:
            with open(filepath, 'r') as f:
                data = yaml.safe_load(f)
            return data
        except Exception as e:
            logger.error(f"Failed to load YAML file {filepath}: {e}")
            return None

    def get(self, endpoint: str) -> Optional[Dict[str, Any]]:
        """
        GET request to Fineract API

        Args:
            endpoint: API endpoint (without base URL)

        Returns:
            Response JSON or None if error
        """
        # Ensure OAuth2 token is valid if using OAuth2
        if self.access_token:
            self._ensure_valid_token()

        url = f"{self.fineract_url}/{endpoint.lstrip('/')}"
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            logger.error(f"HTTP Error on GET {endpoint}: {e}")
            logger.error(f"Response: {e.response.text if e.response else 'No response'}")
            return None
        except Exception as e:
            logger.error(f"Error on GET {endpoint}: {e}")
            return None

    def post(self, endpoint: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        POST request to Fineract API

        Args:
            endpoint: API endpoint
            data: Request payload

        Returns:
            Response JSON or None if error
        """
        # Dry-run mode: Log the action without executing
        if self.dry_run:
            logger.info(f"[DRY-RUN] Would POST to {endpoint}")
            logger.debug(f"[DRY-RUN] Payload: {data}")
            return {"dryRun": True, "resourceId": 0}

        # Ensure OAuth2 token is valid if using OAuth2
        if self.access_token:
            self._ensure_valid_token()

        url = f"{self.fineract_url}/{endpoint.lstrip('/')}"
        try:
            response = self.session.post(url, json=data)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            logger.error(f"HTTP Error on POST {endpoint}: {e}")
            logger.error(f"Request data: {data}")
            logger.error(f"Response: {e.response.text if e.response else 'No response'}")
            return None
        except Exception as e:
            logger.error(f"Error on POST {endpoint}: {e}")
            return None

    def put(self, endpoint: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        PUT request to Fineract API

        Args:
            endpoint: API endpoint
            data: Request payload

        Returns:
            Response JSON or None if error
        """
        # Dry-run mode: Log the action without executing
        if self.dry_run:
            logger.info(f"[DRY-RUN] Would PUT to {endpoint}")
            logger.debug(f"[DRY-RUN] Payload: {data}")
            return {"dryRun": True, "changes": {}}

        # Ensure OAuth2 token is valid if using OAuth2
        if self.access_token:
            self._ensure_valid_token()

        url = f"{self.fineract_url}/{endpoint.lstrip('/')}"
        try:
            response = self.session.put(url, json=data)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            logger.error(f"HTTP Error on PUT {endpoint}: {e}")
            logger.error(f"Response: {e.response.text if e.response else 'No response'}")
            return None
        except Exception as e:
            logger.error(f"Error on PUT {endpoint}: {e}")
            return None

    def get_entity_by_id(self, endpoint: str, entity_id: int) -> Optional[Dict[str, Any]]:
        """
        Get entity details by ID

        Args:
            endpoint: API endpoint
            entity_id: Entity ID

        Returns:
            Entity data or None if not found
        """
        try:
            url = f"{endpoint}/{entity_id}"
            response = self.get(url)
            return response
        except Exception as e:
            logger.warning(f"Error fetching entity {entity_id}: {e}")
            return None

    def has_changes(self, endpoint: str, entity_id: int, new_data: Dict[str, Any],
                    compare_fields: Optional[list] = None) -> bool:
        """
        Check if YAML data differs from existing Fineract entity

        Args:
            endpoint: API endpoint
            entity_id: Existing entity ID
            new_data: New data from YAML
            compare_fields: List of fields to compare (None = compare all)

        Returns:
            True if changes detected, False otherwise
        """
        try:
            # Get current entity from Fineract
            current_entity = self.get_entity_by_id(endpoint, entity_id)
            if not current_entity:
                logger.warning(f"Could not fetch entity {entity_id} for comparison")
                return False

            # If no specific fields provided, compare all fields in new_data
            fields_to_compare = compare_fields or list(new_data.keys())

            # Compare fields
            for field in fields_to_compare:
                # Skip metadata fields
                if field in ['dateFormat', 'locale', 'id', 'resourceId']:
                    continue

                new_value = new_data.get(field)
                current_value = current_entity.get(field)

                # Handle different types
                if isinstance(new_value, (int, float)):
                    # Numeric comparison with tolerance
                    if abs(float(new_value or 0) - float(current_value or 0)) > 0.0001:
                        logger.debug(f"Change detected in field '{field}': {current_value} → {new_value}")
                        return True
                elif isinstance(new_value, bool):
                    if bool(new_value) != bool(current_value):
                        logger.debug(f"Change detected in field '{field}': {current_value} → {new_value}")
                        return True
                else:
                    # String comparison
                    if str(new_value or '').strip() != str(current_value or '').strip():
                        logger.debug(f"Change detected in field '{field}': {current_value} → {new_value}")
                        return True

            return False
        except Exception as e:
            logger.error(f"Error comparing entities: {e}")
            return False

    def should_update(self, entity_type: str, immutable_fields: Optional[list] = None) -> bool:
        """
        Check if update operation should proceed
        Override in subclasses for entity-specific logic

        Args:
            entity_type: Type of entity being updated
            immutable_fields: List of fields that cannot be updated

        Returns:
            True if update is allowed, False otherwise
        """
        # Can be overridden by subclasses for custom validation
        return True

    def _resolve_staff(self, staff_ref: str) -> Optional[int]:
        """
        Resolve staff display name or external ID to staff ID

        Args:
            staff_ref: Staff display name or external ID

        Returns:
            Staff ID or None if not found
        """
        if not staff_ref:
            return None

        # Ensure cache is initialized
        if not hasattr(self, '_reference_cache') or 'staff' not in self._reference_cache:
            try:
                staff_list = self.get('/staff')
                if staff_list:
                    self._reference_cache['staff'] = {
                        s.get('displayName'): s.get('id') for s in staff_list if s.get('displayName')
                    }
                    self._reference_cache['staff_by_external_id'] = {
                        s.get('externalId'): s.get('id') for s in staff_list if s.get('externalId')
                    }
                    logger.info(f"  Cached {len(self._reference_cache['staff'])} staff members")
            except Exception as e:
                logger.warning(f"Error caching staff data: {e}")
                self._reference_cache['staff'] = {}
                self._reference_cache['staff_by_external_id'] = {}

        # Try by display name
        staff_id = self._reference_cache.get('staff', {}).get(staff_ref)
        if staff_id:
            logger.debug(f"Resolved staff '{staff_ref}' to ID {staff_id}")
            return staff_id

        # Try by external ID
        staff_id = self._reference_cache.get('staff_by_external_id', {}).get(staff_ref)
        if staff_id:
            logger.debug(f"Resolved staff external ID '{staff_ref}' to ID {staff_id}")
            return staff_id

        logger.error(f"Could not resolve staff '{staff_ref}'")
        return None

    def entity_exists(self, endpoint: str, identifier: str, identifier_field: str = 'name') -> Optional[int]:
        """
        Check if entity exists by a specific field (e.g., name, externalId)

        Args:
            endpoint: API endpoint to search
            identifier: Value of the identifier field
            identifier_field: The field to search for the identifier (e.g., 'name', 'externalId')

        Returns:
            Entity ID if found, None otherwise
        """
        try:
            # Construct the query parameter based on the identifier field
            query_params = {identifier_field: identifier}
            
            # Some endpoints use different query param names
            if 'externalId' in identifier_field.lower():
                query_params = {'externalId': identifier}


            entities = self.get(f"{endpoint}?{'&'.join([f'{k}={v}' for k, v in query_params.items()])}")

            if not entities:
                return None

            # Handle different response formats
            if isinstance(entities, list) and entities:
                return entities[0].get('id')
            elif isinstance(entities, dict):
                if 'pageItems' in entities and entities['pageItems']:
                    return entities['pageItems'][0].get('id')
                elif 'id' in entities:
                    return entities.get('id')

            return None
        except Exception as e:
            logger.error(f"Error checking entity existence for '{identifier}' in '{endpoint}': {e}")
            return None


    def yaml_to_fineract_api(self, yaml_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert YAML structure to Fineract API payload
        Override in subclasses for entity-specific mapping

        Args:
            yaml_data: YAML data structure

        Returns:
            Fineract API payload
        """
        raise NotImplementedError("Subclasses must implement yaml_to_fineract_api")

    def load_all(self) -> Dict[str, Any]:
        """
        Load all YAML files in directory
        Override in subclasses for entity-specific logic

        Returns:
            Summary of loaded entities
        """
        raise NotImplementedError("Subclasses must implement load_all")

    def get_summary(self) -> Dict[str, Any]:
        """
        Get summary of loading operation

        Returns:
            Summary dict with counts and failures
        """
        total_operations = (
            len(self.loaded_entities) +
            len(self.updated_entities) +
            len(self.skipped_entities) +
            len(self.failed_entities)
        )

        return {
            'total_loaded': len(self.loaded_entities),
            'total_updated': len(self.updated_entities),
            'total_skipped': len(self.skipped_entities),
            'total_failed': len(self.failed_entities),
            'loaded_entities': list(self.loaded_entities.keys()),
            'updated_entities': list(self.updated_entities.keys()),
            'skipped_entities': list(self.skipped_entities.keys()),
            'failed_entities': self.failed_entities,
            'success_rate': (
                (len(self.loaded_entities) + len(self.updated_entities)) / total_operations * 100
                if total_operations > 0
                else 0
            )
        }

    def print_summary(self):
        """Print loading summary"""
        summary = self.get_summary()

        logger.info("=" * 80)
        logger.info("LOADING SUMMARY")
        logger.info("=" * 80)
        logger.info(f"Total Created: {summary['total_loaded']}")
        logger.info(f"Total Updated: {summary['total_updated']}")
        logger.info(f"Total Skipped: {summary['total_skipped']}")
        logger.info(f"Total Failed: {summary['total_failed']}")
        logger.info(f"Success Rate: {summary['success_rate']:.1f}%")

        if summary['loaded_entities']:
            logger.info(f"\nCreated Entities:")
            for entity in summary['loaded_entities']:
                logger.info(f"  ✓ {entity}")

        if summary['updated_entities']:
            logger.info(f"\nUpdated Entities:")
            for entity in summary['updated_entities']:
                logger.info(f"  ↻ {entity}")

        if summary['skipped_entities']:
            logger.info(f"\nSkipped Entities (No Changes):")
            for entity in summary['skipped_entities']:
                logger.info(f"  ⊘ {entity}")

        if summary['failed_entities']:
            logger.info(f"\nFailed Entities:")
            for entity in summary['failed_entities']:
                logger.info(f"  ✗ {entity}")

        logger.info("=" * 80)

    # ========== REFERENCE RESOLUTION HELPERS ==========
    # Added for resolving entity references (names/codes to IDs)

    def _cache_reference_data(self):
        """Pre-load and cache all reference data for fast lookups"""
        if not hasattr(self, '_reference_cache'):
            self._reference_cache = {}
            logger.info("Initializing reference data cache...")

            try:
                # Cache GL Accounts
                gl_accounts = self.get('/glaccounts')
                if gl_accounts:
                    self._reference_cache['gl_accounts'] = {
                        acc.get('glCode'): acc.get('id') for acc in gl_accounts if acc.get('glCode')
                    }
                    self._reference_cache['gl_accounts_by_name'] = {
                        acc.get('name'): acc.get('id') for acc in gl_accounts if acc.get('name')
                    }
                    logger.info(f"  Cached {len(self._reference_cache['gl_accounts'])} GL accounts")

                # Cache Offices
                offices = self.get('/offices')
                if offices:
                    self._reference_cache['offices'] = {
                        off.get('name'): off.get('id') for off in offices if off.get('name')
                    }
                    self._reference_cache['offices_by_external_id'] = {
                        off.get('externalId'): off.get('id') for off in offices if off.get('externalId')
                    }
                    logger.info(f"  Cached {len(self._reference_cache['offices'])} offices")

                # Cache Savings Products
                savings_products = self.get('/savingsproducts')
                if savings_products:
                    self._reference_cache['savings_products'] = {
                        prod.get('name'): prod.get('id') for prod in savings_products if prod.get('name')
                    }
                    self._reference_cache['savings_products_by_short_name'] = {
                        prod.get('shortName'): prod.get('id') for prod in savings_products if prod.get('shortName')
                    }
                    logger.info(f"  Cached {len(self._reference_cache['savings_products'])} savings products")

                # Cache Loan Products
                loan_products = self.get('/loanproducts')
                if loan_products:
                    self._reference_cache['loan_products'] = {
                        prod.get('name'): prod.get('id') for prod in loan_products if prod.get('name')
                    }
                    self._reference_cache['loan_products_by_short_name'] = {
                        prod.get('shortName'): prod.get('id') for prod in loan_products if prod.get('shortName')
                    }
                    logger.info(f"  Cached {len(self._reference_cache['loan_products'])} loan products")

                # Cache Financial Activities
                # Fineract has predefined financial activities - we map common ones
                self._reference_cache['financial_activities'] = {
                    'Asset Transfer': 100,
                    'Liability Transfer': 200,
                    'Cash at Mainvault': 101,
                    'Cash at Teller': 102,
                    'Opening Balances Contra': 300,
                    'Fund Source': 103
                }
                logger.info(f"  Cached {len(self._reference_cache['financial_activities'])} financial activities")

                logger.info("Reference data cache initialized successfully")

            except Exception as e:
                logger.warning(f"Error caching reference data: {e}")
                self._reference_cache = {}

    def _resolve_gl_account(self, gl_code_or_name: str) -> Optional[int]:
        """
        Resolve GL account code or name to GL account ID

        Args:
            gl_code_or_name: GL code (e.g., '42') or GL account name

        Returns:
            GL account ID or None if not found
        """
        if not gl_code_or_name:
            return None

        # Ensure cache is initialized
        if not hasattr(self, '_reference_cache'):
            self._cache_reference_data()

        # Try by GL code first
        gl_id = self._reference_cache.get('gl_accounts', {}).get(str(gl_code_or_name))
        if gl_id:
            logger.debug(f"Resolved GL code '{gl_code_or_name}' to ID {gl_id}")
            return gl_id

        # Try by name
        gl_id = self._reference_cache.get('gl_accounts_by_name', {}).get(gl_code_or_name)
        if gl_id:
            logger.debug(f"Resolved GL name '{gl_code_or_name}' to ID {gl_id}")
            return gl_id

        # Fallback: try live lookup
        logger.warning(f"GL account '{gl_code_or_name}' not in cache, attempting live lookup")
        try:
            gl_accounts = self.get('/glaccounts')
            if gl_accounts:
                for acc in gl_accounts:
                    if acc.get('glCode') == str(gl_code_or_name) or acc.get('name') == gl_code_or_name:
                        logger.info(f"Found GL account '{gl_code_or_name}' with ID {acc.get('id')}")
                        return acc.get('id')
        except Exception as e:
            logger.error(f"Error looking up GL account '{gl_code_or_name}': {e}")

        logger.error(f"Could not resolve GL account '{gl_code_or_name}'")
        return None

    def _resolve_office(self, office_ref: str) -> Optional[int]:
        """
        Resolve office name or external ID to office ID

        Args:
            office_ref: Office name or external ID

        Returns:
            Office ID or None if not found
        """
        if not office_ref:
            return None

        # Ensure cache is initialized
        if not hasattr(self, '_reference_cache'):
            self._cache_reference_data()

        # Try by name
        office_id = self._reference_cache.get('offices', {}).get(office_ref)
        if office_id:
            logger.debug(f"Resolved office '{office_ref}' to ID {office_id}")
            return office_id

        # Try by external ID
        office_id = self._reference_cache.get('offices_by_external_id', {}).get(office_ref)
        if office_id:
            logger.debug(f"Resolved office external ID '{office_ref}' to ID {office_id}")
            return office_id

        # Fallback: try live lookup
        logger.warning(f"Office '{office_ref}' not in cache, attempting live lookup")
        try:
            offices = self.get('/offices')
            if offices:
                for office in offices:
                    if office.get('name') == office_ref or office.get('externalId') == office_ref:
                        logger.info(f"Found office '{office_ref}' with ID {office.get('id')}")
                        return office.get('id')
        except Exception as e:
            logger.error(f"Error looking up office '{office_ref}': {e}")

        logger.error(f"Could not resolve office '{office_ref}' - office must exist before loading data")
        raise ValueError(
            f"Office '{office_ref}' not found. "
            f"Please create the office first or check the office name/externalId. "
            f"Available offices can be listed with: GET /offices"
        )

    def _resolve_product(self, product_name_or_short_name: str, product_type: str = 'savings') -> Optional[int]:
        """
        Resolve product name or short name to product ID

        Args:
            product_name_or_short_name: Product name or short name
            product_type: 'savings' or 'loan'

        Returns:
            Product ID or None if not found
        """
        if not product_name_or_short_name:
            return None

        # Ensure cache is initialized
        if not hasattr(self, '_reference_cache'):
            self._cache_reference_data()

        # Select appropriate cache based on product type
        if product_type == 'savings':
            name_cache = self._reference_cache.get('savings_products', {})
            short_name_cache = self._reference_cache.get('savings_products_by_short_name', {})
            endpoint = '/savingsproducts'
        else:
            name_cache = self._reference_cache.get('loan_products', {})
            short_name_cache = self._reference_cache.get('loan_products_by_short_name', {})
            endpoint = '/loanproducts'

        # Try by name
        product_id = name_cache.get(product_name_or_short_name)
        if product_id:
            logger.debug(f"Resolved {product_type} product '{product_name_or_short_name}' to ID {product_id}")
            return product_id

        # Try by short name
        product_id = short_name_cache.get(product_name_or_short_name)
        if product_id:
            logger.debug(f"Resolved {product_type} product short name '{product_name_or_short_name}' to ID {product_id}")
            return product_id

        # Fallback: try live lookup
        logger.warning(f"{product_type.capitalize()} product '{product_name_or_short_name}' not in cache, attempting live lookup")
        try:
            products = self.get(endpoint)
            if products:
                for product in products:
                    if product.get('name') == product_name_or_short_name or product.get('shortName') == product_name_or_short_name:
                        logger.info(f"Found {product_type} product '{product_name_or_short_name}' with ID {product.get('id')}")
                        return product.get('id')
        except Exception as e:
            logger.error(f"Error looking up {product_type} product '{product_name_or_short_name}': {e}")

        logger.error(f"Could not resolve {product_type} product '{product_name_or_short_name}'")
        return None

    def _resolve_financial_activity(self, activity_name: str) -> Optional[int]:
        """
        Resolve financial activity name to activity ID

        Args:
            activity_name: Financial activity name

        Returns:
            Financial activity ID or None if not found
        """
        if not activity_name:
            return None

        # Ensure cache is initialized
        if not hasattr(self, '_reference_cache'):
            self._cache_reference_data()

        # Try to find in predefined mappings
        activity_id = self._reference_cache.get('financial_activities', {}).get(activity_name)
        if activity_id:
            logger.debug(f"Resolved financial activity '{activity_name}' to ID {activity_id}")
            return activity_id

        # Fallback: try to fetch from API (if Fineract exposes this endpoint)
        logger.warning(f"Financial activity '{activity_name}' not found in predefined mappings")
        logger.warning(f"Available activities: {list(self._reference_cache.get('financial_activities', {}).keys())}")
        return None

    def _format_date(self, date_str: str, output_format: str = None) -> str:
        """
        Format date string to Fineract-expected format

        Args:
            date_str: Date in YYYY-MM-DD format
            output_format: Optional custom output format

        Returns:
            Formatted date string
        """
        from datetime import datetime

        if not date_str:
            return date_str

        try:
            # Parse YYYY-MM-DD format
            dt = datetime.strptime(date_str, '%Y-%m-%d')

            # Default Fineract format is 'dd MMMM yyyy'
            if output_format:
                return dt.strftime(output_format)
            else:
                # Convert to dd MMMM yyyy (e.g., "15 January 2024")
                return dt.strftime('%d %B %Y')
        except Exception as e:
            logger.warning(f"Error formatting date '{date_str}': {e}")
            return date_str
