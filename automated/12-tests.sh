#!/usr/bin/env bash
# Zero Trust evaluation tests. Each test prints PASS/FAIL and the evidence.
source "$(dirname "$0")/lib.sh"
set +e
C1="$C1"; C2="$C2"
URL="https://$APP_HOST:$HTTPS_PORT"
front() { curl -s --max-time 10 --cacert "$WORK/mesh-root-ca.crt" --resolve "$APP_HOST:$HTTPS_PORT:127.0.0.1" "$URL$1"; }

log "T0  Front door: user -> Nginx -> Istio ingress (HTTPS, Vault-issued cert)"
out=$(front /api/tasks)
if echo "$out" | jq -e .tasks >/dev/null 2>&1; then
  ok "API reachable over HTTPS; served by $(echo "$out" | jq -r .cluster)"
else bad "Front door failed: $out"; fi

log "T1  Plaintext from outside the mesh is rejected"
k $C1 create namespace legacy --dry-run=client -o yaml | k $C1 apply -f - >/dev/null
k $C1 -n legacy run legacy --image=curlimages/curl --restart=Never --command -- sleep 3600 >/dev/null 2>&1
k $C1 -n legacy wait --for=condition=Ready pod/legacy --timeout=120s >/dev/null
code=$(k $C1 -n legacy exec legacy -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://kanban-app.kanban.svc.cluster.local:8000/api/tasks)
[ "$code" = "200" ] && bad "Legacy pod got HTTP 200" || ok "Legacy (no sidecar) pod blocked (curl result: ${code:-no response})"
echo "  Evidence of STRICT mTLS on the backend:"
"$ISTIOCTL" --context kind-$C1 x describe pod -n kanban "$(k $C1 -n kanban get pod -l app=kanban-app -o jsonpath='{.items[0].metadata.name}')" 2>/dev/null | grep -iE 'mtls|peerauth' | sed 's/^/    /'

log "T2  Identity beats labels: a pod that copies the label app=kanban-ui but has the wrong service account"
k $C1 -n kanban create serviceaccount intruder --dry-run=client -o yaml | k $C1 apply -f - >/dev/null
k $C1 -n kanban run intruder --image=curlimages/curl --restart=Never --labels=app=kanban-ui,test=intruder \
  --overrides='{"spec":{"serviceAccountName":"intruder"}}' --command -- sleep 3600 >/dev/null 2>&1
k $C1 -n kanban wait --for=condition=Ready pod/intruder --timeout=180s >/dev/null
code=$(k $C1 -n kanban exec intruder -c intruder -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://kanban-app:8000/api/tasks)
[ "$code" = "403" ] && ok "NetworkPolicy let it through (label match) but Istio denied it: HTTP 403" || bad "Expected 403, got ${code:-none}"
k $C1 -n kanban delete pod intruder --wait=false >/dev/null

log "T3  The real frontend identity (kanban-ui) is allowed"
code=$(k $C1 -n kanban exec deploy/kanban-ui -c kanban-ui -- wget -q -S -O /dev/null http://kanban-app:8000/api/tasks 2>&1 | awk '/HTTP\//{print $2}' | tail -1)
[ "$code" = "200" ] && ok "kanban-ui -> kanban-app: HTTP 200" || bad "Expected 200, got ${code:-none}"

log "T4  Egress to unknown destinations is blocked (REGISTRY_ONLY + NetworkPolicy)"
k $C1 -n kanban exec deploy/kanban-app -c kanban-app -- python -c \
  "import urllib.request; urllib.request.urlopen('http://example.com', timeout=5)" >/dev/null 2>&1 \
  && bad "Backend reached example.com" || ok "Backend cannot reach example.com"

log "T5  Dynamic database credentials from Vault"
u1=$(front /api/tasks | jq -r .db_user)
echo "  Current DB user seen by the app: $u1"
echo "  Vault-created roles in PostgreSQL (with expiry):"
docker exec zt-postgres psql -U postgres -tAc "select rolname || '  valid until ' || rolvaliduntil from pg_roles where rolname like 'v-%'" | sed 's/^/    /'
echo "  Active Vault leases:"
vault_cli list -format=json sys/leases/lookup/database/creds/kanban-app 2>/dev/null | jq -r '.[]' | sed 's/^/    /'
echo "  Revoking all leases (simulates a credential leak response)..."
vault_cli lease revoke -prefix database/creds/kanban-app >/dev/null
for c in "${CLUSTERS[@]}"; do k "$c" -n kanban rollout restart deploy/kanban-app >/dev/null; done
for c in "${CLUSTERS[@]}"; do k "$c" -n kanban rollout status deploy/kanban-app --timeout=180s >/dev/null; done
sleep 5
u2=$(front /api/tasks | jq -r .db_user)
[ -n "$u2" ] && [ "$u2" != "null" ] && [ "$u2" != "$u1" ] && ok "Old user revoked, app now uses new user $u2" || bad "Unexpected user after rotation: $u2"

log "T6  Cross-cluster failover (scale backend in $C1 to zero)"
k $C1 -n kanban scale deploy/kanban-app --replicas=0 >/dev/null
sleep 15
seen=$(for i in $(seq 1 10); do front /api/tasks | jq -r .cluster; done | sort | uniq -c)
echo "$seen" | sed 's/^/    /'
echo "$seen" | grep -q "$C1" && bad "Some requests still served by $C1" || ok "All requests served by $C2 through the east-west gateway"
k $C1 -n kanban scale deploy/kanban-app --replicas=1 >/dev/null
k $C1 -n kanban rollout status deploy/kanban-app --timeout=180s >/dev/null

log "T7  Workload certificate chain comes from Vault (not Istio's self-signed CA)"
pod=$(k $C1 -n kanban get pod -l app=kanban-app -o jsonpath='{.items[0].metadata.name}')
"$ISTIOCTL" --context kind-$C1 proxy-config secret -n kanban "$pod" -o json 2>/dev/null \
  | jq -r '.dynamicActiveSecrets[] | select(.name=="default") | .secret.tlsCertificate.certificateChain.inlineBytes' \
  | base64 -d | openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -noout \
  | grep -E 'subject|issuer' | sed 's/^/    /'
echo "  Expect issuer 'ZT Lab Mesh Intermediate CA' and a SPIFFE identity spiffe://cluster.local/ns/kanban/sa/kanban-app"

k $C1 delete namespace legacy --wait=false >/dev/null
log "Done. Open Kiali to see mTLS padlocks and denied requests: $ISTIOCTL dashboard kiali --context kind-$C1"
