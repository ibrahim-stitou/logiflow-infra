variable "region" {
  description = "Région AWS du projet."
  type        = string
  default     = "eu-west-3"
}

variable "github_owner" {
  description = "Propriétaire GitHub du dépôt logiflow-infra (utilisateur ou organisation)."
  type        = string
  default     = "ibrahim-stitou"
}

variable "github_depot_infra" {
  description = "Nom du dépôt d'infrastructure autorisé à assumer les rôles."
  type        = string
  default     = "logiflow-infra"
}
