# cert-manager / istio-csr may only sign mesh certificates
path "pki_int/sign/mesh"  { capabilities = ["create", "update"] }
path "pki_int/issue/mesh" { capabilities = ["create"] }
