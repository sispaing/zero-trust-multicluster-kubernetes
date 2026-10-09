#!/usr/bin/env bash
# Point Nginx at both Istio ingress gateways.
source "$(dirname "$0")/lib.sh"
export C1_INGRESS_IP C2_INGRESS_IP
C1_INGRESS_IP=$(k "$C1" -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
C2_INGRESS_IP=$(k "$C2" -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[ -n "$C1_INGRESS_IP" ] && [ -n "$C2_INGRESS_IP" ] || { echo "Ingress gateway has no LoadBalancer IP"; exit 1; }
log "Nginx: Vault + front door ($C1_INGRESS_IP, $C2_INGRESS_IP)"
render "$RES/nginx/nginx-full.conf.tmpl" VAULT1_IP VAULT2_IP VAULT3_IP VAULT_PORT C1_INGRESS_IP C2_INGRESS_IP > "$WORK/nginx/nginx.conf"
docker exec zt-nginx nginx -t -c /etc/nginx/custom/nginx.conf
docker exec zt-nginx nginx -s reload -c /etc/nginx/custom/nginx.conf
echo "Add to /etc/hosts once:  127.0.0.1  $APP_HOST     then open https://$APP_HOST"
