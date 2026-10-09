# 99 · Clean up

```bash
source ./lab.env
kind delete cluster --name $C1
kind delete cluster --name $C2
docker rm -f vault-1 vault-2 vault-3 zt-nginx zt-postgres
docker volume rm zt-vault-1-data zt-vault-2-data zt-vault-3-data zt-pgdata
```

To start completely fresh, also remove the generated files: certificates, Vault keys, passwords and the Istio download.

```bash
rm -rf .work
```

Remove the `kanban.lab` line from `/etc/hosts` if you no longer need it.
