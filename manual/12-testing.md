# 12 · Zero Trust tests

## Goal
Run each test by hand and keep the output or screenshots as evidence for your report.
`automated/12-tests.sh` runs the same tests in one go.

Load the settings first:

```bash
source ./lab.env
vault() { docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault-1 vault "$@"; }
front() { curl -s --cacert .work/mesh-root-ca.crt "https://$APP_HOST:$HTTPS_PORT$1"; }
```

## T0 · Front door over HTTPS

```bash
front /api/tasks | jq '{cluster, db_user}'
```

**Expected:** JSON with the serving cluster and a `v-...` database user.

## T1 · Plaintext from outside the mesh is rejected

Create a pod in a namespace with no sidecar, and call the backend:

```bash
kubectl --context kind-$C1 create namespace legacy
kubectl --context kind-$C1 -n legacy run legacy --image=curlimages/curl --restart=Never --command -- sleep 3600
kubectl --context kind-$C1 -n legacy wait --for=condition=Ready pod/legacy
kubectl --context kind-$C1 -n legacy exec legacy -- curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://kanban-app.kanban.svc.cluster.local:8000/api/tasks
```

**Expected:** no response, or a connection reset. Two things block it: NetworkPolicy and STRICT mTLS.
For proof of the mTLS mode, run:

```bash
$ISTIOCTL --context kind-$C1 x describe pod -n kanban $(kubectl --context kind-$C1 -n kanban get pod -l app=kanban-app -o jsonpath='{.items[0].metadata.name}')
```

## T2 · Identity beats labels

This pod copies the frontend label `app=kanban-ui`, so NetworkPolicy lets it through. But it uses a different service account, so its SPIFFE identity is wrong:

```bash
kubectl --context kind-$C1 -n kanban create serviceaccount intruder
kubectl --context kind-$C1 -n kanban run intruder --image=curlimages/curl --restart=Never \
  --labels=app=kanban-ui --overrides='{"spec":{"serviceAccountName":"intruder"}}' --command -- sleep 3600
kubectl --context kind-$C1 -n kanban wait --for=condition=Ready pod/intruder --timeout=180s
kubectl --context kind-$C1 -n kanban exec intruder -c intruder -- curl -s -o /dev/null -w '%{http_code}\n' http://kanban-app:8000/api/tasks
kubectl --context kind-$C1 -n kanban delete pod intruder
```

**Expected:** `403`. Istio denied it because of the identity. This is the strongest single result for your report.

## T3 · The real frontend identity is allowed

```bash
kubectl --context kind-$C1 -n kanban exec deploy/kanban-ui -c kanban-ui -- wget -q -S -O /dev/null http://kanban-app:8000/api/tasks 2>&1 | grep HTTP/
```

**Expected:** `200`.

## T4 · Egress to unknown destinations is blocked

```bash
kubectl --context kind-$C1 -n kanban exec deploy/kanban-app -c kanban-app -- \
  python -c "import urllib.request; urllib.request.urlopen('http://example.com', timeout=5)"
```

**Expected:** an error. The backend cannot reach the internet.

## T5 · Dynamic database credentials

1. See the current user, the Postgres roles and the Vault leases:

   ```bash
   front /api/tasks | jq -r .db_user
   docker exec zt-postgres psql -U postgres -tAc "select rolname, rolvaliduntil from pg_roles where rolname like 'v-%'"
   vault list sys/leases/lookup/database/creds/kanban-app
   ```

2. Simulate a response to a credential leak. Revoke every lease, then restart the backends:

   ```bash
   vault lease revoke -prefix database/creds/kanban-app
   for c in $C1 $C2; do kubectl --context kind-$c -n kanban rollout restart deploy/kanban-app; done
   for c in $C1 $C2; do kubectl --context kind-$c -n kanban rollout status deploy/kanban-app; done
   front /api/tasks | jq -r .db_user
   ```

**Expected:** the old users disappear from Postgres, and the app uses a new `v-...` user.

To watch expiry happen quickly, shorten the TTL:
`vault write database/roles/kanban-app default_ttl=2m max_ttl=5m` (also pass the same `creation_statements` again).

## T6 · Cross-cluster failover

```bash
kubectl --context kind-$C1 -n kanban scale deploy/kanban-app --replicas=0
sleep 15
for i in $(seq 1 10); do front /api/tasks | jq -r .cluster; done | sort | uniq -c
kubectl --context kind-$C1 -n kanban scale deploy/kanban-app --replicas=1
```

**Expected:** every request is answered by `cluster2`, through the east-west gateway with mTLS.
In Kiali, the traffic graph shows the cross-cluster edge.

## T7 · Workload certificates come from Vault

```bash
POD=$(kubectl --context kind-$C1 -n kanban get pod -l app=kanban-app -o jsonpath='{.items[0].metadata.name}')
$ISTIOCTL --context kind-$C1 proxy-config secret -n kanban $POD -o json \
  | jq -r '.dynamicActiveSecrets[] | select(.name=="default") | .secret.tlsCertificate.certificateChain.inlineBytes' \
  | base64 -d | openssl x509 -noout -subject -issuer -ext subjectAltName
```

**Expected:** the issuer is `ZT Lab Mesh Intermediate CA`, and the SAN is `URI:spiffe://cluster.local/ns/kanban/sa/kanban-app`.

## Extra tests

- **Vault HA.** Run `docker stop vault-1`. The app keeps working, and new credentials come from the other nodes through Nginx. Then run `docker start vault-1` and unseal it again.
- **Performance.** Use `fortio load -c 8 -qps 200 -t 60s http://kanban-app:8000/api/health` from a meshed pod, then repeat without the sidecar. Compare p50 and p99 latency, and CPU and memory in Grafana.

## Clean up the test namespace

```bash
kubectl --context kind-$C1 delete namespace legacy
```
