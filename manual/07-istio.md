# 07 · Istio multi-primary, multi-network mesh

## Goal
Each cluster runs its own istiod (multi-primary) on its own network. The two clusters connect through **east-west gateways**.

The settings:
- STRICT mTLS for the whole mesh
- egress to unknown destinations is blocked (`REGISTRY_ONLY`)
- certificates come from istio-csr, which means from Vault

Files used: `resources/istio/istiod-values.yaml.tmpl`, `resources/istio/peer-authentication.yaml`.

## Steps

1. Load the settings, download Istio (for `istioctl` and the sample files) and add the Helm repo:

   ```bash
   source ./lab.env
   (cd .work && curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -)
   helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
   ```

2. Run this block once with `c=$C1 n=$C1_NETWORK`, then with `c=$C2 n=$C2_NETWORK`:

   ```bash
   c=$C1; n=$C1_NETWORK
   export CLUSTER_NAME=$c NETWORK=$n

   # CRDs and istiod (built-in CA off, caAddress -> istio-csr)
   helm upgrade --install istio-base istio/base --kube-context kind-$c -n istio-system --version $ISTIO_VERSION --set defaultRevision=default --wait
   envsubst '${MESH_ID} ${CLUSTER_NAME} ${NETWORK}' < resources/istio/istiod-values.yaml.tmpl > .work/istiod-$c.yaml
   helm upgrade --install istiod istio/istiod --kube-context kind-$c -n istio-system --version $ISTIO_VERSION -f .work/istiod-$c.yaml --wait

   # East-west gateway (port 15443) and expose *.local services to the other network
   helm upgrade --install istio-eastwestgateway istio/gateway --kube-context kind-$c -n istio-system --version $ISTIO_VERSION \
     --set name=istio-eastwestgateway --set networkGateway=$n --wait
   kubectl --context kind-$c apply -n istio-system -f $ISTIO_DIR/samples/multicluster/expose-services.yaml

   # Ingress gateway for user traffic
   kubectl --context kind-$c create namespace istio-ingress
   helm upgrade --install istio-ingressgateway istio/gateway --kube-context kind-$c -n istio-ingress --version $ISTIO_VERSION --wait

   # STRICT mTLS everywhere
   kubectl --context kind-$c apply -f resources/istio/peer-authentication.yaml
   ```

3. Exchange remote secrets. Each istiod gets read access to the other cluster's API, so it can discover endpoints there. This is what turns two meshes into one.

   ```bash
   API1=$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' $C1-control-plane)
   API2=$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' $C2-control-plane)
   $ISTIOCTL create-remote-secret --context=kind-$C1 --name=$C1 --server=https://$API1:6443 | kubectl apply --context=kind-$C2 -f -
   $ISTIOCTL create-remote-secret --context=kind-$C2 --name=$C2 --server=https://$API2:6443 | kubectl apply --context=kind-$C1 -f -
   ```

   The `--server` flag uses the API server's Docker IP. The default `127.0.0.1` address only works from your laptop, not from inside the other cluster.

## Check

```bash
$ISTIOCTL remote-clusters --context kind-$C1
kubectl --context kind-$C1 -n istio-system get svc istio-eastwestgateway
kubectl --context kind-$C1 -n istio-ingress get svc istio-ingressgateway
```

The remote cluster shows `synced`, and both gateways have an `EXTERNAL-IP` from MetalLB.
