# Calico

The Calico manifest is downloaded at build time (it is large and versioned upstream):

    https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml

Before applying it, two commented lines are switched on so Calico uses the pod CIDR of each cluster:

    - name: CALICO_IPV4POOL_CIDR
      value: "<pod CIDR>"

`render-calico.sh` in this folder does that edit. Both the automated scripts and the manual guide use it.
