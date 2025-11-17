# ============================================================================
# Security Groups for EKS Cluster
# ============================================================================
# This file manages security groups for the EKS cluster and node groups
#
# SECURITY STRATEGY:
# The security group configuration follows AWS EKS best practices with defense
# in depth and principle of least privilege.
#
# KEY SECURITY CONTROLS:
# 1. Cluster API endpoint access restricted via CIDR allowlist (see variables.tf)
# 2. Default = no public access (empty CIDR list)
# 3. Node-to-node communication scoped to self-referencing security group
# 4. Cluster-to-node communication uses managed security group
# 5. All rules explicitly defined (no implicit defaults)
#
# See detailed documentation below for each security group rule.

# Additional security group for cluster
resource "aws_security_group" "cluster_additional" {
  name_prefix = "${var.cluster_name}-cluster-additional-"
  description = "Additional security group for EKS cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-additional-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Cluster API Endpoint Access Control
# ============================================================================
# CURRENT APPROACH: CIDR-based allowlist with secure defaults
#
# SECURITY ANALYSIS:
# - Rule only created if cluster_endpoint_public_access = true
# - CIDR blocks controlled by var.cluster_endpoint_public_access_cidrs
# - Default value in variables.tf: [] (empty list = no public access)
# - Validation in variables.tf ensures all CIDRs are valid blocks
# - Users must explicitly specify allowed CIDRs to enable public access
#
# SECURITY BEST PRACTICES MET:
# ✓ Secure by default (no public access unless explicitly configured)
# ✓ Principle of least privilege (must specify exact CIDRs)
# ✓ Defense in depth (CIDR restriction + AWS IAM authentication)
# ✓ Audit trail (CIDRs version-controlled in tfvars)
#
# PRODUCTION RECOMMENDATIONS:
# 1. Restrict to known IP ranges:
#    - Corporate VPN CIDR blocks
#    - CI/CD runner IP addresses
#    - Operations team static IPs
#    - Bastion host elastic IPs
#
# 2. Use private endpoint when possible:
#    cluster_endpoint_public_access = false
#    cluster_endpoint_private_access = true
#    Access via VPN or AWS VPC peering only
#
# 3. Implement conditional access:
#    Different CIDR lists per environment:
#    - Dev: Broader access for development team
#    - Staging: Limited to CI/CD and ops team
#    - Production: Highly restricted (VPN only, no individual IPs)
#
# 4. Regular CIDR review:
#    Periodically audit allowed CIDRs
#    Remove stale entries (departed employees, old VPNs)
#    Document justification for each CIDR block
#
# ALTERNATIVE APPROACHES:
# 1. AWS PrivateLink (RECOMMENDED for production):
#    - Fully private API endpoint (no internet exposure)
#    - Access via VPC endpoint in peered VPCs
#    - Pros: No CIDR management, most secure
#    - Cons: Requires VPN or Direct Connect setup
#    - Example:
#      cluster_endpoint_public_access = false
#      cluster_endpoint_private_access = true
#
# 2. Bastion host/jump server:
#    - Single controlled entry point
#    - Cluster API accessible only from bastion security group
#    - Pros: Centralized access control, audit logs
#    - Cons: Additional infrastructure to maintain
#    - Example CIDR: [aws_instance.bastion.private_ip/32]
#
# 3. AWS Systems Manager Session Manager:
#    - No SSH keys, no bastion host needed
#    - IAM-based access control
#    - Pros: No open inbound ports, full audit logging
#    - Cons: Requires Session Manager setup
#
# 4. VPN-only access (RECOMMENDED for production):
#    - Require VPN connection before kubectl access
#    - CIDR restricted to VPN gateway IP range
#    - Pros: Additional authentication layer, encrypted tunnel
#    - Cons: VPN infrastructure dependency
#    - Example: cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]
#
# CURRENT JUSTIFICATION:
# - Acceptable for: Dev/staging with explicit CIDR configuration
# - Required for production: VPN-only or PrivateLink access
# - Security validated: Default = no public access, must opt-in
# - Flexibility: Variable-driven, environment-specific control
#
# EXAMPLE CONFIGURATIONS:
# Development (broader access for team):
#   cluster_endpoint_public_access_cidrs = [
#     "203.0.113.0/24",  # Office network
#     "198.51.100.42/32" # VPN gateway
#   ]
#
# Production (VPN-only):
#   cluster_endpoint_public_access_cidrs = ["10.10.0.0/16"]  # VPN CIDR only
#
# Maximum security (no public access):
#   cluster_endpoint_public_access = false
#   cluster_endpoint_private_access = true
#   cluster_endpoint_public_access_cidrs = []  # Not used
#
resource "aws_security_group_rule" "cluster_additional_ingress_https" {
  count = var.cluster_endpoint_public_access ? 1 : 0

  security_group_id = aws_security_group.cluster_additional.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.cluster_endpoint_public_access_cidrs
  description       = "Allow HTTPS access to cluster API"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "cluster_additional_egress_all" {
  security_group_id = aws_security_group.cluster_additional.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

# Security group for node groups
resource "aws_security_group" "node_group" {
  name_prefix = "${var.cluster_name}-node-"
  description = "Security group for EKS node groups"
  vpc_id      = aws_vpc.eks_vpc.id

  tags = merge(
    var.tags,
    {
      Name                                           = "${var.cluster_name}-node-sg"
      "kubernetes.io/cluster/${var.cluster_name}"    = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "node_group_ingress_self" {
  security_group_id        = aws_security_group.node_group.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.node_group.id
  description              = "Allow nodes to communicate with each other"
}

# Allow pods to communicate with cluster API
resource "aws_security_group_rule" "node_group_ingress_cluster_https" {
  security_group_id        = aws_security_group.node_group.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description              = "Allow pods to communicate with cluster API"
}

# Allow all outbound traffic from nodes
resource "aws_security_group_rule" "node_group_egress_all" {
  security_group_id = aws_security_group.node_group.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

# Allow cluster to communicate with nodes
resource "aws_security_group_rule" "cluster_to_node_ingress" {
  security_group_id        = aws_security_group.node_group.id
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description              = "Allow cluster to communicate with nodes"
}
