variable "nom" {
  description = "Préfixe des ressources (ex. logiflow-prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC dont les flux réseau sont journalisés."
  type        = string
}

variable "email_alertes" {
  description = "Destinataire des alertes de sécurité (abonnement SNS à confirmer par e-mail)."
  type        = string
}

variable "activer_guardduty" {
  description = "Créer le détecteur GuardDuty (false s'il est déjà activé dans le compte et la région)."
  type        = bool
  default     = true
}

variable "severite_minimale_guardduty" {
  description = "Sévérité minimale des découvertes envoyées par e-mail (1 à 8,9 ; 4 = moyenne)."
  type        = number
  default     = 4
}

variable "retention_journaux_jours" {
  description = "Durée de conservation des journaux CloudTrail et VPC Flow Logs."
  type        = number
  default     = 90
}
