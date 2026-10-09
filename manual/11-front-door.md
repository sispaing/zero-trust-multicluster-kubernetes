# 11 · Front door (Nginx → both Istio ingress gateways)

## Goal
Point Nginx at both ingress gateways with TLS passthrough. User traffic then follows this path:

```
browser → Nginx → Istio ingress (cluster1 or cluster2) → Kanban-UI → Kanban-App → PostgreSQL
```

File used: `resources/nginx/nginx-full.conf.tmpl`.

## Steps

1. Get the ingress IPs and render the full Nginx config:

   ```bash
   source ./lab.env
   export C1_INGRESS_IP=$(kubectl --context kind-$C1 -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   export C2_INGRESS_IP=$(kubectl --context kind-$C2 -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   envsubst '${VAULT1_IP} ${VAULT2_IP} ${VAULT3_IP} ${VAULT_PORT} ${C1_INGRESS_IP} ${C2_INGRESS_IP}' \
     < resources/nginx/nginx-full.conf.tmpl > .work/nginx/nginx.conf
   ```

2. Test the config and reload Nginx:

   ```bash
   docker exec zt-nginx nginx -t -c /etc/nginx/custom/nginx.conf
   docker exec zt-nginx nginx -s reload -c /etc/nginx/custom/nginx.conf
   ```

3. Add the hostname once:

   ```bash
   echo "127.0.0.1  $APP_HOST" | sudo tee -a /etc/hosts
   ```

4. Trust the mesh root CA in your browser to remove the warning. In Firefox, go to Settings → Certificates → Authorities → Import, and choose `.work/mesh-root-ca.crt`.

## Check

```bash
curl -s --cacert .work/mesh-root-ca.crt https://$APP_HOST:$HTTPS_PORT/api/tasks | jq '{cluster, db_user}'
```

Then open https://kanban.lab. The banner shows which cluster served the request, and the Vault-issued database user.
