# AWS IAM Requirements for EKS Deployment

**Last Updated**: 2025-11-13
**Target Audience**: DevOps Engineers, System Administrators

This document outlines the minimum AWS IAM permissions required to deploy and manage the Fineract platform on Amazon EKS.

---

## Table of Contents

- [Overview](#overview)
- [Deployment IAM User/Role](#deployment-iamuserrole)
- [IRSA (IAM Roles for Service Accounts)](#irsa-iam-roles-for-service-accounts)
- [Complete IAM Policy Examples](#complete-iam-policy-examples)
- [Setup Instructions](#setup-instructions)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

The Fineract EKS deployment requires two types of IAM permissions:

1. **Deployment Permissions** - For the user/role running Terraform and kubectl
2. **Runtime Permissions (IRSA)** - For Kubernetes pods accessing AWS services

### Permission Boundary Strategy

For production environments, use:
- **Terraform User**: Admin-level permissions (can be scoped down after initial setup)
- **Application Pods**: Least-privilege via IRSA (S3, SES only)
- **EKS Add-ons**: Scoped IRSA roles (EBS CSI, Cluster Autoscaler)

---

## Deployment IAM User/Role

The user or role executing Terraform commands needs permissions to create and manage all AWS resources.

### Option 1: Administrator Access (Recommended for Initial Setup)

For initial setup and testing, use the AWS-managed `AdministratorAccess` policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
```

**Attached Policy ARN**: `arn:aws:iam::aws:policy/AdministratorAccess`

**When to use**:
- Initial EKS cluster creation
- Testing and development environments
- Simplify troubleshooting during setup

### Option 2: Scoped Permissions (Production-Ready)

For production environments, use a scoped-down policy that grants only required permissions.

#### Create Custom Policy: `FineractEKSDeployment`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSClusterManagement",
      "Effect": "Allow",
      "Action": [
        "eks:CreateCluster",
        "eks:DeleteCluster",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:UpdateClusterConfig",
        "eks:UpdateClusterVersion",
        "eks:TagResource",
        "eks:UntagResource",
        "eks:CreateNodegroup",
        "eks:DeleteNodegroup",
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "eks:UpdateNodegroupConfig",
        "eks:UpdateNodegroupVersion",
        "eks:CreateAddon",
        "eks:DeleteAddon",
        "eks:DescribeAddon",
        "eks:ListAddons",
        "eks:UpdateAddon",
        "eks:AssociateIdentityProviderConfig",
        "eks:DescribeIdentityProviderConfig",
        "eks:DisassociateIdentityProviderConfig",
        "eks:ListIdentityProviderConfigs"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2NetworkManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RDSManagement",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance",
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:DescribeDBSubnetGroups",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Management",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Route53Management",
      "Effect": "Allow",
      "Action": [
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetChange",
        "route53:ChangeTagsForResource",
        "route53:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElasticLoadBalancing",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScaling",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:CreateLaunchConfiguration",
        "autoscaling:DeleteLaunchConfiguration",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateManagement",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "arn:aws:s3:::fineract-gitops-terraform-state",
        "arn:aws:s3:::fineract-gitops-terraform-state/*",
        "arn:aws:dynamodb:us-east-2:*:table/fineract-gitops-terraform-lock"
      ]
    }
  ]
}
```

---

## IRSA (IAM Roles for Service Accounts)

IRSA allows Kubernetes pods to assume IAM roles without needing static credentials.

### 1. EBS CSI Driver Role

**Purpose**: Allows the EBS CSI driver to create and manage EBS volumes for persistent storage.

**Created by Terraform**: `terraform/aws/modules/eks/irsa.tf`

**Permissions Required**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:volume/*",
        "arn:aws:ec2:*:*:snapshot/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": [
            "CreateVolume",
            "CreateSnapshot"
          ]
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:volume/*",
        "arn:aws:ec2:*:*:snapshot/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVolume"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVolume"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/CSIVolumeName": "*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteVolume"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteVolume"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "ec2:ResourceTag/CSIVolumeName": "*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteVolume"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "ec2:ResourceTag/kubernetes.io/created-for/pvc/name": "*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
        }
      }
    }
  ]
}
```

**Trust Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### 2. Cluster Autoscaler Role

**Purpose**: Allows the Cluster Autoscaler to scale node groups up/down based on pod demand.

**Created by Terraform**: `terraform/aws/modules/eks/irsa.tf`

**Permissions Required**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true",
          "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/CLUSTER_NAME": "owned"
        }
      }
    }
  ]
}
```

**Trust Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### 3. Application Service Account Role

**Purpose**: Allows Fineract application pods to access S3 for document storage and SES for email.

**Created by Terraform**: `terraform/aws/modules/eks/irsa.tf`

**Permissions Required**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    },
    {
      "Sid": "SESAccess",
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}
```

**Trust Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:fineract-ENV:fineract-aws",
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

---

## Complete IAM Policy Examples

### Creating the Deployment User

```bash
# 1. Create IAM user
aws iam create-user --user-name fineract-deployment

# 2. Attach AdministratorAccess policy (or custom policy)
aws iam attach-user-policy \
  --user-name fineract-deployment \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 3. Create access keys
aws iam create-access-key --user-name fineract-deployment

# 4. Configure AWS CLI
aws configure --profile fineract-deployment
```

---

## Setup Instructions

### Step 1: Create Deployment User

```bash
# Option A: Use AWS Console
# 1. Go to IAM → Users → Add User
# 2. Set username: fineract-deployment
# 3. Enable programmatic access
# 4. Attach AdministratorAccess policy
# 5. Save access key and secret

# Option B: Use AWS CLI
./scripts/setup-deployment-user.sh  # (if script exists)
```

### Step 2: Configure AWS CLI

```bash
aws configure --profile fineract-deployment
# Enter access key
# Enter secret key
# Default region: us-east-2
# Default output: json
```

### Step 3: Verify Permissions

```bash
# Test permissions
aws sts get-caller-identity --profile fineract-deployment

# Should return:
# {
#   "UserId": "AIDAI...",
#   "Account": "123456789012",
#   "Arn": "arn:aws:iam::123456789012:user/fineract-deployment"
# }
```

### Step 4: Deploy with Terraform

```bash
# Use the profile
export AWS_PROFILE=fineract-deployment

# Run Terraform
cd terraform/aws
terraform init
terraform apply -var-file=environments/dev-eks.tfvars
```

---

## Security Best Practices

### 1. Use IAM Roles Instead of Users

For CI/CD pipelines, use IAM roles with AssumeRole:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:role/github-actions-role"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 2. Enable MFA for Deployment User

```bash
aws iam enable-mfa-device \
  --user-name fineract-deployment \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/fineract-deployment \
  --authentication-code-1 123456 \
  --authentication-code-2 789012
```

### 3. Rotate Access Keys Regularly

```bash
# Create new access key
aws iam create-access-key --user-name fineract-deployment

# Test new key
aws sts get-caller-identity --profile new-key

# Delete old key
aws iam delete-access-key \
  --user-name fineract-deployment \
  --access-key-id AKIAIOSFODNN7EXAMPLE
```

### 4. Use Least Privilege for IRSA

Always scope IRSA policies to specific resources:

```json
{
  "Resource": "arn:aws:s3:::fineract-prod-documents/*"  // Specific bucket
}
```

NOT:

```json
{
  "Resource": "*"  // Too broad!
}
```

### 5. Enable CloudTrail Logging

Monitor all IAM actions:

```bash
aws cloudtrail create-trail \
  --name fineract-audit \
  --s3-bucket-name fineract-cloudtrail-logs
```

---

## Troubleshooting

### Error: "User is not authorized to perform: eks:CreateCluster"

**Cause**: Insufficient IAM permissions

**Solution**:
1. Check attached policies: `aws iam list-attached-user-policies --user-name fineract-deployment`
2. Attach missing policy or use AdministratorAccess temporarily
3. Verify policy is not denied by SCP (Service Control Policy)

### Error: "An error occurred (UnauthorizedOperation) when calling the RunInstances operation"

**Cause**: Missing EC2 permissions for node group creation

**Solution**:
```bash
# Add EC2 full access temporarily
aws iam attach-user-policy \
  --user-name fineract-deployment \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

### Error: "InvalidClientTokenId: The security token included in the request is invalid"

**Cause**: Expired or invalid AWS credentials

**Solution**:
```bash
# Verify credentials
aws sts get-caller-identity

# Reconfigure if needed
aws configure --profile fineract-deployment
```

### Error: "Access Denied" when pod tries to access S3

**Cause**: IRSA not configured correctly

**Solution**:
1. Verify service account annotation: `kubectl get sa fineract-aws -n fineract-dev -o yaml`
2. Check IRSA role trust policy includes correct OIDC provider
3. Verify pod is using the service account: `kubectl get pod <pod-name> -o yaml | grep serviceAccountName`
4. Run verification script: `./scripts/verify-irsa-credentials.sh dev`

---

## Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [EKS IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Terraform AWS Provider Authentication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration)
- [EBS CSI Driver IAM Policy](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/example-iam-policy.json)

---

## Summary Checklist

- [ ] Create deployment IAM user/role with sufficient permissions
- [ ] Configure AWS CLI with credentials
- [ ] Verify permissions with `aws sts get-caller-identity`
- [ ] Run Terraform to create IRSA roles
- [ ] Verify IRSA roles exist in IAM
- [ ] Verify service accounts have correct annotations
- [ ] Test IRSA with `./scripts/verify-irsa-credentials.sh`
- [ ] Enable MFA for deployment user (production)
- [ ] Rotate access keys regularly
- [ ] Enable CloudTrail for audit logging

---

For questions or issues, see `docs/TROUBLESHOOTING_EKS.md` or contact the DevOps team.
