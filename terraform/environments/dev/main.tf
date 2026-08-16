# Stack "dev" : assemble les modules réseau / sécurité / IAM / secrets / compute pour provisionner
# les 3 instances de l'environnement de développement (backend, IA, frontend). Toute la
# configuration applicative (Docker, déploiement des services) est déléguée à Ansible — ce stack ne
# fait QUE provisionner l'infrastructure.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  user_data = templatefile("${path.module}/templates/user_data.yaml.tpl", {
    ssh_public_key = var.ssh_public_key
  })
}

module "network" {
  source = "../../modules/network"

  project_name      = var.project_name
  environment       = var.environment
  availability_zone = var.availability_zone
}

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.network.vpc_id
}

# --- Secrets applicatifs (générés aléatoirement, jamais commités) ---

resource "random_password" "db_password" {
  length  = 32
  special = false # évite les soucis d'échappement dans les URL JDBC / .env
}

resource "random_password" "internal_api_key" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.project_name}/${var.environment}/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_secretsmanager_secret" "internal_api_key" {
  name = "${var.project_name}/${var.environment}/internal-api-key"
}

resource "aws_secretsmanager_secret_version" "internal_api_key" {
  secret_id     = aws_secretsmanager_secret.internal_api_key.id
  secret_string = random_password.internal_api_key.result
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment

  backend_secret_arns = [
    aws_secretsmanager_secret.db_password.arn,
    aws_secretsmanager_secret.internal_api_key.arn,
  ]
  ai_secret_arns = [
    aws_secretsmanager_secret.internal_api_key.arn,
  ]
}

# --- Instances ---

module "backend" {
  source = "../../modules/compute"

  name                 = "${var.project_name}-${var.environment}-backend"
  ami_id               = data.aws_ami.ubuntu.id
  instance_type        = var.backend_instance_type
  subnet_id            = module.network.private_backend_subnet_id
  security_group_ids   = [module.security.backend_sg_id]
  iam_instance_profile = module.iam.instance_profile_names["backend"]
  associate_public_ip  = false
  root_volume_gb       = 30
  user_data            = local.user_data
  tags                 = { Role = "backend" }
}

module "ai" {
  source = "../../modules/compute"

  name                 = "${var.project_name}-${var.environment}-ai"
  ami_id               = data.aws_ami.ubuntu.id
  instance_type        = var.ai_instance_type
  subnet_id            = module.network.private_ai_subnet_id
  security_group_ids   = [module.security.ai_sg_id]
  iam_instance_profile = module.iam.instance_profile_names["ai"]
  associate_public_ip  = false
  root_volume_gb       = 60 # modèles Ollama volumineux (plusieurs Go par modèle)
  user_data            = local.user_data
  tags                 = { Role = "ai" }
}

module "frontend" {
  source = "../../modules/compute"

  name                 = "${var.project_name}-${var.environment}-frontend"
  ami_id               = data.aws_ami.ubuntu.id
  instance_type        = var.frontend_instance_type
  subnet_id            = module.network.public_subnet_id
  security_group_ids   = [module.security.frontend_sg_id]
  iam_instance_profile = module.iam.instance_profile_names["frontend"]
  associate_public_ip  = true
  root_volume_gb       = 20
  user_data            = local.user_data
  tags                 = { Role = "frontend" }
}
