variable "region" {
  description = "Région AWS (Paris)."
  type        = string
  default     = "eu-west-3"
}

variable "environnement" {
  description = "Nom de l'environnement (préfixe des ressources et des paramètres SSM)."
  type        = string
  default     = "prod"
}

variable "type_instance" {
  description = "Type EC2 : t3.large (8 Go) recommandé ; t3.medium (4 Go) possible, plus lent."
  type        = string
  default     = "t3.large"
}

variable "taille_disque_go" {
  type    = number
  default = 30
}

variable "domaine" {
  description = <<-EOT
    Nom de domaine (ex. logiflow.exemple.fr) : l'application sera servie sur app.<domaine> et
    auth.<domaine> (enregistrements DNS A à créer vers l'IP de sortie « ip_publique »).
    Vide : domaines gratuits sslip.io dérivés de l'IP.
  EOT
  type        = string
  default     = ""
}

variable "donnees_demo" {
  description = "Charger le jeu de démonstration et créer les 6 comptes de démo (un par rôle)."
  type        = bool
  default     = true
}

variable "mfa_obligatoire" {
  description = "Le backend exige une preuve OTP dans les jetons (comptes configurés avec OTP)."
  type        = bool
  default     = false
}

variable "llm_api_key" {
  description = "Clé du fournisseur LLM (Groq). Facultatif ici : se renseigne aussi avec `make secret-llm`."
  type        = string
  default     = ""
  sensitive   = true
}

variable "email_alertes" {
  description = "E-mail destinataire des alertes de budget."
  type        = string
}

variable "budget_mensuel_usd" {
  type    = number
  default = 30
}

variable "arret_automatique" {
  description = "Arrêter le serveur chaque soir pour économiser les crédits."
  type        = bool
  default     = true
}

variable "cron_arret" {
  description = "Heure d'arrêt (heure de Paris), au format EventBridge Scheduler."
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "demarrage_automatique" {
  description = "Démarrer le serveur à 8 h les jours ouvrés."
  type        = bool
  default     = false
}

variable "retention_sauvegardes_jours" {
  type    = number
  default = 14
}
