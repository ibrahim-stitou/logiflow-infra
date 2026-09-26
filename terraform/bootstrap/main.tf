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

resource "aws_s3_bucket" "etat" {
  bucket = "logiflow-tfstate-${local.compte}"
}

resource "aws_s3_bucket_versioning" "etat" {
  bucket = aws_s3_bucket.etat.id
  versioning_configuration {
    status = "Enabled"
  }
}

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
      "ec2:*", "ssm:*", "s3:*", "cloudwatch:*", "budgets:*", "scheduler:*",
      "kms:DescribeKey", "kms:ListAliases", "sts:GetCallerIdentity",
    ]
    resources = ["*"]
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
