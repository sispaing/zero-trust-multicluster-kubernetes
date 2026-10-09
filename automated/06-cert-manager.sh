#!/usr/bin/env bash
# cert-manager + Vault ClusterIssuer + istio-csr in each cluster.
source "$(dirname "$0")/lib.sh"
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
export VAULT_TLS_CA_B64; VAULT_TLS_CA_B64=$(base64 -w0 "$WORK/tls/lab-ca.crt")
for c in "${CLUSTERS[@]}"; do
  export CLUSTER_NAME="$c"
  log "[$c] cert-manager"
  helm upgrade --install cert-manager jetstack/cert-manager --kube-context "kind-$c" -n cert-manager --create-namespace \
    --version "$CERT_MANAGER_VERSION" --set crds.enabled=true --wait >/dev/null
  k "$c" create namespace istio-system --dry-run=client -o yaml | k "$c" apply -f - >/dev/null
  k "$c" label namespace istio-system topology.istio.io/network="$(cval "$c" NETWORK)" --overwrite >/dev/null

  log "[$c] Vault ClusterIssuer"
  render "$RES/cert-manager/vault-issuer.yaml.tmpl" CLUSTER_NAME VAULT_ADDR_EXT VAULT_TLS_CA_B64 | k "$c" apply -f - >/dev/null
  retry bash -c "kubectl --context kind-$c get clusterissuer vault-issuer -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True" \
    || { k "$c" describe clusterissuer vault-issuer; exit 1; }

  log "[$c] istio-csr"
  k "$c" -n cert-manager create secret generic istio-root-ca --from-file=ca.pem="$WORK/mesh-root-ca.crt" --dry-run=client -o yaml | k "$c" apply -f - >/dev/null
  render "$RES/cert-manager/istio-csr-values.yaml.tmpl" CLUSTER_NAME > "$WORK/istio-csr-$c.yaml"
  helm upgrade --install cert-manager-istio-csr jetstack/cert-manager-istio-csr --kube-context "kind-$c" -n cert-manager -f "$WORK/istio-csr-$c.yaml" --wait >/dev/null
  retry k "$c" -n istio-system get secret istiod-tls >/dev/null 2>&1
  ok "[$c] istiod-tls issued by Vault"
done
