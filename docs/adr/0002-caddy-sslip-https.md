# ADR 0002 : Caddy et sslip.io pour un HTTPS sans domaine acheté

- **Statut** : acceptée
- **Date** : 2026-09-26

## Contexte

Keycloak (OIDC) exige HTTPS en production : cookies `Secure` et contraintes des navigateurs sur
PKCE hors `localhost`. Il faut donc un nom de domaine et un certificat valides, alors que le
projet ne possède pas de domaine. L'application et Keycloak doivent avoir des origines distinctes
et stables, qui restent les mêmes d'un redémarrage à l'autre.

## Décision

- **Caddy** sert de reverse proxy. Il obtient et renouvelle automatiquement les certificats
  Let's Encrypt (repli ZeroSSL), et gère HTTP/2, HTTP/3 et les redirections.
- Les domaines par défaut sont **`app.<ip>.sslip.io`** et **`auth.<ip>.sslip.io`**. Le service
  DNS public sslip.io résout ces noms vers l'IP qu'ils contiennent.
- L'IP est **fixe** (Elastic IP), donc domaines et certificats survivent aux arrêts.
- Un domaine personnalisé se configure par une seule variable Terraform (`domaine`).
- L'API est servie sous `app.<domaine>/api`, à la **même origine** que l'interface : il n'y a pas
  de CORS côté navigateur.

## Alternatives

| Option | Rejet |
|---|---|
| ALB + ACM | ≈ 20 $/mois, et ACM exige un domaine |
| nginx + certbot | Plus de configuration et de pièces mobiles (cron de renouvellement, rechargement) |
| CloudFront devant l'instance | Complexité pour le SSE du copilote et les WebSockets de Keycloak |
| Domaine acheté + Route 53 | Possible (≈ 12 $/an), pas nécessaire pour un projet d'étude : prévu en option |

## Conséquences

- (+) HTTPS valide sans coût ni démarche.
- (+) Le Caddyfile tient en 40 lignes, et le streaming SSE est configuré explicitement
  (`flush_interval -1`).
- (−) L'application dépend de la disponibilité de sslip.io. En cas de problème, on bascule sur
  un domaine propre.
- (−) Les limites de débit Let's Encrypt s'appliquent au domaine sslip.io partagé. En pratique,
  Caddy bascule sur ZeroSSL, et le volume `caddy-data` évite les réémissions.
