#!/usr/bin/env bash
# Shared helpers for the automated scripts. Sourced by every step; not run directly.
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LAB_ROOT
# shellcheck disable=SC1091
source "$LAB_ROOT/lab.env"

CLUSTERS=("$C1" "$C2")
# per-cluster lookups:  cval <cluster> POD_CIDR  ->  value of C1_POD_CIDR or C2_POD_CIDR
cval() { local p; [ "$1" = "$C1" ] && p=C1 || p=C2; local v="${p}_$2"; echo "${!v}"; }

log()   { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m  [PASS]\033[0m %s\n' "$*"; }
bad()   { printf '\033[1;31m  [FAIL]\033[0m %s\n' "$*"; }
k()     { local c="$1"; shift; kubectl --context "kind-$c" "$@"; }
retry() { local n=0; until "$@"; do n=$((n+1)); [ "$n" -ge 30 ] && return 1; sleep 5; done; }
api_ip(){ docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$1-control-plane"; }
# render <template> [VAR ...]  -> substitutes only the listed variables
render(){ local f="$1"; shift; local list=""; for v in "$@"; do list+="\${$v} "; done; envsubst "$list" < "$f"; }
# Vault CLI runs inside vault-1, so no Vault binary is needed on the host
vault_cli(){ docker exec -i -e VAULT_TOKEN="$(jq -r .root_token "$WORK/vault-init.json")" vault-1 vault "$@"; }
