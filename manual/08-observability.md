# 08 · Observability (Kiali, Prometheus, Grafana, Jaeger)

## Goal
Install the Istio sample add-ons in both clusters, and send 100% of traces to Jaeger.

File used: `resources/istio/telemetry.yaml`.

## Steps

1. Install the add-ons:

   ```bash
   source ./lab.env
   for c in $C1 $C2; do
     for a in prometheus grafana kiali jaeger; do
       kubectl --context kind-$c apply -f $ISTIO_DIR/samples/addons/$a.yaml
     done
     kubectl --context kind-$c apply -f resources/istio/telemetry.yaml
   done
   ```

   If a CRD error appears on the first run, run the loop again. Some add-ons create CRDs that the next file uses.

2. Open a dashboard. Each command opens your browser and keeps a port-forward running until you press Ctrl+C:

   ```bash
   $ISTIOCTL dashboard kiali   --context kind-$C1
   $ISTIOCTL dashboard grafana --context kind-$C1
   $ISTIOCTL dashboard jaeger  --context kind-$C1
   ```

## Check
Kiali opens. After step 09, open **Traffic Graph**, choose namespace `kanban`, and turn on **Display → Security**.
The padlocks on each edge show mTLS.
