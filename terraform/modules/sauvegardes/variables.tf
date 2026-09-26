variable "nom" {
  description = "Préfixe des buckets (ex. logiflow-prod)."
  type        = string
}

variable "retention_jours" {
  description = "Durée de conservation des sauvegardes sur S3."
  type        = number
  default     = 14
}

variable "suppression_forcee" {
  description = "Autoriser `terraform destroy` à vider les buckets (fin de projet)."
  type        = bool
  default     = true
}
