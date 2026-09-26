output "instance_id" {
  description = "Identifiant de l'instance (commandes SSM, démarrage/arrêt)."
  value       = module.serveur.instance_id
}

output "ip_publique" {
  description = "IP publique fixe (Elastic IP)."
  value       = module.serveur.ip_publique
}

output "url_application" {
  value = "https://${local.app_domain}"
}

output "url_keycloak" {
  description = "Console d'administration : <url>/admin"
  value       = "https://${local.auth_domain}"
}

output "prefixe_ssm" {
  value = local.prefixe
}

output "bucket_sauvegardes" {
  value = module.sauvegardes.bucket_sauvegardes
}

output "bucket_transferts" {
  description = "Bucket utilisé par le connecteur Ansible aws_ssm."
  value       = module.sauvegardes.bucket_transferts
}

output "region" {
  value = var.region
}

output "enregistrements_dns" {
  description = "Noms publiés dans Route 53 (vide avec sslip.io)."
  value       = local.domaine_propre ? module.dns[0].enregistrements : []
}
