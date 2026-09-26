# 4. Premier déploiement, pas à pas

Ce guide part d'un compte AWS vide et aboutit à LogiFlow en ligne en HTTPS. Comptez environ
**45 minutes**, dont 15 d'attente. Chaque étape indique le **résultat attendu** : ne passez à la
suivante que s'il est obtenu.

```mermaid
graph LR
    A[0. Prérequis] --> B[1. Bootstrap<br/>+ zone DNS]
    B --> B2[1 bis. Namecheap<br/>→ Route 53]
    B2 --> C[2. Paramètres]
    C --> D[3. Infrastructure]
    D --> E[4. Clé LLM]
    E --> F[5. Configuration<br/>+ déploiement]
    F --> G[6. Vérification]
    G -.-> H[7. GitHub Actions]
```

## Étape 0 : prérequis

Toute la page [Prérequis](02-prerequis.md), en particulier :

- `make outils` affiche tout à `ok`, avec votre ARN AWS ;
- les images GHCR existent et sont **publiques**, sinon prévoyez le jeton (§ 2.3) ;
- une clé Groq est disponible.

```bash
git clone https://github.com/ibrahim-stitou/logiflow-infra.git ~/logiflow-infra
cd ~/logiflow-infra
```

## Étape 1 : bootstrap (une seule fois par compte AWS)

Cette étape crée les ressources **durables**, qui survivent à la destruction de
l'environnement :

- le bucket S3 de l'**état Terraform**, versionné, chiffré et verrouillé ;
- le fournisseur **OIDC GitHub** ;
- les deux **rôles** assumables par les workflows GitHub ;
- la **zone Route 53** de votre domaine, avec un enregistrement CAA.

```bash
cp terraform/bootstrap/terraform.tfvars.example terraform/bootstrap/terraform.tfvars
# y renseigner : domaine = "votre-domaine.com" (et github_owner si besoin)
make bootstrap
```

Terraform affiche le plan, puis demande confirmation : répondre `yes`.

Résultat attendu :

```
Outputs:
bucket_etat              = "logiflow-tfstate-123456789012"
role_github_deploiement  = "arn:aws:iam::123456789012:role/logiflow-github-deploiement"
role_github_terraform    = "arn:aws:iam::123456789012:role/logiflow-github-terraform"
serveurs_de_noms         = [
  "ns-1234.awsdns-12.org",
  "ns-567.awsdns-34.net",
  "ns-89.awsdns-56.com",
  "ns-1890.awsdns-78.co.uk",
]
```

Notez ces valeurs. Les serveurs de noms servent à l'étape 1 bis, les rôles et le bucket à
l'étape 7.

> L'état du bootstrap reste **local** (`terraform/bootstrap/terraform.tfstate`, ignoré par Git).
> **Conservez-le**, avec `terraform.tfvars`, car il décrit la zone DNS. Pour le retrouver sur
> un autre poste, relancez `make bootstrap` avec les mêmes variables après avoir importé les
> ressources existantes (`terraform import`).

## Étape 1 bis : déléguer le domaine Namecheap vers Route 53

*À faire tout de suite* : la propagation prend de quelques minutes à quelques heures. Elle
s'effectue pendant les étapes suivantes.

1. Connectez-vous à Namecheap, puis ouvrez *Domain List* et cliquez sur **Manage** en face du
   domaine.
2. Vérifiez dans *Advanced DNS* que **DNSSEC** est désactivé.
3. Dans l'onglet *Domain*, section **Nameservers**, choisissez **Custom DNS**.
4. Saisissez les **4 serveurs de noms** de la sortie `serveurs_de_noms`, sans le point final,
   puis cliquez sur la coche verte pour enregistrer.

   ```
   ns-1234.awsdns-12.org
   ns-567.awsdns-34.net
   ns-89.awsdns-56.com
   ns-1890.awsdns-78.co.uk
   ```

5. Namecheap affiche « DNS server update may take up to 48 hours ». En pratique, cela prend
   souvent de 5 à 30 minutes.

