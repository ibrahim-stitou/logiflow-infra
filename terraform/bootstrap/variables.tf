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

variable "domaine" {
  description = <<-EOT
    Domaine acheté chez un registraire (ex. logiflow.ma), géré par Route 53 : une zone publique est
    créée, ses serveurs de noms (sortie « serveurs_de_noms ») sont à déclarer chez le registraire.
    Vide : pas de zone (domaines gratuits sslip.io).
  EOT
  type        = string
  default     = ""
}
