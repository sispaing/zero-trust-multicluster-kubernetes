# 06 · cert-manager and istio-csr

## Goal
In each cluster:
- Install cert-manager.
- Add a `ClusterIssuer` that signs certificates with Vault (`pki_int/sign/mesh`).
- Install istio-csr. It replaces Istio's built-in CA, so every workload certificate is signed by Vault.

istio-csr must be running **before** istiod is installed in step 07.

Files used: `resources/cert-manager/vault-issuer.yaml.tmpl`, `resources/cert-manager/istio-csr-values.yaml.tmpl`.

## Steps

1. Load the settings and add the Helm repo:

   ```bash
   source ./lab.env
   helm repo add jetstack https://charts.jetstack.io --force-update
   export VAULT_TLS_CA_B64=$(base64 -w0 .work/tls/lab-ca.crt)
   ```

2. Run this block once with `c=$C1 n=$C1_NETWORK`, then with `c=$C2 n=$C2_NETWORK`:

   ```bash
   c=$C1; n=$C1_NETWORK
   export CLUSTER_NAME=$c

   # cert-manager
   helm upgrade --install cert-manager jetstack/cert-manager --kube-context kind-$c \
     -n cert-manager --create-namespace --version $CERT_MANAGER_VERSION --set crds.enabled=true --wait

   # istio-system namespace, labelled with this cluster's network
   kubectl --context kind-$c create namespace istio-system
   kubectl --context kind-$c label namespace istio-system topology.istio.io/network=$n

   # Vault ClusterIssuer (logs in through auth/kubernetes-<cluster>)
   envsubst '${CLUSTER_NAME} ${VAULT_ADDR_EXT} ${VAULT_TLS_CA_B64}' < resources/cert-manager/vault-issuer.yaml.tmpl \
     | kubectl --context kind-$c apply -f -
   kubectl --context kind-$c get clusterissuer vault-issuer      # wait until READY = True

   # istio-csr, which needs the mesh root CA so it can hand it to workloads
   kubectl --context kind-$c -n cert-manager create secret generic istio-root-ca --from-file=ca.pem=.work/mesh-root-ca.crt
   envsubst '${CLUSTER_NAME}' < resources/cert-manager/istio-csr-values.yaml.tmpl > .work/istio-csr-$c.yaml
   helm upgrade --install cert-manager-istio-csr jetstack/cert-manager-istio-csr --kube-context kind-$c \
     -n cert-manager -f .work/istio-csr-$c.yaml --wait
   ```

## Check

```bash
kubectl --context kind-$C1 get clusterissuer vault-issuer
kubectl --context kind-$C1 -n istio-system get certificate,secret istiod-tls
```

The issuer shows `READY True`, and an `istiod-tls` secret exists. That secret was issued by Vault for istiod.

If the issuer is not ready, run `kubectl describe clusterissuer vault-issuer`. The usual cause is that Vault is sealed.
