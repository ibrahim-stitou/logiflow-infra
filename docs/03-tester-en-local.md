# 3. Tester la stack de production en local

La stack qui tourne sur le serveur (`stack/`) se lance à l'identique sur un poste. C'est utile
pour valider une modification du `compose.yaml`, du `Caddyfile` ou du realm Keycloak **avant** de
la déployer, sans dépenser de crédits.

> Pour **développer** l'application (rechargement à chaud, profil `local` sans authentification),
> utilisez plutôt le `docker/docker-compose.yml` du dépôt backend. Cette page concerne la stack
> de production.

## 3.1 Prérequis

- Docker Desktop (ou Docker Engine) avec **au moins 6 Go de mémoire** alloués. La stack complète
  consomme environ 3,5 Go au repos.
- Les images GHCR accessibles : paquets publics, ou `docker login ghcr.io` avec un jeton
  `read:packages`.
- `app.localhost` et `auth.localhost` pointent nativement vers `127.0.0.1` dans les navigateurs
  modernes. Pour `curl` ou d'autres outils, ajouter au fichier hosts :
  `127.0.0.1 app.localhost auth.localhost`.

## 3.2 Lancer

```bash
cp stack/.env.example stack/.env
# Renseigner les secrets vides (valeurs quelconques en local) :
for v in DB_PASSWORD AI_DB_PASSWORD KEYCLOAK_DB_PASSWORD KEYCLOAK_ADMIN_PASSWORD \
         AI_INTERNAL_API_KEY AI_CALLBACK_API_KEY DEMO_USERS_PASSWORD; do
  sed -i "s|^$v=$|$v=$(openssl rand -hex 16)|" stack/.env
done
# Facultatif : LLM_API_KEY=gsk_... pour les agents IA

make local-up
```

`make local-up` démarre les 6 services, attend qu'ils soient sains, puis crée les comptes de
démonstration dans Keycloak.

| URL | Contenu |
|---|---|
| <https://app.localhost> | Application (accepter l'avertissement : certificat interne de Caddy) |
| <https://auth.localhost/admin> | Console Keycloak (`admin` / `KEYCLOAK_ADMIN_PASSWORD`) |
| <https://app.localhost/swagger-ui.html> | Documentation de l'API |

Les comptes de démonstration sont `admin`, `responsable`, `exploitant`, `commercial`,
`atelier` et `chauffeur`, tous avec le mot de passe `DEMO_USERS_PASSWORD`.

> **Certificat local** : Caddy émet un certificat depuis sa propre autorité. Le navigateur
> affiche un avertissement, à accepter **sur les deux domaines**. Commencez par ouvrir
> <https://auth.localhost> et acceptez-le, sinon la redirection de connexion échoue
> silencieusement. Pour faire confiance à l'autorité :
> `docker compose -f stack/compose.yaml cp caddy:/data/caddy/pki/authorities/local/root.crt .`
> puis importez le certificat dans le magasin du système.

## 3.3 Opérations

```bash
make local-journaux SERVICE=backend    # suivre un service
cd stack && docker compose ps          # état
make local-down                        # arrêter (données conservées)
make local-down ARGS=-v                # arrêter et effacer toutes les données
```

## 3.4 Validation statique (sans rien lancer)

```bash
make valider
```

Cette commande exécute `terraform fmt` et `validate`, `ansible-lint`, `shellcheck`, puis
`docker compose config`. Ce sont les contrôles du workflow `Qualité`, lancés sur le poste.
