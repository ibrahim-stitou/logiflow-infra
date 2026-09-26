# Maîtrise des coûts :
#   - budget mensuel avec alertes par e-mail (réel et prévisionnel) ;
#   - arrêt automatique du serveur chaque soir (et démarrage automatique en option), via EventBridge
#     Scheduler : on ne paie le calcul que pendant les heures de travail.

data "aws_region" "courante" {}

resource "aws_budgets_budget" "mensuel" {
  name         = "${var.nom}-mensuel"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_mensuel_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.email_alertes]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.email_alertes]
  }
}

# --- Arrêt / démarrage planifiés -----------------------------------------------------------------

data "aws_iam_policy_document" "confiance_scheduler" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "planificateur" {
  name               = "${var.nom}-planificateur"
  assume_role_policy = data.aws_iam_policy_document.confiance_scheduler.json
}

resource "aws_iam_role_policy" "planificateur" {
  name = "${var.nom}-demarrer-arreter"
  role = aws_iam_role.planificateur.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:StartInstances", "ec2:StopInstances"]
      Resource = var.instance_arn
    }]
  })
}

resource "aws_scheduler_schedule" "arret" {
  name                         = "${var.nom}-arret-soir"
  description                  = "Arret automatique du serveur LogiFlow chaque soir"
  schedule_expression          = var.cron_arret
  schedule_expression_timezone = "Europe/Paris"
  state                        = var.arret_automatique ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.planificateur.arn
    input    = jsonencode({ InstanceIds = [var.instance_id] })
  }
}

resource "aws_scheduler_schedule" "demarrage" {
  name                         = "${var.nom}-demarrage-matin"
  description                  = "Demarrage automatique du serveur LogiFlow les jours ouvres"
  schedule_expression          = var.cron_demarrage
  schedule_expression_timezone = "Europe/Paris"
  state                        = var.demarrage_automatique ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.planificateur.arn
    input    = jsonencode({ InstanceIds = [var.instance_id] })
  }
}
