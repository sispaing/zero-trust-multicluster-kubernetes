# 01 · Kubernetes clusters (KinD + Calico + MetalLB)

## Goal
Create `cluster1` and `cluster2`. Each one gets:
- Calico as the CNI, because it enforces Kubernetes NetworkPolicy and the default kindnet does not
- region and zone labels, which Istio uses for locality-aware load balancing
- MetalLB, so `LoadBalancer` services get a real IP on the Docker `kind` network

Files used: `resources/kind/cluster.yaml.tmpl`, `resources/calico/render-calico.sh`, `resources/metallb/ip-pool.yaml.tmpl`.

## Steps

1. Load the settings:

   ```bash
   source ./lab.env
   ```

2. Render the cluster definition for `cluster1` and look at it. Note `disableDefaultCNI: true` and the separate pod and service ranges.

   ```bash
   CLUSTER_NAME=$C1 POD_CIDR=$C1_POD_CIDR SVC_CIDR=$C1_SVC_CIDR \
     envsubst '${CLUSTER_NAME} ${POD_CIDR} ${SVC_CIDR}' < resources/kind/cluster.yaml.tmpl > .work/kind-$C1.yaml
   cat .work/kind-$C1.yaml
   ```

3. Create the cluster:

   ```bash
   kind create cluster --config .work/kind-$C1.yaml
   ```

   The node stays `NotReady` for now. That is expected, because there is no CNI yet.

4. Do the same for `cluster2`:

   ```bash
   CLUSTER_NAME=$C2 POD_CIDR=$C2_POD_CIDR SVC_CIDR=$C2_SVC_CIDR \
     envsubst '${CLUSTER_NAME} ${POD_CIDR} ${SVC_CIDR}' < resources/kind/cluster.yaml.tmpl > .work/kind-$C2.yaml
   kind create cluster --config .work/kind-$C2.yaml
   ```

5. Re-load the settings. The `kind` Docker network now exists, so the fixed IPs get calculated:

   ```bash
   source ./lab.env
   echo "Nginx=$NGINX_IP  Postgres=$PG_IP  C1 pool=$C1_LB_RANGE  C2 pool=$C2_LB_RANGE"
   ```

6. Download the Calico manifest once:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml -o .work/calico.yaml
   ```

7. Install Calico in each cluster with that cluster's pod range, then wait for it:

   ```bash
   resources/calico/render-calico.sh .work/calico.yaml $C1_POD_CIDR | kubectl --context kind-$C1 apply -f -
   resources/calico/render-calico.sh .work/calico.yaml $C2_POD_CIDR | kubectl --context kind-$C2 apply -f -
   kubectl --context kind-$C1 -n kube-system rollout status ds/calico-node --timeout=600s
   kubectl --context kind-$C2 -n kube-system rollout status ds/calico-node --timeout=600s
   ```

8. Label each node with a region and a zone:

   ```bash
   kubectl --context kind-$C1 label node $C1-control-plane topology.kubernetes.io/region=$REGION topology.kubernetes.io/zone=$C1_ZONE --overwrite
   kubectl --context kind-$C2 label node $C2-control-plane topology.kubernetes.io/region=$REGION topology.kubernetes.io/zone=$C2_ZONE --overwrite
   ```

9. Install MetalLB in both clusters and wait for the controller:

   ```bash
   for c in $C1 $C2; do
     kubectl --context kind-$c apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml
     kubectl --context kind-$c -n metallb-system rollout status deploy/controller --timeout=300s
   done
   ```

10. Give each cluster its own address pool, so the two clusters never hand out the same IP:

    ```bash
    LB_RANGE=$C1_LB_RANGE envsubst '${LB_RANGE}' < resources/metallb/ip-pool.yaml.tmpl | kubectl --context kind-$C1 apply -f -
    LB_RANGE=$C2_LB_RANGE envsubst '${LB_RANGE}' < resources/metallb/ip-pool.yaml.tmpl | kubectl --context kind-$C2 apply -f -
    ```

    If this fails with a webhook error, wait 30 seconds and run it again. The MetalLB webhook takes a moment to start.

## Check

```bash
kubectl --context kind-$C1 get nodes -L topology.kubernetes.io/zone
kubectl --context kind-$C2 get nodes -L topology.kubernetes.io/zone
```

Both nodes are `Ready` and show `zone-1` and `zone-2`.
