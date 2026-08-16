output "state_bucket_name" {
  description = "À reporter dans environments/*/backend.tf (bucket)."
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "À reporter dans environments/*/backend.tf (dynamodb_table)."
  value       = aws_dynamodb_table.terraform_lock.name
}

output "github_actions_role_arn" {
  description = "À renseigner dans le secret GitHub AWS_TERRAFORM_ROLE_ARN (workflows CI/CD)."
  value       = aws_iam_role.github_actions_terraform.arn
}
