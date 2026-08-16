.PHONY: bootstrap-init bootstrap-apply init plan apply fmt validate lint inventory ping site backend ai frontend hardening

TF_DEV = terraform/environments/dev

## Bootstrap (backend d'état + rôle OIDC GitHub Actions) — à lancer UNE SEULE FOIS
bootstrap-init:
	cd terraform/bootstrap && terraform init

bootstrap-apply:
	cd terraform/bootstrap && terraform apply

## Stack applicatif (dev)
init:
	cd $(TF_DEV) && terraform init -backend-config=backend.hcl

plan:
	cd $(TF_DEV) && terraform plan

## Provisionne de vraies ressources facturées (dont un GPU) — confirmation manuelle requise
apply:
	cd $(TF_DEV) && terraform apply

fmt:
	cd terraform && terraform fmt -recursive

validate:
	cd $(TF_DEV) && terraform validate

lint:
	tflint --init --chdir=terraform
	tflint --recursive --chdir=terraform
	ansible-lint ansible/playbooks ansible/roles

## Vérifie que l'inventaire dynamique résout bien les 3 instances
inventory:
	cd ansible && ansible-inventory -i inventory/aws_ec2.yml --graph

## Vérifie la connectivité SSM vers les 3 instances
ping:
	cd ansible && ansible all -m ping

site:
	cd ansible && ansible-playbook playbooks/site.yml

backend:
	cd ansible && ansible-playbook playbooks/backend.yml

ai:
	cd ansible && ansible-playbook playbooks/ai.yml

frontend:
	cd ansible && ansible-playbook playbooks/frontend.yml

hardening:
	cd ansible && ansible-playbook playbooks/hardening.yml
