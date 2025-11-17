# Cert-Manager

Automated TLS certificate management using cert-manager and Let's Encrypt for the Fineract GitOps deployment.

## Overview

Cert-manager automates the management and issuance of TLS certificates from various certificate authorities (CAs), including Let's Encrypt. This component provides:

- **Automated certificate issuance** - Certificates are automatically requested and renewed
- **Let's Encrypt integration** - Free, automated certificates from Let's Encrypt
- **Self-signed certificates** - For development and internal services
- **Certificate lifecycle management** - Automatic renewal before expiration

## Components

### Certificate Issuers

1. **selfsigned-issuer.yaml** - Self-signed certificate issuer
   - Used for bootstrapping and internal CA creation
   - Creates the internal CA certificate
   - Not exposed to external services

2. **internal-ca-certificate.yaml** - Internal CA certificate
   - Self-signed CA certificate for internal services
   - Used for development and non-production environments
   - Can be trusted in browsers for local development

3. **letsencrypt-staging.yaml** - Let's Encrypt staging issuer
   - Used for testing certificate issuance
   - Higher rate limits than production
   - Issues certificates from staging CA (not trusted by browsers)
   - **Use this first** before switching to production

4. **letsencrypt-prod.yaml** - Let's Encrypt production issuer
   - Used for production certificate issuance
   - Strict rate limits (5 duplicate certificates per week)
   - Issues browser-trusted certificates
   - **Only use after testing with staging**

### Installation

5. **cert-manager.yaml** - Cert-manager installation
   - Installs cert-manager CRDs and controllers
   - Version: v1.13.3
   - Namespace: cert-manager

6. **namespace.yaml** - Cert-manager namespace
   - Creates the cert-manager namespace
   - All cert-manager resources run in this namespace

## Usage

### Request a Certificate

Create a Certificate resource in your application namespace:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fineract-tls
  namespace: fineract-dev
spec:
  secretName: fineract-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - fineract.example.com
    - www.fineract.example.com
```

### Ingress Annotation (Automatic)

Cert-manager can automatically create certificates from Ingress resources:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - fineract.example.com
      secretName: fineract-tls
  rules:
    - host: fineract.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fineract
                port:
                  number: 8080
```

## Certificate Lifecycle

### Staging to Production Migration

1. **Test with staging first:**
   ```yaml
   cert-manager.io/cluster-issuer: "letsencrypt-staging"
   ```

2. **Verify certificate issuance:**
   ```bash
   kubectl describe certificate fineract-tls -n fineract-dev
   kubectl get secret fineract-tls -n fineract-dev
   ```

3. **Switch to production:**
   ```yaml
   cert-manager.io/cluster-issuer: "letsencrypt-prod"
   ```

### Certificate Renewal

Cert-manager automatically renews certificates:
- **Renewal trigger**: 30 days before expiration (configurable)
- **Let's Encrypt certificates**: Valid for 90 days
- **Automatic renewal**: No manual intervention required

### Monitoring Certificates

Check certificate status:

```bash
# List all certificates
kubectl get certificates --all-namespaces

# Check certificate details
kubectl describe certificate <name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate expiration
kubectl get certificate <name> -n <namespace> -o jsonpath='{.status.notAfter}'
```

## Let's Encrypt Rate Limits

### Production Issuer Limits

- **Certificates per Registered Domain**: 50 per week
- **Duplicate Certificates**: 5 per week
- **Failed Validations**: 5 per account, per hostname, per hour
- **Accounts per IP Address**: 10 per 3 hours

### Best Practices

1. **Always test with staging first** - Avoid hitting production rate limits
2. **Use DNS validation for wildcards** - More reliable than HTTP validation
3. **Monitor certificate expiration** - Set up alerts for renewal failures
4. **Reuse certificates** - Don't delete and recreate frequently

## DNS Challenge (Optional)

For wildcard certificates or private networks, use DNS challenge:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
      - dns01:
          route53:
            region: us-east-1
            accessKeyID: AKIAIOSFODNN7EXAMPLE
            secretAccessKeySecretRef:
              name: route53-credentials
              key: secret-access-key
```

## Troubleshooting

### Certificate Not Issuing

1. **Check CertificateRequest:**
   ```bash
   kubectl get certificaterequest -n <namespace>
   kubectl describe certificaterequest <name> -n <namespace>
   ```

2. **Check Order and Challenges:**
   ```bash
   kubectl get order -n <namespace>
   kubectl get challenge -n <namespace>
   kubectl describe challenge <name> -n <namespace>
   ```

3. **Check cert-manager logs:**
   ```bash
   kubectl logs -n cert-manager deploy/cert-manager -f
   ```

### Common Issues

| Issue | Solution |
|-------|----------|
| Certificate stuck in "Pending" | Check DNS/HTTP validation is accessible |
| "too many certificates already issued" | Hit Let's Encrypt rate limit, wait or use staging |
| "self-signed certificate" in browser | Using staging issuer or self-signed, switch to prod |
| Certificate not renewing | Check cert-manager logs, verify ACME account is valid |

### HTTP-01 Challenge Requirements

For Let's Encrypt HTTP-01 validation to work:
- **Port 80 must be accessible** from the internet
- **Ingress must route** `/.well-known/acme-challenge/` to cert-manager
- **DNS must resolve** to your cluster's load balancer

## Environment-Specific Configuration

### Development
- Use **self-signed issuer** or **letsencrypt-staging**
- Trust the internal CA certificate in your browser
- No external DNS required

### Production
- Use **letsencrypt-prod** issuer
- Ensure DNS is properly configured
- Monitor certificate expiration
- Set up alerts for renewal failures

## Integration with Ingress

This cert-manager setup integrates with:
- **NGINX Ingress Controller** (apps/ingress-nginx)
- **Traefik** (if used)
- **Istio Gateway** (if used)

The ingress controller must support cert-manager annotations.

## Security Considerations

1. **Private keys** are stored in Kubernetes Secrets
2. **ACME account credentials** are stored securely
3. **Let's Encrypt staging** should not be used for production (untrusted CA)
4. **Rate limits** prevent abuse but can block legitimate use

## References

- **[Cert-Manager Documentation](https://cert-manager.io/docs/)**
- **[Let's Encrypt Documentation](https://letsencrypt.org/docs/)**
- **[Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)**
- **[Cert-Manager Best Practices](https://cert-manager.io/docs/usage/best-practice/)**

---

**Namespace**: `cert-manager`
**Managed by**: ArgoCD
**Component**: Certificate Management
**Purpose**: Automated SSL/TLS with Let's Encrypt
