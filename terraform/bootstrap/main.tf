# Bootstrap : à appliquer UNE SEULE FOIS, avec un état local (voir docs/04-premier-deploiement.md).
#
# Crée :
#   - le bucket S3 de l'état Terraform de l'environnement (versionné, chiffré, verrouillage natif
#     S3 : pas de table DynamoDB) ;
#   - le fournisseur d'identité OIDC de GitHub et deux rôles assumables par GitHub Actions, sans
#     aucune clé AWS stockée dans GitHub :
#       * logiflow-github-terraform : plan / apply de l'infrastructure ;
#       * logiflow-github-deploiement : déploiement de l'application (AWS SSM) uniquement.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Projet    = "logiflow"
      GereePar  = "terraform"
      Composant = "bootstrap"
    }
  }
}

data "aws_caller_identity" "courant" {}

locals {
  compte    = data.aws_caller_identity.courant.account_id
  depot_iac = "repo:${var.github_owner}/${var.github_depot_infra}"
}

# --- État Terraform ------------------------------------------------------------------------------

# SSE-S3 (clé gérée par AWS) : écart assumé, voir docs/07-securite.md (§ 7.7).
#trivy:ignore:AWS-0132
resource "aws_s3_bucket" "etat" {
  bucket = "logiflow-tfstate-${local.compte}"
}

resource "aws_s3_bucket_versioning" "etat" {
  bucket = aws_s3_bucket.etat.id
  versioning_configuration {
    status = "Enabled"
  }
}

#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "etat" {
  bucket = aws_s3_bucket.etat.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "etat" {
  bucket                  = aws_s3_bucket.etat.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "etat" {
  bucket = aws_s3_bucket.etat.id
  rule {
    id     = "anciennes-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# --- GitHub Actions (OIDC) -----------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "confiance_terraform" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Plans depuis les pull requests et la branche main (protégée par revue), apply uniquement
    # depuis l'environnement GitHub « production » (approbation manuelle, voir docs/06-ci-cd.md).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.depot_iac}:pull_request",
        "${local.depot_iac}:ref:refs/heads/main",
        "${local.depot_iac}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name                 = "logiflow-github-terraform"
  assume_role_policy   = data.aws_iam_policy_document.confiance_terraform.json
  max_session_duration = 3600
}

# Droits limités aux services réellement utilisés par l'infrastructure ; IAM restreint aux
# ressources nommées « logiflow-* ».
data "aws_iam_policy_document" "terraform" {
  statement {
    sid = "Services"
    actions = [
      "ec2:*", "ssm:*", "cloudwatch:*", "budgets:*", "scheduler:*",
      "kms:DescribeKey", "kms:ListAliases", "sts:GetCallerIdentity",
      # Enregistrements DNS de l'application (la zone elle-même reste gérée par le bootstrap).
      "route53:Get*", "route53:List*", "route53:ChangeResourceRecordSets",
      # Services de sécurité (module securite) : détection, audit, alertes.
      "guardduty:*", "access-analyzer:*", "cloudtrail:*", "sns:*", "events:*",
      "logs:CreateLogDelivery", "logs:DeleteLogDelivery", "logs:GetLogDelivery", "logs:ListLogDeliveries",
      "s3:ListAllMyBuckets",
    ]
    resources = ["*"]
  }
  # S3 : uniquement les buckets du projet (état, sauvegardes, transferts, journaux).
  statement {
    sid = "S3Projet"
    actions = [
      "s3:CreateBucket", "s3:DeleteBucket", "s3:DeleteBucketPolicy",
      "s3:Get*", "s3:List*", "s3:Put*", "s3:DeleteObject", "s3:DeleteObjectVersion",
    ]
    resources = ["arn:aws:s3:::logiflow-*", "arn:aws:s3:::logiflow-*/*"]
  }
  # Rôles liés aux services de sécurité, créés automatiquement à leur activation.
  statement {
    sid       = "RolesLiesSecurite"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["guardduty.amazonaws.com", "malware-protection.guardduty.amazonaws.com", "access-analyzer.amazonaws.com"]
    }
  }
  statement {
    sid = "IamProjet"
    actions = [
      "iam:*Role", "iam:*RolePolicy", "iam:*RolePolicies", "iam:*InstanceProfile",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:TagRole", "iam:UntagRole", "iam:PassRole",
      "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${local.compte}:role/logiflow-*",
      "arn:aws:iam::${local.compte}:instance-profile/logiflow-*",
    ]
  }
  statement {
    sid       = "IamLecture"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_terraform" {
  name   = "logiflow-terraform"
  role   = aws_iam_role.github_terraform.id
  policy = data.aws_iam_policy_document.terraform.json
}

data "aws_iam_policy_document" "confiance_deploiement" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.depot_iac}:environment:production"]
    }
  }
}

resource "aws_iam_role" "github_deploiement" {
  name               = "logiflow-github-deploiement"
  assume_role_policy = data.aws_iam_policy_document.confiance_deploiement.json
}

# Déploiement : réveiller l'instance du projet et y exécuter une commande via SSM, rien d'autre.
data "aws_iam_policy_document" "deploiement" {
  statement {
    sid       = "Lecture"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
  statement {
    sid       = "DemarrerInstanceProjet"
    actions   = ["ec2:StartInstances"]
    resources = ["arn:aws:ec2:${var.region}:${local.compte}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Projet"
      values   = ["logiflow"]
    }
  }
  statement {
    sid       = "CommandeSurInstanceProjet"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.region}:${local.compte}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Projet"
      values   = ["logiflow"]
    }
  }
  statement {
    sid       = "DocumentShell"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
  }
}

resource "aws_iam_role_policy" "github_deploiement" {
  name   = "logiflow-deploiement"
  role   = aws_iam_role.github_deploiement.id
  policy = data.aws_iam_policy_document.deploiement.json
}

# --- DNS (facultatif) : zone Route 53 du domaine acheté chez un registraire (ex. Namecheap) ------
#
# Créée ici, et non dans l'environnement, pour survivre à `make detruire` : ses 4 serveurs de noms,
# déclarés une fois chez le registraire, ne changent donc jamais. Les enregistrements de
# l'application (app, auth, racine, www) sont gérés par l'environnement prod (module dns).

resource "aws_route53_zone" "principale" {
  count   = var.domaine != "" ? 1 : 0
  name    = var.domaine
  comment = "LogiFlow - zone publique, deleguee depuis le registraire"

  lifecycle {
    # Supprimer la zone changerait les serveurs de noms : à faire volontairement (docs/05).
    prevent_destroy = true
  }
}

# Seules les autorités utilisées par Caddy (Let's Encrypt, et ZeroSSL/Sectigo en repli) peuvent
# émettre des certificats pour ce domaine.
resource "aws_route53_record" "caa" {
  count   = var.domaine != "" ? 1 : 0
  zone_id = aws_route53_zone.principale[0].zone_id
  name    = var.domaine
  type    = "CAA"
  ttl     = 3600
  records = [
    "0 issue \"letsencrypt.org\"",
    "0 issue \"sectigo.com\"",
  ]
}
