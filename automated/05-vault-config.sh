#!/usr/bin/env bash
# Vault PKI (mesh root of trust), database secrets engine, Kubernetes auth per cluster.
source "$(dirname "$0")/lib.sh"
has_secret(){ vault_cli secrets list -format=json | jq -e --arg p "$1/" 'has($p)' >/dev/null; }
has_auth()  { vault_cli auth list    -format=json | jq -e --arg p "$1/" 'has($p)' >/dev/null; }

if ! has_secret pki; then
  log "Root CA (pki/)"
  vault_cli secrets enable pki
  vault_cli secrets tune -max-lease-ttl=87600h pki
  vault_cli write -field=certificate pki/root/generate/internal common_name="ZT Lab Mesh Root CA" ttl=87600h >/dev/null
fi
vault_cli read -field=certificate pki/cert/ca > "$WORK/mesh-root-ca.crt"
if ! has_secret pki_int; then
  log "Intermediate CA (pki_int/)"
  vault_cli secrets enable -path=pki_int pki
  vault_cli secrets tune -max-lease-ttl=43800h pki_int
  CSR=$(vault_cli write -format=json pki_int/intermediate/generate/internal common_name="ZT Lab Mesh Intermediate CA" | jq -r .data.csr)
  SIGNED=$(printf '%s' "$CSR" | vault_cli write -format=json pki/root/sign-intermediate csr=- format=pem_bundle ttl=43800h | jq -r .data.certificate)
  printf '%s' "$SIGNED" | vault_cli write pki_int/intermediate/set-signed certificate=- >/dev/null
fi
log "PKI role 'mesh'"
vault_cli write pki_int/roles/mesh allow_any_name=true enforce_hostnames=false require_cn=false \
  allowed_uri_sans="spiffe://*" allow_ip_sans=true use_csr_common_name=true use_csr_sans=true key_type=any max_ttl=72h >/dev/null

log "Policies"
vault_cli policy write cert-manager - < "$RES/vault/policies/cert-manager.hcl"
vault_cli policy write kanban-db    - < "$RES/vault/policies/kanban-db.hcl"

has_secret database || vault_cli secrets enable database
log "Database connection + role 'kanban-app'"
vault_cli write database/config/kanban plugin_name=postgresql-database-plugin allowed_roles=kanban-app \
  connection_url="postgresql://{{username}}:{{password}}@$PG_IP:5432/kanban?sslmode=verify-full&sslrootcert=/vault/tls/lab-ca.crt" \
  username=vaultadmin password="$VAULT_DB_ADMIN_PASSWORD" >/dev/null
vault_cli write database/roles/kanban-app db_name=kanban default_ttl=1h max_ttl=24h creation_statements=- \
  < "$RES/vault/db-role-creation.sql" >/dev/null

for c in "${CLUSTERS[@]}"; do
  log "[$c] Kubernetes auth"
  k "$c" apply -f "$RES/k8s/vault-auth.yaml" >/dev/null
  retry bash -c "kubectl --context kind-$c -n kube-system get secret vault-auth-token -o jsonpath='{.data.token}' | grep -q ."
  TOKEN=$(k "$c" -n kube-system get secret vault-auth-token -o jsonpath='{.data.token}' | base64 -d)
  KCA=$(k "$c" -n kube-system get secret vault-auth-token -o jsonpath='{.data.ca\.crt}' | base64 -d)
  has_auth "kubernetes-$c" || vault_cli auth enable -path="kubernetes-$c" kubernetes
  vault_cli write "auth/kubernetes-$c/config" kubernetes_host="https://$(api_ip "$c"):6443" kubernetes_ca_cert="$KCA" token_reviewer_jwt="$TOKEN" >/dev/null
  vault_cli write "auth/kubernetes-$c/role/cert-manager" bound_service_account_names=vault-issuer bound_service_account_namespaces=cert-manager \
    audience="vault://vault-issuer" token_policies=cert-manager token_ttl=20m >/dev/null
  vault_cli write "auth/kubernetes-$c/role/kanban-app" bound_service_account_names=kanban-app bound_service_account_namespaces=kanban \
    token_policies=kanban-db token_ttl=1h >/dev/null
done
log "Test: issue one set of DB credentials"
vault_cli read database/creds/kanban-app
