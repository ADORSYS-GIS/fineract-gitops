# SSL/TLS Setup Guide

**Automated SSL/TLS certificates with cert-manager and Let's Encrypt**

## Overview

This guide covers the complete SSL/TLS setup for the Fineract GitOps platform using:
- **cert-manager** - Automated certificate management
- **Let's Encrypt** - Free SSL certificates with automatic renewal
- **nginx-ingress** - Ingress controller with TLS termination
- **NetworkPolicies** - Service isolation and security

## Architecture

```
Internet (HTTPS only)
    ↓
nginx-ingress-controller (LoadBalancer)
    ↓
TLS Termination (Let's Encrypt certificates)
    ↓
    ├→ apps.fineract.example.com → Apache Gateway → Frontend Apps
    └→ auth.fineract.example.com → Keycloak → SSO

Internal (no external access):
- Fineract API (accessed via Apache Gateway only)
- PostgreSQL (accessed by Fineract only)
- MinIO Console (accessed via port-forward only)
```

## Components

| Component | Purpose | Version |
|-----------|---------|---------|
| **cert-manager** | Certificate management | v1.14.0 |
| **nginx-ingress** | Ingress controller | v1.10.0 |
| **Let's Encrypt** | Certificate authority | ACME v2 |
| **NetworkPolicies** | Service isolation | Kubernetes native |

## Prerequisites

1. ✅ Kubernetes cluster with LoadBalancer support
2. ✅ Domain name with DNS control
3. ✅ kubectl configured
4. ✅ ArgoCD installed

## Step 1: Deploy cert-manager via ArgoCD

cert-manager is deployed automatically via ArgoCD Application.

```bash
# cert-manager is deployed via ArgoCD (sync-wave: -1)
# Check if already deployed:
kubectl get pods -n cert-manager

# If not deployed, ArgoCD will sync it automatically
# To manually sync:
argocd app sync cert-manager

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cert-manager \
  -n cert-manager \
  --timeout=300s

# Verify installation
kubectl get clusterissuer
# Should show: letsencrypt-staging, letsencrypt-prod, selfsigned-issuer, internal-ca-issuer
```

**Note:** cert-manager and all ClusterIssuers are managed by ArgoCD in `argocd/applications/cluster-scoped/cert-manager.yaml`

## Step 2: Configure Let's Encrypt Email (Optional)

ClusterIssuers are already deployed via ArgoCD. Update the email address for certificate expiration notifications.

**Edit email addresses:**
```bash
# Update platform-team@example.com with your email
nano apps/cert-manager/base/letsencrypt-staging.yaml
nano apps/cert-manager/base/letsencrypt-prod.yaml

# Change:
# email: platform-team@example.com
# To:
# email: your-email@example.com

# Commit changes
git add apps/cert-manager/base/
git commit -m "Update Let's Encrypt email"
git push

# ArgoCD will sync automatically
argocd app sync cert-manager
```

**Verify issuers:**
```bash
kubectl get clusterissuer
# Should show all 4 issuers: letsencrypt-staging, letsencrypt-prod, selfsigned-issuer, internal-ca-issuer

kubectl describe clusterissuer letsencrypt-prod
# Check email is updated
```

## Step 3: Deploy nginx-ingress Controller via ArgoCD

nginx-ingress is deployed automatically via ArgoCD.

```bash
# nginx-ingress is deployed via ArgoCD
# Check if already deployed:
kubectl get pods -n ingress-nginx

# To manually sync:
argocd app sync nginx-ingress

# Wait for LoadBalancer IP
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx \
  --timeout=300s

# Get LoadBalancer IP (THIS IS CRITICAL for DNS)
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Example output:
# NAME                       TYPE           EXTERNAL-IP      PORT(S)
# ingress-nginx-controller   LoadBalancer   203.0.113.10     80:30080/TCP,443:30443/TCP
```

**Save the EXTERNAL-IP** - you'll need it for DNS configuration in the next step.

## Step 4: Configure DNS

Create DNS A records pointing to the LoadBalancer IP.

**Required DNS records:**
```
apps.fineract.example.com    A    203.0.113.10
auth.fineract.example.com    A    203.0.113.10
```

**Or use wildcard:**
```
*.fineract.example.com       A    203.0.113.10
```

**Verify DNS propagation:**
```bash
# Check DNS resolution
dig +short apps.fineract.example.com
dig +short auth.fineract.example.com

# Should return your LoadBalancer IP
```

## Step 5: Update Ingress Domains

Domains are configured per environment via Kustomize overlays.

