# Security groups : aucun port SSH n'est ouvert vers Internet — l'administration passe par AWS
# SSM Session Manager (voir module iam), qui ne nécessite aucun trafic entrant. Chaque service
# n'accepte du trafic que depuis le security group de son appelant légitime (principe du moindre
# privilège), jamais depuis 0.0.0.0/0 sauf pour le frontend (seul point d'entrée public HTTP/HTTPS).

resource "aws_security_group" "frontend" {
  name_prefix = "${var.project_name}-${var.environment}-frontend-"
  description = "Frontend Angular/nginx - seul service expose publiquement"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP public"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS public"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-frontend-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "backend" {
  name_prefix = "${var.project_name}-${var.environment}-backend-"
  description = "Backend Spring Boot + PostgreSQL - accessible uniquement depuis le frontend"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-backend-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "backend_from_frontend" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.backend.id
  source_security_group_id = aws_security_group.frontend.id
  description              = "API Spring Boot, appelee par le frontend"
}

resource "aws_security_group" "ai" {
  name_prefix = "${var.project_name}-${var.environment}-ai-"
  description = "Service IA (Flask + Ollama) - accessible uniquement depuis le backend"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-ai-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ai_from_backend" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ai.id
  source_security_group_id = aws_security_group.backend.id
  description              = "API Flask (/internal/ai/v1/**), appelee uniquement par le backend"
}

# Ollama (11434) n'a volontairement AUCUNE règle d'ingress : Flask lui parle en loopback
# (localhost), sur la même instance — il n'a jamais besoin d'être joignable depuis un autre host.
