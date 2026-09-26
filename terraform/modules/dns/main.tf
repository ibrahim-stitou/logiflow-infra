# Enregistrements DNS de l'application dans la zone Route 53 du domaine (créée par le bootstrap) :
#   - app.<domaine>  : interface et API ;
#   - auth.<domaine> : Keycloak ;
#   - <domaine> et www.<domaine> : redirigés par Caddy vers app.<domaine>.
# Tous pointent vers l'IP fixe du serveur (Elastic IP).

data "aws_route53_zone" "principale" {
  name         = var.domaine
  private_zone = false
}

locals {
  noms = {
    racine = var.domaine
    www    = "www.${var.domaine}"
    app    = "app.${var.domaine}"
    auth   = "auth.${var.domaine}"
  }
}

resource "aws_route53_record" "serveur" {
  for_each = local.noms

  zone_id = data.aws_route53_zone.principale.zone_id
  name    = each.value
  type    = "A"
  ttl     = 300
  records = [var.ip_publique]
}
