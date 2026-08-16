variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "AZ unique pour tous les sous-réseaux (POC à 3 instances : la résilience multi-AZ n'est pas l'objectif ici)."
  type        = string
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "private_backend_subnet_cidr" {
  type    = string
  default = "10.0.10.0/24"
}

variable "private_ai_subnet_cidr" {
  type    = string
  default = "10.0.11.0/24"
}
