# ADR 0005 : chaîne DevSecOps avec des outils open source et gratuits

- **Statut** : acceptée
- **Date** : 2026-09-26

## Contexte

La sécurité doit être vérifiée en continu, du commit à la production, et démontrable dans le
cadre d'un projet d'étude évalué. Le budget est de 70 $ de crédits AWS, les dépôts sont publics
sur GitHub, et l'application est exposée sur Internet (HTTPS). L'incident de mars 2026 sur
`trivy-action`, dont les étiquettes ont été détournées pour voler les secrets des CI, rappelle
aussi que les outils de sécurité font eux-mêmes partie de la surface d'attaque.

## Décision

Une défense en profondeur par couches, avec des outils standards, gratuits (ou presque) et
automatisés :

| Couche | Outils | Politique |
|---|---|---|
| Code | Gitleaks, CodeQL (`security-extended`), Trivy fs, Dependabot | Secrets et CVE CRITIQUES corrigeables **bloquants** ; SAST en alertes |
| IaC | Trivy config | CRITIQUE bloquant ; chaque écart justifié **sur la ressource** (`#trivy:ignore`) |
| Build | Trivy image **avant publication**, SBOM et provenance SLSA | Image applicative vulnérable **jamais publiée** |
| Déploiement | OWASP ZAP baseline après chaque déploiement | Règles `FAIL` sur les en-têtes de sécurité essentiels |
| Hôte | CrowdSec (+ bouncer iptables sur `INPUT` et `DOCKER-USER`), auditd, Lynis, sysctl durcis, conteneurs non-root sans capacités, `no-new-privileges` | Blocage automatique ; audits hebdomadaires |
| Cloud | GuardDuty, IAM Access Analyzer, CloudTrail (fichiers signés), VPC Flow Logs, alertes e-mail | Détection et traçabilité |

Principes associés :

- les actions de sécurité sont **épinglées par SHA de commit** ;
- les portes ne bloquent que sur ce qui est **actionnable** (CVE avec correctif) ;
- toute exception est **justifiée et datée**.

## Alternatives

| Option | Rejet |
|---|---|
| SonarCloud, Snyk | Comptes et jetons supplémentaires, limites des offres gratuites ; CodeQL et Trivy couvrent le même besoin |
| AWS Security Hub + Config | ≈ 10 $/mois : 15 % du budget pour une vue agrégée, sans détection supplémentaire |
| AWS WAF | Nécessite un ALB ou CloudFront (≥ 20 $/mois) ; CrowdSec couvre scans, force brute et CVE connues |
| Wazuh (SIEM) | 4 à 8 Go de mémoire : il faudrait un second serveur |
| Fail2ban | Pas de scénarios HTTP maintenus ni de réputation partagée ; ne gère pas `DOCKER-USER` nativement |
| Porte bloquante sur toutes les CVE HIGH | Blocages permanents sur des CVE sans correctif ou non exploitables, puis contournements |

## Conséquences

- (+) Chaque couche du cycle de vie est contrôlée, et les résultats sont centralisés dans
  l'onglet *Security* de GitHub et par e-mail.
- (+) Dès la mise en place, la chaîne a détecté et fait corriger :
  - 3 CVE CRITIQUES de Tomcat (backend) ;
  - une CVE CRITIQUE d'OpenSSL dans l'image de base du frontend ;
  - un conteneur IA exécuté en root.
- (+) Coût AWS d'environ 1 $/mois, à l'issue de la période gratuite de GuardDuty.
- (−) CrowdSec bloque aussi les scanners légitimes (ZAP) : il faut les débloquer ponctuellement.
- (−) Les images tierces (PostgreSQL, Keycloak) ne sont pas bloquantes. On les suit chaque
  semaine, et elles se mettent à jour via Dependabot.
- (−) Les journaux applicatifs restent locaux (pas de SIEM). CloudTrail et Flow Logs sont
  conservés dans S3 pour les investigations.
