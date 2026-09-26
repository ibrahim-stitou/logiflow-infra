#!/bin/bash
# Exécute une commande shell sur le serveur LogiFlow via AWS SSM Run Command (sans SSH) et affiche
# sa sortie. Utilisé par le Makefile et par le workflow GitHub « Déployer ».
#
# Usage : scripts/ssm-exec.sh <instance-id> "<commande>" [délai max en secondes, défaut 900]
set -euo pipefail

INSTANCE_ID=${1:?instance-id manquant}
COMMANDE=${2:?commande manquante}
DELAI=${3:-900}
REGION=${AWS_REGION:-eu-west-3}

PARAMETRES=$(jq -nc --arg c "$COMMANDE" '{commands: [$c], executionTimeout: ["3600"]}')

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "logiflow: $(echo "$COMMANDE" | cut -c1-80)" \
  --parameters "$PARAMETRES" \
  --query Command.CommandId --output text)

echo "commande SSM $COMMAND_ID envoyée à $INSTANCE_ID"

FIN=$((SECONDS + DELAI))
STATUT=Pending
while [[ $SECONDS -lt $FIN ]]; do
  sleep 5
  STATUT=$(aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUT" in
    Pending|InProgress|Delayed) continue ;;
    *) break ;;
  esac
done

aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" --query StandardOutputContent --output text
ERREURS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" --query StandardErrorContent --output text)
[[ -n "$ERREURS" && "$ERREURS" != "None" ]] && echo "$ERREURS" >&2

echo "statut : $STATUT"
[[ "$STATUT" == "Success" ]]
