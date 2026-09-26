# ADR 0004 : domaine Namecheap délégué à Route 53

- **Statut** : acceptée
- **Date** : 2026-09-26
- **Complète** : [ADR 0002](0002-caddy-sslip-https.md), où sslip.io devient le mode de repli

## Contexte

Le projet dispose d'un nom de domaine acheté chez **Namecheap**. L'application doit être servie
sur ce domaine (`app.`, `auth.`, avec la racine et `www` redirigés), et la configuration DNS doit
être **reproductible et versionnée**, comme le reste de l'infrastructure.

## Décision

- Le domaine reste **enregistré** chez Namecheap. Sa **zone DNS** est hébergée par **AWS
  Route 53** : chez Namecheap, les serveurs de noms passent en *Custom DNS* vers les 4 serveurs
  Route 53.
- La **zone** est créée par le **bootstrap** Terraform, avec `prevent_destroy`. Elle survit à la
  destruction de l'environnement : ses serveurs de noms, déclarés une seule fois chez Namecheap,
  ne changent jamais.
- Les **enregistrements** (A `app`, `auth`, racine, `www`) sont gérés par l'environnement `prod`
  (module `dns`), à partir de l'Elastic IP. Une reconstruction les met à jour automatiquement.
- Un enregistrement **CAA** limite l'émission de certificats aux autorités utilisées par Caddy
  (Let's Encrypt, Sectigo/ZeroSSL).
- La racine et `www` sont redirigés (301) vers `app.` par Caddy. Le fichier de site est généré
  par Ansible uniquement quand un domaine est configuré.
- Sans domaine (`domaine = ""`), le fonctionnement sslip.io de l'ADR 0002 reste disponible.

## Alternatives

| Option | Rejet |
|---|---|
| DNS Namecheap (BasicDNS) avec enregistrements saisis à la main | Non versionné, oubli de mise à jour si l'IP change, pas d'automatisation depuis la CI |
| Transférer le domaine vers Route 53 Domains | Frais de transfert, délai ; aucun bénéfice par rapport à la délégation |
| Zone gérée dans l'environnement `prod` | `make detruire` changerait les serveurs de noms : ressaisie chez Namecheap et propagation à chaque reconstruction |
| Provider Terraform Namecheap | API Namecheap soumise à une liste blanche d'IP et à des conditions de solde : inadaptée à la CI |

## Conséquences

- (+) Le DNS est décrit dans le code : `terraform plan` montre toute modification.
- (+) Une reconstruction complète ne demande aucune action manuelle côté DNS.
- (+) La CAA renforce la sécurité ; DNSSEC reste activable plus tard.
- (−) Coût de 0,50 $/mois pour la zone, facturée même serveur détruit.
- (−) Il faut désactiver DNSSEC chez Namecheap pendant la délégation, et recréer dans Route 53
  les éventuels autres enregistrements (e-mail).
- (−) Le rôle Terraform de la CI reçoit des droits Route 53 : lecture, et modification des
  enregistrements uniquement. La zone reste gérée par le poste d'administration.
