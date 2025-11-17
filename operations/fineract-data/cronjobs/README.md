# Fineract Configuration Drift Detection

Automated monitoring system that detects when manual changes are made to Fineract configuration outside of GitOps workflows.

## Overview

The drift detection CronJob compares YAML configuration files from Git (source of truth) against live Fineract API data to identify discrepancies.

**Schedule**: Every 6 hours (`0 */6 * * *`)

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│ 1. CronJob triggers every 6 hours                      │
│ 2. Loads YAML configs from mounted ConfigMaps          │
│ 3. Queries Fineract API for current state              │
│ 4. Compares YAML vs API for each entity type           │
│ 5. Generates drift report                              │
│ 6. Sends alerts via Slack + Email (if drift detected)  │
└─────────────────────────────────────────────────────────┘
```

## Entities Monitored

- **Loan Products**: Name, currency, interest rates, principal limits
- **Offices**: Office structure and hierarchy
- **Code Values**: System code value definitions

## Alert Configuration

### Slack Alerts

Configure via sealed secret `slack-credentials`:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: slack-credentials
  namespace: fineract-dev
spec:
  encryptedData:
    webhook-url: AgB...  # Slack incoming webhook URL
```

### Email Alerts

Configure via sealed secret `smtp-credentials`:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: smtp-credentials
  namespace: fineract-dev
spec:
  encryptedData:
    host: AgB...          # SMTP server hostname
    port: AgB...          # SMTP port (587 for TLS)
    username: AgB...      # SMTP authentication username
    password: AgB...      # SMTP authentication password
    from-address: AgB...  # From email address
    to-address: AgB...    # To email (comma-separated for multiple)
```

## Interpreting Drift Reports

### Drift Types

**1. `missing_in_api`** - Entity exists in Git but not in Fineract
```
Loan product 'personal-loan' exists in Git but not in Fineract API
Source: data/dev/loan-products/personal-loan.yaml
```

**Action**: Entity was deleted manually from Fineract UI → Re-sync from Git

**2. `extra_in_api`** - Entity exists in Fineract but not in Git
```
Loan product 'emergency-loan' exists in Fineract API but not in Git
```

**Action**: Entity was created manually → Add to Git or remove from Fineract

**3. `field_mismatch`** - Entity field values don't match
```
Loan product 'personal-loan'
Field: interestRate
Git value: 15.0
API value: 18.5
Source: data/dev/loan-products/personal-loan.yaml
```

**Action**: Field was modified manually → Revert in Fineract or update Git

## Disabling Alerts for Planned Changes

If you're making intentional manual changes (e.g., testing), temporarily disable alerts:

### Option 1: Suspend CronJob

```bash
kubectl patch cronjob config-drift-detection -n fineract-dev \
  -p '{"spec": {"suspend": true}}'

# Re-enable after changes
kubectl patch cronjob config-drift-detection -n fineract-dev \
  -p '{"spec": {"suspend": false}}'
```

### Option 2: Remove Alert Secrets (Alerts won't send, but drift still logged)

```bash
kubectl delete secret slack-credentials -n fineract-dev
kubectl delete secret smtp-credentials -n fineract-dev
```

## Manual Drift Detection

Run drift detection manually:

```bash
# Get script from ConfigMap
kubectl get cm fineract-drift-detection-scripts -n fineract-dev \
  -o jsonpath='{.data.detect_drift\.py}' > detect_drift.py

# Run locally with dry-run
python3 detect_drift.py \
  --yaml-dir operations/fineract-data/data/dev \
  --fineract-url http://localhost:8080/fineract-provider/api/v1 \
  --dry-run
```

## Viewing Drift Detection History

```bash
# List recent drift detection jobs
kubectl get jobs -n fineract-dev -l job-type=monitoring

# View logs from last job
kubectl logs -n fineract-dev \
  $(kubectl get pods -n fineract-dev -l job-type=monitoring \
  --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

## Troubleshooting

### Drift detection job failing

```bash
# Check job status
kubectl describe cronjob config-drift-detection -n fineract-dev

# Check recent job pods
kubectl get pods -n fineract-dev -l app=fineract-operations

# View job logs
kubectl logs -n fineract-dev -l job-name=config-drift-detection-xxx
```

### Authentication errors

```bash
# Verify admin credentials secret exists
kubectl get secret fineract-admin-credentials -n fineract-dev

# Check OAuth2 token endpoint
kubectl get secret fineract-admin-credentials -n fineract-dev \
  -o jsonpath='{.data.token-url}' | base64 -d
```

### Alerts not sending

**Slack**:
```bash
# Verify webhook secret exists
kubectl get secret slack-credentials -n fineract-dev

# Test webhook manually
WEBHOOK_URL=$(kubectl get secret slack-credentials -n fineract-dev \
  -o jsonpath='{.data.webhook-url}' | base64 -d)
  
curl -X POST $WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text": "Test alert from drift detection"}'
```

**Email**:
```bash
# Verify SMTP credentials exist
kubectl get secret smtp-credentials -n fineract-dev

# Check SMTP configuration
kubectl get secret smtp-credentials -n fineract-dev -o yaml
```

## Related Documentation

- [Operations Guide](../../../docs/OPERATIONS_GUIDE.md)
- [Troubleshooting Guide](../../../docs/TROUBLESHOOTING_GUIDE.md)
- [Fineract Data README](../README.md)
