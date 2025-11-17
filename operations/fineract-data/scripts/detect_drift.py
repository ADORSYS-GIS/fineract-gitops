#!/usr/bin/env python3
"""
Fineract Configuration Drift Detection

This script compares YAML configuration files from Git (source of truth)
against live Fineract API data to detect configuration drift.

Drift occurs when manual changes are made to Fineract configuration
outside of the GitOps workflow (e.g., via Fineract UI or direct database changes).

Features:
- OAuth2 authentication (Keycloak) with token refresh
- Fallback to Basic Authentication
- Alert via Slack webhook
- Alert via Email (SMTP)
- Comprehensive drift reporting
- Exit code 1 if drift detected (for monitoring/alerting)

Usage:
    python3 detect_drift.py [--yaml-dir DIR] [--fineract-url URL] [--tenant TENANT] [--dry-run]

Environment Variables:
    Authentication:
        FINERACT_CLIENT_ID - OAuth2 client ID
        FINERACT_CLIENT_SECRET - OAuth2 client secret
        FINERACT_TOKEN_URL - OAuth2 token endpoint
        FINERACT_USERNAME - Basic auth username (fallback)
        FINERACT_PASSWORD - Basic auth password (fallback)

    Alerting - Slack:
        SLACK_WEBHOOK_URL - Slack incoming webhook URL

    Alerting - Email:
        SMTP_HOST - SMTP server hostname
        SMTP_PORT - SMTP server port (default: 587)
        SMTP_USERNAME - SMTP authentication username
        SMTP_PASSWORD - SMTP authentication password
        SMTP_USE_TLS - Use TLS encryption (default: true)
        ALERT_EMAIL_FROM - From email address
        ALERT_EMAIL_TO - To email address (comma-separated for multiple)
        ALERT_EMAIL_SUBJECT - Email subject (optional, uses default)
"""

