# K3s Module Variables

variable "cluster_name" {
  description = "Name of the K3s cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where K3s cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for K3s instances (use public subnets)"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for K3s nodes"
  type        = string
  default     = "t3.medium" # x86, 2 vCPU, 4GB RAM (8GB needed for dev, will override)
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 30
}

variable "k3s_version" {
  description = "K3s version to install"
  type        = string
  default     = "v1.28.5+k3s1"
}

variable "high_availability" {
  description = "Enable high availability (2 server nodes instead of 1)"
  type        = bool
  default     = false
}

variable "agent_count" {
  description = "Number of agent (worker) nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.agent_count >= 1 && var.agent_count <= 10
    error_message = "Agent count must be between 1 and 10."
  }
}

variable "api_access_cidrs" {
  description = "CIDR blocks allowed to access K3s API (kubectl)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Open to world. Restrict in production!
}

variable "ssh_access_cidrs" {
  description = "CIDR blocks allowed SSH access to K3s nodes"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Open to world. Restrict in production!
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair to use for EC2 instances"
  type        = string
  default     = null
}

variable "additional_security_group_ids" {
  description = "Additional security groups to attach to K3s instances"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
