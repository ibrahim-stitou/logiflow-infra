variable "nom" {
  type = string
}

variable "instance_id" {
  type = string
}

variable "instance_arn" {
  type = string
}

variable "budget_mensuel_usd" {
  description = "Budget mensuel (USD) déclenchant les alertes à 50, 80 et 100 %."
  type        = number
  default     = 30
}

variable "email_alertes" {
  description = "Adresse qui reçoit les alertes de budget."
  type        = string
}

variable "arret_automatique" {
  type    = bool
  default = true
}

variable "cron_arret" {
  description = "Heure d'arrêt automatique (heure de Paris)."
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "demarrage_automatique" {
  description = "Démarrer automatiquement le matin des jours ouvrés (désactivé par défaut)."
  type        = bool
  default     = false
}

variable "cron_demarrage" {
  type    = string
  default = "cron(0 8 ? * MON-FRI *)"
}
