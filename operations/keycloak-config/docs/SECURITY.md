# Keycloak Security Architecture - Webank

## Overview

This document describes the comprehensive security architecture implemented for Webank's Keycloak identity provider, including authentication flows, security policies, monitoring, and incident response procedures.

## Security Principles

### Defense in Depth

Multiple layers of security controls:
- **Network Layer**: NetworkPolicies, Ingress rules blocking admin routes
- **Application Layer**: Admin console disabled, WebAuthn 2FA, brute force protection
- **Data Layer**: Encrypted secrets, token encryption, secure password policies
- **Monitoring Layer**: Real-time alerts, audit logging, security dashboards

### Least Privilege

- Service accounts with minimal permissions
- Role-based access control (RBAC)
- Network policies restricting pod-to-pod communication
- Admin console completely disabled in production

### Immutable Infrastructure

- All configuration via GitOps (keycloak-config-cli)
- No manual changes allowed in production
- Version-controlled realm configuration
- Automated deployments with ArgoCD

## Architecture

### Client Configuration (6 Clients)

#### 1. apache-gateway (Confidential)
**Purpose**: Main authentication client for ALL web applications
**Flow**: Authorization Code
**Characteristics**:
- Server-side confidential client
- Protects: Client Portal, Staff Dashboard, Admin Console
- Single sign-on across all web apps
- Client secret stored in Kubernetes Secret

**Security Features**:
- HTTPS only
- Token binding
- Session affinity
- Claims mapping (fineract_user_id, office_id, employee_id)

#### 2. mobile-app (Public)
**Purpose**: Native mobile application
**Flow**: Authorization Code + PKCE
**Characteristics**:
- Public client (no secret)
- PKCE required for security
- Refresh tokens for offline access (30 days)
- Direct OIDC flow (not through Apache)

**Security Features**:
- PKCE with S256 challenge
- No direct access grants
- Certificate pinning (recommended)
- App attestation (future)

#### 3. admin-cli (Confidential)
**Purpose**: Keycloak configuration management and user synchronization
**Flow**: Client Credentials
**Characteristics**:
- Service account only
- realm-admin role
- Used by keycloak-config-cli and user sync service

**Security Features**:
- Rotated credentials
- Network policy restrictions
- Audit logging of all operations
- No user interaction

#### 4. fineract-api (Confidential)
**Purpose**: Generic backend service account
**Flow**: Client Credentials
**Characteristics**:
- Backend integrations with Fineract API
- No user interaction

#### 5. message-gateway (Confidential)
**Purpose**: SMS/Email notification microservice
**Flow**: Client Credentials

#### 6. payment-gateway (Confidential)
**Purpose**: Payment processing microservice
**Flow**: Client Credentials

### Authentication Flows

#### Standard Login Flow

```
1. User → Apache Gateway → Keycloak Login Page (Webank Theme)
2. User enters username + password
3. Keycloak validates credentials
4. If valid → Check for required actions:
   a. UPDATE_PASSWORD (if temporary password)
   b. VERIFY_EMAIL (if not verified)
   c. webauthn-register (if no device registered)
5. User completes required actions
6. Keycloak issues tokens → Apache Gateway
7. Apache injects headers → Frontend App
8. User authenticated
```

#### First Login Flow

```
1. Admin creates user in Fineract
2. User sync service creates matching Keycloak user with:
   - Temporary password (16 chars, secure)
   - Required actions: UPDATE_PASSWORD, VERIFY_EMAIL, webauthn-register
3. User receives temporary password (secure channel)
4. User logs in → Redirected to "Update Password" page
5. User sets new password (meets policy: 12 chars, uppercase, digit, special)
6. Redirected to "Register Your Device" page
7. User registers Face ID / Touch ID / Security Key
8. Device registered → User authenticated
9. Future logins: Username → Password → WebAuthn (automatic)
```

#### WebAuthn Authentication

```
1. User enters username + password
2. Keycloak checks: Does user have WebAuthn credential registered?
3. If yes → Challenge user with WebAuthn
4. Browser prompts: "Use Face ID to sign in to Webank"
5. User authenticates biometrically
6. Token issued → User logged in
```

## Security Hardening

### Password Policy

```
Minimum length: 12 characters
Requirements:
  - At least 1 uppercase letter
  - At least 1 lowercase letter
  - At least 2 digits
  - At least 1 special character (!@#$%^&*)
  - Cannot be same as username
  - Cannot be in last 5 passwords (history)
Hash iterations: 27,500
```

### Brute Force Protection

```
Max failed attempts: 3
Wait increment: 2 minutes
Max wait time: 30 minutes
Quick login check: 500ms
Permanent lockout: Disabled (temporary only)
```

**Behavior**:
- 1st failure: No delay
- 2nd failure: No delay
- 3rd failure: Account locked for 2 minutes
- 4th failure (after unlock): Locked for 4 minutes
- Continues exponentially up to 30 minutes max

