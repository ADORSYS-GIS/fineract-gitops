# OAuth2-Proxy Client Secret Update

## Issue
The OAuth2-Proxy client secret was invalid, causing authentication failures with the error:
```
Error redeeming code during OAuth2 callback: token exchange failed: oauth2: cannot fetch token: 401 Unauthorized
Response: {"error":"unauthorized_client","error_description":"Invalid client or Invalid client credentials"}
```

## Fix Applied (Manual - 2025-11-11)

### Kubernetes Secret Updated
```bash
kubectl patch secret oauth2-proxy-secrets -n fineract-dev \
  --type='json' \
  -p='[{"op":"replace","path":"/data/client-secret","value":"c0lMbkUwbWQ3TUNNS3RWVTRnek9wQ0FOOTZGbWhFN0c="}]'
```

Decoded value: `sILnE0md7MCMKtVU4gzOpCAN96FmhE7G`

### OAuth2-Proxy Restarted
```bash
kubectl rollout restart deployment/oauth2-proxy -n fineract-dev
```

## Keycloak Configuration
Client ID: `fineract-oauth2-proxy`
Client Secret: `sILnE0md7MCMKtVU4gzOpCAN96FmhE7G`
Realm: `fineract`

## ✅ COMPLETED: Secret Persistence Across Redeployments

The following actions were completed to ensure this secret persists (see Current Status section below):

1. **✅ Updated Sealed Secret (Option 2 - Completed)**
   - Regenerated the sealed secret file: `secrets/dev/oauth2-proxy-secrets-sealed.yaml`
   - Used command:
     ```bash
     kubectl create secret generic oauth2-proxy-secrets \
       --namespace=fineract-dev \
       --from-literal=client-id=fineract-oauth2-proxy \
       --from-literal=client-secret=sILnE0md7MCMKtVU4gzOpCAN96FmhE7G \
       --from-literal=cookie-secret=cTVYTWNOdVJXb2xkTnlRZUsxM3JlUk0x \
       --from-literal=redis-password= \
       --dry-run=client -o yaml | \
       kubeseal --format=yaml > secrets/dev/oauth2-proxy-secrets-sealed.yaml
     ```
   - Committed the updated sealed secret to Git
   - **Result**: Secret now persists across full redeployments

**Alternative Options Not Pursued:**
- Option 1 (AWS Secrets Manager): Not needed since sealed secret approach works
- Option 3 (Keycloak Config Script): Not recommended for security reasons

## Current Status (Updated 2025-11-11)
- ✅ Kubernetes secret updated manually
- ✅ OAuth2-Proxy restarted and working
- ✅ Sealed secret file updated and committed to Git
- ✅ Sealed-secrets controller service selector fixed (was missing endpoints)
- ✅ **Fix is now permanent** - will persist across redeployments

## Resolution Details
The sealed-secrets controller was deployed but the service had no endpoints due to label selector mismatch:
- Service selector included ArgoCD labels that pods didn't have
- Fixed by patching service selector to match pod labels: `name: sealed-secrets-controller`
- After fix, successfully generated and committed sealed secret with correct client secret

## Sealed Secret Generation
```bash
# Fixed sealed-secrets controller service
kubectl patch svc sealed-secrets-controller -n kube-system \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/selector","value":{"name":"sealed-secrets-controller"}}]'

# Fetched certificate from Kubernetes secret
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > /tmp/sealed-secrets-cert.pem

# Generated sealed secret
kubectl create secret generic oauth2-proxy-secrets \
  --namespace=fineract-dev \
  --from-literal=client-id=fineract-oauth2-proxy \
  --from-literal=client-secret=sILnE0md7MCMKtVU4gzOpCAN96FmhE7G \
  --from-literal=cookie-secret=cTVYTWNOdVJXb2xkTnlRZUsxM3JlUk0x \
  --from-literal=redis-password= \
  --dry-run=client -o yaml | \
  kubeseal --cert=/tmp/sealed-secrets-cert.pem --format=yaml \
  > secrets/dev/oauth2-proxy-secrets-sealed.yaml
```
