#!/bin/bash
# Déploie (ou met à jour) la stack LogiFlow sur le serveur : récupère les images, redémarre les
# services modifiés, rejoue l'initialisation de Keycloak et attend que tout soit sain.
#
# Usage (sur le serveur, en root) :  /opt/logiflow/bin/deployer.sh
# Lancé par : Ansible (make configure), GitHub Actions (workflow « Déployer ») via AWS SSM.
set -euo pipefail

cd "$(dirname "$0")/.."
COMPOSE=(docker compose --env-file .env -f compose.yaml)

horodatage() { date '+%Y-%m-%d %H:%M:%S'; }
echo "[$(horodatage)] déploiement de $(pwd)"

"${COMPOSE[@]}" config --quiet

echo "[$(horodatage)] récupération des images"
"${COMPOSE[@]}" pull --quiet

echo "[$(horodatage)] démarrage des services"
"${COMPOSE[@]}" up -d --remove-orphans --wait --wait-timeout 600 \
  caddy frontend backend ai keycloak postgres

echo "[$(horodatage)] configuration de Keycloak"
"${COMPOSE[@]}" run --rm keycloak-init

# Santé vue depuis l'extérieur : l'API répond derrière Caddy.
APP_DOMAIN=$(grep -E '^APP_DOMAIN=' .env | cut -d= -f2-)
for tentative in $(seq 1 30); do
  if curl -fsS --max-time 5 "https://${APP_DOMAIN}/actuator/health" | grep -q '"status":"UP"'; then
    echo "[$(horodatage)] OK : https://${APP_DOMAIN} répond"
    "${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Status}}'
    docker image prune -f >/dev/null
    exit 0
  fi
  echo "[$(horodatage)] attente de l'API (${tentative}/30)"
  sleep 10
done

echo "[$(horodatage)] ÉCHEC : l'API ne répond pas. Journaux récents :" >&2
"${COMPOSE[@]}" logs --tail 50 backend caddy >&2
exit 1
