# Environnement de production LogiFlow : un serveur unique qui exécute toute la stack.
# Voir docs/01-architecture.md pour le schéma et les choix, docs/08-couts.md pour le budget.

locals {
  nom     = "logiflow-${var.environnement}"
  prefixe = "/logiflow/${var.environnement}"

  # Domaines : le vôtre s'il est fourni (zone Route 53 créée par le bootstrap, enregistrements par
  # le module dns), sinon sslip.io (résolution DNS gratuite à partir de l'IP, compatible
  # Let's Encrypt), ex. app.13-38-12-4.sslip.io.
  domaine_propre = var.domaine != ""
  ip_tirets      = replace(module.serveur.ip_publique, ".", "-")
  app_domain     = local.domaine_propre ? "app.${var.domaine}" : "app.${local.ip_tirets}.sslip.io"
  auth_domain    = local.domaine_propre ? "auth.${var.domaine}" : "auth.${local.ip_tirets}.sslip.io"
}

module "reseau" {
  source = "../../modules/reseau"
  nom    = local.nom
}

module "sauvegardes" {
  source          = "../../modules/sauvegardes"
  nom             = local.nom
  retention_jours = var.retention_sauvegardes_jours
}

module "serveur" {
  source           = "../../modules/serveur"
  nom              = local.nom
  vpc_id           = module.reseau.vpc_id
  subnet_id        = module.reseau.subnet_public_id
  type_instance    = var.type_instance
  taille_disque_go = var.taille_disque_go
  prefixe_ssm      = local.prefixe
  buckets_arn      = module.sauvegardes.buckets_arn
}

module "dns" {
  source      = "../../modules/dns"
  count       = local.domaine_propre ? 1 : 0
  domaine     = var.domaine
  ip_publique = module.serveur.ip_publique
}

module "secrets" {
  source        = "../../modules/secrets"
  prefixe       = local.prefixe
  environnement = var.environnement
  llm_api_key   = var.llm_api_key

  # Lu par Ansible (make configure) et par le workflow de déploiement.
  configuration = merge(
    {
      app-domain         = local.app_domain
      auth-domain        = local.auth_domain
      bucket-sauvegardes = module.sauvegardes.bucket_sauvegardes
      demo-data          = tostring(var.donnees_demo)
      mfa-required       = tostring(var.mfa_obligatoire)
    },
    # Domaine racine et www : redirigés vers l'application par Caddy.
    local.domaine_propre ? { domaine-racine = var.domaine } : {},
  )
}

module "couts" {
  source                = "../../modules/couts"
  nom                   = local.nom
  instance_id           = module.serveur.instance_id
  instance_arn          = module.serveur.instance_arn
  budget_mensuel_usd    = var.budget_mensuel_usd
  email_alertes         = var.email_alertes
  arret_automatique     = var.arret_automatique
  cron_arret            = var.cron_arret
  demarrage_automatique = var.demarrage_automatique
}

module "securite" {
  source            = "../../modules/securite"
  nom               = local.nom
  vpc_id            = module.reseau.vpc_id
  email_alertes     = var.email_alertes
  activer_guardduty = var.activer_guardduty
}
