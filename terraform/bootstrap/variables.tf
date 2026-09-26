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

variable "enregistrements_dns" {
  description = <<-EOT
    Enregistrements DNS existants à recréer dans Route 53 (messagerie, vérifications…), sinon
    perdus lors de la délégation. nom : "" pour la racine, "mail" pour mail.<domaine>. Un seul
    élément par couple (nom, type) ; valeurs TXT sans guillemets (ajoutés par le provider).
  EOT
  type = list(object({
    nom     = string
    type    = string
    ttl     = optional(number, 3600)
    valeurs = list(string)
  }))
  default = []
}
