#!/usr/bin/env bash
# Script de vérification locale (fmt/validate déjà faits côté Terraform). Utilisé une fois,
# manuellement, depuis WSL pour vérifier la syntaxe Ansible avant de committer. N'est pas destiné
# à tourner en CI (voir .github/workflows/ansible-lint.yml pour l'équivalent CI, sur un
# filesystem natif Linux où le souci "world writable /mnt/c" ne se pose pas).
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:"$HOME/.local/bin"

cd "$(dirname "$0")/../ansible"
export ANSIBLE_CONFIG="$(pwd)/ansible.cfg"

for playbook in playbooks/*.yml; do
  echo "== syntax-check: ${playbook} =="
  ansible-playbook "${playbook}" --syntax-check -i /dev/null
done

echo "== ansible-lint =="
ansible-lint playbooks roles || true
