# 09 · Kanban application

## Goal
Deploy the Kanban app to both clusters.
- **Kanban-UI** is Nginx. It serves the board and proxies `/api/` to the backend.
- **Kanban-App** is a Python FastAPI backend. It has two sidecars:
  - an Envoy sidecar for mTLS
  - a Vault Agent sidecar, which logs in with the pod's service account and writes short-lived DB credentials to `/vault/secrets/db-creds`

Files used: everything in `resources/app/`, plus `resources/k8s/namespace-kanban.yaml`, `resources/k8s/app.yaml.tmpl` and `resources/k8s/ingress.yaml.tmpl`.

## Steps

1. Load the settings and build the backend image once:

   ```bash
   source ./lab.env
   docker build -t $APP_IMAGE resources/app/backend
   helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
   ```

2. Run this block once with `c=$C1`, then with `c=$C2`:

   ```bash
   c=$C1
   export CLUSTER_NAME=$c

   # Image into the cluster (KinD cannot pull local images)
   kind load docker-image $APP_IMAGE --name $c

   # Vault Agent Injector only (Vault itself runs outside, behind Nginx)
   helm upgrade --install vault hashicorp/vault --kube-context kind-$c -n vault --create-namespace \
     --set global.externalVaultAddr=$VAULT_ADDR_EXT --set server.enabled=false --set injector.enabled=true --wait

   # Namespace with sidecar injection on
   kubectl --context kind-$c apply -f resources/k8s/namespace-kanban.yaml

   # CA for Vault/Postgres TLS, and the frontend files
   kubectl --context kind-$c -n kanban create secret generic vault-ca --from-file=ca.crt=.work/tls/lab-ca.crt
   kubectl --context kind-$c -n kanban create configmap db-ca --from-file=ca.crt=.work/tls/lab-ca.crt
   kubectl --context kind-$c -n kanban create configmap kanban-ui-html --from-file=resources/app/frontend/index.html
   kubectl --context kind-$c -n kanban create configmap kanban-ui-nginx --from-file=default.conf=resources/app/frontend/nginx.conf

   # Workloads, ServiceEntry for Postgres, locality DestinationRules
   envsubst '${CLUSTER_NAME} ${PG_IP} ${VAULT_LB_IP} ${APP_IMAGE} ${NGINX_IMAGE}' < resources/k8s/app.yaml.tmpl \
     | kubectl --context kind-$c apply -f -

   # HTTPS: Vault-issued certificate, Istio Gateway, VirtualService
   envsubst '${APP_HOST}' < resources/k8s/ingress.yaml.tmpl | kubectl --context kind-$c apply -f -
   ```

3. Read the key parts of `resources/k8s/app.yaml.tmpl`. You can explain these in your report:
   - **`vault.hashicorp.com/*` annotations.** These tell Vault Agent which role to use, which auth mount to use, and how to write the credentials file.
   - **`excludeOutboundIPRanges`.** This lets the Vault Agent init container reach Vault before the Envoy sidecar has started.
   - **`ServiceEntry` for Postgres.** It is needed because egress is `REGISTRY_ONLY`.
   - **`DestinationRule` with `localityLbSetting` and `outlierDetection`.** This makes each cluster prefer its own backend and fail over to the other cluster.

## Check

```bash
kubectl --context kind-$C1 -n kanban get pods                    # kanban-app shows 3/3 (app + envoy + vault-agent)
kubectl --context kind-$C1 -n kanban exec deploy/kanban-app -c kanban-app -- cat /vault/secrets/db-creds
kubectl --context kind-$C1 -n istio-ingress get certificate kanban-tls
```

The credentials file shows a `v-...` user, and the certificate is `READY True`.
