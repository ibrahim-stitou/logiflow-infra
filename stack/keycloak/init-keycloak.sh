#!/bin/bash
# Configuration du realm « logiflow » après son import (tâche ponctuelle keycloak-init).
# Idempotent : rejoué sans risque à chaque déploiement.
#
# - DEMO_DATA=true : crée (ou met à jour) les 6 utilisateurs de démonstration, un par rôle, avec
#   le mot de passe DEMO_USERS_PASSWORD.
# - DEMO_DATA=false : désactive ces comptes s'ils existent (les comptes réels se créent dans la
#   console d'administration, voir docs/05-exploitation.md).
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
REALM=logiflow
export HOME=/tmp   # kcadm écrit sa configuration dans $HOME/.keycloak

echo "keycloak-init: connexion à l'API d'administration"
$KCADM config credentials --server http://keycloak:8080 --realm master \
  --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

# URL du frontend : l'import ne s'applique qu'à la création du realm ; on réaligne le client à
# chaque déploiement (changement de domaine ou d'IP).
if [[ -n "${LOGIFLOW_APP_URL:-}" ]]; then
  client=$($KCADM get clients -r "$REALM" -q clientId=logiflow-frontend --fields id --format csv --noquotes | head -n1)
  $KCADM update "clients/$client" -r "$REALM" \
    -s "rootUrl=$LOGIFLOW_APP_URL" \
    -s "redirectUris=[\"$LOGIFLOW_APP_URL/connexion/retour\"]" \
    -s "webOrigins=[\"$LOGIFLOW_APP_URL\"]" \
    -s "attributes.\"post.logout.redirect.uris\"=$LOGIFLOW_APP_URL/connexion"
  echo "keycloak-init: client logiflow-frontend aligné sur $LOGIFLOW_APP_URL"
fi

# identifiant:rôle:prénom:nom
UTILISATEURS_DEMO=(
  "admin:ADMINISTRATEUR:Amina:Admin"
  "responsable:RESPONSABLE_EXPLOITATION:Rachid:Responsable"
  "exploitant:EXPLOITANT:Salma:Exploitante"
  "commercial:COMMERCIAL:Karim:Commercial"
  "atelier:ATELIER:Youssef:Atelier"
  "chauffeur:CHAUFFEUR:Hamza:Chauffeur"
)

id_utilisateur() {
  $KCADM get users -r "$REALM" -q "username=$1" -q exact=true --fields id --format csv --noquotes | head -n1
}

for entree in "${UTILISATEURS_DEMO[@]}"; do
  IFS=: read -r login role prenom nom <<<"$entree"
  id=$(id_utilisateur "$login")

  if [[ "${DEMO_DATA:-false}" != "true" ]]; then
    if [[ -n "$id" ]]; then
      $KCADM update "users/$id" -r "$REALM" -s enabled=false
      echo "keycloak-init: compte de démo $login désactivé"
    fi
    continue
  fi

  if [[ -z "${DEMO_USERS_PASSWORD:-}" ]]; then
    echo "keycloak-init: DEMO_USERS_PASSWORD vide, utilisateurs de démo ignorés" >&2
    break
  fi

  if [[ -z "$id" ]]; then
    $KCADM create users -r "$REALM" -s "username=$login" -s enabled=true \
      -s "firstName=$prenom" -s "lastName=$nom" -s "email=$login@logiflow.demo" \
      -s emailVerified=true >/dev/null
    id=$(id_utilisateur "$login")
    echo "keycloak-init: utilisateur $login créé"
  else
    $KCADM update "users/$id" -r "$REALM" -s enabled=true
  fi
  $KCADM set-password -r "$REALM" --userid "$id" --new-password "$DEMO_USERS_PASSWORD"
  $KCADM add-roles -r "$REALM" --uid "$id" --rolename "$role"
done

echo "keycloak-init: terminé (DEMO_DATA=${DEMO_DATA:-false})"
