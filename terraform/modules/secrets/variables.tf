variable "prefixe" {
  description = "Préfixe des paramètres SSM (ex. /logiflow/prod)."
  type        = string
}

variable "environnement" {
  type = string
}

variable "llm_api_key" {
  description = "Clé du fournisseur LLM à la création (facultatif, modifiable ensuite hors Terraform)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "configuration" {
  description = "Paramètres non secrets publiés sous <prefixe>/config/<clé>."
  type        = map(string)
}
