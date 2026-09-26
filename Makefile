# LogiFlow Infra : toutes les opérations courantes. `make aide` pour la liste.
# À lancer depuis Linux, macOS ou WSL (voir docs/02-prerequis.md).

SHELL := /bin/bash
.DEFAULT_GOAL := aide

REGION     ?= eu-west-3
TF_ENV     := terraform/environments/prod
TF         := terraform -chdir=$(TF_ENV)
SERVICE    ?= backend
IMAGE_TAG  ?= latest
TAG_BACKEND  ?= $(IMAGE_TAG)
TAG_AI       ?= $(IMAGE_TAG)
TAG_FRONTEND ?= $(IMAGE_TAG)
ARCHIVE    ?=
export AWS_REGION := $(REGION)

# Sorties Terraform (évaluées à la demande).
instance   = $(shell $(TF) output -raw instance_id 2>/dev/null)
bucket_ssm = $(shell $(TF) output -raw bucket_transferts 2>/dev/null)
prefixe    = $(shell $(TF) output -raw prefixe_ssm 2>/dev/null)

ANSIBLE = cd ansible && ANSIBLE_CONFIG=$(CURDIR)/ansible/ansible.cfg ansible-playbook \
	-e ansible_aws_ssm_bucket_name=$(bucket_ssm) -e logiflow_tag_backend=$(TAG_BACKEND) \
	-e logiflow_tag_ai=$(TAG_AI) -e logiflow_tag_frontend=$(TAG_FRONTEND)

.PHONY: aide outils bootstrap dns init plan apply sortie secret-llm configure configure-app deployer \
	demarrer arreter statut etat journaux console sauvegarder restaurer sauvegardes \
	identifiants valider detruire local-up local-down local-journaux

aide: ## Affiche cette aide
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- Mise en place --------------------------------------------------------------------------------

outils: ## Vérifie les outils du poste (terraform, aws, ansible, plugin SSM, jq, dig)
	@for t in terraform aws ansible-playbook session-manager-plugin jq dig; do \
	  printf '%-24s' "$$t"; command -v $$t >/dev/null && echo ok || echo "MANQUANT"; done
	@aws sts get-caller-identity --query Arn --output text || echo "AWS CLI non authentifiée"

bootstrap: ## (une fois) Crée l'état distant, les rôles GitHub OIDC et la zone Route 53
	terraform -chdir=terraform/bootstrap init
	terraform -chdir=terraform/bootstrap apply

dns: ## Serveurs de noms à déclarer chez Namecheap et état de la propagation
	@echo "Serveurs de noms Route 53 (Namecheap > Domain > Nameservers > Custom DNS) :"
	@terraform -chdir=terraform/bootstrap output -json serveurs_de_noms | jq -r '.[]' | sed 's/^/  /'
	@d=$$(sed -nE 's/^domaine *= *"(.*)"/\1/p' terraform/bootstrap/terraform.tfvars); \
	  test -n "$$d" || { echo "aucun domaine configuré (sslip.io)"; exit 0; }; \
	  echo "Vus depuis Internet (8.8.8.8) pour $$d :"; \
	  echo "  NS   : $$(dig +short NS $$d @8.8.8.8 | tr '\n' ' ')"; \
	  echo "  app  : $$(dig +short app.$$d @8.8.8.8)"; \
	  echo "  auth : $$(dig +short auth.$$d @8.8.8.8)"

init: ## Initialise Terraform (prod) avec l'état distant
	$(TF) init -backend-config=backend.hcl
	cd ansible && ansible-galaxy collection install -r requirements.yml

plan: ## Montre les changements d'infrastructure prévus
	$(TF) plan

apply: ## Crée ou met à jour l'infrastructure AWS
	$(TF) apply

sortie: ## Affiche les sorties Terraform (URL, IP, instance…)
	$(TF) output

secret-llm: ## Enregistre la clé du fournisseur LLM (Groq) dans SSM : make secret-llm CLE=gsk_...
	@test -n "$(CLE)" || (echo "usage : make secret-llm CLE=<clé>"; exit 1)
	aws ssm put-parameter --name "$(prefixe)/secrets/llm-api-key" --type SecureString \
	  --value "$(CLE)" --overwrite >/dev/null && echo "clé LLM enregistrée ; appliquer avec : make configure-app"

# --- Déploiement ----------------------------------------------------------------------------------

configure: ## Configure le serveur (système, Docker) et déploie l'application
	$(ANSIBLE) site.yml

configure-app: ## Redéploie l'application (fichiers, .env, images) sans toucher au système
	$(ANSIBLE) deployer.yml

deployer: ## Met à jour l'application (nouvelles images) via SSM, sans Ansible
	scripts/ssm-exec.sh $(instance) /opt/logiflow/bin/deployer.sh 1200

