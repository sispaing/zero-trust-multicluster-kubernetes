#!/usr/bin/env bash
# Prometheus, Grafana, Kiali, Jaeger.
source "$(dirname "$0")/lib.sh"
for c in "${CLUSTERS[@]}"; do
  log "[$c] Observability add-ons"
  for a in prometheus grafana kiali jaeger; do retry k "$c" apply -f "$ISTIO_DIR/samples/addons/$a.yaml" >/dev/null; done
  k "$c" apply -f "$RES/istio/telemetry.yaml" >/dev/null
  k "$c" -n istio-system rollout status deploy/kiali --timeout=300s
done
echo "Open: $ISTIOCTL dashboard kiali --context kind-$C1"
