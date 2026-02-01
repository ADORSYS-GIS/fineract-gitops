# Payment Gateway Secrets Management

This document describes how to create and manage secrets for the Payment Gateway Service, which integrates with MTN MoMo, Orange Money, and CinetPay payment providers.

## Overview

The `payment-gateway-secrets` Kubernetes Secret contains sensitive credentials for:
- **MTN MoMo API** - Mobile money collection and disbursement
- **Orange Money API** - Mobile money web payments
- **CinetPay API** - Payment gateway that routes to MTN/Orange (dynamic GL mapping)

These secrets are encrypted using [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) before being committed to Git, following the pattern established in [ADR-003-sealed-secrets](architecture/ADR-003-sealed-secrets.md).

## Prerequisites

Before creating the secrets, ensure you have:

1. **kubeseal CLI** installed:
   ```bash
   # macOS
   brew install kubeseal

   # Linux
   wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz
   tar -xvzf kubeseal-0.27.0-linux-amd64.tar.gz
   sudo mv kubeseal /usr/local/bin/
   ```

2. **kubectl** configured with cluster access

3. **Sealed Secrets controller** deployed in the cluster (in `kube-system` namespace)

4. **Payment provider accounts**:
   - MTN MoMo Developer account: https://momodeveloper.mtn.com
   - Orange Developer account: https://developer.orange.com
   - CinetPay Merchant account: https://my.cinetpay.com

## Secret Keys Reference

| Key | Description | Source |
|-----|-------------|--------|
| `mtn-collection-key` | MTN MoMo Collection API subscription key | MTN Developer Portal → Products → Collection |
| `mtn-disbursement-key` | MTN MoMo Disbursement API subscription key | MTN Developer Portal → Products → Disbursement |
| `mtn-api-user-id` | UUID for API authentication | Created via MTN provisioning endpoint |
| `mtn-api-key` | API key for authentication | Generated after API user creation |
| `mtn-gl-account-code` | Fineract GL account for MTN transactions | Fineract Chart of Accounts (default: 43) |
| `orange-client-id` | Orange Money OAuth2 client ID | Orange Developer Portal → My Apps |
| `orange-client-secret` | Orange Money OAuth2 client secret | Orange Developer Portal → My Apps |
| `orange-merchant-code` | Merchant identifier assigned by Orange | Orange Money merchant registration |
| `orange-gl-account-code` | Fineract GL account for Orange transactions | Fineract Chart of Accounts (default: 44) |
| `cinetpay-api-key` | CinetPay API key for payment initiation | CinetPay Merchant Dashboard → API Settings |
| `cinetpay-site-id` | CinetPay Site ID (merchant identifier) | CinetPay Merchant Dashboard → API Settings |
| `cinetpay-api-password` | CinetPay API password for transfer auth | CinetPay Merchant Dashboard → API Settings |

## Step-by-Step Instructions

### Step 1: Copy the Template

```bash
cd /path/to/fineract-gitops/secrets/dev
cp payment-gateway-secrets.yaml.template payment-gateway-secrets.yaml
```

### Step 2: Fill in Actual Values

Edit `payment-gateway-secrets.yaml` and replace all `CHANGE_ME` placeholders with actual credentials:

```bash
# Use your preferred editor
vim payment-gateway-secrets.yaml
```

### Step 3: Seal the Secret

```bash
# Seal using the cluster's public key
kubeseal --format yaml \
  --controller-namespace kube-system \
  < payment-gateway-secrets.yaml \
  > payment-gateway-secrets-sealed.yaml
```

**Alternative: Seal from a specific cluster**
```bash
# Fetch the public key first (for offline sealing)
kubeseal --fetch-cert \
  --controller-namespace kube-system \
  > sealed-secrets-pub.pem

# Seal using the public key
kubeseal --format yaml \
  --cert sealed-secrets-pub.pem \
  < payment-gateway-secrets.yaml \
  > payment-gateway-secrets-sealed.yaml
```

### Step 4: Delete the Plaintext File

```bash
rm payment-gateway-secrets.yaml
```

### Step 5: Verify the Sealed Secret

```bash
# Validate the YAML structure
kubectl apply --dry-run=client -f payment-gateway-secrets-sealed.yaml

# Check it can be unsealed (requires cluster access)
kubectl apply -f payment-gateway-secrets-sealed.yaml
kubectl get secret payment-gateway-secrets -n fineract-dev
```

### Step 6: Commit the Sealed Secret

```bash
git add payment-gateway-secrets-sealed.yaml
git commit -m "feat(secrets): add payment-gateway-secrets for dev environment"
```

## Provider Setup Guides

### MTN MoMo Developer Portal

1. **Create an Account**
   - Go to https://momodeveloper.mtn.com
   - Sign up for a developer account

2. **Subscribe to Products**
   - Navigate to Products
   - Subscribe to "Collection" (for deposits)
   - Subscribe to "Disbursement" (for withdrawals)
   - Copy the subscription keys (Primary Key)

