output "zone_id" {
  value = data.aws_route53_zone.principale.zone_id
}

output "enregistrements" {
  description = "Noms publiés dans la zone."
  value       = [for r in aws_route53_record.serveur : r.fqdn]
}
