#cloud-config
# Aucune instance n'a le port 22 ouvert dans son security group (voir modules/security) :
# l'accès Ansible passe par un tunnel SSM (voir scripts/ssm-proxy.sh), la clé SSH ci-dessous
# n'étant utilisée qu'à l'intérieur de ce tunnel, jamais exposée à Internet.
ssh_authorized_keys:
  - ${ssh_public_key}

runcmd:
  - [bash, -c, "snap start amazon-ssm-agent || systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service || true"]
