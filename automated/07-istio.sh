#!/usr/bin/env bash
# Istio multi-primary, multi-network mesh.
source "$(dirname "$0")/lib.sh"
[ -x "$ISTIOCTL" ] || (cd "$WORK" && curl -sL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh - >/dev/null)
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null
for c in "${CLUSTERS[@]}"; do
  export CLUSTER_NAME="$c" NETWORK; NETWORK=$(cval "$c" NETWORK)
  log "[$c] istio-base + istiod"
  helm upgrade --install istio-base istio/base --kube-context "kind-$c" -n istio-system --version "$ISTIO_VERSION" --set defaultRevision=default --wait >/dev/null
  render "$RES/istio/istiod-values.yaml.tmpl" MESH_ID CLUSTER_NAME NETWORK > "$WORK/istiod-$c.yaml"
  helm upgrade --install istiod istio/istiod --kube-context "kind-$c" -n istio-system --version "$ISTIO_VERSION" -f "$WORK/istiod-$c.yaml" --wait >/dev/null

  log "[$c] East-west gateway"
  helm upgrade --install istio-eastwestgateway istio/gateway --kube-context "kind-$c" -n istio-system --version "$ISTIO_VERSION" \
    --set name=istio-eastwestgateway --set networkGateway="$NETWORK" --wait >/dev/null
  k "$c" apply -n istio-system -f "$ISTIO_DIR/samples/multicluster/expose-services.yaml" >/dev/null

  log "[$c] Ingress gateway + STRICT mTLS"
  k "$c" create namespace istio-ingress --dry-run=client -o yaml | k "$c" apply -f - >/dev/null
  helm upgrade --install istio-ingressgateway istio/gateway --kube-context "kind-$c" -n istio-ingress --version "$ISTIO_VERSION" --wait >/dev/null
  k "$c" apply -f "$RES/istio/peer-authentication.yaml" >/dev/null
done
log "Exchanging remote secrets"
"$ISTIOCTL" create-remote-secret --context="kind-$C1" --name="$C1" --server="https://$(api_ip "$C1"):6443" | kubectl apply --context="kind-$C2" -f - >/dev/null
"$ISTIOCTL" create-remote-secret --context="kind-$C2" --name="$C2" --server="https://$(api_ip "$C2"):6443" | kubectl apply --context="kind-$C1" -f - >/dev/null
"$ISTIOCTL" remote-clusters --context="kind-$C1" || true
