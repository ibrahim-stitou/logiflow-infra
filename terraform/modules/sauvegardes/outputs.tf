output "bucket_sauvegardes" {
  value = aws_s3_bucket.bucket["sauvegardes"].bucket
}

output "bucket_transferts" {
  value = aws_s3_bucket.bucket["transferts"].bucket
}

output "buckets_arn" {
  value = [for b in aws_s3_bucket.bucket : b.arn]
}
