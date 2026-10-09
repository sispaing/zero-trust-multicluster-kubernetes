# 10 · Security policies (default deny, two layers)

## Goal
Apply both layers from `resources/k8s/security.yaml.tmpl`:

| Layer | Tool | Rules |
|---|---|---|
| L7 (identity) | Istio `AuthorizationPolicy` | `allow-nothing` denies everything by default. Kanban-UI only accepts the ingress gateway identity. Kanban-App only accepts `cluster.local/ns/kanban/sa/kanban-ui` on `/api/*`. |
| L3/L4 (network) | Kubernetes `NetworkPolicy`, enforced by Calico | Everything is denied by default. Only these flows are allowed: DNS, istiod and istio-csr, remote east-west gateways (15443), UI → App (8000), App → Postgres (5432) and App → Vault (8443). |

If one layer has a mistake, the other one still protects the app.

## Steps

1. Look at the policy before you apply it:

   ```bash
   source ./lab.env
   envsubst '${LB_CIDR} ${PG_IP} ${VAULT_LB_IP}' < resources/k8s/security.yaml.tmpl | less
   ```

2. Apply it to both clusters:

   ```bash
   for c in $C1 $C2; do
     envsubst '${LB_CIDR} ${PG_IP} ${VAULT_LB_IP}' < resources/k8s/security.yaml.tmpl | kubectl --context kind-$c apply -f -
   done
   ```

## Check

```bash
kubectl --context kind-$C1 -n kanban get authorizationpolicy,networkpolicy
kubectl --context kind-$C1 -n kanban exec deploy/kanban-ui -c kanban-ui -- wget -qO- http://kanban-app:8000/api/health
```

The UI can still reach the backend and gets `{"status":"ok",...}`. The tests in step 12 prove that everything else is blocked.
