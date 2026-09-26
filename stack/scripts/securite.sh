#!/bin/bash
# Tableau de bord sécurité du serveur (voir docs/10-outils-securite.md).
#
# Usage (sur le serveur, en root) :
#   securite.sh etat              CrowdSec : journaux analysés, IP bloquées, dernières alertes
#   securite.sh audit             audit Lynis : indice de durcissement et avertissements
#   securite.sh debloquer <ip>    lève le blocage d'une IP (faux positif)
#   securite.sh journal [clé]     événements auditd (défaut : accès aux secrets)
set -euo pipefail

titre() { printf '\n== %s ==\n' "$1"; }

case "${1:-etat}" in
  etat)
    titre "CrowdSec : journaux analysés"
    cscli metrics show acquisition 2>/dev/null || cscli metrics
    titre "IP bloquées (décisions actives)"
    cscli decisions list
    titre "Dernières alertes"
    cscli alerts list --limit 15
    titre "Bouncers"
    cscli bouncers list
    ;;
  audit)
    echo "audit Lynis en cours (1 à 2 minutes)…"
    lynis audit system --quick --no-colors > /var/log/lynis-dernier.log 2>&1 || true
    RAPPORT=/var/log/lynis-report.dat
    titre "Lynis"
    echo "Indice de durcissement : $(sed -n 's/^hardening_index=//p' "$RAPPORT")/100"
    echo "Tests réalisés : $(sed -n 's/^lynis_tests_done=//p' "$RAPPORT")"
    titre "Avertissements"
    sed -n 's/^warning\[\]=//p' "$RAPPORT" | cut -d'|' -f1,2 | sed 's/^/  /' || true
    titre "Suggestions"
    echo "  $(grep -c '^suggestion\[\]=' "$RAPPORT" || true) suggestions (détail : $RAPPORT, /var/log/lynis-dernier.log)"
    ;;
  debloquer)
    ip="${2:?usage : securite.sh debloquer <ip>}"
    cscli decisions delete --ip "$ip"
    ;;
  journal)
    cle="${2:-logiflow-secrets}"
    ausearch -k "$cle" -i --start today 2>/dev/null | tail -n 60 || echo "aucun événement aujourd'hui pour la clé $cle"
    ;;
  *)
    echo "usage : securite.sh [etat|audit|debloquer <ip>|journal [clé]]" >&2
    exit 2
    ;;
esac
