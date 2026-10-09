#!/usr/bin/env bash
# Lab infrastructure CA + TLS certs for Vault and PostgreSQL.
source "$(dirname "$0")/lib.sh"
TLS="$WORK/tls"; mkdir -p "$TLS"; cd "$TLS"
if [ ! -f lab-ca.crt ]; then
  log "Creating lab infrastructure CA"
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout lab-ca.key -out lab-ca.crt -subj "/CN=ZT Lab Infrastructure CA" 2>/dev/null
fi
cp lab-ca.crt ca.crt
issue() { # name CN
  [ -f "$1.crt" ] && { echo "  $1.crt exists"; return; }
  render "$RES/certs/$1.ext.tmpl" NGINX_IP VAULT1_IP VAULT2_IP VAULT3_IP PG_IP > "$1.ext"
  openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "/CN=$2" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA lab-ca.crt -CAkey lab-ca.key -CAcreateserial -out "$1.crt" -days 825 -sha256 -extfile "$1.ext" 2>/dev/null
  echo "  issued $1.crt"
}
log "Issuing certificates"
issue vault vault
issue postgres postgres
chmod 644 ./*.key   # lab only: Vault (uid 100) must read its key
