output "bucket_etat" {
  description = "Bucket de l'état Terraform (à reporter dans environments/prod/backend.hcl)."
  value       = aws_s3_bucket.etat.bucket
}

output "role_github_terraform" {
  description = "ARN à enregistrer dans la variable GitHub AWS_ROLE_TERRAFORM."
  value       = aws_iam_role.github_terraform.arn
}

output "role_github_deploiement" {
  description = "ARN à enregistrer dans la variable GitHub AWS_ROLE_DEPLOIEMENT."
  value       = aws_iam_role.github_deploiement.arn
}

output "serveurs_de_noms" {
  description = "Serveurs de noms Route 53 à déclarer chez le registraire (Namecheap : Custom DNS)."
  value       = var.domaine != "" ? aws_route53_zone.principale[0].name_servers : []
}
