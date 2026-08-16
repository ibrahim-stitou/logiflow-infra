variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "backend_secret_arns" {
  description = "ARNs Secrets Manager que le rôle backend est autorisé à lire (mot de passe DB, clé API interne)."
  type        = list(string)
  default     = []
}

variable "ai_secret_arns" {
  description = "ARNs Secrets Manager que le rôle IA est autorisé à lire (clé API interne)."
  type        = list(string)
  default     = []
}
