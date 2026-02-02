output "zone_name" {
  description = "DNS zone name"
  value       = length(google_dns_managed_zone.main) > 0 ? google_dns_managed_zone.main[0].name : null
}

output "name_servers" {
  description = "DNS nameservers"
  value       = length(google_dns_managed_zone.main) > 0 ? google_dns_managed_zone.main[0].name_servers : []
}
