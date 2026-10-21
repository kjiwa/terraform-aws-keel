output "zone_ids" {
  description = "Map of domain name to Route53 zone ID."
  value       = { for k, z in aws_route53_zone.this : k => z.zone_id }
}

output "ns_records" {
  description = "Map of domain name to list of NS record values. Update registrar for all domains."
  value       = { for k, z in aws_route53_zone.this : k => z.name_servers }
}

output "ds_records" {
  description = "Map of domain name to DS record string (paste into registrar). Only present for DNSSEC-enabled domains."
  value       = { for k, ksk in aws_route53_key_signing_key.this : k => ksk.ds_record }
}
