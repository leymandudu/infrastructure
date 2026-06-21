output "hosted_zone_id" {
  description = "Route 53 hosted zone ID for yusmojsolutions.com"
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "Name servers to configure at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}
