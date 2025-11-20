# Changelog - EKS Module

All notable changes to the EKS Terraform module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-20

### Added
- Initial versioned release of EKS module
- EKS cluster provisioning with managed node groups
- VPC creation with public/private subnets
- Security groups configuration
- IRSA (IAM Roles for Service Accounts) support
- Cluster autoscaler IAM configuration
- KMS encryption support
- CloudWatch logging configuration

### Features
- **Cluster Version**: Configurable EKS version
- **Node Groups**: Managed node groups with auto-scaling
- **Networking**: Custom VPC with NAT gateways
- **Security**: Security groups for nodes and pods
- **IAM**: Service account IAM roles (IRSA)
- **Monitoring**: CloudWatch logs integration

### Module Outputs
- `cluster_id`: EKS cluster ID
- `cluster_endpoint`: EKS cluster API endpoint
- `cluster_security_group_id`: Cluster security group ID
- `node_security_group_id`: Node security group ID
- `vpc_id`: VPC ID
- `private_subnet_ids`: Private subnet IDs
- `public_subnet_ids`: Public subnet IDs

### Git Tag
`modules/terraform/aws/eks/v1.0.0`

---

## Versioning Strategy

This module uses **Git tags** for versioning:
- Tags follow the format: `modules/terraform/aws/eks/vX.Y.Z`
- Semantic versioning (MAJOR.MINOR.PATCH)
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes (backward compatible)

## Usage

The EKS module is currently used with **local paths** in the monorepo:

```hcl
module "eks" {
  source = "./modules/eks"
  # ...
}
```

For external repositories, reference via Git tag:

```hcl
module "eks" {
  source = "git::https://github.com/your-org/fineract-gitops.git//terraform/aws/modules/eks?ref=modules/terraform/aws/eks/v1.0.0"
  # ...
}
```

---

[1.0.0]: https://github.com/your-org/fineract-gitops/releases/tag/modules/terraform/aws/eks/v1.0.0
