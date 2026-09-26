# Secrets et configuration de l'application dans AWS SSM Parameter Store (niveau standard :
# gratuit). Les secrets sont générés ici, chiffrés (SecureString, clé KMS gérée par AWS) et lus
# par Ansible au déploiement. Ils ne figurent jamais dans Git ni dans GitHub.
#
# La clé LLM (fournisseur externe) n'est pas générée : Terraform crée le paramètre avec une valeur
# provisoire et ne l'écrase plus ensuite (voir `make secret-llm`).

resource "random_password" "secret" {
  for_each = toset([
    "db-password",
    "ai-db-password",
    "keycloak-db-password",
    "keycloak-admin-password",
    "ai-internal-api-key",
    "ai-callback-api-key",
  ])
  length  = 32
  special = false
}

# Mot de passe commun des comptes de démonstration : lisible, communicable aux évaluateurs.
resource "random_password" "demo" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "secret" {
  for_each    = random_password.secret
  name        = "${var.prefixe}/secrets/${each.key}"
  description = "LogiFlow ${var.environnement} : ${each.key} (généré par Terraform)"
  type        = "SecureString"
  value       = each.value.result
}

resource "aws_ssm_parameter" "demo_password" {
  name        = "${var.prefixe}/secrets/demo-users-password"
  description = "LogiFlow ${var.environnement} : mot de passe des comptes de démonstration"
  type        = "SecureString"
  value       = random_password.demo.result
}

resource "aws_ssm_parameter" "llm_api_key" {
  name        = "${var.prefixe}/secrets/llm-api-key"
  description = "LogiFlow ${var.environnement} : clé API du fournisseur LLM (make secret-llm)"
  type        = "SecureString"
  value       = var.llm_api_key == "" ? "A_RENSEIGNER" : var.llm_api_key
  lifecycle {
    ignore_changes = [value]
  }
}

# Configuration non secrète, lue par Ansible et par le workflow de déploiement.
resource "aws_ssm_parameter" "config" {
  for_each    = var.configuration
  name        = "${var.prefixe}/config/${each.key}"
  description = "LogiFlow ${var.environnement} : ${each.key}"
  type        = "String"
  value       = each.value
}
