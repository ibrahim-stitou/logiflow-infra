#!/bin/bash
# Restaure une sauvegarde produite par sauvegarder.sh : les trois bases et les pièces jointes.
# DESTRUCTIF : remplace les données actuelles. Les applications sont arrêtées pendant l'opération.
#
# Usage :
#   /opt/logiflow/bin/restaurer.sh --liste                 archives disponibles (locales et S3)
#   /opt/logiflow/bin/restaurer.sh logiflow-<date>.tar     restaure (téléchargée depuis S3 si absente)
set -euo pipefail

cd "$(dirname "$0")/.."
COMPOSE=(docker compose --env-file .env -f compose.yaml)
DOSSIER=/var/backups/logiflow
BACKUP_BUCKET=$(grep -E '^BACKUP_BUCKET=' .env | cut -d= -f2- || true)

if [[ "${1:-}" == "--liste" || -z "${1:-}" ]]; then
  echo "Locales :"
  find "$DOSSIER" -maxdepth 1 -name 'logiflow-*.tar' -printf '%f\n' 2>/dev/null | sort -r || true
  if [[ -n "$BACKUP_BUCKET" ]]; then
    echo "Sur S3 :"; aws s3 ls "s3://$BACKUP_BUCKET/sauvegardes/" | awk '{print $4}' | sort -r
  fi
  exit 0
fi

NOM=$(basename "$1")
ARCHIVE="$DOSSIER/$NOM"
if [[ ! -f "$ARCHIVE" ]]; then
  [[ -n "$BACKUP_BUCKET" ]] || { echo "archive introuvable : $ARCHIVE" >&2; exit 1; }
  mkdir -p "$DOSSIER"
  aws s3 cp --only-show-errors "s3://$BACKUP_BUCKET/sauvegardes/$NOM" "$ARCHIVE"
fi

read -r -p "Remplacer TOUTES les données par $NOM ? Taper « restaurer » : " confirmation
[[ "$confirmation" == "restaurer" ]] || { echo "annulé"; exit 1; }

TRAVAIL=$(mktemp -d)
trap 'rm -rf "$TRAVAIL"' EXIT
tar xf "$ARCHIVE" -C "$TRAVAIL"
SOURCE=$(find "$TRAVAIL" -mindepth 1 -maxdepth 1 -type d | head -n1)

echo "arrêt des applications (la base reste démarrée)"
"${COMPOSE[@]}" stop caddy frontend backend ai keycloak

# Chaque base appartient au rôle du même nom (logiflow, logiflow_ai, keycloak).
for base in logiflow logiflow_ai keycloak; do
  echo "restauration de $base"
  "${COMPOSE[@]}" exec -T postgres pg_restore -U logiflow -d "$base" --clean --if-exists \
    --no-owner --role="$base" < "$SOURCE/$base.dump"
done

echo "restauration des pièces jointes"
docker run --rm -v logiflow_backend-uploads:/uploads -v "$SOURCE":/entree:ro alpine:3 \
  sh -c 'rm -rf /uploads/* && tar xzf /entree/uploads.tar.gz -C /uploads'

echo "redémarrage"
"$(dirname "$0")/deployer.sh"
