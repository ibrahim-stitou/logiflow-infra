# Module EC2 générique, réutilisé pour les 3 services (frontend, backend, ai) avec des paramètres
# différents. Volume racine chiffré par défaut (KMS géré AWS) ; IMDSv2 imposé (tokens obligatoires,
# protection contre l'exfiltration de métadonnées via SSRF) — pratiques de sécurité de base pour
# toute instance EC2 en 2026.

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = var.associate_public_ip
  user_data                   = var.user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 uniquement
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [ami] # évite un remplacement d'instance si l'AMI "latest" change entre deux plans
  }
}