### Token Security

```
Access token lifespan: 15 minutes
SSO session idle: 30 minutes
SSO session max: 4 hours
Refresh token max reuse: 0 (one-time use)
Revoke refresh token: Enabled
Offline session idle: 30 days (mobile app only)
```

### WebAuthn Policy

```
RP Entity Name: Webank
RP ID: ${DOMAIN}
Signature Algorithms: ES256, RS256
Attestation: None (for compatibility)
Authenticator Attachment: Platform + Cross-platform
User Verification: Required
Timeout: 60 seconds
Resident Key: Not required
```

**Supported Authenticators**:
- ✅ Face ID (iOS, macOS)
- ✅ Touch ID (iOS, macOS)
- ✅ Windows Hello (Windows)
- ✅ YubiKey 5 series
- ✅ Google Titan Security Key
- ✅ Any FIDO2-compliant authenticator

### Security Headers

```http
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; frame-ancestors 'none';
X-Content-Type-Options: nosniff
X-Robots-Tag: none
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

### Network Security

#### Production NetworkPolicy

```yaml
# Blocks all traffic except:
- Apache Gateway → Keycloak (auth requests)
- User Sync Service → Keycloak (user creation)
- Config CLI Job → Keycloak (GitOps)
- Prometheus → Keycloak (metrics)
# Explicitly blocks:
- Direct access to /admin routes
- Access to /realms/master
```

#### Ingress Security

```yaml
# Nginx annotations:
- Rate limiting: 10 requests/second per IP
- Connection limit: 5 concurrent connections
- Server-side block of /admin routes (returns 403)
```

## Admin Console Lockdown

### Production Configuration

**Admin console is COMPLETELY DISABLED in production.**

**Enforcement mechanisms**:
1. **Environment variables**: `KC_FEATURES=-admin,-admin2`
2. **NetworkPolicy**: Blocks ingress to admin routes
3. **Ingress rules**: Returns 403 for /admin requests
4. **Master realm**: Disabled

**All configuration changes MUST be made via GitOps:**

```bash
# 1. Edit configuration
vim operations/keycloak-config/config/realm-fineract.yaml

# 2. Validate
python3 scripts/validate-data.py

# 3. Commit
git add operations/keycloak-config/
git commit -m "keycloak: update security policy"
git push

# 4. ArgoCD auto-applies within 3 minutes
```

### Emergency Access Procedure

**Only use in critical situations with written approval.**

See: `operations/keycloak-config/security-policies/keycloak-production-config.yaml`

## Monitoring & Alerting

### Security Metrics

Prometheus collects:
- Login success/failure rates
- Failed login attempts by username
- Account lockout events
- WebAuthn registration/authentication events
- Password reset requests
- Admin console access attempts
- Token revocation events
- Session counts

### Critical Alerts

| Alert | Threshold | Severity | Action |
|-------|-----------|----------|--------|
| High Failed Login Rate | >10/sec for 5min | Warning | Investigate for brute force |
| Multiple Account Lockouts | >5 in 10min | Warning | Check for attack pattern |
| Admin Console Access (Prod) | >0 | **CRITICAL** | Immediate investigation required |
| Keycloak Down | Service unavailable for 2min | Critical | Escalate to on-call |
| Password Reset Abuse | >10/sec for 5min | Warning | Possible enumeration attack |
| High Response Time | p95 >2s for 10min | Warning | Performance investigation |

### Grafana Dashboard

**Keycloak Security & Authentication Dashboard** includes:
- Login success rate (real-time)
- Active sessions counter
- Failed login attempts (last hour)
- WebAuthn adoption rate
- Account lockouts
- Top 10 usernames with failed logins
- Authentication events timeline
- Response time (p95, p99)
- Client logins by application
- Database connection pool status

## Audit Logging

### Event Types Logged

```
LOGIN, LOGIN_ERROR
LOGOUT, LOGOUT_ERROR
UPDATE_PASSWORD, UPDATE_PASSWORD_ERROR
UPDATE_EMAIL
VERIFY_EMAIL
REMOVE_CREDENTIAL (device removal)
UPDATE_CREDENTIAL (device registration)
SEND_RESET_PASSWORD
CLIENT_LOGIN, CLIENT_LOGIN_ERROR
REFRESH_TOKEN
```

### Retention

- **Keycloak database**: 7 days
- **Loki (log aggregation)**: 30 days
- **Long-term archive** (S3/GCS): 1 year (compliance)

### Query Examples

```bash
# View all failed logins in last hour
kubectl logs -n fineract deployment/keycloak | grep "LOGIN_ERROR" | tail -100

# Export audit events
kubectl exec -n fineract deployment/keycloak -- \
  /opt/keycloak/bin/kc.sh export --dir /tmp/export --realm fineract