Pour vérifier (à relancer jusqu'à obtenir les serveurs AWS), utilisez `make dns`, ou directement :

```bash
dig +short NS votre-domaine.com @8.8.8.8
# attendu : les 4 serveurs awsdns
```

> Les serveurs de noms ne changent plus ensuite, même après `make detruire` et une
> reconstruction, car la zone vit dans le bootstrap. Cette étape n'est faite **qu'une fois**.

## Étape 2 : paramètres de l'environnement

```bash
cd terraform/environments/prod
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
cd -
```

1. Dans `backend.hcl`, remplacez `<ID_COMPTE_AWS>` : le nom exact est la sortie `bucket_etat`
   de l'étape 1.
2. Dans `terraform.tfvars`, **renseignez `email_alertes`** et **`domaine`**, avec la même
   valeur qu'au bootstrap. Les autres valeurs par défaut conviennent :

| Variable | Défaut | Rôle |
|---|---|---|
| `email_alertes` | — | **Obligatoire** : destinataire des alertes de budget |
| `type_instance` | `t3.large` | 8 Go de mémoire (voir [coûts](08-couts.md)) |
| `budget_mensuel_usd` | `30` | Alertes à 50, 80 et 100 % du réel, et à 100 % du prévisionnel |
| `domaine` | `""` | Domaine Route 53, qui donne `app.`, `auth.`, puis la racine et `www` redirigés. Vide : `app.<ip>.sslip.io` |
| `donnees_demo` | `true` | Jeu de démonstration et 6 comptes (un par rôle) |
| `mfa_obligatoire` | `false` | Le backend exige l'OTP dans les jetons |
| `arret_automatique` | `true` | Arrêt chaque soir à 20 h (heure de Paris) |
| `demarrage_automatique` | `false` | Démarrage à 8 h du lundi au vendredi |
| `retention_sauvegardes_jours` | `14` | Durée de conservation dans S3 |

```bash
make init
```

Résultat attendu : `Terraform has been successfully initialized!`, puis l'installation des
collections Ansible.

## Étape 3 : créer l'infrastructure

```bash
make plan     # facultatif : liste les ressources qui seront créées (≈ 40)
make apply    # répondre « yes »
```

Durée : environ 3 minutes. Résultat attendu :

```
Outputs:
bucket_sauvegardes  = "logiflow-prod-sauvegardes-123456789012"
bucket_transferts   = "logiflow-prod-transferts-123456789012"
enregistrements_dns = ["votre-domaine.com", "www.votre-domaine.com", "app.votre-domaine.com", "auth.votre-domaine.com"]
instance_id         = "i-0abc123def4567890"
ip_publique         = "13.38.1.2"
prefixe_ssm         = "/logiflow/prod"
region              = "eu-west-3"
url_application     = "https://app.votre-domaine.com"
url_keycloak        = "https://auth.votre-domaine.com"
```

Avant l'étape 5, **le DNS doit résoudre**, sinon Caddy ne peut pas obtenir les certificats :

```bash
dig +short app.votre-domaine.com @8.8.8.8     # attendu : ip_publique
```

À ce stade :

- le serveur Ubuntu tourne, mais aucune application n'est installée ;
- tous les secrets (mots de passe des bases, de Keycloak et des comptes de démo, clés internes)
  ont été **générés** dans SSM Parameter Store ;
- les services de sécurité AWS sont actifs : GuardDuty, CloudTrail, VPC Flow Logs, Access Analyzer ;
- AWS envoie **un e-mail de confirmation** pour les alertes de sécurité (SNS). **Cliquez sur « Confirm
  subscription »**, sinon aucune alerte ne vous parviendra. Les alertes de budget, elles, arrivent
  directement.

> Attendez **2 à 3 minutes** avant l'étape 5 : l'agent SSM du serveur doit s'enregistrer. Pour
> vérifier : `aws ssm describe-instance-information --query 'InstanceInformationList[].PingStatus'`
> doit afficher `Online`.

## Étape 4 : enregistrer la clé LLM

```bash
make secret-llm CLE=gsk_votre_cle
```

Résultat attendu : `clé LLM enregistrée`.

> Astuce : précédez la commande d'une espace pour qu'elle n'entre pas dans l'historique du shell
> (`HISTCONTROL=ignorespace`, réglage par défaut sous Ubuntu).

Si les paquets GHCR sont **privés**, enregistrez aussi `ghcr-user` et `ghcr-token` maintenant
(voir [§ 2.3](02-prerequis.md#images-docker-ghcr)).

## Étape 5 : configurer le serveur et déployer

```bash
make configure
```

Ansible se connecte au serveur **par SSM**, sans SSH, et exécute dans l'ordre :

| Rôle | Actions |
|---|---|
| `base` | Paquets, mises à jour de sécurité automatiques, fuseau Europe/Paris, swap de 2 Go, désactivation de SSH |
| `docker` | Docker Engine et Compose depuis le dépôt officiel, rotation des journaux |
| `logiflow` | Lecture des secrets et de la configuration dans SSM, copie de la stack dans `/opt/logiflow`, génération de `.env` (droits 600), puis `deployer.sh` : téléchargement des images, démarrage, comptes Keycloak, contrôle de santé HTTPS |
| `sauvegardes` | Sauvegarde quotidienne à 19 h 45 vers S3 |

Durée : environ 10 minutes au premier passage (téléchargement des images, première migration de
base, émission des certificats). Résultat attendu, en fin de journal :

```
[...] OK : https://app.votre-domaine.com répond
SERVICE    STATUS
backend    Up 2 minutes (healthy)
...
PLAY RECAP
i-0abc123def4567890 : ok=42 changed=30 unreachable=0 failed=0
```

## Étape 6 : vérifier

```bash
make identifiants
```

Résultat :

```
Application : https://app.votre-domaine.com
Keycloak    : https://auth.votre-domaine.com/admin
Admin Keycloak : admin / Xy...
Comptes de démo (admin, responsable, exploitant, commercial, atelier, chauffeur) : Ab...
```

Parcours de vérification :

1. Ouvrir l'URL de l'application : on est redirigé vers la page de connexion LogiFlow de
   Keycloak.
2. Se connecter avec `admin` et le mot de passe de démo : le tableau de bord s'affiche.
3. Ouvrir un module, par exemple **Flotte** : les données de démonstration sont présentes.
4. Ouvrir le **copilote** et poser une question (« Quels véhicules sont en maintenance ? »). La
   réponse doit arriver en flux continu (streaming).
5. `make etat` : tous les services sont `healthy` et l'API répond `UP`.
6. Ouvrir `https://votre-domaine.com` et `https://www.votre-domaine.com` : on doit être redirigé
   vers `https://app.votre-domaine.com`.

**LogiFlow est en production.** Le serveur s'arrêtera ce soir à 20 h ; il se relance par
`make demarrer`.

## Étape 7 : brancher GitHub Actions (facultatif)

Cette étape permet d'appliquer Terraform et de déployer depuis GitHub, sans poste configuré.

1. Poussez le dépôt sur GitHub, si ce n'est déjà fait.
2. *Settings → Environments → New environment* : `production`. Cochez **Required reviewers**
   (vous-même) : chaque `apply` et chaque déploiement demandera une approbation.
3. *Settings → Secrets and variables → Actions → **Variables*** (ce ne sont pas des secrets, car
   il n'y a aucune clé) :

| Variable | Valeur (sorties de l'étape 1) |
|---|---|
| `AWS_ROLE_TERRAFORM` | `arn:aws:iam::<compte>:role/logiflow-github-terraform` |
| `AWS_ROLE_DEPLOIEMENT` | `arn:aws:iam::<compte>:role/logiflow-github-deploiement` |
| `TF_STATE_BUCKET` | `logiflow-tfstate-<compte>` |
| `EMAIL_ALERTES` | la même adresse que dans `terraform.tfvars` |
| `DOMAINE` | le même domaine que dans `terraform.tfvars` (vide avec sslip.io) |

4. Test : *Actions → Déployer → Run workflow*, puis approuver. Le workflow démarre le serveur
   s'il est arrêté, et déploie. Une fois le déploiement réussi, le workflow **DAST (OWASP ZAP)**
   s'exécute automatiquement : son rapport est dans les artefacts.
5. **Sécurité des 4 dépôts** : activez *Secret scanning*, *Push protection* et les alertes
   Dependabot (commande prête à l'emploi dans
   [Outils de sécurité § 10.1](10-outils-securite.md#réglages-github-à-activer-une-fois-par-dépôt)).

Le fonctionnement détaillé, et le déploiement automatique à chaque push des dépôts applicatifs,
sont décrits dans [CI/CD](06-ci-cd.md).

---

## Variante : sans domaine (sslip.io)

Laissez `domaine = ""` dans les deux `terraform.tfvars` et sautez l'étape 1 bis. L'application
est alors servie sur `https://app.<ip-avec-tirets>.sslip.io`, avec un certificat valide, sans
aucune configuration DNS.

## Changer de domaine plus tard

1. Au bootstrap, mettez la nouvelle valeur de `domaine`. Terraform refusera de supprimer
   l'ancienne zone (`prevent_destroy`) : retirez-la d'abord de l'état avec
   `terraform -chdir=terraform/bootstrap state rm 'aws_route53_zone.principale[0]' 'aws_route53_record.caa[0]'`,
   puis supprimez-la dans la console Route 53 si elle n'est plus utile.
2. `make bootstrap`, puis refaites l'étape 1 bis avec les nouveaux serveurs de noms.
3. Mettez le nouveau `domaine` dans `terraform/environments/prod/terraform.tfvars` (et dans la
   variable GitHub `DOMAINE`), puis lancez `make apply` et `make configure-app`.

Caddy obtient les nouveaux certificats automatiquement. `keycloak-init` réaligne les URL
autorisées du client `logiflow-frontend` (redirections, origines) à chaque déploiement.

## En cas d'échec

Consultez le [Dépannage](09-depannage.md). Les étapes sont **idempotentes** : après correction,
relancez simplement la commande qui a échoué (`make apply`, `make configure`).
