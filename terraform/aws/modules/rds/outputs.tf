output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.fineract.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.fineract.arn
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.fineract.endpoint
}

output "db_instance_address" {
  description = "RDS instance address"
  value       = aws_db_instance.fineract.address
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.fineract.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.fineract.db_name
}

output "master_username" {
  description = "Master username"
  value       = aws_db_instance.fineract.username
  sensitive   = true
}

output "master_password" {
  description = "Master password"
  value       = random_password.master.result
  sensitive   = true
}

output "jdbc_url" {
  description = "JDBC connection URL"
  value       = "jdbc:postgresql://${aws_db_instance.fineract.endpoint}/${aws_db_instance.fineract.db_name}"
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.fineract.name
}

output "keycloak_db_username" {
  description = "Keycloak database username"
  value       = "keycloak"
}

output "keycloak_db_password" {
  description = "Keycloak database password"
  value       = random_password.keycloak.result
  sensitive   = true
}

output "keycloak_jdbc_url" {
  description = "JDBC connection URL for Keycloak"
  value       = "jdbc:postgresql://${aws_db_instance.fineract.endpoint}/keycloak"
  sensitive   = true
}
