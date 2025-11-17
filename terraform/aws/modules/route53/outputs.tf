# Route53 Module Outputs

output "zone_id" {
  description = "The hosted zone ID"
  value       = try(aws_route53_zone.main[0].zone_id, "")
}

output "name_servers" {
  description = "List of name servers for the hosted zone"
  value       = try(aws_route53_zone.main[0].name_servers, [])
}

output "zone_arn" {
  description = "The ARN of the hosted zone"
  value       = try(aws_route53_zone.main[0].arn, "")
}
