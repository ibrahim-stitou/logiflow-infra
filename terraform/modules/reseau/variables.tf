variable "nom" {
  description = "Préfixe des ressources (ex. logiflow-prod)."
  type        = string
}

variable "cidr_vpc" {
  description = "Plage d'adresses du VPC."
  type        = string
  default     = "10.20.0.0/16"
}