# Query via Loki
{app="keycloak", namespace="fineract"} |= "LOGIN_ERROR" | json
```

## Incident Response

### Suspected Brute Force Attack

**Symptoms**: High failed login rate alert, multiple account lockouts

**Response**:
1. Check Grafana dashboard for attack pattern
2. Identify source IPs from logs
3. Block at network level (Ingress/WAF)
4. Notify affected users if accounts locked
5. Review and tighten rate limits if needed

### Compromised Credentials

**Symptoms**: Login from unusual location, concurrent sessions from different IPs

**Response**:
1. Immediately revoke user's sessions via Keycloak API
2. Force password reset for affected user
3. Review audit logs for damage assessment
4. Notify user via secure channel
5. Escalate if sensitive data accessed

### Admin Console Access in Production

**Symptoms**: Critical alert fires

**Response**:
1. **IMMEDIATE**: Check who accessed (audit logs)
2. Verify if authorized emergency access
3. If unauthorized: Consider security breach
4. Rotate all Keycloak admin credentials
5. Review all changes made
6. Incident report within 1 hour

### Service Outage

**Symptoms**: Keycloak Down alert, users cannot login

**Response**:
1. Check pod status: `kubectl get pods -n fineract`
2. Check logs: `kubectl logs -n fineract deployment/keycloak`
3. Check database connectivity
4. Restart pods if needed: `kubectl rollout restart deployment/keycloak -n fineract`
5. If database issue, escalate to DBA
6. Post-incident review

## Security Best Practices

### For Administrators

✅ **DO**:
- Use GitOps for all configuration changes
- Test changes in dev/staging first
- Rotate client secrets regularly (quarterly)
- Monitor security dashboards daily
- Review audit logs weekly
- Keep Keycloak updated with security patches
- Use strong admin credentials (stored in vault)
- Enable MFA for admin access (via port-forward)

❌ **DON'T**:
- Access admin console in production
- Share client secrets
- Disable security features "temporarily"
- Make manual configuration changes
- Ignore security alerts
- Use weak passwords for service accounts
- Commit secrets to Git

### For Developers

✅ **DO**:
- Use HTTPS for all Keycloak connections
- Validate tokens on backend
- Implement proper session management
- Use secure cookie attributes
- Handle token refresh properly
- Implement proper logout
- Store tokens securely (not localStorage for sensitive apps)

❌ **DON'T**:
- Store access tokens long-term
- Pass tokens in URLs
- Disable HTTPS certificate validation
- Use implicit flow (deprecated)
- Hardcode client secrets

### For Users

✅ **DO**:
- Use strong, unique passwords
- Register WebAuthn device (Face ID/Touch ID)
- Enable MFA fallback (TOTP)
- Logout when done
- Report suspicious activity

❌ **DON'T**:
- Share passwords
- Use same password across sites
- Save password in unsecure location
- Access from public computers without logout

## Compliance

### Data Protection

- **GDPR Compliance**: User consent, right to be forgotten (user deletion)
- **PCI DSS**: Strong authentication, encrypted communications
- **SOC 2**: Audit logging, access controls, incident response

### Password Storage

- Passwords hashed with PBKDF2 (27,500 iterations)
- Salted per-user
- Never logged or transmitted in clear text
- Temporary passwords force immediate change

### Audit Trail

- All authentication events logged
- Admin actions logged
- Logs immutable (write-once)
- Retained per compliance requirements

## Security Checklist

### Pre-Production

- [ ] All client secrets rotated from defaults
- [ ] Admin console disabled (production)
- [ ] NetworkPolicies applied
- [ ] TLS/HTTPS enforced everywhere
- [ ] Rate limiting configured
- [ ] Security headers enabled
- [ ] Monitoring dashboards deployed
- [ ] Alert rules configured
- [ ] Grafana dashboard imported
- [ ] Audit logging enabled
- [ ] Backup strategy in place (Velero)
- [ ] Incident response procedures documented
- [ ] Security training for team completed

### Post-Production

- [ ] Monitor security dashboards daily
- [ ] Review audit logs weekly
- [ ] Rotate secrets quarterly
- [ ] Test incident response procedures quarterly
- [ ] Update security documentation as needed
- [ ] Conduct security assessments annually
- [ ] Penetration testing (external)

## References

- [Keycloak Security Documentation](https://www.keycloak.org/docs/latest/server_admin/index.html#_threat)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [WebAuthn Specification](https://www.w3.org/TR/webauthn-2/)
- [NIST Digital Identity Guidelines](https://pages.nist.gov/800-63-3/)

## Support

For security incidents or questions:
- **Security Team**: security@webank.com
- **On-call Engineer**: PagerDuty
- **Documentation**: https://docs.webank.com/security/keycloak

---

**Document Version**: 1.0
**Last Updated**: 2025-01-26
**Next Review**: 2025-04-26
