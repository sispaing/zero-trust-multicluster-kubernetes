#!/usr/bin/env bash
# Two KinD clusters + Calico + zone labels + MetalLB.
source "$(dirname "$0")/lib.sh"
for c in "${CLUSTERS[@]}"; do
  if kind get clusters 2>/dev/null | grep -qx "$c"; then log "$c already exists"; continue; fi
  log "Creating KinD cluster $c"
  CLUSTER_NAME="$c" POD_CIDR=$(cval "$c" POD_CIDR) SVC_CIDR=$(cval "$c" SVC_CIDR) \
    render "$RES/kind/cluster.yaml.tmpl" CLUSTER_NAME POD_CIDR SVC_CIDR > "$WORK/kind-$c.yaml"
  kind create cluster --config "$WORK/kind-$c.yaml"
done
source "$LAB_ROOT/lab.env"   # kind network now exists -> IPs are set

[ -f "$WORK/calico.yaml" ] || curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" -o "$WORK/calico.yaml"
for c in "${CLUSTERS[@]}"; do
  log "[$c] Calico"
  "$RES/calico/render-calico.sh" "$WORK/calico.yaml" "$(cval "$c" POD_CIDR)" | k "$c" apply -f - >/dev/null
  k "$c" -n kube-system rollout status ds/calico-node --timeout=600s
  k "$c" wait --for=condition=Ready nodes --all --timeout=300s

  log "[$c] Region/zone labels (Istio locality)"
  k "$c" label node "$c-control-plane" --overwrite topology.kubernetes.io/region="$REGION" topology.kubernetes.io/zone="$(cval "$c" ZONE)"

  log "[$c] MetalLB"
  k "$c" apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml" >/dev/null
  k "$c" -n metallb-system rollout status deploy/controller --timeout=300s
  LB_RANGE=$(cval "$c" LB_RANGE) render "$RES/metallb/ip-pool.yaml.tmpl" LB_RANGE > "$WORK/metallb-$c.yaml"
  retry k "$c" apply -f "$WORK/metallb-$c.yaml" >/dev/null
done
