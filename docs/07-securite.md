# 7. Sécurité

## 7.1 Surface exposée

| Port | Service | Remarque |
|---|---|---|
| 80/tcp | Caddy | Redirection vers HTTPS et validation Let's Encrypt uniquement |
| 443/tcp, 443/udp | Caddy | HTTPS (TLS 1.2+, HTTP/2, HTTP/3) |
| **22** | — | **Fermé**, et le service SSH est désactivé |

- PostgreSQL, le backend, le service IA et Keycloak ne publient **aucun port** : ils ne sont
  joignables que sur le réseau Docker interne.
- Sur `auth.<domaine>`, les points `/metrics` et `/health` de Keycloak sont bloqués par Caddy.
- Le groupe de sécurité par défaut du VPC est vidé de toute règle.

## 7.2 Accès d'administration

| Accès | Mécanisme |
|---|---|
| Terminal sur le serveur | **SSM Session Manager** (`make console`) : identité IAM, aucune clé SSH, aucun port |
| Configuration (Ansible) | Connecteur `aws_ssm` : les fichiers transitent par un bucket S3 privé purgé chaque jour |
| Déploiement (GitHub) | SSM Run Command, rôle OIDC restreint (voir [CI/CD](06-ci-cd.md#63-authentification-sans-clé-oidc)) |
| Console Keycloak | `https://auth.<domaine>/admin`, compte `admin` dont le mot de passe est généré |

Chaque session et chaque commande SSM est tracée dans AWS CloudTrail (historique de 90 jours,
gratuit).

## 7.3 Secrets

- **Générés** par Terraform (`random_password`, 32 caractères), jamais saisis ni choisis à la
  main.
- **Stockés** dans SSM Parameter Store en `SecureString`, chiffrés par KMS (clé gérée par AWS).
- **Lus** par Ansible au moment du déploiement et écrits dans `/opt/logiflow/.env` (droits
  `600`, root). Tâches marquées `no_log`.
- **Jamais dans Git** : `.gitignore` exclut `.env`, `*.tfvars`, `backend.hcl` et l'état
  Terraform.
- Clés **distinctes par sens** entre le backend et le service IA : `AI_INTERNAL_API_KEY` pour
  Spring vers l'IA, `AI_CALLBACK_API_KEY` pour les outils du copilote vers Spring.
- Chaque composant a son propre **rôle PostgreSQL** : `logiflow`, `logiflow_ai` et `keycloak`
  ont chacun leur base et leur mot de passe.

> L'**état Terraform** contient les secrets générés en clair. Il est stocké dans un bucket S3
> **chiffré, versionné, privé**, et accessible uniquement aux administrateurs et au rôle
> Terraform.

## 7.4 Identités et autorisations

- **Keycloak** (OIDC, *Authorization Code* + PKCE, client public sans secret) :
  - protection contre la force brute activée ;
  - MFA (OTP) activable (`mfa_obligatoire`) ;
  - redirections limitées à `https://app.<domaine>/connexion/retour`.
- **Backend** (profil `prod`) :
  - toute requête `/api/**` exige un jeton JWT valide : signature, émetteur
    `https://auth.<domaine>/realms/logiflow`, expiration ;
  - autorisations par rôle (6 rôles métier) ;
  - aucun accès anonyme ;
  - `/actuator/health` sans détails.
- **Rôle IAM du serveur** (moindre privilège) :
  - SSM (agent) ;
  - lecture de **ses** paramètres (`/logiflow/prod/*`) ;
  - lecture et écriture dans **ses** deux buckets.
  - Il n'a aucun autre droit.

## 7.5 Durcissement

| Couche | Mesure |
|---|---|
| Instance | IMDSv2 obligatoire (protection SSRF), disque EBS chiffré, mises à jour de sécurité Ubuntu automatiques |
| Docker | Rotation des journaux, `live-restore`, limites mémoire par conteneur, frontend nginx **non-root** |
| Keycloak | Image **optimisée** (`kc.sh build`) ; démarrage `--optimized` en mode production, derrière proxy (`xforwarded`) |
| HTTP | Caddy pose `Strict-Transport-Security`, `X-Content-Type-Options` et `Referrer-Policy`, et supprime `Server`. nginx (frontend) ajoute `X-Frame-Options: DENY`. Keycloak gère ses propres en-têtes (CSP, cadres) |
| S3 | Accès public bloqué, chiffrement, versionnage (état), cycle de vie |
| DNS | Zone Route 53 versionnée dans Terraform ; enregistrement **CAA** limitant l'émission de certificats à Let's Encrypt et Sectigo ; zone protégée contre la suppression accidentelle |
| Réseau | Aucun port d'administration ; flux internes uniquement sur le réseau Docker |

## 7.6 Sauvegarde et continuité

- Sauvegarde quotidienne hors du serveur (S3) : bases, pièces jointes et comptes Keycloak.
- Restauration testable en une commande ([Exploitation § 5.6](05-exploitation.md#56-restaurer)).
- Récupération automatique de l'instance en cas de panne matérielle (alarme CloudWatch).
- **RPO** : 24 h (sauvegarde quotidienne). **RTO** : environ 30 min (restauration), ou environ
  1 h pour reconstruire depuis zéro (`make apply`, `make configure`, restauration).

## 7.7 Écarts assumés

Choix faits en connaissance de cause pour un projet d'étude au budget de 70 $, avec la
correction à apporter en contexte réel :

| Écart | Raison | En production réelle |
|---|---|---|
| Instance dans un sous-réseau **public** | Pas de passerelle NAT (≈ 35 $/mois) ; seuls 80/443 sont ouverts | Sous-réseau privé + ALB + NAT ou points de terminaison VPC |
| **Pas de WAF** managé | Coût (≈ 10 $/mois minimum) ; compensé par CrowdSec (scénarios HTTP, CVE, réputation) | AWS WAF devant un ALB ou CloudFront |
| **Pas de haute disponibilité** | Coût : une seule instance | Plusieurs zones, base managée (RDS Multi-AZ) |
| PostgreSQL **en conteneur** | Coût (RDS ≈ 15 $/mois minimum) | Amazon RDS, sauvegardes PITR |
| Groupe de sécurité ouvert en **sortie** | Images, LLM, OSRM, Let's Encrypt, API AWS | Proxy de sortie ou liste de destinations |
| Rôle Terraform CI large sur EC2, SSM et les services de sécurité (S3 limité aux buckets `logiflow-*`) | Simplicité ; limité par la confiance OIDC et l'approbation manuelle | Permissions au niveau des ressources, *permission boundary* |
| Clé KMS **gérée par AWS** | Gratuit | Clé KMS client avec rotation (1 $/mois) |
| Journaux applicatifs **locaux** (Docker) ; audit AWS dans S3 | Pas de coût CloudWatch Logs ; CrowdSec analyse les journaux sur place | Centralisation (CloudWatch Logs ou Loki) et alertes |
| Pas de **Security Hub** ni **AWS Config** | ≈ 10 $/mois ; GuardDuty, Access Analyzer et Trivy couvrent l'essentiel | Security Hub (CIS, FSBP) et Config (conformité continue) |
| Pas de **CSP** stricte sur l'application | Nécessite d'auditer les styles et scripts d'Angular ; signalé par ZAP (`WARN`) | En-tête `Content-Security-Policy` dans nginx |
| Pas de **DNSSEC** sur la zone | Configuration plus lourde (clé KMS dédiée, DS chez Namecheap) | DNSSEC Route 53 + enregistrement DS chez le registraire |
| Swagger UI **public** | Démonstration de l'API | `API_DOCS_ENABLED=false` |

Dans le code, chaque écart d'infrastructure est justifié **sur la ressource concernée**, par un
commentaire `#trivy:ignore:AWS-XXXX`. L'analyse Trivy de l'IaC ne remonte donc aucun écart non
justifié, et sa porte CRITICAL reste active.

## 7.8 Outils de sécurité

La chaîne DevSecOps complète (CI, DAST, serveur, AWS), le traitement des vulnérabilités et la
réaction aux alertes sont décrits dans [Outils de sécurité](10-outils-securite.md).

## 7.9 Checklist avant une démonstration publique

- [ ] `make identifiants` : changer le mot de passe `admin` de Keycloak dans la console.
- [ ] Ne pas projeter les secrets : `make identifiants` les affiche en clair.
- [ ] Vérifier la note A de <https://www.ssllabs.com/ssltest/> sur `app.<domaine>`.
- [ ] Vérifier que <https://securityheaders.com> détecte HSTS et les autres en-têtes.
- [ ] Faire une sauvegarde récente (`make sauvegardes`).
- [ ] Onglet *Security* des 4 dépôts : aucune alerte critique ouverte.
- [ ] Dernier rapport ZAP sans `FAIL`, et `make audit` pour relever l'indice Lynis.
- [ ] `make alertes-securite` : aucune découverte GuardDuty inexpliquée.
- [ ] Après la démonstration : `donnees_demo = false` si l'application est ouverte au public.
