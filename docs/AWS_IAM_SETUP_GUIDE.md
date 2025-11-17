# AWS IAM User Setup Guide for Fineract Infrastructure

**Last Updated:** 2025-10-27
**Purpose:** Secure AWS access setup for Fineract infrastructure management
**Audience:** DevOps engineers, Infrastructure administrators

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create IAM User](#step-1-create-iam-user)
4. [Step 2: Attach Permissions](#step-2-attach-permissions)
5. [Step 3: Create Access Keys](#step-3-create-access-keys)
6. [Step 4: Configure AWS CLI](#step-4-configure-aws-cli)
7. [Step 5: Enable MFA (Critical)](#step-5-enable-mfa-critical)
8. [Step 6: Verify Setup](#step-6-verify-setup)
9. [Security Best Practices](#security-best-practices)
10. [Troubleshooting](#troubleshooting)
11. [Next Steps](#next-steps)

---

## Overview

### Why IAM User Instead of Root?

AWS strongly recommends **never using root account credentials** for day-to-day operations:

| Root Account | IAM User |
|--------------|----------|
| ❌ Unlimited access to everything | ✅ Limited to specific permissions |
| ❌ Cannot restrict permissions | ✅ Granular permission control |
| ❌ If compromised, full account control | ✅ Limited blast radius |
| ❌ No audit trail separation | ✅ Individual accountability |
| ❌ Cannot be rotated easily | ✅ Easy credential rotation |

**Best Practice:** Use root account only for:
- Initial account setup
- Billing management (if no IAM access)
- Account closure
- Critical account recovery

---

## Prerequisites

Before you begin:

- ✅ AWS account created
- ✅ Root account email and password
- ✅ MFA device (smartphone with authenticator app)
- ✅ Secure password manager (1Password, LastPass, Bitwarden, etc.)
- ✅ AWS CLI installed on your machine
  ```bash
  # Verify installation
  aws --version
  # Should show: aws-cli/2.x.x or higher
  ```

---

## Step 1: Create IAM User

### 1.1 Access IAM Console

1. Log into AWS Console with root account
2. Go to **IAM** (search "IAM" in top search bar)
3. Click **Users** in left sidebar
4. Click **Create user** button

### 1.2 Configure User Details

**User name:** `fineract-infra-admin` (or your preferred name)

**AWS access type options:**
- ✅ **Provide user access to the AWS Management Console** - Optional but recommended
  - Allows login to AWS Console with this user
  - Choose **"I want to create an IAM user"**
  - Set custom password or auto-generate
  - Uncheck "User must create a new password at next sign-in" (optional)

**Click "Next"**

---

## Step 2: Attach Permissions

### 2.1 Choose Permission Type

Select: **"Attach policies directly"**

### 2.2 Required AWS Managed Policies

Search and select the following policies:

#### **Core Infrastructure Policies (Required)**

| Policy Name | Purpose | What It Controls |
|-------------|---------|------------------|
| ✅ **AmazonRDSFullAccess** | PostgreSQL Database | - Create/delete RDS instances<br>- Manage read replicas<br>- Create snapshots<br>- Modify instance settings |
| ✅ **AmazonElastiCacheFullAccess** | Redis Cache | - Create/delete ElastiCache clusters<br>- Manage Redis nodes<br>- Configure replication<br>- Modify cache parameters |
| ✅ **AmazonS3FullAccess** | Object Storage | - Create/delete S3 buckets<br>- Upload/download files<br>- Configure bucket policies<br>- Manage versioning |
| ✅ **AmazonVPCFullAccess** | Networking | - Create VPCs and subnets<br>- Configure security groups<br>- Manage route tables<br>- Set up NAT gateways |
| ✅ **SecretsManagerReadWrite** | Credentials Storage | - Create/read secrets<br>- Store database passwords<br>- Manage secret rotation |

#### **Self-Service Policies (Recommended)**

| Policy Name | Purpose |
|-------------|---------|
| ✅ **IAMUserChangePassword** | Allow user to change own password |
| ✅ **IAMUserSSHKeys** | Manage own SSH keys (optional) |

#### **Optional Policies (Add if Needed)**

| Policy Name | When to Add |
|-------------|-------------|
| **AmazonEKSClusterPolicy** | If using AWS EKS for Kubernetes |
| **AmazonEC2FullAccess** | If creating EC2 instances directly |
| **CloudWatchLogsFullAccess** | For comprehensive monitoring and logging |
| **AWSKeyManagementServicePowerUser** | If using AWS KMS for encryption |
| **AmazonRoute53FullAccess** | If managing DNS records |

### 2.3 Review Permissions

**Total policies for Fineract infrastructure:** 5-6 core policies

**Click "Next"**

---

## Step 3: Create Access Keys

### 3.1 Review and Create User

1. **Review** all settings on the final page
2. **Add tags** (recommended for organization):
   ```
   Key: Project          Value: Fineract
   Key: Environment      Value: Development
   Key: ManagedBy        Value: YourName
   Key: Purpose          Value: Infrastructure Management
   ```
3. **Click "Create user"**

### 3.2 Generate Access Keys

After user creation:

1. **Click on the user name** (`fineract-infra-admin`)
2. Go to **"Security credentials"** tab
3. Scroll to **"Access keys"** section
4. Click **"Create access key"**

### 3.3 Select Use Case

**Choose:** "Command Line Interface (CLI)"
- ✅ Check "I understand the above recommendation and want to proceed to create an access key"
- Click **"Next"**

### 3.4 Add Description (Optional but Recommended)

**Description tag:**
```
Fineract infrastructure management from local development machine - Created 2025-10-27
```

Click **"Create access key"**

### 3.5 Save Credentials Securely ⚠️

**CRITICAL STEP - Read Carefully:**

You will see:
- **Access key ID:** AKIAIOSFODNN7EXAMPLE
- **Secret access key:** wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

**You MUST do ALL of the following:**

1. ✅ **Copy Access Key ID** to password manager
2. ✅ **Click "Show"** on Secret Access Key
3. ✅ **Copy Secret Access Key** to password manager
4. ✅ **Download .csv file** as backup
5. ✅ Store .csv file in secure location (encrypted drive)

⚠️ **WARNING:** You can NEVER retrieve the secret access key again! If you lose it, you must create a new access key.

**Click "Done"**

---

## Step 4: Configure AWS CLI

### 4.1 Open Terminal

On your local machine, open terminal or command prompt.

### 4.2 Run AWS Configure

```bash
aws configure
```

You'll be prompted for 4 values:

### 4.3 Enter Configuration

```bash
AWS Access Key ID [None]: <paste your Access Key ID>
# Example: AKIAIOSFODNN7EXAMPLE

AWS Secret Access Key [None]: <paste your Secret Access Key>
# Example: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

Default region name [None]: us-east-2
# Choose your region:
# - us-east-2 (N. Virginia) - Default
# - us-west-2 (Oregon)
# - eu-west-1 (Ireland)
# - ap-southeast-1 (Singapore)
# - See: https://aws.amazon.com/about-aws/global-infrastructure/regions_az/

Default output format [None]: json
# Options: json, yaml, text, table
# Recommended: json
```

### 4.4 Verify Configuration

```bash
# Check configuration
aws configure list

# Should show:
#       Name                    Value             Type    Location
#       ----                    -----             ----    --------
#    profile                <not set>             None    None
# access_key     ****************MPLE shared-credentials-file
# secret_key     ****************MPLE shared-credentials-file
#     region                us-east-2      config-file    ~/.aws/config
```

### 4.5 Configuration Files

Your credentials are stored in:
- **Credentials:** `~/.aws/credentials` (DO NOT commit to git!)
- **Config:** `~/.aws/config`

**Add to .gitignore:**
```bash
# In your project .gitignore
.aws/credentials
.aws/config
*.pem
*.key
.env
```

---

## Step 5: Enable MFA (Critical) 🔐

### Why MFA is Critical

Even if someone steals your access keys, they cannot access your account without your MFA device.

### 5.1 Install Authenticator App

**Recommended apps:**
- Google Authenticator (iOS/Android)
- Authy (iOS/Android/Desktop)
- Microsoft Authenticator (iOS/Android)
- 1Password (if you use 1Password)

### 5.2 Enable MFA in IAM Console

1. Go to **IAM Console** → **Users** → `fineract-infra-admin`
2. Click **"Security credentials"** tab
3. Scroll to **"Multi-factor authentication (MFA)"** section
4. Click **"Assign MFA device"**

### 5.3 Configure MFA

1. **Device name:** `my-phone` or `personal-device`
2. **MFA device type:** Choose **"Authenticator app"**
3. Click **"Next"**

### 5.4 Scan QR Code

1. **Show QR code** appears
2. **Open authenticator app** on your phone
3. **Scan QR code** with the app
4. **Secret configuration key** also shown (save as backup in password manager)

### 5.5 Enter MFA Codes

1. Authenticator app will show 6-digit codes that change every 30 seconds
2. **Enter first MFA code** (wait for it to refresh)
3. **Enter second MFA code** (the next code that appears)
4. Click **"Add MFA"**

### 5.6 Verify MFA is Active

You should see:
```
✅ Assigned MFA device: arn:aws:iam::123456789012:mfa/fineract-infra-admin
```

### 5.7 Also Enable MFA on Root Account! 🚨

**CRITICAL:** Don't forget to enable MFA on your root account too:

1. Log out of IAM user
2. Log in as root
3. Go to **Security Credentials** (top-right corner menu)
4. Enable MFA for root account
5. Log out

---

## Step 6: Verify Setup

### 6.1 Test Authentication

```bash
# Test 1: Get caller identity
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/fineract-infra-admin"
}
```

✅ If you see your user ARN, authentication is working!

### 6.2 Test Service Access

```bash
# Test 2: List S3 buckets (should work even if empty)
aws s3 ls

# Test 3: List RDS instances (should work even if empty)
aws rds describe-db-instances

# Test 4: List ElastiCache clusters (should work even if empty)
aws elasticache describe-cache-clusters

# Test 5: List VPCs
aws ec2 describe-vpcs
```

### 6.3 Test Secrets Manager

```bash
# Test creating a secret
aws secretsmanager create-secret \
  --name test-secret-delete-me \
  --secret-string "test-value"

# Verify it was created
aws secretsmanager list-secrets

# Delete the test secret
aws secretsmanager delete-secret \
  --secret-id test-secret-delete-me \
  --force-delete-without-recovery
```

### 6.4 Verify Region

```bash
# Check which region you're using
aws configure get region

# List all available regions
aws ec2 describe-regions --output table
```

---

## Security Best Practices

### ✅ Security Checklist

After completing all steps above, verify:

- [ ] ✅ IAM user created (not using root)
- [ ] ✅ Only required permissions attached (principle of least privilege)
- [ ] ✅ MFA enabled on IAM user
- [ ] ✅ MFA enabled on root account
- [ ] ✅ Access keys stored in password manager
- [ ] ✅ Access keys NOT in .aws/credentials committed to git
- [ ] ✅ .gitignore updated with `.aws/credentials`
- [ ] ✅ Root account login credentials stored securely
- [ ] ✅ Root access keys NOT created
- [ ] ✅ Tags added to IAM user for tracking
- [ ] ✅ Authenticator app backup codes saved

### 🔒 Ongoing Security Practices

#### 1. Rotate Access Keys Every 90 Days

```bash
# Create new access key (you can have max 2)
aws iam create-access-key --user-name fineract-infra-admin

# Update ~/.aws/credentials with new key
aws configure

# Test new key works
aws sts get-caller-identity

# Delete old access key
aws iam delete-access-key \
  --user-name fineract-infra-admin \
  --access-key-id <OLD_ACCESS_KEY_ID>
```

#### 2. Review IAM User Activity

```bash
# Check when access keys were last used
aws iam get-access-key-last-used --access-key-id <YOUR_ACCESS_KEY_ID>

# Review user activity in CloudTrail (if enabled)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=fineract-infra-admin
```

#### 3. Enable CloudTrail for Audit Logging

```bash
# Create S3 bucket for logs
aws s3 mb s3://fineract-cloudtrail-logs-$(aws sts get-caller-identity --query Account --output text)

# Create CloudTrail
aws cloudtrail create-trail \
  --name fineract-audit-trail \
  --s3-bucket-name fineract-cloudtrail-logs-$(aws sts get-caller-identity --query Account --output text)

# Start logging
aws cloudtrail start-logging --name fineract-audit-trail
```

#### 4. Use AWS Secrets Manager for Application Credentials

**Never hardcode credentials!**

```bash
# Store database password
aws secretsmanager create-secret \
  --name fineract/dev/db-password \
  --secret-string "your-secure-password-here"

# Retrieve in application
aws secretsmanager get-secret-value \
  --secret-id fineract/dev/db-password \
  --query SecretString \
  --output text
```

#### 5. Monitor Costs

```bash
# Check current month costs
aws ce get-cost-and-usage \
  --time-period Start=2025-10-01,End=2025-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost

# Set up billing alerts in AWS Console:
# Billing Dashboard → Billing preferences → Enable alerts
```

---

## Troubleshooting

### Issue 1: "Unable to locate credentials"

**Symptom:**
```bash
$ aws s3 ls
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**Solution:**
```bash
# Re-run configuration
aws configure

# Verify credentials file exists
cat ~/.aws/credentials

# Check permissions
ls -la ~/.aws/
```

---

### Issue 2: "Access Denied" or "UnauthorizedOperation"

**Symptom:**
```bash
$ aws rds describe-db-instances
An error occurred (AccessDenied) when calling the DescribeDBInstances operation
```

**Solution:**
1. Verify IAM user has the correct policy attached
2. Check in IAM Console → Users → fineract-infra-admin → Permissions
3. Ensure `AmazonRDSFullAccess` is attached
4. Wait 1-2 minutes for permissions to propagate

---

### Issue 3: MFA Code Not Working

**Symptom:**
```
Invalid MFA code
```

**Solutions:**
- Ensure phone time is synchronized (Settings → Date & Time → Automatic)
- Wait for code to refresh and try again
- Use the backup codes saved during MFA setup
- Re-sync authenticator app

---

### Issue 4: Wrong Region

**Symptom:**
Resources not showing up, but commands work.

**Solution:**
```bash
# Check current region
aws configure get region

# Change region
aws configure set region us-east-2

# Or specify region in command
aws s3 ls --region eu-west-1
```

---

### Issue 5: Access Key Limit Reached

**Symptom:**
```
LimitExceeded: Cannot exceed quota for AccessKeysPerUser: 2
```

**Solution:**
```bash
# List existing access keys
aws iam list-access-keys --user-name fineract-infra-admin

# Delete old/unused access key
aws iam delete-access-key \
  --user-name fineract-infra-admin \
  --access-key-id <OLD_ACCESS_KEY_ID>

# Create new access key
aws iam create-access-key --user-name fineract-infra-admin
```

---

## Next Steps

Now that AWS CLI is configured, you can:

### 1. **Verify Existing Resources**

```bash
# Check what already exists in your account
aws rds describe-db-instances --output table
aws elasticache describe-cache-clusters --output table
aws s3 ls
aws ec2 describe-vpcs --output table
```

### 2. **Create Fineract Infrastructure**

Choose your approach:

#### Option A: Use Terraform (Recommended)
```bash
cd infrastructure/terraform/aws
terraform init
terraform plan
terraform apply
```

See: [AWS Terraform Documentation](../infrastructure/terraform/aws/README.md)

#### Option B: Manual AWS CLI Commands

Follow guides in `docs/` directory:
- Create RDS PostgreSQL instance
- Create ElastiCache Redis cluster
- Create S3 buckets
- Configure VPC and security groups

### 3. **Deploy Fineract to Kubernetes**

Once AWS resources are provisioned:

```bash
# Deploy dev-aws environment
kubectl apply -k environments/dev-aws/

# Verify deployment
kubectl get pods -n fineract-dev
kubectl get svc -n fineract-dev
```

See: [Deployment Documentation](./MIFOS_WEB_APP_SETUP.md)

### 4. **Configure Secrets in Kubernetes**

Create Kubernetes secrets with AWS resource connection details:

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier fineract-dev-postgres \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Create secret
kubectl create secret generic fineract-db-credentials \
  --from-literal=host=$RDS_ENDPOINT \
  --from-literal=username=fineract \
  --from-literal=password=<your-password> \
  -n fineract-dev
```

---

## Additional Resources

### AWS Documentation
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [MFA for AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html)

### Project Documentation
- [Mifos Web App Setup](./MIFOS_WEB_APP_SETUP.md)
- [Mifos Implementation Summary](./MIFOS_WEB_APP_IMPLEMENTATION_SUMMARY.md)
- [Keycloak Configuration](../operations/keycloak-config/README.md)

### Security Resources
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [OWASP Cloud Security](https://owasp.org/www-project-cloud-security/)

---

## Support

For issues or questions:
- **AWS Issues:** AWS Support Console
- **Fineract Issues:** GitHub Issues
- **Internal Team:** Contact DevOps team

---

**Document Version:** 1.0
**Last Updated:** 2025-10-27
**Maintained By:** DevOps Team
