# 8. Coûts

> Tarifs publics AWS pour `eu-west-3` (Paris), en USD hors taxes, à la date de rédaction.
> Vérifiez-les avec le [AWS Pricing Calculator](https://calculator.aws/). Les ordres de grandeur
> suffisent pour piloter un budget de 70 $.

## 8.1 Ce qui est facturé

| Ressource | Tarif | Facturé quand |
|---|---|---|
| EC2 `t3.large` (2 vCPU, 8 Go) | ≈ 0,099 $/h | **Uniquement quand l'instance tourne** |
| Disque EBS gp3 30 Go | ≈ 0,093 $/Go/mois, soit ≈ **2,80 $/mois** | En permanence |
| IPv4 publique (Elastic IP) | 0,005 $/h, soit ≈ **3,65 $/mois** | En permanence (même instance arrêtée) |
| S3 (état, sauvegardes, transferts) | ≈ 0,024 $/Go/mois | Quelques Go, donc < 0,20 $ |
| Alarme CloudWatch | 0,10 $/mois | En permanence |
| Transfert sortant | 100 Go/mois gratuits | Négligeable pour une démonstration |
| SSM Parameter Store (standard), Session Manager, Run Command | Gratuit | — |
| KMS (clé gérée par AWS), IAM, OIDC | Gratuit | — |
| AWS Budgets (2 premiers budgets) | Gratuit | — |
| EventBridge Scheduler | Gratuit (14 M d'invocations/mois) | — |
| Groq (LLM) | Offre gratuite | Hors AWS |

**Coût fixe**, même serveur arrêté : environ **6,90 $/mois** (disque + IP + alarme).

## 8.2 Scénarios

| Utilisation | Heures/mois | Calcul | **Total/mois** |
|---|---|---|---|
| Serveur arrêté (entre deux périodes de test) | 0 | fixe | **≈ 7 $** |
| À la demande (≈ 3 h par jour ouvré) | 60 | 6 $ + fixe | **≈ 13 $** |
| Jours ouvrés 8 h – 20 h (démarrage auto) | 264 | 26 $ + fixe | **≈ 33 $** |
| Allumé 24 h/24 (sans arrêt auto) | 730 | 72 $ + fixe | **≈ 80 $** ⚠ |

**Avec 70 $ de crédits :**

- l'usage à la demande tient **environ 5 mois** ;
- l'allumage en jours ouvrés tient **environ 2 mois** ;
- l'allumage permanent ne tient **même pas un mois**. C'est pourquoi l'arrêt automatique de 20 h
  est activé par défaut.

## 8.3 Garde-fous en place

1. **Arrêt automatique à 20 h** chaque jour (EventBridge Scheduler) : un oubli ne coûte au plus
   qu'une soirée.
2. **Budget mensuel** (`budget_mensuel_usd`, 30 $ par défaut) avec e-mails :
   - à 50 %, 80 % et 100 % de la dépense **réelle** ;
   - à 100 % de la dépense **prévue** en fin de mois (alerte précoce).
3. **Aucune ressource coûteuse cachée** : ni NAT Gateway (≈ 35 $/mois), ni ALB (≈ 20 $/mois),
   ni RDS, ni instance GPU.
4. Cycle de vie S3 : les sauvegardes expirent après 14 jours, les transferts après 1 jour.

> Les alertes de budget se basent sur le coût **avant crédits**, ce qui est le bon indicateur de
> consommation des crédits. Validez l'e-mail de confirmation d'abonnement envoyé par AWS après
> le premier `make apply`.

## 8.4 Réduire encore

| Levier | Économie | Contrepartie |
|---|---|---|
| `type_instance = "t3.medium"` (4 Go, ≈ 0,050 $/h) | Calcul divisé par 2 | Stack à l'étroit : réduire les limites mémoire, démarrages lents, risque d'OOM |
| Arrêter dès la fin de la séance (`make arreter`) | Heures non consommées | Discipline |
| `taille_disque_go = 20` | ≈ 0,90 $/mois | Moins de marge pour images et sauvegardes locales |
| Instance Spot | ≈ -60 % sur le calcul | Interruption possible : déconseillé pour une soutenance |
| Détruire entre deux périodes (`make detruire`) | Supprime le coût fixe (7 $) | Données perdues sauf sauvegarde archivée ; reconstruction ≈ 20 min |

## 8.5 Suivre la consommation

- **Billing → Credits** : crédits restants et date d'expiration.
- **Cost Explorer**, filtré par le tag `Projet = logiflow` : toutes les ressources portent les
  tags `Projet`, `Environnement`, `GereePar` et `Depot`. Pour activer ce filtre, allez dans
  *Billing → Cost allocation tags* et activez `Projet` ; le filtre est disponible au bout de 24 h.
- `make statut` : vérifier qu'aucune instance ne tourne inutilement.

## 8.6 Planning type pour un projet d'étude

| Période | Réglage | Coût estimé |
|---|---|---|
| Mise en place et tests (2 semaines) | À la demande | ≈ 7 $ |
| Recette et préparation de la soutenance (2 semaines) | Démarrage auto en jours ouvrés | ≈ 17 $ |
| Semaine de soutenance | `arret_automatique = false` pendant 3 jours | ≈ 10 $ |
| Après la soutenance | `make detruire` (après archivage d'une sauvegarde) | 0 $ |
| **Total** | | **≈ 35 $** sur 70 $ |
