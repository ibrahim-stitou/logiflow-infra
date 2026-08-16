# Un rôle IAM par service, attaché en instance profile EC2. Chaque rôle :
#   - peut être administré via AWS SSM Session Manager (pas de clé SSH, pas de port 22 ouvert) ;
#   - ne peut lire QUE les secrets Secrets Manager qui le concernent (moindre privilège) ;
#   - remonte ses métriques/logs vers CloudWatch.
# Aucune clé d'accès IAM longue durée n'est créée ni distribuée : l'authentification AWS des
# instances passe entièrement par le rôle assumé (identité de l'instance), pas par des secrets à
# gérer.

locals {
  services = {
    frontend = { secret_arns = [] }
    backend  = { secret_arns = var.backend_secret_arns }
    ai       = { secret_arns = var.ai_secret_arns }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.services

  name = "${var.project_name}-${var.environment}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-${var.environment}-${each.key}-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = local.services
  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  for_each   = local.services
  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "secrets_access" {
  for_each = { for k, v in local.services : k => v if length(v.secret_arns) > 0 }

  name = "${var.project_name}-${var.environment}-${each.key}-secrets"
  role = aws_iam_role.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = each.value.secret_arns
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  for_each = local.services

  name = "${var.project_name}-${var.environment}-${each.key}"
  role = aws_iam_role.this[each.key].name
}
