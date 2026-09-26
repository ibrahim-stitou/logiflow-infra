output "instance_id" {
  value = aws_instance.serveur.id
}

output "instance_arn" {
  value = aws_instance.serveur.arn
}

output "ip_publique" {
  value = aws_eip.serveur.public_ip
}
