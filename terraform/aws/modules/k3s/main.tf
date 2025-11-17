# K3s Module - Lightweight Kubernetes on EC2
# Replaces EKS to save $72/month control plane cost
# Uses ARM Graviton (t4g) instances for additional 20% cost savings

locals {
  k3s_server_count = var.high_availability ? 2 : 1
  k3s_agent_count  = var.agent_count
}

# Get latest Ubuntu AMI (supports both ARM and x86)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]  # Changed from arm64 to amd64 for x86 instances
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for K3s Cluster
resource "aws_security_group" "k3s" {
  name        = "${var.cluster_name}-${var.environment}-k3s"
  description = "Security group for K3s cluster nodes"
  vpc_id      = var.vpc_id

  # K3s API Server (kubectl access)
  ingress {
    description = "K3s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.api_access_cidrs
  }

  # SSH access (for debugging)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_access_cidrs
  }

  # HTTP access (required for Let's Encrypt ACME challenge)
  ingress {
    description = "HTTP (Lets Encrypt ACME challenge)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access (secure web traffic)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic within cluster
  ingress {
    description = "Intra-cluster communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Intra-cluster UDP"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-k3s-sg"
    }
  )
}

# IAM Role for K3s instances
resource "aws_iam_role" "k3s" {
  name = "${var.cluster_name}-${var.environment}-k3s-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Attach policies for AWS services access
resource "aws_iam_role_policy_attachment" "k3s_ssm" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "k3s_ecr" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Custom policy for RDS and S3 access (will be attached by IAM module)
resource "aws_iam_instance_profile" "k3s" {
  name = "${var.cluster_name}-${var.environment}-k3s-profile"
  role = aws_iam_role.k3s.name

  tags = var.tags
}

# Elastic IP for K3s server (stable API endpoint)
resource "aws_eip" "k3s_server" {
  count = local.k3s_server_count

  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-k3s-server-${count.index + 1}"
    }
  )
}

# Associate EIP with server instance
resource "aws_eip_association" "k3s_server" {
  count = local.k3s_server_count

  instance_id   = aws_instance.k3s_server[count.index].id
  allocation_id = aws_eip.k3s_server[count.index].id
}

# K3s Server Instances (Control Plane)
resource "aws_instance" "k3s_server" {
  count = local.k3s_server_count

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name

  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = concat([aws_security_group.k3s.id], var.additional_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.k3s.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data-server.sh", {
    cluster_name    = var.cluster_name
    k3s_version     = var.k3s_version
    k3s_token       = random_password.k3s_token.result
    is_first_server = count.index == 0
    server_url      = count.index == 0 ? "" : "https://${aws_eip.k3s_server[0].public_ip}:6443"
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-k3s-server-${count.index + 1}"
      Role = "server"
      Type = "control-plane"
    }
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# K3s Agent Instances (Worker Nodes)
resource "aws_instance" "k3s_agent" {
  count = local.k3s_agent_count

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name

  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = concat([aws_security_group.k3s.id], var.additional_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.k3s.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data-agent.sh", {
    cluster_name = var.cluster_name
    k3s_version  = var.k3s_version
    k3s_token    = random_password.k3s_token.result
    server_url   = "https://${aws_eip.k3s_server[0].public_ip}:6443"
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-k3s-agent-${count.index + 1}"
      Role = "agent"
      Type = "worker"
    }
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_instance.k3s_server]
}

# Random token for K3s cluster
resource "random_password" "k3s_token" {
  length  = 32
  special = false
}

# Kubeconfig generation
data "external" "kubeconfig" {
  program = ["bash", "${path.module}/get-kubeconfig.sh"]

  query = {
    server_ip    = aws_eip.k3s_server[0].public_ip
    k3s_token    = random_password.k3s_token.result
    cluster_name = "${var.cluster_name}-${var.environment}"
  }

  depends_on = [aws_instance.k3s_server]
}
