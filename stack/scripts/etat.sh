#!/bin/bash
# État de la stack : services, santé, ressources, disque, dernière sauvegarde.
# Usage : /opt/logiflow/bin/etat.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
COMPOSE=(docker compose --env-file .env -f compose.yaml)
APP_DOMAIN=$(grep -E '^APP_DOMAIN=' .env | cut -d= -f2-)
AUTH_DOMAIN=$(grep -E '^AUTH_DOMAIN=' .env | cut -d= -f2-)

echo "== Services"
"${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Status}}\t{{.Image}}'

echo; echo "== Santé publique"
printf 'API         https://%s/actuator/health  -> ' "$APP_DOMAIN"
curl -fsS --max-time 5 "https://$APP_DOMAIN/actuator/health" || echo "INJOIGNABLE"
echo
printf 'Keycloak    https://%s/realms/logiflow  -> ' "$AUTH_DOMAIN"
curl -fsS -o /dev/null -w '%{http_code}\n' --max-time 5 "https://$AUTH_DOMAIN/realms/logiflow" || echo "INJOIGNABLE"

echo; echo "== Ressources"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
free -h | head -2

echo; echo "== Disque"
df -h / | tail -1

echo; echo "== Dernière sauvegarde"
find /var/backups/logiflow -maxdepth 1 -name 'logiflow-*.tar' -printf '%f\n' 2>/dev/null \
  | sort -r | head -1
