output "parametres_secrets" {
  description = "Noms des paramètres SSM secrets."
  value = concat(
    [for p in aws_ssm_parameter.secret : p.name],
    [aws_ssm_parameter.demo_password.name, aws_ssm_parameter.llm_api_key.name],
  )
}