**Update environment-specific domains:**
```bash
# For dev environment:
nano apps/ingress/overlays/dev/kustomization.yaml

# Update the configMapGenerator with your domains:
# - apps-hostname=apps.dev.yourdomain.com
# - auth-hostname=auth.dev.yourdomain.com

# For UAT environment:
nano apps/ingress/overlays/uat/kustomization.yaml

# For production:
nano apps/ingress/overlays/prod/kustomization.yaml

# Commit changes
git add apps/ingress/overlays/
git commit -m "Update ingress domains for environment"
git push
```

## Step 6: Deploy Ingress Resources (Staging Certificates)

Ingresses are deployed via ArgoCD and already configured with `letsencrypt-staging` by default.

```bash
# Ingresses are deployed via ArgoCD Application "ingress"
# Check if already deployed:
kubectl get ingress -n fineract-dev

# To manually sync:
argocd app sync ingress

# Watch certificate issuance (automatic when ingress deployed)
kubectl get certificate -n fineract-dev -w

# Check certificate status
kubectl describe certificate fineract-tls -n fineract-dev
kubectl describe certificate keycloak-tls -n fineract-dev
```

**Expected output:**
```
NAME            READY   SECRET          AGE
fineract-tls    True    fineract-tls    2m
keycloak-tls    True    keycloak-tls    2m
```

**Note:** cert-manager automatically creates Certificate resources based on the `cert-manager.io/cluster-issuer` annotation in ingresses.

## Step 7: Test Staging Certificates

```bash
# Test HTTPS with staging certificate
curl https://apps.fineract.example.com -v

# You'll see "Fake LE Intermediate X1" in the certificate chain
# This is normal for staging certificates

# Test HTTP to HTTPS redirect
curl -I http://apps.fineract.example.com
# Should return: HTTP/1.1 308 Permanent Redirect
# Location: https://apps.fineract.example.com/
```

## Step 8: Switch to Production Certificates

Once staging works, switch to production certificates.

**Update Ingress annotations:**
```bash
# Edit the base ingress file
nano apps/ingress/base/ingress.yaml

# Change this annotation in ALL 4 ingresses:
# FROM: cert-manager.io/cluster-issuer: "letsencrypt-staging"
# TO:   cert-manager.io/cluster-issuer: "letsencrypt-prod"

# Commit changes
git add apps/ingress/base/ingress.yaml
git commit -m "Switch to Let's Encrypt production certificates"
git push
```

**Delete old staging certificates:**
```bash
# Delete staging certificates (they will be recreated with production issuer)
kubectl delete certificate fineract-tls -n fineract-dev
kubectl delete certificate keycloak-tls -n fineract-dev

# Delete staging secrets (they will be recreated)
kubectl delete secret fineract-tls -n fineract-dev
kubectl delete secret keycloak-tls -n fineract-dev
```

**ArgoCD will sync automatically:**
```bash
# Verify ArgoCD synced the changes
argocd app sync ingress

# Watch new production certificates being issued
kubectl get certificate -n fineract-dev -w
```

## Step 9: Verify Production Certificates

```bash
# Test HTTPS with production certificate
curl https://apps.fineract.example.com -v

# Should show "Let's Encrypt Authority X3"
# No certificate warnings

# Test in browser
open https://apps.fineract.example.com

# Should show green padlock, valid certificate
```

## Step 10: Deploy NetworkPolicies

Apply NetworkPolicies for service isolation.

```bash
# Deploy NetworkPolicies
kubectl apply -k apps/network-policies/

# Verify policies
kubectl get networkpolicies -n fineract
kubectl get networkpolicies -n backup
```

## Service Access After SSL/TLS Setup

### Publicly Accessible (HTTPS only)

| Service | URL | Certificate |
|---------|-----|-------------|
| **Frontend Apps** | https://apps.fineract.example.com | Let's Encrypt (auto-renewed) |
| **Keycloak SSO** | https://auth.fineract.example.com | Let's Encrypt (auto-renewed) |

### Internal Only (ClusterIP)

| Service | Access Method | Notes |
|---------|---------------|-------|
| **Fineract API** | Via Apache Gateway | Network Policy: Apache Gateway only |
| **PostgreSQL** | From Fineract pods | Network Policy: Fineract + backup only |
| **MinIO Console** | `kubectl port-forward` | Network Policy: backup namespace only |
| **Redis** | From Fineract pods | Internal caching |

### Access MinIO Console (Internal)

```bash
# Port-forward MinIO console
kubectl port-forward -n backup svc/minio 9001:9001

# Open browser
open http://localhost:9001

# Login with credentials from minio-credentials secret
```

## Certificate Renewal

Let's Encrypt certificates expire after **90 days**. cert-manager automatically renews them **30 days before expiration**.