import os
import sys
import json
import yaml
import argparse
import logging
import requests
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class FineractDriftDetector:
    """Detects configuration drift between Git YAML and live Fineract API"""

    def __init__(self, yaml_dir: str, fineract_url: str, tenant: str = 'default'):
        self.yaml_dir = Path(yaml_dir)
        self.fineract_url = fineract_url.rstrip('/')
        self.tenant = tenant

        # OAuth2 authentication
        self.client_id = os.getenv('FINERACT_CLIENT_ID')
        self.client_secret = os.getenv('FINERACT_CLIENT_SECRET')
        self.token_url = os.getenv('FINERACT_TOKEN_URL')

        # Basic auth fallback
        self.username = os.getenv('FINERACT_USERNAME', 'mifos')
        self.password = os.getenv('FINERACT_PASSWORD', 'password')

        # Alert configuration
        self.slack_webhook = os.getenv('SLACK_WEBHOOK_URL')
        self.smtp_host = os.getenv('SMTP_HOST')
        self.smtp_port = int(os.getenv('SMTP_PORT', '587'))
        self.smtp_username = os.getenv('SMTP_USERNAME')
        self.smtp_password = os.getenv('SMTP_PASSWORD')
        self.smtp_use_tls = os.getenv('SMTP_USE_TLS', 'true').lower() == 'true'
        self.email_from = os.getenv('ALERT_EMAIL_FROM')
        self.email_to = os.getenv('ALERT_EMAIL_TO')
        self.email_subject = os.getenv('ALERT_EMAIL_SUBJECT', 'Fineract Configuration Drift Detected')

        # OAuth2 token management
        self.access_token = None
        self.token_expiry = None

        # Session for HTTP requests
        self.session = requests.Session()
        self.session.headers.update({
            'Fineract-Platform-TenantId': tenant,
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })

    def _obtain_oauth2_token(self) -> Optional[str]:
        """Obtain OAuth2 access token from Keycloak"""
        if not all([self.client_id, self.client_secret, self.token_url]):
            logger.debug("OAuth2 credentials not configured, will use basic auth")
            return None

        try:
            response = requests.post(
                self.token_url,
                data={
                    'grant_type': 'client_credentials',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret
                },
                timeout=10
            )
            response.raise_for_status()

            token_data = response.json()
            self.access_token = token_data['access_token']
            expires_in = token_data.get('expires_in', 300)
            self.token_expiry = datetime.now() + timedelta(seconds=expires_in - 30)

            logger.info("OAuth2 token obtained successfully")
            return self.access_token

        except Exception as e:
            logger.warning(f"Failed to obtain OAuth2 token: {e}")
            return None

    def _get_auth_header(self) -> Dict[str, str]:
        """Get authentication header (OAuth2 or Basic)"""
        # Try OAuth2 first
        if self.client_id and self.client_secret and self.token_url:
            if not self.access_token or (self.token_expiry and datetime.now() >= self.token_expiry):
                self._obtain_oauth2_token()

            if self.access_token:
                return {'Authorization': f'Bearer {self.access_token}'}

        # Fallback to Basic auth
        from base64 import b64encode
        credentials = b64encode(f"{self.username}:{self.password}".encode()).decode()
        return {'Authorization': f'Basic {credentials}'}

    def get(self, endpoint: str) -> Optional[Dict]:
        """Make authenticated GET request to Fineract API"""
        url = f"{self.fineract_url}/{endpoint.lstrip('/')}"
        headers = self._get_auth_header()
        self.session.headers.update(headers)

        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Failed to GET {endpoint}: {e}")
            return None

    def load_yaml_entities(self, entity_type: str) -> List[Dict]:
        """Load YAML entities of a specific type from Git"""
        entities = []

        # Search for YAML files in subdirectories matching entity type
        search_patterns = [
            f"**/{entity_type}/*.yaml",
            f"**/{entity_type}/*.yml",
            f"**/base/{entity_type}/*.yaml",
            f"**/dev/{entity_type}/*.yaml"
        ]

        for pattern in search_patterns:
            for yaml_file in self.yaml_dir.glob(pattern):
                if yaml_file.name == 'kustomization.yaml':
                    continue

                try:
                    with open(yaml_file, 'r') as f:
                        data = yaml.safe_load(f)
                        if data:
                            data['_source_file'] = str(yaml_file.relative_to(self.yaml_dir))
                            entities.append(data)
                except Exception as e:
                    logger.warning(f"Failed to load {yaml_file}: {e}")

        return entities

    def compare_loan_products(self) -> List[Dict]:
        """Compare loan products between YAML and Fineract API"""
        logger.info("Comparing loan products...")

        # Load from Git
        yaml_products = self.load_yaml_entities('loan-products')

        # Load from Fineract API
        api_response = self.get('loanproducts')
        if not api_response:
            logger.error("Failed to fetch loan products from API")
            return []

        api_products = {p['name']: p for p in api_response}
        drift_findings = []

        for yaml_product in yaml_products:
            product_name = yaml_product.get('spec', {}).get('name') or yaml_product.get('metadata', {}).get('name')

            if not product_name:
                logger.warning(f"Skipping product with missing name in {yaml_product.get('_source_file')}")
                continue

            if product_name not in api_products:
                drift_findings.append({
                    'type': 'loan_product',
                    'name': product_name,
                    'drift_type': 'missing_in_api',
                    'message': f"Loan product '{product_name}' exists in Git but not in Fineract API",
                    'source_file': yaml_product.get('_source_file')
                })
            else:
                # Compare key fields
                api_product = api_products[product_name]
                spec = yaml_product.get('spec', {})

                # Compare currency
                if spec.get('currency') and spec['currency'] != api_product.get('currencyCode'):
                    drift_findings.append({
                        'type': 'loan_product',
                        'name': product_name,
                        'drift_type': 'field_mismatch',
                        'field': 'currency',
                        'yaml_value': spec.get('currency'),
                        'api_value': api_product.get('currencyCode'),
                        'source_file': yaml_product.get('_source_file')
                    })

                # Compare interest rate
                if spec.get('interestRate', {}).get('default'):
                    yaml_rate = float(spec['interestRate']['default'])
                    api_rate = float(api_product.get('interestRatePerPeriod', 0))
                    if abs(yaml_rate - api_rate) > 0.01:  # Allow 0.01% difference
                        drift_findings.append({
                            'type': 'loan_product',
                            'name': product_name,
                            'drift_type': 'field_mismatch',
                            'field': 'interestRate',
                            'yaml_value': yaml_rate,
                            'api_value': api_rate,
                            'source_file': yaml_product.get('_source_file')
                        })

        # Check for products in API but not in Git
        yaml_product_names = {
            p.get('spec', {}).get('name') or p.get('metadata', {}).get('name')
            for p in yaml_products if p.get('spec', {}).get('name') or p.get('metadata', {}).get('name')
        }

        for api_product_name in api_products.keys():
            if api_product_name not in yaml_product_names:
                drift_findings.append({
                    'type': 'loan_product',
                    'name': api_product_name,
                    'drift_type': 'extra_in_api',
                    'message': f"Loan product '{api_product_name}' exists in Fineract API but not in Git"
                })

        return drift_findings

    def compare_offices(self) -> List[Dict]:
        """Compare offices between YAML and Fineract API"""
        logger.info("Comparing offices...")

        yaml_offices = self.load_yaml_entities('offices')
        api_response = self.get('offices')

        if not api_response:
            logger.error("Failed to fetch offices from API")
            return []

        api_offices = {o['name']: o for o in api_response}
        drift_findings = []

        for yaml_office in yaml_offices:
            office_name = yaml_office.get('spec', {}).get('name') or yaml_office.get('metadata', {}).get('name')

            if not office_name:
                continue

            if office_name not in api_offices:
                drift_findings.append({
                    'type': 'office',
                    'name': office_name,
                    'drift_type': 'missing_in_api',
                    'message': f"Office '{office_name}' exists in Git but not in Fineract API",
                    'source_file': yaml_office.get('_source_file')
                })

        yaml_office_names = {
            o.get('spec', {}).get('name') or o.get('metadata', {}).get('name')
            for o in yaml_offices if o.get('spec', {}).get('name') or o.get('metadata', {}).get('name')
        }

        for api_office_name in api_offices.keys():
            if api_office_name not in yaml_office_names:
                drift_findings.append({
                    'type': 'office',
                    'name': api_office_name,
                    'drift_type': 'extra_in_api',
                    'message': f"Office '{api_office_name}' exists in Fineract API but not in Git"
                })

        return drift_findings

    def compare_code_values(self) -> List[Dict]:
        """Compare code values between YAML and Fineract API"""
        logger.info("Comparing code values...")

        yaml_code_values = self.load_yaml_entities('code-values')
        yaml_code_values.extend(self.load_yaml_entities('codes-and-values'))

        api_response = self.get('codes')
        if not api_response:
            logger.error("Failed to fetch codes from API")
            return []

        drift_findings = []
        api_codes = {c['name']: c for c in api_response}

        for yaml_code in yaml_code_values:
            code_name = yaml_code.get('spec', {}).get('name') or yaml_code.get('metadata', {}).get('name')

            if not code_name:
                continue

            if code_name not in api_codes:
                drift_findings.append({
                    'type': 'code_value',
                    'name': code_name,
                    'drift_type': 'missing_in_api',
                    'message': f"Code '{code_name}' exists in Git but not in Fineract API",
                    'source_file': yaml_code.get('_source_file')
                })

        return drift_findings

    def detect_all_drift(self) -> List[Dict]:
        """Run all drift detection checks"""
        all_drift = []

        all_drift.extend(self.compare_loan_products())
        all_drift.extend(self.compare_offices())
        all_drift.extend(self.compare_code_values())

        return all_drift

    def format_drift_report(self, drift_findings: List[Dict]) -> str:
        """Format drift findings into human-readable report"""
        if not drift_findings:
            return "✅ No configuration drift detected. Git and Fineract API are in sync."

        report = [
            "⚠️  CONFIGURATION DRIFT DETECTED",
            "=" * 60,
            f"Drift findings: {len(drift_findings)}",
            f"Detection time: {datetime.now().isoformat()}",
            "",
            "Details:",
            ""
        ]

        # Group by entity type
        by_type = {}
        for finding in drift_findings:
            entity_type = finding['type']
            if entity_type not in by_type:
                by_type[entity_type] = []
            by_type[entity_type].append(finding)

        for entity_type, findings in by_type.items():
            report.append(f"\n{entity_type.upper()} ({len(findings)} issues):")
            report.append("-" * 60)

            for finding in findings:
                report.append(f"  • {finding.get('name', 'Unknown')}")
                report.append(f"    Drift Type: {finding['drift_type']}")

                if 'message' in finding:
                    report.append(f"    {finding['message']}")

                if 'field' in finding:
                    report.append(f"    Field: {finding['field']}")
                    report.append(f"    Git value: {finding.get('yaml_value')}")
                    report.append(f"    API value: {finding.get('api_value')}")

                if 'source_file' in finding:
                    report.append(f"    Source: {finding['source_file']}")

                report.append("")

        report.append("=" * 60)
        report.append("⚠️  Manual changes detected outside GitOps workflow.")
        report.append("    Please sync changes back to Git or revert manual changes.")

        return "\n".join(report)

    def send_slack_alert(self, drift_report: str) -> bool:
        """Send drift alert to Slack"""
        if not self.slack_webhook:
            logger.info("Slack webhook not configured, skipping Slack alert")
            return False

        try:
            payload = {
                'text': 'Fineract Configuration Drift Detected',
                'attachments': [{
                    'color': 'warning',
                    'text': f"```\n{drift_report}\n```",
                    'footer': 'Fineract Drift Detection',
                    'ts': int(datetime.now().timestamp())
                }]
            }

            response = requests.post(
                self.slack_webhook,
                json=payload,
                timeout=10
            )
            response.raise_for_status()

            logger.info("Slack alert sent successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to send Slack alert: {e}")
            return False

    def send_email_alert(self, drift_report: str) -> bool:
        """Send drift alert via Email (SMTP)"""
        if not all([self.smtp_host, self.email_from, self.email_to]):
            logger.info("Email not configured, skipping email alert")
            return False

        try:
            msg = MIMEMultipart('alternative')
            msg['Subject'] = self.email_subject
            msg['From'] = self.email_from
            msg['To'] = self.email_to

            # Plain text version
            text_body = drift_report

            # HTML version
            html_body = f"""
            <html>
              <head></head>
              <body>
                <h2 style="color: #ff9800;">⚠️ Fineract Configuration Drift Detected</h2>
                <pre style="background-color: #f5f5f5; padding: 15px; border-left: 4px solid #ff9800;">
{drift_report}
                </pre>
                <hr>
                <p style="color: #666; font-size: 12px;">
                  This alert was generated by the Fineract Configuration Drift Detection system.<br>
                  Detection Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
                </p>
              </body>
            </html>
            """

            part1 = MIMEText(text_body, 'plain')
            part2 = MIMEText(html_body, 'html')
            msg.attach(part1)
            msg.attach(part2)

            # Connect to SMTP server
            if self.smtp_use_tls:
                server = smtplib.SMTP(self.smtp_host, self.smtp_port)
                server.starttls()
            else:
                server = smtplib.SMTP_SSL(self.smtp_host, self.smtp_port)

            if self.smtp_username and self.smtp_password:
                server.login(self.smtp_username, self.smtp_password)

            # Send email to all recipients
            recipients = [email.strip() for email in self.email_to.split(',')]
            server.sendmail(self.email_from, recipients, msg.as_string())
            server.quit()

            logger.info(f"Email alert sent successfully to {len(recipients)} recipient(s)")
            return True

        except Exception as e:
            logger.error(f"Failed to send email alert: {e}")
            return False


