output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_backend_subnet_id" {
  value = aws_subnet.private_backend.id
}

output "private_ai_subnet_id" {
  value = aws_subnet.private_ai.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}
