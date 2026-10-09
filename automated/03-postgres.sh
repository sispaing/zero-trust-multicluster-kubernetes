#!/usr/bin/env bash
# PostgreSQL on the kind network, TLS required for network logins.
source "$(dirname "$0")/lib.sh"
if docker ps -a --format '{{.Names}}' | grep -qx zt-postgres; then docker start zt-postgres >/dev/null; log "zt-postgres already exists"; exit 0; fi
log "Starting PostgreSQL at $PG_IP"
docker run -d --name zt-postgres --network kind --ip "$PG_IP" \
  -e POSTGRES_PASSWORD="$PG_SUPER_PASS" -e VAULT_DB_ADMIN_PASSWORD="$VAULT_DB_ADMIN_PASSWORD" \
  -v "$WORK/tls:/certs:ro" -v "$RES/postgres:/cfg:ro" -v zt-pgdata:/var/lib/postgresql/data \
  --entrypoint bash "$POSTGRES_IMAGE" -c '
    set -e
    mkdir -p /etc/pgtls
    cp /certs/postgres.crt /certs/postgres.key /cfg/pg_hba.conf /etc/pgtls/
    cp /cfg/init.sh /docker-entrypoint-initdb.d/10-init.sh
    chown -R postgres:postgres /etc/pgtls && chmod 600 /etc/pgtls/postgres.key
    exec docker-entrypoint.sh postgres -c ssl=on \
      -c ssl_cert_file=/etc/pgtls/postgres.crt -c ssl_key_file=/etc/pgtls/postgres.key \
      -c hba_file=/etc/pgtls/pg_hba.conf' >/dev/null
retry docker exec zt-postgres psql -U postgres -d kanban -tAc 'select 1 from tasks limit 1' >/dev/null 2>&1
ok "PostgreSQL is ready"