**Monitor certificate expiration:**
```bash
# Check certificate expiration dates
kubectl get certificate -n fineract -o custom-columns=\
NAME:.metadata.name,\
READY:.status.conditions[0].status,\
EXPIRES:.status.notAfter

# Example output:
# NAME                  READY   EXPIRES
# apache-gateway-tls    True    2025-04-26T12:34:56Z
# keycloak-tls          True    2025-04-26T12:35:10Z
```

**View cert-manager logs:**
```bash
# Check cert-manager renewal activity
kubectl logs -n cert-manager deployment/cert-manager -f
```

## Troubleshooting

### Certificate Not Issued

**Problem:** Certificate stuck in "False" status

**Debug:**
```bash
# Check certificate status
kubectl describe certificate fineract-tls -n fineract-dev
kubectl describe certificate keycloak-tls -n fineract-dev

# Check certificate request
kubectl get certificaterequest -n fineract-dev
kubectl describe certificaterequest <name> -n fineract-dev

# Check challenge (Let's Encrypt HTTP-01 validation)
kubectl get challenge -n fineract-dev
kubectl describe challenge <name> -n fineract-dev

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=100

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50
```

**Common causes:**
- DNS not pointing to LoadBalancer IP
- Firewall blocking ports 80/443
- Let's Encrypt rate limit hit (use staging first!)
- Ingress missing cert-manager annotation
- ArgoCD not synced

### HTTP-01 Challenge Fails

**Problem:** Let's Encrypt can't validate domain ownership

**Debug:**
```bash
# Test if Let's Encrypt can reach your domain
curl http://apps.fineract.example.com/.well-known/acme-challenge/test

# Should reach nginx-ingress
```

**Fix:**
- Ensure LoadBalancer is accessible from internet
- Check firewall rules (allow ports 80 and 443)
- Verify DNS propagation (`dig +short apps.fineract.example.com`)

### Certificate Shows "Fake LE"

**Problem:** Still using staging certificates

**Fix:**
- Update Ingress annotation to `letsencrypt-prod`
- Delete old certificates and secrets
- Re-apply Ingress resources

### ArgoCD Not Syncing Changes

**Problem:** Made changes to ingress but cert-manager not picking them up

**Debug:**
```bash
# Check ArgoCD app status
argocd app get ingress
argocd app get cert-manager

# Check if apps are out of sync
argocd app list

# View sync status
kubectl get applications -n argocd
```

**Fix:**
```bash
# Manual sync
argocd app sync ingress
argocd app sync cert-manager

# Or sync all apps
argocd app sync -l app.kubernetes.io/instance=app-of-apps

# Check if auto-sync is enabled
argocd app get ingress | grep "Sync Policy"
```

### Ingress Created but No Certificate

**Problem:** Ingress exists but cert-manager doesn't create certificate

**Debug:**
```bash
# Check if ingress has cert-manager annotation
kubectl get ingress -n fineract-dev fineract-oauth2-protected -o yaml | grep cert-manager

# Should show:
# cert-manager.io/cluster-issuer: letsencrypt-staging

# Check if ClusterIssuer exists
kubectl get clusterissuer letsencrypt-staging

# Check cert-manager webhook
kubectl get pods -n cert-manager -l app=webhook
```

**Fix:**
- Ensure ingress has `cert-manager.io/cluster-issuer` annotation
- Verify ClusterIssuer name matches annotation
- Restart cert-manager if webhook not working:
  ```bash
  kubectl rollout restart deployment/cert-manager -n cert-manager
  ```

## Security Best Practices

1. ✅ **Always use HTTPS** - HTTP redirects to HTTPS automatically
2. ✅ **TLS 1.2+ only** - Configured in Ingress annotations
3. ✅ **HSTS headers** - Configured in Ingress (31536000 seconds = 1 year)
4. ✅ **Internal services stay internal** - Use NetworkPolicies
5. ✅ **Monitor certificate expiration** - Set up alerts 30 days before
6. ✅ **Test staging first** - Avoid Let's Encrypt rate limits
7. ✅ **Keep cert-manager updated** - Check for security patches

## Let's Encrypt Rate Limits

| Limit | Value | Notes |
|-------|-------|-------|
| **Certificates per domain** | 50/week | Applies to production only |
| **Failed validations** | 5/hour | Too many failures = temporary block |
| **Duplicate certificates** | 5/week | Same domain + same SANs |

**Best practice:** Always test with **staging** first!

## Next Steps

1. ✅ Set up monitoring for certificate expiration
2. ✅ Configure backup for cert-manager secrets
3. ✅ Test disaster recovery (restore certificates)
4. ✅ Add more domains if needed (edit Ingress resources)

## Related Documentation

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [nginx-ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes NetworkPolicies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

**Created:** 2025-10-26  
**Status:** ✅ Production Ready  
**SSL Provider:** Let's Encrypt (ACME)  
**Certificate Renewal:** Automatic (30 days before expiration)
