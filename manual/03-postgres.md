# 03 · PostgreSQL

## Goal
Run PostgreSQL 16 outside the clusters, at a fixed IP on the `kind` network. It is set up like this:
- `pg_hba.conf` only accepts network logins over TLS (`hostssl`).
- On first start, `init.sh` creates the `kanban` database, a `tasks` table with sample rows, and a `vaultadmin` account. Vault uses `vaultadmin` to create short-lived users.

Files used: `resources/postgres/pg_hba.conf`, `resources/postgres/init.sh`.

## Steps

1. Load the settings and start the container:

   ```bash
   source ./lab.env
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
         -c hba_file=/etc/pgtls/pg_hba.conf'
   ```

   The wrapper copies the key so Postgres can own it with mode 600. Postgres refuses to start with a key that other users can read.

2. Wait about 15 seconds, then look at the data:

   ```bash
   docker exec zt-postgres psql -U postgres -d kanban -c 'select * from tasks;'
   ```

## Check
Prove that a login without TLS is refused:

```bash
docker run --rm --network kind -e PGPASSWORD="$VAULT_DB_ADMIN_PASSWORD" $POSTGRES_IMAGE \
  psql "host=$PG_IP user=vaultadmin dbname=kanban sslmode=disable" -c 'select 1'
```

It should fail with `no pg_hba.conf entry ... no encryption`. Change `sslmode=disable` to `sslmode=require` and it works.
This is a good screenshot for the report.
