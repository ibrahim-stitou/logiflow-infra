variable "aws_region" {
  description = "Région AWS où créer le bucket S3 et la table DynamoDB de state."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Préfixe de nommage des ressources (bucket, table de lock)."
  type        = string
  default     = "logiflow"
}

variable "github_repository" {
  description = "Dépôt GitHub autorisé à assumer le rôle OIDC Terraform, au format owner/repo."
  type        = string
  default     = "ibrahim-stitou/logiflow-infra"
}
