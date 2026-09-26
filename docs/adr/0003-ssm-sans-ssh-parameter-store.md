# ADR 0003 : administration par AWS SSM (sans SSH) et secrets dans Parameter Store

- **Statut** : acceptée
- **Date** : 2026-09-26

## Contexte

Le serveur doit être administré (Ansible, déploiements, dépannage) depuis les postes de
l'équipe et depuis GitHub Actions. La stack a besoin d'une dizaine de secrets : mots de passe
des bases, admin Keycloak, clés internes entre services, clé LLM. Il faut éviter les clés SSH
partagées, les ports d'administration exposés et les secrets dans Git ou dans GitHub.

## Décision

- **Aucun SSH** : le port 22 est fermé et le service désactivé. Tous les accès passent par
  **AWS Systems Manager** :
  - Session Manager pour le terminal ;
  - le connecteur Ansible `community.aws.aws_ssm` pour la configuration ;
  - Run Command pour les déploiements depuis GitHub.
- **Secrets** générés par Terraform et stockés dans **SSM Parameter Store** (`SecureString`,
  KMS). Ansible les lit au moment du déploiement et les écrit dans un `.env` en `600` sur le
  serveur.
- **GitHub Actions** s'authentifie par **OIDC** auprès de deux rôles IAM dédiés (Terraform,
  déploiement), sans aucune clé AWS stockée.

## Alternatives

| Option | Rejet |
|---|---|
| SSH + clé partagée + IP autorisée | Clé à distribuer et à révoquer, port exposé, IP des postes et des runners variables |
| Bastion | Coût, surface supplémentaire |
| AWS Secrets Manager | 0,40 $/secret/mois ; la rotation automatique n'est pas nécessaire ici |
| Ansible Vault dans Git | Secret de déchiffrement à partager ; secrets versionnés |
| Clés AWS dans les secrets GitHub | Identifiants longue durée, risque de fuite |

## Conséquences

- (+) Aucune surface d'administration exposée ; chaque accès est authentifié par IAM et tracé
  (CloudTrail).
- (+) Secrets gratuits, chiffrés, centralisés, régénérables (`terraform apply -replace`).
- (+) Pas de clé à gérer, ni sur les postes, ni dans GitHub.
- (−) Le poste doit disposer du plugin Session Manager, et Ansible d'un bucket S3 de transfert
  (fourni, purgé chaque jour).
- (−) L'état Terraform contient les secrets générés : il est stocké dans un bucket chiffré et
  privé.
