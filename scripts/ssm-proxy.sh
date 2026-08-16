#!/usr/bin/env bash
# ProxyCommand pour Ansible/SSH : tunnelise la connexion via AWS SSM Session Manager.
# Aucune instance de ce projet n'a de port 22 ouvert dans son security group (voir
# terraform/modules/security) — c'est ce tunnel qui rend SSH utilisable malgré tout, y compris
# vers les instances sans IP publique (backend, ai).
#
# Prérequis : aws-cli v2 + session-manager-plugin, et des identifiants AWS avec les permissions
# ssm:StartSession sur les instances ciblées.
#
# Utilisé via ansible_ssh_common_args (voir inventory/aws_ec2.yml) :
#   -o ProxyCommand="scripts/ssm-proxy.sh %h %p"
# où %h est l'ID d'instance EC2 (ansible_host doit être l'instance ID, pas une IP).

set -euo pipefail

INSTANCE_ID="$1"
PORT="$2"

exec aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=${PORT}"
