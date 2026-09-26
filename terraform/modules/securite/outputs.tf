output "bucket_journaux" {
  description = "Bucket des journaux d'audit (CloudTrail, VPC Flow Logs)."
  value       = aws_s3_bucket.journaux.bucket
}

output "sujet_alertes" {
  description = "Sujet SNS des alertes de sécurité."
  value       = aws_sns_topic.alertes.arn
}
