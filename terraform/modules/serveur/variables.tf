variable "nom" {
  description = "Nom du serveur et préfixe de ses ressources."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "type_instance" {
  description = "Type EC2. t3.large (2 vCPU, 8 Go) : confortable pour toute la stack."
  type        = string
  default     = "t3.large"
}

variable "taille_disque_go" {
  description = "Taille du disque système (images Docker, base, sauvegardes locales)."
  type        = number
  default     = 30
}

variable "prefixe_ssm" {
  description = "Préfixe des paramètres SSM lisibles par le serveur (ex. /logiflow/prod)."
  type        = string
}

variable "buckets_arn" {
  description = "ARN des buckets S3 accessibles au serveur (sauvegardes, transferts Ansible)."
  type        = list(string)
}
