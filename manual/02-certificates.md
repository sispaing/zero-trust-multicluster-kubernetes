# 02 · Lab certificates

## Goal
Create a small "infrastructure CA" with openssl. It signs the TLS certificates for Vault and PostgreSQL.

This CA only protects infrastructure connections. Mesh workload certificates come from Vault PKI later, in step 05.

Files used: `resources/certs/vault.ext.tmpl`, `resources/certs/postgres.ext.tmpl`.

## Steps

1. Load the settings and go to the TLS folder:

   ```bash
   source ./lab.env
   mkdir -p .work/tls && cd .work/tls
   ```

2. Create the CA. It is valid for 10 years.

   ```bash
   openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
     -keyout lab-ca.key -out lab-ca.crt -subj "/CN=ZT Lab Infrastructure CA"
   cp lab-ca.crt ca.crt
   ```

3. Create the Vault certificate. Its Subject Alternative Names cover the three node IPs and the Nginx IP, so clients can connect to any of them.

   ```bash
   envsubst '${NGINX_IP} ${VAULT1_IP} ${VAULT2_IP} ${VAULT3_IP}' < $RES/certs/vault.ext.tmpl > vault.ext
   openssl req -newkey rsa:2048 -nodes -keyout vault.key -out vault.csr -subj "/CN=vault"
   openssl x509 -req -in vault.csr -CA lab-ca.crt -CAkey lab-ca.key -CAcreateserial \
     -out vault.crt -days 825 -sha256 -extfile vault.ext
   ```

4. Create the PostgreSQL certificate the same way:

   ```bash
   envsubst '${PG_IP}' < $RES/certs/postgres.ext.tmpl > postgres.ext
   openssl req -newkey rsa:2048 -nodes -keyout postgres.key -out postgres.csr -subj "/CN=postgres"
   openssl x509 -req -in postgres.csr -CA lab-ca.crt -CAkey lab-ca.key -CAcreateserial \
     -out postgres.crt -days 825 -sha256 -extfile postgres.ext
   ```

5. Make the keys readable by the Vault container, which runs as uid 100. This is a lab shortcut, so list it as a limitation.

   ```bash
   chmod 644 *.key
   cd "$LAB_ROOT"
   ```

## Check

```bash
openssl x509 -in .work/tls/vault.crt -noout -ext subjectAltName
openssl verify -CAfile .work/tls/lab-ca.crt .work/tls/vault.crt .work/tls/postgres.crt
```

The SANs list your IPs, and both certificates print `OK`.
