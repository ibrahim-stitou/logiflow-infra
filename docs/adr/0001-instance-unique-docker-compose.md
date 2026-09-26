# ADR 0001 : une instance EC2 unique avec Docker Compose

- **Statut** : acceptée
- **Date** : 2026-09-26
- **Remplace** : l'infrastructure initiale (3 instances, dont une GPU pour Ollama, sans
  authentification ni HTTPS)

## Contexte

LogiFlow compte 6 composants : Angular, Spring Boot, le service IA Flask, Keycloak, PostgreSQL
(PostGIS, pgvector) et un reverse proxy. Le projet est un projet d'étude, évalué, avec un budget
de **70 $ de crédits AWS**. L'infrastructure doit être disponible pendant les périodes de test et
la soutenance, et démontrer des pratiques professionnelles :

- IaC ;
- secrets gérés ;
- HTTPS ;
- sauvegardes ;
- CI/CD ;
- moindre privilège.

La première version (3 EC2, dont une GPU) coûtait plusieurs centaines de dollars par mois. Elle
ne comportait ni Keycloak, ni la base du service IA, ni HTTPS.

## Décision

Toute la stack s'exécute sur **une instance `t3.large`** avec **Docker Compose**. L'instance est
provisionnée par Terraform, configurée par Ansible et arrêtée automatiquement chaque soir. Le LLM
est **externalisé** (Groq, API compatible OpenAI) au lieu d'un GPU auto-hébergé.

## Alternatives étudiées

| Option | Coût mensuel estimé | Rejet |
|---|---|---|
| 3 EC2 en sous-réseau privé + NAT + ALB | ≈ 150 $ | Budget épuisé en 2 semaines |
| ECS Fargate + RDS + ALB | ≈ 90 $ | Budget, et complexité sans bénéfice à cette échelle |
| EKS | ≥ 75 $ (plan de contrôle seul) | Disproportionné |
| EC2 GPU + Ollama | ≥ 400 $ | Hors budget ; Groq est gratuit et plus rapide |
| **1 EC2 + Compose, arrêt nocturne** | **≈ 13 à 33 $** | Retenue |

## Conséquences

- (+) La stack Compose est **identique** en local et en production (`make local-up`).
- (+) L'exploitation est simple : une commande par opération, et la reconstruction complète
  prend environ 20 min.
- (+) Le budget tient pendant toute la durée du projet ([Coûts](../08-couts.md)).
- (−) Il n'y a pas de haute disponibilité. C'est compensé par la récupération automatique de
  l'instance et des sauvegardes quotidiennes hors du serveur.
- (−) PostgreSQL tourne en conteneur (pas de PITR). Le RPO est de 24 h.
- Évolution : les frontières sont nettes (un conteneur par composant, configuration par
  variables d'environnement). Une migration vers ECS et RDS ne modifierait pas les images.
