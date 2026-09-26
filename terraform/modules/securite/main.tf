# Services de sécurité AWS (détection, audit, alertes), choisis pour un coût quasi nul :
#   - GuardDuty : détection de menaces (CloudTrail, flux VPC, DNS, accès S3) ;
#   - IAM Access Analyzer : ressources partagées hors du compte (gratuit) ;
#   - CloudTrail : journal d'audit de toutes les actions API, intègre (validation des fichiers),
#     conservé dans S3 ;
#   - VPC Flow Logs : journal des connexions réseau, dans S3 ;
#   - alertes par e-mail (SNS) des découvertes GuardDuty et Access Analyzer.
# Security Hub et AWS Config sont écartés (coût disproportionné pour ce budget, voir
# docs/10-outils-securite.md).

data "aws_caller_identity" "courant" {}
data "aws_region" "courante" {}
data "aws_partition" "courante" {}

locals {
  compte     = data.aws_caller_identity.courant.account_id
  region     = data.aws_region.courante.name
  nom_trail  = "${var.nom}-audit"
  arn_trail  = "arn:${data.aws_partition.courante.partition}:cloudtrail:${local.region}:${local.compte}:trail/${local.nom_trail}"
  nom_bucket = "${var.nom}-journaux-${local.compte}"
}

# --- Bucket des journaux (CloudTrail, VPC Flow Logs) ---------------------------------------------

# SSE-S3 : écart assumé (clé KMS client à 1 $/mois), voir docs/07-securite.md (§ 7.7).
#trivy:ignore:AWS-0132
resource "aws_s3_bucket" "journaux" {
  bucket        = local.nom_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "journaux" {
  bucket                  = aws_s3_bucket.journaux.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "journaux" {
  bucket = aws_s3_bucket.journaux.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "journaux" {
  bucket = aws_s3_bucket.journaux.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "journaux" {
  bucket = aws_s3_bucket.journaux.id
  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    expiration {
      days = var.retention_journaux_jours
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_iam_policy_document" "journaux" {
  statement {
    sid       = "CloudTrailVerifierAcl"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.journaux.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_trail]
    }
  }
  statement {
    sid       = "CloudTrailEcrire"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.journaux.arn}/cloudtrail/AWSLogs/${local.compte}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_trail]
    }
  }
  statement {
    sid       = "FluxVpcVerifierAcl"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.journaux.arn]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.compte]
    }
  }
  statement {
    sid       = "FluxVpcEcrire"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.journaux.arn}/vpc-flow-logs/AWSLogs/${local.compte}/*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.compte]
    }
  }
  statement {
    sid       = "RefuserSansTls"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.journaux.arn, "${aws_s3_bucket.journaux.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "journaux" {
  bucket     = aws_s3_bucket.journaux.id
  policy     = data.aws_iam_policy_document.journaux.json
  depends_on = [aws_s3_bucket_public_access_block.journaux]
}

# --- CloudTrail ----------------------------------------------------------------------------------

# Écarts assumés (docs/07-securite.md, § 7.7) : pas de clé KMS client (AWS-0015), pas d'envoi vers
# CloudWatch Logs (AWS-0162, payant) ; l'intégrité est assurée par la validation des fichiers.
#trivy:ignore:AWS-0015
#trivy:ignore:AWS-0162
resource "aws_cloudtrail" "audit" {
  name                          = local.nom_trail
  s3_bucket_name                = aws_s3_bucket.journaux.id
  s3_key_prefix                 = "cloudtrail"
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.journaux]
}

# --- VPC Flow Logs -------------------------------------------------------------------------------

resource "aws_flow_log" "vpc" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${aws_s3_bucket.journaux.arn}/vpc-flow-logs"
  depends_on           = [aws_s3_bucket_policy.journaux]
  tags                 = { Name = "${var.nom}-flux-vpc" }
}

# --- GuardDuty -----------------------------------------------------------------------------------

resource "aws_guardduty_detector" "principal" {
  count                        = var.activer_guardduty ? 1 : 0
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# Protections complémentaires : S3 conservée (accès anormaux aux sauvegardes), les autres
# désactivées (sans objet ici ou coûteuses : analyse de disques, EKS, RDS, Lambda, agent runtime).
resource "aws_guardduty_detector_feature" "fonction" {
  for_each = var.activer_guardduty ? {
    S3_DATA_EVENTS         = "ENABLED"
    EBS_MALWARE_PROTECTION = "DISABLED"
    EKS_AUDIT_LOGS         = "DISABLED"
    RDS_LOGIN_EVENTS       = "DISABLED"
    LAMBDA_NETWORK_LOGS    = "DISABLED"
    RUNTIME_MONITORING     = "DISABLED"
  } : {}
  detector_id = aws_guardduty_detector.principal[0].id
  name        = each.key
  status      = each.value
}

# --- IAM Access Analyzer -------------------------------------------------------------------------

resource "aws_accessanalyzer_analyzer" "compte" {
  analyzer_name = "${var.nom}-acces-externes"
  type          = "ACCOUNT"
}

# --- Alertes par e-mail --------------------------------------------------------------------------

# Chiffrement SNS non activé : EventBridge ne peut pas publier vers un sujet chiffré par la clé
# gérée par AWS, et une clé client coûte 1 $/mois ; les messages ne contiennent que des résumés.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "alertes" {
  name = "${var.nom}-alertes-securite"
}

data "aws_iam_policy_document" "alertes" {
  statement {
    sid       = "EventBridgePublier"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alertes.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.compte]
    }
  }
}

resource "aws_sns_topic_policy" "alertes" {
  arn    = aws_sns_topic.alertes.arn
  policy = data.aws_iam_policy_document.alertes.json
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alertes.arn
  protocol  = "email"
  endpoint  = var.email_alertes
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  name        = "${var.nom}-guardduty"
  description = "Decouvertes GuardDuty de severite moyenne ou plus"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", var.severite_minimale_guardduty] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty" {
  rule = aws_cloudwatch_event_rule.guardduty.name
  arn  = aws_sns_topic.alertes.arn
  input_transformer {
    input_paths = {
      severite = "$.detail.severity"
      titre    = "$.detail.title"
      type     = "$.detail.type"
      region   = "$.region"
    }
    input_template = "\"[LogiFlow][GuardDuty] Severite <severite> : <titre> (type <type>). Console : https://<region>.console.aws.amazon.com/guardduty/home?region=<region>#/findings\""
  }
}

resource "aws_cloudwatch_event_rule" "acces_externes" {
  name        = "${var.nom}-access-analyzer"
  description = "Ressources accessibles depuis l exterieur du compte"
  event_pattern = jsonencode({
    source        = ["aws.access-analyzer"]
    "detail-type" = ["Access Analyzer Finding"]
    detail        = { status = ["ACTIVE"] }
  })
}

resource "aws_cloudwatch_event_target" "acces_externes" {
  rule = aws_cloudwatch_event_rule.acces_externes.name
  arn  = aws_sns_topic.alertes.arn
  input_transformer {
    input_paths = {
      ressource = "$.detail.resource"
      type      = "$.detail.resourceType"
      public    = "$.detail.isPublic"
    }
    input_template = "\"[LogiFlow][Access Analyzer] <type> <ressource> accessible hors du compte (public : <public>). A verifier dans IAM > Access Analyzer.\""
  }
}
