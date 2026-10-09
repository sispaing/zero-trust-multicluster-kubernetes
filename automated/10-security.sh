#!/usr/bin/env bash
# Default-deny Istio AuthorizationPolicies (L7) + Calico NetworkPolicies (L3/L4).
source "$(dirname "$0")/lib.sh"
for c in "${CLUSTERS[@]}"; do
  log "[$c] Security policies"
  render "$RES/k8s/security.yaml.tmpl" LB_CIDR PG_IP VAULT_LB_IP | k "$c" apply -f -
done
