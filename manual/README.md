# Manual build guide

These guides build the same lab as `automated/run-all.sh`, one component at a time, with every command shown.
Use them to learn how each piece works, to take screenshots for your report, or to fix one layer without rebuilding everything.

Both paths use the same config files in `../resources/` and the same settings in `../lab.env`, so you can mix them.
For example, you can run `automated/01-clusters.sh` and then do Vault by hand with `04-vault-cluster.md`.

## Before every session

Open a terminal in the repo root and load the settings:

```bash
cd zt-istio-lab
source ./lab.env
```

Run `source ./lab.env` again after you create the first cluster in step 01. That is when the IP addresses get filled in.
To check, run `echo $NGINX_IP $PG_IP`. Both should print an address.

Most guides also use this short helper, which runs the Vault CLI inside the `vault-1` container:

```bash
vault() { docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault-1 vault "$@"; }
```

## Order

| Step | Guide | Builds |
|---|---|---|
| 00 | [00-prerequisites.md](00-prerequisites.md) | Tools and host settings |
| 01 | [01-clusters.md](01-clusters.md) | Two KinD clusters, Calico, MetalLB |
| 02 | [02-certificates.md](02-certificates.md) | Lab CA, Vault and PostgreSQL certificates |
| 03 | [03-postgres.md](03-postgres.md) | PostgreSQL with TLS |
| 04 | [04-vault-cluster.md](04-vault-cluster.md) | 3-node Vault cluster behind Nginx |
| 05 | [05-vault-config.md](05-vault-config.md) | PKI, database secrets, Kubernetes auth |
| 06 | [06-cert-manager.md](06-cert-manager.md) | cert-manager and istio-csr |
| 07 | [07-istio.md](07-istio.md) | Istio multi-primary mesh |
| 08 | [08-observability.md](08-observability.md) | Kiali, Prometheus, Grafana, Jaeger |
| 09 | [09-application.md](09-application.md) | Kanban app with Vault Agent |
| 10 | [10-security-policies.md](10-security-policies.md) | Istio AuthorizationPolicy and NetworkPolicy |
| 11 | [11-front-door.md](11-front-door.md) | Nginx in front of both ingress gateways |
| 12 | [12-testing.md](12-testing.md) | Zero Trust tests, one by one |
| 99 | [99-cleanup.md](99-cleanup.md) | Remove everything |

Each guide ends with a **Check** section. Do not move on until the check passes.
