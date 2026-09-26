# Le serveur applicatif : une instance EC2 Ubuntu 24.04 qui exécute toute la stack Docker Compose.
#
# - Aucun port d'administration ouvert : seuls 80/443 sont publics, l'accès se fait par AWS SSM
#   Session Manager (pas de clé SSH, pas de bastion).
# - IP publique fixe (Elastic IP) : les domaines sslip.io et les certificats restent valides
#   après un arrêt/redémarrage.
# - IMDSv2 obligatoire, disque chiffré, récupération automatique en cas de panne matérielle.

data "aws_region" "courante" {}
data "aws_caller_identity" "courant" {}

# Dernière AMI Ubuntu 24.04 LTS publiée par Canonical.
data "aws_ssm_parameter" "ami_ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_security_group" "serveur" {
  name        = "${var.nom}-serveur"
  description = "LogiFlow - HTTP et HTTPS publics uniquement"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP (redirection vers HTTPS, validation Lets Encrypt)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP/3 (QUIC)"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Sortant - images Docker, LLM, OSRM, Lets Encrypt, API AWS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.nom}-serveur" }
}

# --- Identité de l'instance ----------------------------------------------------------------------

data "aws_iam_policy_document" "confiance_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "serveur" {
  name               = "${var.nom}-serveur"
  assume_role_policy = data.aws_iam_policy_document.confiance_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.serveur.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "serveur" {
  statement {
    sid     = "LireSecretsEtConfiguration"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:${data.aws_region.courante.name}:${data.aws_caller_identity.courant.account_id}:parameter${var.prefixe_ssm}",
      "arn:aws:ssm:${data.aws_region.courante.name}:${data.aws_caller_identity.courant.account_id}:parameter${var.prefixe_ssm}/*",
    ]
  }
  statement {
    sid       = "DechiffrerSecrets"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.courante.name}.amazonaws.com"]
    }
  }
  statement {
    sid       = "Sauvegardes"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject", "s3:GetBucketLocation"]
    resources = [for arn in var.buckets_arn : arn]
  }
  statement {
    sid       = "ObjetsSauvegardes"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = [for arn in var.buckets_arn : "${arn}/*"]
  }
}

resource "aws_iam_role_policy" "serveur" {
  name   = "${var.nom}-serveur"
  role   = aws_iam_role.serveur.id
  policy = data.aws_iam_policy_document.serveur.json
}

resource "aws_iam_instance_profile" "serveur" {
  name = "${var.nom}-serveur"
  role = aws_iam_role.serveur.name
}

# --- Instance ------------------------------------------------------------------------------------

resource "aws_instance" "serveur" {
  ami                    = data.aws_ssm_parameter.ami_ubuntu.value
  instance_type          = var.type_instance
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.serveur.id]
  iam_instance_profile   = aws_iam_instance_profile.serveur.name
  monitoring             = false

  metadata_options {
    http_tokens                 = "required" # IMDSv2 uniquement
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.taille_disque_go
    encrypted             = true
    delete_on_termination = true
  }

  # Préparation minimale ; la configuration complète est faite par Ansible (make configure).
  user_data = <<-EOT
    #cloud-config
    timezone: Europe/Paris
    hostname: ${var.nom}
    package_update: true
  EOT

  lifecycle {
    # Une nouvelle AMI Ubuntu ne doit pas recréer le serveur (et ses données).
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name = var.nom
    Role = "serveur-applicatif"
  }
}

resource "aws_eip" "serveur" {
  domain   = "vpc"
  instance = aws_instance.serveur.id
  tags     = { Name = "${var.nom}-ip" }
}

# Récupération automatique sur un autre hôte physique en cas de panne matérielle AWS.
resource "aws_cloudwatch_metric_alarm" "recuperation" {
  alarm_name          = "${var.nom}-recuperation-auto"
  alarm_description   = "Relance l'instance sur un autre hôte si le contrôle système échoue"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { InstanceId = aws_instance.serveur.id }
  alarm_actions       = ["arn:aws:automate:${data.aws_region.courante.name}:ec2:recover"]
}
