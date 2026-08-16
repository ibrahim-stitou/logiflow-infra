variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "project_name" {
  type    = string
  default = "logiflow"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "availability_zone" {
  type    = string
  default = "eu-west-3a"
}

variable "ssh_public_key" {
  description = <<-EOT
    Clé publique SSH injectée sur les 3 instances (via cloud-init), utilisée uniquement à
    l'intérieur du tunnel SSM — aucun security group n'ouvre le port 22. Pas de valeur par
    défaut : à fournir explicitement (ex. contenu de ~/.ssh/logiflow-infra.pub) pour éviter
    qu'une clé d'exemple ne se retrouve accidentellement déployée.
  EOT
  type        = string
}

# --- Images Docker (publiées par la CI de chaque dépôt applicatif vers GHCR) ---

variable "backend_image" {
  description = "Image Docker du backend Spring Boot (logiflow-backend)."
  type        = string
  default     = "ghcr.io/ibrahim-stitou/logiflow-backend:latest"
}

variable "ai_image" {
  description = "Image Docker du service IA Flask (logiflow-ai-service)."
  type        = string
  default     = "ghcr.io/ibrahim-stitou/logiflow-ai-service:latest"
}

variable "frontend_image" {
  description = "Image Docker du frontend Angular (logiflow-frontend), une fois ce dépôt disponible."
  type        = string
  default     = "ghcr.io/ibrahim-stitou/logiflow-frontend:latest"
}

# --- Gabarits d'instance ---
# GPU obligatoire pour l'IA (Ollama) : g4dn.xlarge (T4 16 Go VRAM) est le plus petit gabarit GPU
# disponible sur AWS, ~0,55 $/h en eu-west-3 — à ARRÊTER (`aws ec2 stop-instances`) entre deux
# sessions de travail si le budget est contraint (voir docs/architecture.md, section coûts).

variable "backend_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ai_instance_type" {
  type    = string
  default = "g4dn.xlarge"
}

variable "frontend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ollama_model" {
  description = "Modèle Ollama à pré-télécharger sur l'instance IA au provisioning."
  type        = string
  default     = "llama3.1"
}
