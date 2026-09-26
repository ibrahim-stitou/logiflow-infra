#!/bin/bash
# Sauvegarde les trois bases (logiflow, logiflow_ai, keycloak) et les pièces jointes, puis envoie
# l'archive sur S3 si BACKUP_BUCKET est défini. Conserve les 7 dernières archives localement ;
# côté S3, une règle de cycle de vie (Terraform) supprime les archives de plus de 14 jours.
#
# Usage : /opt/logiflow/bin/sauvegarder.sh        (cron quotidien installé par Ansible)
set -euo pipefail

cd "$(dirname "$0")/.."
COMPOSE=(docker compose --env-file .env -f compose.yaml)
DOSSIER=/var/backups/logiflow
HORODATAGE=$(date -u '+%Y%m%dT%H%M%SZ')
CIBLE="$DOSSIER/$HORODATAGE"
BACKUP_BUCKET=$(grep -E '^BACKUP_BUCKET=' .env | cut -d= -f2- || true)

mkdir -p "$CIBLE"
chmod 700 "$DOSSIER"

for base in logiflow logiflow_ai keycloak; do
  "${COMPOSE[@]}" exec -T postgres pg_dump -U logiflow -d "$base" --format=custom --no-owner \
    > "$CIBLE/$base.dump"
done

# Pièces jointes (volume backend-uploads), lues par un conteneur jetable.
docker run --rm -v logiflow_backend-uploads:/uploads:ro -v "$CIBLE":/sortie alpine:3 \
  tar czf /sortie/uploads.tar.gz -C /uploads .

ARCHIVE="$DOSSIER/logiflow-$HORODATAGE.tar"
tar cf "$ARCHIVE" -C "$DOSSIER" "$HORODATAGE"
rm -rf "$CIBLE"
echo "sauvegarde locale : $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

if [[ -n "$BACKUP_BUCKET" ]]; then
  aws s3 cp --only-show-errors "$ARCHIVE" "s3://$BACKUP_BUCKET/sauvegardes/$(basename "$ARCHIVE")"
  echo "copiée sur s3://$BACKUP_BUCKET/sauvegardes/"
fi

# Rétention locale : les 7 plus récentes.
find "$DOSSIER" -maxdepth 1 -name 'logiflow-*.tar' -printf '%T@ %p\n' | sort -rn | tail -n +8 \
  | cut -d' ' -f2- | xargs -r rm -f
