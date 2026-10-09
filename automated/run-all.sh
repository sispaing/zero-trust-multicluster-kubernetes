#!/usr/bin/env bash
# Build the whole lab in order. Each step is safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
for s in 00-prereqs 01-clusters 02-certs 03-postgres 04-vault 05-vault-config \
         06-cert-manager 07-istio 08-observability 09-app 10-security 11-frontdoor; do
  echo; echo "################ $s ################"; bash "./$s.sh"
done
echo; echo "Build complete. Run ./12-tests.sh for the Zero Trust tests."
