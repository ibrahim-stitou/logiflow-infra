# 9. Dépannage

Les premiers réflexes :

```bash
make statut                         # l'instance tourne-t-elle ?
make etat                           # services, santé, ressources
make journaux SERVICE=<service>     # 200 dernières lignes
```

## 9.1 Poste de travail et Terraform

| Symptôme | Cause | Correction |
|---|---|---|
| `make outils` : `session-manager-plugin MANQUANT` | Plugin non installé | [Prérequis § 2.2](02-prerequis.md#22-outils-du-poste-de-travail) |
| `Unable to locate credentials` / `ExpiredToken` | Session AWS absente ou expirée | `aws sso login`, et vérifier `AWS_PROFILE` |
| `make init` : `S3 bucket does not exist` | `backend.hcl` non renseigné | Mettre la sortie `bucket_etat` du bootstrap |
| `Error acquiring the state lock` | Un autre `plan` ou `apply` en cours (CI ou poste), ou interruption brutale | Attendre ; si aucune exécution n'est en cours : `terraform -chdir=terraform/environments/prod force-unlock <ID>` |
| `No valid credential sources found` dans GitHub Actions | Variable `AWS_ROLE_*` absente, ou dépôt ou environnement différent de la confiance OIDC | Vérifier les variables et `github_owner` du bootstrap |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Workflow lancé hors `main` ou hors environnement `production` | Lancer depuis `main` |
| `VcpuLimitExceeded` | Quota de vCPU du compte trop bas (comptes neufs) | *Service Quotas → EC2 → Running On-Demand Standard instances*, demander 8 vCPU |
| `ansible.cfg` ignoré, rôles introuvables | Dépôt cloné dans `/mnt/c/...` (WSL) | Cloner dans `~/` |

## 9.2 Ansible et SSM

| Symptôme | Cause | Correction |
|---|---|---|
| `make configure` : aucun hôte (`skipping: no hosts matched`) | Instance arrêtée, ou pas de filtrage par la région et les tags | `make demarrer` ; vérifier le tag `Projet=logiflow` |
| `TargetNotConnected` / l'hôte ne répond pas | Agent SSM pas encore enregistré (1 à 3 min après démarrage) | `aws ssm describe-instance-information` → `PingStatus` `Online`, puis relancer |
| `Failed to find the S3 bucket` / `AccessDenied` sur le bucket de transfert | `bucket_transferts` non passé, ou `terraform output` vide | Lancer depuis la racine du dépôt, après `make init` |
| `SessionManagerPlugin is not found` | Plugin absent du `PATH` | Réinstaller le plugin |
| Échec sur `A_RENSEIGNER` / copilote muet | Clé LLM non enregistrée | `make secret-llm CLE=…` puis `make configure-app` |
| `denied: denied` / `unauthorized` sur `docker pull` | Paquet GHCR privé, jeton absent ou sans accès | Rendre public, ou `ghcr-user`/`ghcr-token` ([§ 2.3](02-prerequis.md#images-docker-ghcr)) |
| `manifest unknown` | Image jamais publiée (CI du dépôt en échec), ou SHA erroné | Vérifier la CI du dépôt et le paquet GHCR |

## 9.3 Application

### Le site ne répond pas du tout

1. `make statut` : l'état doit être `running`. Sinon `make demarrer` (arrêt automatique de 20 h).
2. `make etat` : le conteneur `caddy` doit être `Up`.
3. `make journaux SERVICE=caddy`.

### Erreur de certificat, ou `ERR_SSL_PROTOCOL_ERROR`

Caddy n'a pas encore obtenu ses certificats, ou n'y parvient pas.

- Consultez `make journaux SERVICE=caddy` et cherchez `obtaining certificate` ou `challenge failed`.
- **Limite de débit Let's Encrypt** (`too many certificates`) : elle arrive après trop de
  recréations. Le volume `caddy-data` conserve les certificats : ne le supprimez pas. Attendez,
  car Caddy bascule automatiquement sur ZeroSSL.
- **Domaine personnalisé** : les enregistrements A doivent pointer vers `ip_publique`
  (`dig +short app.<domaine>`).
- **DNS non délégué ou non propagé** : voir [§ 9.5](#95-dns-et-domaine).

### `502 Bad Gateway`

Un service interne n'est pas prêt, ce qui est normal pendant 1 à 2 minutes après un démarrage.
S'il persiste :

```bash
make etat                       # quel service n'est pas healthy ?
make journaux SERVICE=backend
```

### Boucle de redirection à la connexion, ou `Invalid parameter: redirect_uri`

Les URL du client Keycloak ne correspondent pas au domaine réel, par exemple après un
changement de domaine.

```bash
make configure-app   # keycloak-init réaligne le client logiflow-frontend
```

Pour vérifier : console Keycloak → realm `logiflow` → *Clients* → `logiflow-frontend` →
*Valid redirect URIs* doit contenir `https://app.<domaine>/connexion/retour`.

### Connexion réussie mais l'API répond `401`

Le backend rejette le jeton. Dans les journaux du backend, cherchez `iss` ou `JWT` :

- **Émetteur différent** : `OAUTH2_ISSUER_URI` doit valoir exactement
  `https://auth.<domaine>/realms/logiflow`. Il est généré par Ansible, donc relancez
  `make configure-app`.
- **MFA** : avec `mfa_obligatoire = true`, un jeton sans OTP est refusé. L'utilisateur doit
  configurer l'OTP.

### Connexion réussie mais l'API répond `403`

L'utilisateur n'a pas le rôle requis. Attribuez-le dans la console Keycloak
([Exploitation § 5.7](05-exploitation.md#57-comptes-utilisateurs-keycloak)), puis
déconnexion et reconnexion.

### Le copilote ou les agents IA ne répondent pas

```bash
make journaux SERVICE=ai
```

| Message | Correction |
|---|---|
| `401` / `invalid_api_key` (Groq) | Clé LLM erronée : `make secret-llm CLE=…` puis `make configure-app` |
| `429` / `rate_limit` | Quota gratuit Groq atteint : attendre, ou choisir un modèle plus léger (`logiflow_llm_modele`) |
| `401` sur les appels vers le backend (outils du copilote) | Clés internes désalignées : `make configure-app` régénère `.env` depuis SSM et recrée les deux conteneurs |
| Réponse coupée ou pas de streaming | Vérifier que la route `/api/*` du Caddyfile garde `flush_interval -1` |

### Service redémarré en boucle (`Restarting`), `OOMKilled`

```bash
make console
sudo docker inspect --format '{{.State.OOMKilled}}' logiflow-backend-1
free -h
```

La mémoire est insuffisante : vérifiez qu'aucun `type_instance` plus petit que `t3.large` n'est
utilisé, ou augmentez la limite du service dans `stack/compose.yaml`, puis `make configure-app`.

### Disque plein

```bash
make console
sudo df -h /
sudo docker system df
sudo docker image prune -a -f          # images inutilisées
sudo ls -lh /var/backups/logiflow      # archives locales (7 conservées)
```

Pour agrandir durablement : `taille_disque_go = 40`, `make apply`. Le volume EBS est étendu à
chaud, puis étendez le système de fichiers depuis la console :
`sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1`.

### Les données de démonstration n'apparaissent pas

Le jeu de démonstration (migrations Flyway `seed`) ne s'applique qu'à une **base neuve**. Sur
une base existante créée avec `donnees_demo = false`, il faut repartir d'une base vide. Cette
opération est destructive :

```bash
make console
sudo -i && cd /opt/logiflow
docker compose down
docker volume rm logiflow_postgres-data
/opt/logiflow/bin/deployer.sh
```

## 9.4 Sauvegardes

| Symptôme | Correction |
|---|---|
| Pas de sauvegarde du jour | Le serveur était éteint à 19 h 45 : `make sauvegarder` |
| Échec d'envoi vers S3 | `sudo tail -50 /var/log/logiflow-sauvegarde.log` (droits S3 du rôle, nom du bucket dans `.env`) |
| Restauration : `role "..." does not exist` | Base restaurée sur un serveur neuf avant le premier déploiement : lancer `make configure` d'abord, puis restaurer |

## 9.5 DNS et domaine

Diagnostic de base, depuis n'importe quel poste :

```bash
dig +short NS votre-domaine.com @8.8.8.8        # attendu : 4 serveurs *.awsdns-*
dig +short app.votre-domaine.com @8.8.8.8       # attendu : ip_publique
dig +short app.votre-domaine.com @ns-1234.awsdns-12.org   # interroger Route 53 directement
```

| Symptôme | Cause | Correction |
|---|---|---|
| `NS` renvoie encore `dns1.registrar-servers.com` | Délégation Namecheap non faite ou pas encore propagée | Vérifier *Custom DNS* chez Namecheap ([étape 1 bis](04-premier-deploiement.md#étape-1-bis--déléguer-le-domaine-namecheap-vers-route-53)) ; attendre (jusqu'à 48 h, souvent < 30 min) |
| `NS` correct mais `app.` ne résout pas | Enregistrements absents : `make apply` pas encore lancé, ou `domaine` vide dans la prod | `make sortie` → `enregistrements_dns` ; relancer `make apply` avec le bon `domaine` |
| Route 53 répond, mais Google non | Cache DNS (TTL de 300 s pour les enregistrements A ; jusqu'à 48 h pour les NS) | Attendre, ou vider le cache local (`ipconfig /flushdns`) |
| `SERVFAIL` | DNSSEC encore actif chez Namecheap alors que la zone Route 53 n'est pas signée | Désactiver DNSSEC chez Namecheap |
| `make apply` : `no matching Route 53 Hosted Zone found` | Zone non créée : `domaine` absent du `terraform.tfvars` **du bootstrap**, ou orthographe différente | Même valeur dans les deux `terraform.tfvars`, puis `make bootstrap` |
| `make bootstrap` : `Instance cannot be destroyed` (prevent_destroy) | Changement ou suppression de `domaine` au bootstrap | Voulu : voir [Changer de domaine](04-premier-deploiement.md#changer-de-domaine-plus-tard) |
| Workflow Terraform : le plan veut supprimer les enregistrements DNS | Variable GitHub `DOMAINE` absente | La définir ([CI/CD § 6.4](06-ci-cd.md#64-configuration-du-dépôt-une-fois)) |
| Certificat refusé : `CAA record prevents issuance` | Autorité non autorisée par l'enregistrement CAA | Normalement impossible avec Caddy (Let's Encrypt et Sectigo autorisés) ; vérifier `dig CAA votre-domaine.com` |
| `votre-domaine.com` ne redirige pas vers `app.` | Fichier de redirection absent (config `domaine-racine` manquante) | `make configure-app`, puis vérifier `/opt/logiflow/caddy-sites/redirection.caddy` |
| Le déploiement échoue sur « attente de l'API (30/30) » juste après la délégation | Caddy ne peut pas encore obtenir de certificat, car le DNS n'est pas propagé | Attendre la propagation, puis `make deployer` : Caddy réessaie automatiquement |

## 9.6 Outils de sécurité

| Symptôme | Cause | Correction |
|---|---|---|
| CI applicative rouge sur « Analyser l'image » ou « Porte de qualité » | CVE CRITIQUE avec correctif dans une dépendance ou l'image de base | Monter la version (ou fusionner la PR Dependabot) ; voir [Traiter une vulnérabilité](10-outils-securite.md#traiter-une-vulnérabilité) |
| Workflow *Sécurité* rouge sur Gitleaks | Secret détecté dans l'historique | Révoquer le secret **d'abord**, puis le retirer ; faux positif : fichier `.gitleaksignore` avec l'empreinte indiquée |
| Push refusé : `GH013: Repository rule violations… secret` | Push protection de GitHub | Retirer le secret du commit (`git commit --amend`, `git rebase`) ; ne jamais contourner pour un vrai secret |
| Pas de résultats dans l'onglet Security | Envoi SARIF impossible (permission `security-events`) ou code scanning désactivé | Vérifier le journal de l'étape `upload-sarif` ; dépôts publics : fonction gratuite |
| Le site ne répond plus **pour vous seul** (délai d'attente) | Votre IP a été bloquée par CrowdSec (scan, trop d'erreurs 404…) | Depuis un autre réseau ou par SSM : `make securite` pour repérer l'IP, puis `make debloquer IP=<ip>` |
| Rapport ZAP quasi vide | Runner GitHub bloqué par CrowdSec pendant le scan | Attendu ([§ 10.2](10-outils-securite.md#102-dast--owasp-zap)) : débloquer l'IP et relancer |
| `make apply` : `detector already exists` (GuardDuty) | Un détecteur existe déjà dans ce compte et cette région | `activer_guardduty = false` (et dans `variables.tf` pour la CI), ou importer le détecteur existant |
| Aucune alerte de sécurité reçue | Abonnement SNS non confirmé | Cliquer sur « Confirm subscription » dans l'e-mail d'AWS (ou `aws sns list-subscriptions` : `PendingConfirmation`) |
| `make audit` : `lynis: command not found` | Rôle `securite` jamais appliqué | `make configure` (et pas seulement `configure-app`) |
| Un conteneur ne démarre plus après le durcissement (`operation not permitted`) | Capacité Linux nécessaire supprimée par `cap_drop: ALL` | `make journaux SERVICE=<service>`, puis ajouter la seule capacité requise (`cap_add`) dans `stack/compose.yaml`, et `make configure-app` |

## 9.7 Tout reconstruire

Quand le serveur est dans un état incompréhensible, la reconstruction est prévue et rapide
(environ 20 min) :

```bash
make sauvegarder                                                    # si possible
terraform -chdir=terraform/environments/prod apply -replace=module.serveur.aws_instance.serveur
make configure
make console   # puis : sudo /opt/logiflow/bin/restaurer.sh <dernière archive>
```

L'Elastic IP est réattachée : les URL ne changent pas. Les secrets (SSM) et les sauvegardes (S3)
ne dépendent pas du serveur.
