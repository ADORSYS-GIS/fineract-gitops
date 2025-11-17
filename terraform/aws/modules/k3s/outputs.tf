# K3s Module Outputs

output "cluster_endpoint" {
  description = "K3s API server endpoint"
  value       = "https://${aws_eip.k3s_server[0].public_ip}:6443"
}

output "cluster_token" {
  description = "K3s cluster token (sensitive)"
  value       = random_password.k3s_token.result
  sensitive   = true
}

output "server_public_ips" {
  description = "Public IPs of K3s server nodes"
  value       = aws_eip.k3s_server[*].public_ip
}

output "server_instance_ids" {
  description = "Instance IDs of K3s server nodes"
  value       = aws_instance.k3s_server[*].id
}

output "agent_instance_ids" {
  description = "Instance IDs of K3s agent nodes"
  value       = aws_instance.k3s_agent[*].id
}

output "agent_private_ips" {
  description = "Private IPs of K3s agent nodes"
  value       = aws_instance.k3s_agent[*].private_ip
}

output "security_group_id" {
  description = "Security group ID for K3s cluster"
  value       = aws_security_group.k3s.id
}

output "iam_role_name" {
  description = "IAM role name for K3s instances"
  value       = aws_iam_role.k3s.name
}

output "iam_role_arn" {
  description = "IAM role ARN for K3s instances"
  value       = aws_iam_role.k3s.arn
}

output "iam_instance_profile_name" {
  description = "IAM instance profile name for K3s instances"
  value       = aws_iam_instance_profile.k3s.name
}

output "kubeconfig" {
  description = "Kubeconfig for accessing the K3s cluster"
  value       = data.external.kubeconfig.result.kubeconfig
  sensitive   = true
}

output "ssh_command_server" {
  description = "SSH command to connect to K3s server"
  value       = "ssh ubuntu@${aws_eip.k3s_server[0].public_ip}"
}

output "kubectl_command" {
  description = "Command to use kubectl with this cluster"
  value       = "export KUBECONFIG=~/.kube/config-${var.cluster_name}-${var.environment} && kubectl get nodes"
}
