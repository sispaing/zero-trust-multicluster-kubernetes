#!/usr/bin/env bash
# Usage: render-calico.sh <downloaded calico.yaml> <pod CIDR>   -> prints the edited manifest
set -euo pipefail
sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
    -e "s|#   value: \"192.168.0.0/16\"|  value: \"$2\"|" "$1"
