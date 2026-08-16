# Fédération OIDC GitHub Actions -> AWS : les workflows CI/CD assument ce rôle via
# `aws-actions/configure-aws-credentials` (voir .github/workflows/terraform-*.yml), sans AUCUNE
# clé d'accès IAM longue durée stockée en secret GitHub. Le token OIDC émis par GitHub est
# vérifié par AWS lui-même (thumbprint + condition sur le repo/ref), pas de secret partagé à
# gérer ni à faire tourner.

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "github_actions_terraform" {
  name = "${var.project_name}-github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Restreint aux workflows du dépôt logiflow-infra, sur n'importe quelle branche/PR — le
        # gate réel sur QUAND appliquer (vs seulement planifier) vit dans les workflows
        # eux-mêmes (environment "production" avec approbation manuelle), pas ici.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
        }
      }
    }]
  })
}

# Politique volontairement scopée aux types de ressources que ce projet provisionne (pas
# d'AdministratorAccess) : EC2/VPC, les rôles IAM applicatifs créés par environments/dev, les 2
# secrets applicatifs, et le backend d'état (S3 + DynamoDB) lui-même.
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "${var.project_name}-github-actions-terraform"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2AndVpc"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      {
        Sid    = "IamForApplicationRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:PassRole",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        ]
        Resource = "arn:aws:iam::*:role/${var.project_name}-*"
      },
      {
        Sid      = "IamInstanceProfiles"
        Effect   = "Allow"
        Action   = ["iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile"]
        Resource = "arn:aws:iam::*:instance-profile/${var.project_name}-*"
      },
      {
        Sid      = "Secrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:*"]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project_name}/*"
      },
      {
        Sid      = "TerraformStateBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.project_name}-terraform-state-*", "arn:aws:s3:::${var.project_name}-terraform-state-*/*"]
      },
      {
        Sid      = "TerraformLockTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-terraform-lock"
      },
      {
        Sid      = "ReadOnlyAccountInfo"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity", "iam:ListPolicies", "iam:GetPolicy"]
        Resource = "*"
      },
    ]
  })
}
