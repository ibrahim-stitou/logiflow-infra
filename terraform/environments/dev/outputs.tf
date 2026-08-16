output "frontend_public_ip" {
  value = module.frontend.public_ip
}

output "backend_private_ip" {
  value = module.backend.private_ip
}

output "ai_private_ip" {
  value = module.ai.private_ip
}

output "backend_instance_id" {
  value = module.backend.instance_id
}

output "ai_instance_id" {
  value = module.ai.instance_id
}

output "frontend_instance_id" {
  value = module.frontend.instance_id
}

output "db_password_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "internal_api_key_secret_arn" {
  value = aws_secretsmanager_secret.internal_api_key.arn
}
