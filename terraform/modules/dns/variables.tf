variable "domaine" {
  description = "Domaine dont la zone Route 53 existe déjà (bootstrap)."
  type        = string
}

variable "ip_publique" {
  description = "IP fixe du serveur."
  type        = string
}
