#!/usr/bin/env bash

export WORKDIR="$(pwd)/work/tls"
export VAULT_K8S_NAMESPACE="vault"

# Check vault status (sealed etc)
STATUS=$(kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault status | \
     grep -E '^Initialized *true$|^Sealed *false' | wc -l)

[ ${STATUS} -ne 2 ] && echo "REQUIRES WORKING VAULT" && exit 2 

[ -z $VAULT_TOKEN ] && echo "MISSING ENV: VAULT_TOKEN" && exit 2

export VAULT_ADDR="https://$(minikube ip):30001"
export VAULT_CACERT="$(pwd)/work/vault.ca"

CA_PASSPHRASE="Connection-Press-Reject-Garage-Honest-Criminal"

export VAULT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/cluster-keys.json)
kubectl -n vault exec vault-0 -- vault login $VAULT_TOKEN

mkdir -p ${WORKDIR}/terraform
cd ${WORKDIR}/terraform
mkdir -p out

# Vars
SSL_C="ZA"
SSL_ST="Gauteng"
SSL_L="Johannesburg"
SSL_O="Home"
SSL_OU="Home Lab"
SSL_CN="Home Lab CA"

DOMAIN='home.local'

FN_SSL_CN=$(echo $SSL_CN | tr ' ' '_')
FN_SSL_OU=$(echo $SSL_OU | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
PN_SSL_OU=$(echo $SSL_OU | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
LC_SSL_OU=$(echo $SSL_OU | tr '[:upper:]' '[:lower:]')
PN_DOMAIN=$(echo $DOMAIN \
    | tr '[:upper:]' '[:lower:]' \
    | sed  's/\./-dot-/')

certstrap init \
     --organization "${SSL_O}" \
     --organizational-unit "${SSL_OU}" \
     --country "${SSL_C}" \
     --province "${SSL_ST}" \
     --locality "${SSL_L}" \
     --common-name "${SSL_CN}" \
     --expires "10 year" \
     --passphrase  "$CA_PASSPHRASE"

openssl x509 -in out/${FN_SSL_CN}.crt -noout  -subject -issuer -enddate

# tcl/tk: mkpasswd -l 31 -d 6 -C 6 -s 6 -2

cat > main.tf << EOF
provider "vault" {}

locals {
  default_10y_in_sec  = 315360000
  default_3y_in_sec   = 94608000
  default_1y_in_sec   = 31536000
  default_1hr_in_sec  = 3600
}

EOF

cat > ${FN_SSL_OU}_ica1.tf << EOF
resource "vault_mount" "${FN_SSL_OU}_v1_ica1_v1" {
 path                      = "${PN_SSL_OU}/v1/ica1/v1"
 type                      = "pki"
 description               = "PKI engine hosting intermediate CA1 v1 for ${LC_SSL_OU}"
 default_lease_ttl_seconds = local.default_3y_in_sec
 max_lease_ttl_seconds     = local.default_10y_in_sec
}

resource "vault_pki_secret_backend_intermediate_cert_request" "${FN_SSL_OU}_v1_ica1_v1" {
 depends_on   = [vault_mount.${FN_SSL_OU}_v1_ica1_v1]
 backend      = vault_mount.${FN_SSL_OU}_v1_ica1_v1.path
 type         = "internal"
 common_name  = "${SSL_OU} Intermediate CA1 v1 "
 key_type     = "rsa"
 key_bits     = "2048"
 ou           = "${LC_SSL_OU}"
 organization = "${SSL_O}"
 country      = "${SSL_C}"
 locality     = "${SSL_L}"
 province     = "${SSL_ST}"
}
EOF

terraform init
terraform apply

find $WORKDIR
mkdir csr

terraform show -json \
    | jq '.values["root_module"]["resources"][].values.csr' -r \
    | grep -v null > csr/${FN_SSL_CN}_v1_ICA1_v1.csr

certstrap sign \
     --expires "10 year" \
     --csr csr/${FN_SSL_CN}_v1_ICA1_v1.csr \
     --cert out/${FN_SSL_OU}_Intermediate_CA1_v1.crt \
     --intermediate \
     --path-length "1" \
     --CA "${SSL_CN}" \
     "${SSL_OU} Intermediate CA1 v1" \
     --passphrase  "$CA_PASSPHRASE"

mkdir cacerts

cat out/${FN_SSL_OU}_Intermediate_CA1_v1.crt \
    out/${FN_SSL_CN}.crt \
    > cacerts/${FN_SSL_OU}_v1_ica1_v1.crt

cat >> ${FN_SSL_OU}_ica1.tf << EOF

resource "vault_pki_secret_backend_intermediate_set_signed" "${FN_SSL_OU}_v1_ica1_v1_signed_cert" {
 depends_on   = [vault_mount.${FN_SSL_OU}_v1_ica1_v1]
 backend      = vault_mount.${FN_SSL_OU}_v1_ica1_v1.path

 certificate = file("\${path.module}/cacerts/${FN_SSL_OU}_v1_ica1_v1.crt")
}

EOF

terraform apply

find $WORKDIR
curl --cacert $VAULT_CACERT \
    -s $VAULT_ADDR/v1/${PN_SSL_OU}/v1/ica1/v1/ca/pem \
    | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  \
    | openssl pkcs7 -print_certs -noout
curl --cacert $VAULT_CACERT \
    -s $VAULT_ADDR/v1/${PN_SSL_OU}/v1/ica1/v1/ca_chain \
    | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  \
    | openssl pkcs7 -print_certs -noout

cat > ${FN_SSL_OU}_ica2.tf << EOF
resource "vault_mount" "${FN_SSL_OU}_v1_ica2_v1" {
 path                      = "${PN_SSL_OU}/v1/ica2/v1"
 type                      = "pki"
 description               = "PKI engine hosting intermediate CA2 v1 for ${LC_SSL_OU}"
 default_lease_ttl_seconds = local.default_3y_in_sec
 max_lease_ttl_seconds     = local.default_10y_in_sec
}

resource "vault_pki_secret_backend_intermediate_cert_request" "${FN_SSL_OU}_v1_ica2_v1" {
 depends_on   = [vault_mount.${FN_SSL_OU}_v1_ica2_v1]
 backend      = vault_mount.${FN_SSL_OU}_v1_ica2_v1.path
 type         = "internal"
 common_name  = "${SSL_OU} Intermediate CA2 v1 "
 key_type     = "rsa"
 key_bits     = "2048"
 ou           = "${LC_SSL_OU}"
 organization = "${SSL_O}"
 country      = "${SSL_C}"
 locality     = "${SSL_L}"
 province     = "${SSL_ST}"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "${FN_SSL_OU}_v1_sign_ica2_v1_by_ica1_v1" {
 depends_on = [
   vault_mount.${FN_SSL_OU}_v1_ica1_v1,
   vault_pki_secret_backend_intermediate_cert_request.${FN_SSL_OU}_v1_ica2_v1,
 ]
 backend              = vault_mount.${FN_SSL_OU}_v1_ica1_v1.path
 csr                  = vault_pki_secret_backend_intermediate_cert_request.${FN_SSL_OU}_v1_ica2_v1.csr
 common_name          = "${SSL_OU} Intermediate CA2 v1.1"
 exclude_cn_from_sans = true
 ou                   = "${LC_SSL_OU}"
 organization         = "${SSL_O}"
 country              = "${SSL_C}"
 locality             = "${SSL_L}"
 province             = "${SSL_ST}"
 max_path_length      = 1
 ttl                  = local.default_10y_in_sec
}

resource "vault_pki_secret_backend_intermediate_set_signed" "${FN_SSL_OU}_v1_ica2_v1_signed_cert" {
 depends_on  = [vault_pki_secret_backend_root_sign_intermediate.${FN_SSL_OU}_v1_sign_ica2_v1_by_ica1_v1]
 backend     = vault_mount.${FN_SSL_OU}_v1_ica2_v1.path
 certificate = format("%s\n%s", vault_pki_secret_backend_root_sign_intermediate.${FN_SSL_OU}_v1_sign_ica2_v1_by_ica1_v1.certificate, file("\${path.module}/cacerts/${FN_SSL_OU}_v1_ica1_v1.crt"))
}
EOF

terraform apply
find $WORKDIR

curl --cacert $VAULT_CACERT \
    -s $VAULT_ADDR/v1/${PN_SSL_OU}/v1/ica2/v1/ca/pem \
    | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  \
    | openssl pkcs7 -print_certs -noout
curl --cacert $VAULT_CACERT \
    -s $VAULT_ADDR/v1/${PN_SSL_OU}/v1/ica2/v1/ca_chain \
    | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  \
    | openssl pkcs7 -print_certs -noout

curl --cacert $VAULT_CACERT \
    -s $VAULT_ADDR/v1/${PN_SSL_OU}/v1/ica2/v1/ca/pem \
    | openssl x509 -in /dev/stdin -noout -text \
    | grep "X509v3 extensions"  -A 13

cat > ${FN_SSL_OU}_ica2_role_test_dot_com.tf << EOF
resource "vault_pki_secret_backend_role" "role" {
 backend            = vault_mount.${FN_SSL_OU}_v1_ica2_v1.path
 name               = "${PN_DOMAIN}-subdomain"
 ttl                = local.default_3y_in_sec
 allow_ip_sans      = true
 key_type           = "rsa"
 key_bits           = 2048
 key_usage          = [ "DigitalSignature"]
 allow_any_name     = false
 allow_localhost    = false
 allowed_domains    = ["${DOMAIN}"]
 allow_bare_domains = false
 allow_subdomains   = true
 server_flag        = false
 client_flag        = true
 no_store           = true
 country            = ["${SSL_C}"]
 locality           = ["${SSL_L}"]
 province           = ["${SSL_ST}"]
}

EOF

terraform apply
find $WORKDIR

vault write \
    -format=json ${PN_SSL_OU}/v1/ica2/v1/issue/${PN_DOMAIN}-subdomain \
    common_name=test.iss.nttltd.global.ntt \
    | jq .data.certificate -r \
    | openssl x509 -in /dev/stdin -text -noout

