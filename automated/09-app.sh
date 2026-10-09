#!/usr/bin/env bash
# Build backend image, install Vault Agent Injector, deploy Kanban app to both clusters.
source "$(dirname "$0")/lib.sh"
log "Building $APP_IMAGE"
docker build -q -t "$APP_IMAGE" "$RES/app/backend" >/dev/null
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update >/dev/null
for c in "${CLUSTERS[@]}"; do
  export CLUSTER_NAME="$c"
  log "[$c] Loading image + Vault Agent Injector"
  kind load docker-image "$APP_IMAGE" --name "$c" >/dev/null
  helm upgrade --install vault hashicorp/vault --kube-context "kind-$c" -n vault --create-namespace \
    --set global.externalVaultAddr="$VAULT_ADDR_EXT" --set server.enabled=false --set injector.enabled=true --wait >/dev/null

  log "[$c] Namespace, config, workloads"
  k "$c" apply -f "$RES/k8s/namespace-kanban.yaml" >/dev/null
  for kind_name in "secret generic vault-ca --from-file=ca.crt=$WORK/tls/lab-ca.crt" \
                   "configmap db-ca --from-file=ca.crt=$WORK/tls/lab-ca.crt" \
                   "configmap kanban-ui-html --from-file=$RES/app/frontend/index.html" \
                   "configmap kanban-ui-nginx --from-file=default.conf=$RES/app/frontend/nginx.conf"; do
    # shellcheck disable=SC2086
    k "$c" -n kanban create $kind_name --dry-run=client -o yaml | k "$c" apply -f - >/dev/null
  done
  render "$RES/k8s/app.yaml.tmpl" CLUSTER_NAME PG_IP VAULT_LB_IP APP_IMAGE NGINX_IMAGE | k "$c" apply -f - >/dev/null
  render "$RES/k8s/ingress.yaml.tmpl" APP_HOST | k "$c" apply -f - >/dev/null
done
for c in "${CLUSTERS[@]}"; do
  k "$c" -n kanban rollout status deploy/kanban-app --timeout=300s
  k "$c" -n kanban rollout status deploy/kanban-ui --timeout=300s
  k "$c" -n istio-ingress wait --for=condition=Ready certificate/kanban-tls --timeout=120s
done
