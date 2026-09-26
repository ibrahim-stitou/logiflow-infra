#!/bin/bash
# Premier démarrage de PostgreSQL uniquement (volume vide) : crée les bases du service IA et de
# Keycloak, chacune avec son propre utilisateur. La base « logiflow » (backend) est créée par
# l'image elle-même (POSTGRES_DB / POSTGRES_USER).
set -euo pipefail

# Extensions de la base métier (géométrie, recherche plein texte approximative, UUID, vecteurs).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v ai_pwd="$AI_DB_PASSWORD" -v kc_pwd="$KEYCLOAK_DB_PASSWORD" <<'SQL'
CREATE ROLE logiflow_ai LOGIN PASSWORD :'ai_pwd';
CREATE DATABASE logiflow_ai OWNER logiflow_ai;
REVOKE ALL ON DATABASE logiflow_ai FROM PUBLIC;

CREATE ROLE keycloak LOGIN PASSWORD :'kc_pwd';
CREATE DATABASE keycloak OWNER keycloak;
REVOKE ALL ON DATABASE keycloak FROM PUBLIC;
SQL

# Extensions et schéma du service IA (pgvector pour la base de connaissance du copilote).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname logiflow_ai <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA IF NOT EXISTS copilote AUTHORIZATION logiflow_ai;
SQL

echo "logiflow: bases logiflow_ai et keycloak créées"
