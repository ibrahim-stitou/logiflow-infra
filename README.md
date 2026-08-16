# LogiFlow Infra

Infrastructure as Code du TMS **LogiFlow** : Terraform (provisioning AWS) + Ansible
(configuration & déploiement). Dépôt séparé des applications
([logiflow-backend](https://github.com/ibrahim-stitou/logiflow-backend),
[logiflow-ai-service](https://github.com/ibrahim-stitou/logiflow-ai-service)) — voir
[docs/architecture.md](docs/architecture.md) pour le détail complet (schéma, sécurité, coûts).

3 instances EC2 (`eu-west-3`) : **frontend** (public), **backend** (privé, Spring Boot +
PostgreSQL), **ai** (privé, GPU — Flask + Ollama). Administration exclusivement via AWS SSM
Session Manager, aucun port SSH exposé.

> ⚠️ **`terraform apply` provisionne de vraies ressources facturées**, dont une instance GPU
> (~0,55 $/h). Rien ne s'applique automatiquement : voir "Déploiement" ci-dessous.

## Prérequis

- Terraform ≥ 1.9, AWS CLI v2 configuré (`aws sts get-caller-identity` doit répondre)
- Ansible ≥ 2.16 + collections (`ansible-galaxy collection install -r ansible/requirements.yml`)
- `session-manager-plugin` (AWS) installé, pour le tunnel SSM utilisé par `scripts/ssm-proxy.sh`
- Une paire de clés SSH dédiée (`ssh-keygen -t ed25519 -f ~/.ssh/logiflow-infra`) — la clé
  publique est injectée sur les instances via cloud-init, jamais utilisée hors du tunnel SSM

## Démarrage

### 1. Bootstrap (une seule fois)

Crée le bucket S3 + table DynamoDB du state Terraform, et le rôle OIDC utilisé par la CI/CD.

```bash
cd terraform/bootstrap
terraform init && terraform apply
terraform output -raw state_bucket_name   # -> à reporter dans environments/dev/backend.hcl
terraform output -raw lock_table_name
terraform output -raw github_actions_role_arn   # -> variable GitHub Actions AWS_TERRAFORM_ROLE_ARN
```

### 2. Provisionner l'infrastructure

```bash
cd terraform/environments/dev
cp backend.hcl.example backend.hcl        # renseigner bucket/table depuis l'étape 1
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan   # -e ssh_public_key="$(cat ~/.ssh/logiflow-infra.pub)"
terraform apply  # confirmation manuelle requise
```

### 3. Configurer l'inventaire et déployer

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/aws_ec2.yml --graph   # vérifier que les 3 hôtes apparaissent
ansible all -m ping                                    # vérifier la connectivité SSM

ansible-playbook playbooks/site.yml
```

Voir le [Makefile](Makefile) pour les raccourcis (`make bootstrap-apply`, `make plan`,
`make site`, `make ping`, ...).

## Structure

```
terraform/
  bootstrap/          état distant (S3+DynamoDB) + rôle OIDC GitHub Actions — apply unique
  modules/            network, security, iam, compute — réutilisables
  environments/dev/   assemble les modules pour l'environnement de dev

ansible/
  inventory/           inventaire dynamique (tags EC2, aucune IP en dur)
  roles/                hardening, docker, monitoring, backend, ai, frontend
  playbooks/            site.yml (tout) + un playbook par service (déploiement ciblé)

scripts/ssm-proxy.sh   ProxyCommand SSH-sur-SSM (aucun port 22 exposé)
```

## CI/CD

- **PR touchant `terraform/`** : format, validate, `tflint`, scan de sécurité `tfsec`, puis
  `terraform plan` commenté sur la PR.
- **PR touchant `ansible/`** : `ansible-lint` + vérification syntaxique.
- **`terraform apply`** : déclenchement manuel (`workflow_dispatch`), protégé par un
  environnement GitHub à approbation requise.

Authentification 100 % OIDC (aucune clé AWS stockée dans GitHub) — voir
[docs/architecture.md](docs/architecture.md#sécurité).

## Notes d'installation (WSL)

Deux particularités rencontrées en développant ce dépôt depuis WSL, avec ce dépôt monté sous
`/mnt/c/...` :

- **`pip install ansible` échoue avec `externally-managed-environment`** (PEP 668, Ubuntu
  24.04+) : installer avec `pip install --user --break-system-packages ansible ansible-lint`
  (sans risque, `--user` n'installe que dans le profil de l'utilisateur courant, jamais dans les
  paquets système gérés par `dpkg`).
- **`ansible.cfg` est ignoré avec un avertissement "world writable directory"** : les points de
  montage `/mnt/c` sous WSL sont considérés world-writable par défaut, et Ansible refuse d'y
  charger un `ansible.cfg` par sécurité. Contournement : `export ANSIBLE_CONFIG=$(pwd)/ansible.cfg`
  avant toute commande `ansible`/`ansible-playbook`. Non pertinent en CI (filesystem Linux natif
  sur les runners GitHub Actions).

## Arrêter les ressources (maîtriser le coût)

```bash
aws ec2 stop-instances --instance-ids $(terraform -chdir=terraform/environments/dev output -raw ai_instance_id)
```

Le stockage EBS reste facturé à l'arrêt (marginal), mais plus le calcul GPU (poste de coût
dominant — voir [docs/architecture.md](docs/architecture.md#estimation-des-coûts-eu-west-3-usage-continu)).