# --- Exploitation ---------------------------------------------------------------------------------

demarrer: ## Démarre le serveur (et attend qu'il soit prêt)
	aws ec2 start-instances --instance-ids $(instance) --query 'StartingInstances[0].CurrentState.Name' --output text
	aws ec2 wait instance-status-ok --instance-ids $(instance)
	@echo "serveur prêt ; l'application redémarre seule en 1 à 2 minutes : $$($(TF) output -raw url_application)"

arreter: ## Arrête le serveur (le calcul n'est plus facturé)
	aws ec2 stop-instances --instance-ids $(instance) --query 'StoppingInstances[0].CurrentState.Name' --output text

statut: ## État de l'instance EC2
	@aws ec2 describe-instances --instance-ids $(instance) \
	  --query 'Reservations[0].Instances[0].[State.Name,InstanceType,PublicIpAddress]' --output text

etat: ## État de l'application (services, santé, ressources, sauvegardes)
	scripts/ssm-exec.sh $(instance) /opt/logiflow/bin/etat.sh 120

journaux: ## Derniers journaux d'un service : make journaux SERVICE=backend|ai|keycloak|caddy|frontend|postgres
	scripts/ssm-exec.sh $(instance) "cd /opt/logiflow && docker compose logs --tail 200 $(SERVICE)" 120

console: ## Ouvre un terminal sur le serveur (SSM Session Manager)
	aws ssm start-session --target $(instance)

sauvegarder: ## Lance une sauvegarde immédiate (bases + pièces jointes → S3)
	scripts/ssm-exec.sh $(instance) /opt/logiflow/bin/sauvegarder.sh 900

sauvegardes: ## Liste les sauvegardes disponibles
	scripts/ssm-exec.sh $(instance) "/opt/logiflow/bin/restaurer.sh --liste" 120

restaurer: ## Restaure une sauvegarde (interactif, sur le serveur) : make restaurer
	@echo "La restauration est interactive : ouvrez une console (make console) puis lancez"
	@echo "  sudo /opt/logiflow/bin/restaurer.sh --liste"
	@echo "  sudo /opt/logiflow/bin/restaurer.sh logiflow-<date>.tar"

identifiants: ## Affiche les URL et les identifiants (admin Keycloak, comptes de démo)
	@echo "Application : $$($(TF) output -raw url_application)"
	@echo "Keycloak    : $$($(TF) output -raw url_keycloak)/admin"
	@echo "Admin Keycloak : admin / $$(aws ssm get-parameter --with-decryption --name $(prefixe)/secrets/keycloak-admin-password --query Parameter.Value --output text)"
	@echo "Comptes de démo (admin, responsable, exploitant, commercial, atelier, chauffeur) : $$(aws ssm get-parameter --with-decryption --name $(prefixe)/secrets/demo-users-password --query Parameter.Value --output text)"

# --- Poste local (docs/03-tester-en-local.md) ------------------------------------------------------

LOCAL = cd stack && docker compose --env-file .env -f compose.yaml

local-up: ## (local) Lance la stack de production sur ce poste, avec stack/.env
	@test -f stack/.env || (echo "créer d'abord stack/.env à partir de stack/.env.example"; exit 1)
	$(LOCAL) up -d --wait --wait-timeout 600 caddy frontend backend ai keycloak postgres
	$(LOCAL) run --rm keycloak-init
	@echo "https://app.localhost (certificat interne de Caddy : accepter l'avertissement)"

local-journaux: ## (local) Journaux d'un service : make local-journaux SERVICE=backend
	$(LOCAL) logs -f --tail 200 $(SERVICE)

local-down: ## (local) Arrête la stack locale (ARGS=-v pour effacer aussi les données)
	$(LOCAL) down $(ARGS)

# --- Qualité / fin de vie -------------------------------------------------------------------------

valider: ## Vérifications locales : terraform fmt/validate, ansible-lint, shellcheck, compose
	terraform fmt -check -recursive terraform
	terraform -chdir=terraform/bootstrap validate
	$(TF) validate
	cd ansible && ansible-lint
	shellcheck scripts/*.sh stack/scripts/*.sh stack/keycloak/*.sh stack/postgres/init/*.sh
	sed 's/=$$/=validation/' stack/.env.example > /tmp/logiflow-validation.env
	docker compose --env-file /tmp/logiflow-validation.env -f stack/compose.yaml config --quiet

detruire: ## Supprime TOUTE l'infrastructure (données comprises) — fin de projet
	@read -r -p "Supprimer toute l'infrastructure LogiFlow et ses données ? Taper « detruire » : " c; \
	  [[ "$$c" == "detruire" ]] && $(TF) destroy || echo "annulé"
