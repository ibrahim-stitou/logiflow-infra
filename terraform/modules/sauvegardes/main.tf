# Stockage S3 :
#   - sauvegardes : archives quotidiennes (bases + pièces jointes), conservées 14 jours ;
#   - transferts  : fichiers temporaires du connecteur Ansible « aws_ssm » (supprimés après 1 jour).
# Chiffrés, privés, versionnage désactivé (coût minimal).

data "aws_caller_identity" "courant" {}

locals {
  buckets = {
    sauvegardes = { nom = "${var.nom}-sauvegardes-${data.aws_caller_identity.courant.account_id}", jours = var.retention_jours }
    transferts  = { nom = "${var.nom}-transferts-${data.aws_caller_identity.courant.account_id}", jours = 1 }
  }
}

resource "aws_s3_bucket" "bucket" {
  for_each      = local.buckets
  bucket        = each.value.nom
  force_destroy = var.suppression_forcee
}

resource "aws_s3_bucket_public_access_block" "bucket" {
  for_each                = aws_s3_bucket.bucket
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  for_each = aws_s3_bucket.bucket
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  for_each = aws_s3_bucket.bucket
  bucket   = each.value.id
  rule {
    id     = "expiration"
    status = "Enabled"
    filter {}
    expiration {
      days = local.buckets[each.key].jours
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