3. **Create API User**
   ```bash
   # Generate a UUID for the API user
   API_USER_ID=$(uuidgen)

   # Create the API user (sandbox)
   curl -X POST "https://sandbox.momodeveloper.mtn.com/v1_0/apiuser" \
     -H "Content-Type: application/json" \
     -H "X-Reference-Id: $API_USER_ID" \
     -H "Ocp-Apim-Subscription-Key: YOUR_COLLECTION_KEY" \
     -d '{"providerCallbackHost": "https://payments.webank.cm"}'
   ```

4. **Generate API Key**
   ```bash
   curl -X POST "https://sandbox.momodeveloper.mtn.com/v1_0/apiuser/$API_USER_ID/apikey" \
     -H "Ocp-Apim-Subscription-Key: YOUR_COLLECTION_KEY"
   ```

5. **Save the Credentials**
   - `mtn-collection-key`: Your Collection subscription key
   - `mtn-disbursement-key`: Your Disbursement subscription key
   - `mtn-api-user-id`: The UUID you generated
   - `mtn-api-key`: The API key from the response

### Orange Money API

1. **Create Developer Account**
   - Go to https://developer.orange.com
   - Sign up and verify your email

2. **Create an Application**
   - Navigate to "My Apps"
   - Create a new application
   - Select "Orange Money Webpay" API

3. **Get Credentials**
   - Copy the Client ID and Client Secret
   - Note: Production credentials require merchant registration with Orange

4. **Merchant Registration** (Production only)
   - Contact Orange Money business team
   - Complete KYC verification
   - Receive merchant code

5. **Save the Credentials**
   - `orange-client-id`: OAuth2 Client ID
   - `orange-client-secret`: OAuth2 Client Secret
   - `orange-merchant-code`: Assigned merchant code

### CinetPay API (Payment Gateway)

CinetPay is a payment gateway that routes transactions to the underlying provider (MTN MoMo, Orange Money, etc.). The actual payment method is chosen by the customer at checkout, and GL accounting is mapped dynamically based on the `cpm_payment_method` field in the callback.

**Key Architecture Point:** No separate GL account is needed for CinetPay - transactions are recorded against the MTN or Orange GL accounts based on the actual payment method used.

1. **Create Merchant Account**
   - Go to https://my.cinetpay.com
   - Sign up for a merchant account
   - Complete KYC verification

2. **Get API Credentials**
   - Navigate to API Settings in the merchant dashboard
   - Copy your API Key and Site ID
   - Note your API Password (for transfer operations)

3. **Configure Callback URLs**
   - In CinetPay dashboard, configure your callback URLs:
     - Payment callback: `https://payments.webank.cm/api/callbacks/cinetpay/payment`
     - Transfer callback: `https://payments.webank.cm/api/callbacks/cinetpay/transfer`

4. **Test in Sandbox**
   - CinetPay provides test credentials for sandbox testing
   - Test phone numbers and cards are documented at https://docs.cinetpay.com

5. **Save the Credentials**
   - `cinetpay-api-key`: Your API Key
   - `cinetpay-site-id`: Your Site ID (merchant identifier)
   - `cinetpay-api-password`: Your API Password

## Troubleshooting

### "cannot fetch certificate" error

```
error: cannot fetch certificate: no endpoints available
```

**Solution:** Ensure the Sealed Secrets controller is running:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### "no key could decrypt secret" error

This occurs when the sealed secret was encrypted with a different cluster's key.

**Solution:** Re-seal the secret using the correct cluster's public key:
```bash
kubeseal --fetch-cert --controller-namespace kube-system > pub.pem
kubeseal --cert pub.pem < payment-gateway-secrets.yaml > payment-gateway-secrets-sealed.yaml
```

### Secret not decrypting in cluster

Check the Sealed Secrets controller logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### GL Account codes not matching

Ensure the GL account codes in the secret match those configured in Fineract:
- GL 43: MTN Mobile Money (default)
- GL 44: Orange Money (default)

Verify in Fineract Admin → Accounting → Chart of Accounts.

## Updating Secrets

To update credentials (e.g., key rotation):

1. Create a new plaintext secret file with updated values
2. Re-seal using the same process
3. Commit the new sealed secret
4. ArgoCD will automatically apply the update

```bash
# The sealed secret name stays the same
# Only the encryptedData changes
kubeseal --format yaml \
  --controller-namespace kube-system \
  < payment-gateway-secrets-updated.yaml \
  > payment-gateway-secrets-sealed.yaml

rm payment-gateway-secrets-updated.yaml
git add payment-gateway-secrets-sealed.yaml
git commit -m "chore(secrets): rotate payment-gateway credentials"
```

## Related Resources

- [ADR-003: Sealed Secrets](architecture/ADR-003-sealed-secrets.md) - Architecture decision for secrets management
- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [MTN MoMo API Documentation](https://momodeveloper.mtn.com/api-documentation)
- [Orange Money API Documentation](https://developer.orange.com/apis/om-webpay)
- [CinetPay API Documentation](https://docs.cinetpay.com/)
- [CinetPay Payment Initialization](https://docs.cinetpay.com/api/1.0-en/checkout/initialisation)
- [CinetPay Transfer API](https://docs.cinetpay.com/api/1.0-en/transfert/utilisation)
- [Fineract GL Accounts](../config/self-service/gl-accounts.json) - GL account configuration
