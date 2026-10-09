#!/bin/bash
# Runs once on first start. "vaultadmin" is the account Vault uses to create short-lived users.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<EOSQL
CREATE ROLE vaultadmin WITH LOGIN PASSWORD '${VAULT_DB_ADMIN_PASSWORD}' CREATEROLE;
CREATE DATABASE kanban OWNER vaultadmin;
\c kanban
SET ROLE vaultadmin;
CREATE TABLE tasks (
  id         SERIAL PRIMARY KEY,
  title      TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','doing','done')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO tasks (title, status) VALUES
  ('Write project proposal', 'done'),
  ('Build Istio multi-cluster mesh', 'doing'),
  ('Run Zero Trust tests', 'todo');
EOSQL