def main():
    parser = argparse.ArgumentParser(description='Detect Fineract configuration drift')
    parser.add_argument('--yaml-dir', default='/data',
                        help='Directory containing YAML configuration files')
    parser.add_argument('--fineract-url',
                        default='http://fineract-read-service:8080/fineract-provider/api/v1',
                        help='Fineract API base URL')
    parser.add_argument('--tenant', default='default',
                        help='Fineract tenant identifier')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run detection but do not send alerts')

    args = parser.parse_args()

    logger.info("=" * 60)
    logger.info("Fineract Configuration Drift Detection")
    logger.info("=" * 60)
    logger.info(f"YAML Directory: {args.yaml_dir}")
    logger.info(f"Fineract URL: {args.fineract_url}")
    logger.info(f"Tenant: {args.tenant}")
    logger.info(f"Dry Run: {args.dry_run}")
    logger.info("=" * 60)

    # Initialize detector
    detector = FineractDriftDetector(
        yaml_dir=args.yaml_dir,
        fineract_url=args.fineract_url,
        tenant=args.tenant
    )

    # Detect drift
    drift_findings = detector.detect_all_drift()
    drift_report = detector.format_drift_report(drift_findings)

    # Print report
    print("\n" + drift_report + "\n")

    # Send alerts (unless dry run)
    if drift_findings and not args.dry_run:
        logger.info("Sending alerts...")
        detector.send_slack_alert(drift_report)
        detector.send_email_alert(drift_report)
    elif args.dry_run:
        logger.info("Dry run mode - alerts not sent")

    # Exit with code 1 if drift detected
    if drift_findings:
        logger.warning(f"Configuration drift detected: {len(drift_findings)} issues found")
        sys.exit(1)
    else:
        logger.info("No configuration drift detected")
        sys.exit(0)


if __name__ == '__main__':
    main()
