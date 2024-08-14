#!/usr/bin/env bash

export WORKDIR="$(pwd)/work"
export VAULT_K8S_NAMESPACE="vault"

cd $WORKDIR

# Check vault status (sealed etc)
STATUS=$(kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault status | \
     grep -E '^Initialized *true$|^Sealed *false' | wc -l)
export VAULT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/tls/cluster-keys.json)

[ ${STATUS} -ne 2 ] && echo "REQUIRES WORKING VAULT" && exit 2 

[ -z $VAULT_TOKEN ] && echo "MISSING ENV: VAULT_TOKEN" && exit 2

export VAULT_ADDR="https://$(minikube ip):30001"
export VAULT_CACERT="${WORKDIR}/tls/vault.ca"

CA_PASSPHRASE="Connection-Press-Reject-Garage-Honest-Criminal"

kubectl -n vault exec vault-0 -- vault login $VAULT_TOKEN

mkdir -p out csr cacerts ca

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

[ ! -f out/${FN_SSL_CN}.crt ] && \
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

cp out/${FN_SSL_CN}.crt ca/

# Throws error after 1st run: "path is already in use at pki/"
vault secrets enable \
    -description="PKI engine hosting intermediate CA for ${SSL_OU}" \
    -max-lease-ttl=87600h  -default-lease-ttl=87600h pki || true

[ ! -f csr/${FN_SSL_CN}_intermediate_CA.csr ] && \
vault write -format=json \
    pki/intermediate/generate/internal \
    common_name="${SSL_OU} Intermediate Authority" \
    | jq -r '.data.csr' > csr/${FN_SSL_CN}_intermediate_CA.csr

[ ! -f out/${FN_SSL_CN}_intermediate_CA.crt ] && \
certstrap sign \
    --expires "10 year" \
    --csr csr/${FN_SSL_CN}_intermediate_CA.csr \
    --cert out/${FN_SSL_CN}_intermediate_CA.crt \
    --intermediate \
    --path-length "1" \
    --CA "${SSL_CN}" \
    "${SSL_OU} Intermediate CA1 v1" \
    --passphrase  "$CA_PASSPHRASE" && \
cat out/${FN_SSL_CN}_intermediate_CA.crt \
    out/${FN_SSL_CN}.crt \
    > cacerts/${FN_SSL_OU}_intermediate_CA.crt

cp cacerts/${FN_SSL_OU}_intermediate_CA.crt ca/

vault write pki/config/urls \
    issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
    crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

vault write pki/intermediate/set-signed \
    certificate=@cacerts/${FN_SSL_OU}_intermediate_CA.crt

vault write pki/roles/generate-cert-role \
    allow_wildcard_certificates=true \
    allow_localhost=true \
    allowed_domains="${DOMAIN},vault-internal,local,vault" \
    allow_subdomains=true \
    max_ttl=2160h

exit
mkdir certs
cd certs
CERT_FOR_FQDN="test.${DOMAIN}"
DATA="${CERT_FOR_FQDN}.cert.data"
KEY="${CERT_FOR_FQDN}.key"
CRT="${CERT_FOR_FQDN}.crt"
CA_CHAIN="${CERT_FOR_FQDN}.ca.bundle.crt"

vault write -format=json \
    pki/issue/generate-cert-role \
    common_name="${CERT_FOR_FQDN}" \
    | jq .data -r > ${DATA}

jq -r '.private_key' $DATA > $KEY
jq -r '.certificate' $DATA > $CRT
jq -r '.ca_chain[]' $DATA > $CA_CHAIN

rm $DATA

