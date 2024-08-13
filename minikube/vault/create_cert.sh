#!/usr/bin/env bash

CERT_FOR="test"
WORKDIR=$(pwd)/work/tls

[ ! -z $1 ] && CERT_FOR=$1

VAULT_K8S_NAMESPACE="vault"
SSL_OU="Home Lab"
DOMAIN='home.local'
PN_SSL_OU=$(echo $SSL_OU | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
PN_DOMAIN=$(echo $DOMAIN \
    | tr '[:upper:]' '[:lower:]' \
    | sed  's/\./-dot-/')
CERT_FOR_FQDN="${CERT_FOR}.${DOMAIN}"

# Check vault status (sealed etc)
STATUS=$(kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault status | \
     grep -E '^Initialized *true$|^Sealed *false' | wc -l)
export VAULT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/cluster-keys.json)
export VAULT_ADDR="https://$(minikube ip):30001"
export VAULT_CACERT="${WORKDIR}/vault.ca"

[ ${STATUS} -ne 2 ] && echo "REQUIRES WORKING VAULT" && exit 2

[ -z $VAULT_TOKEN ] && echo "MISSING ENV: VAULT_TOKEN" && exit 2

WORKDIR=$(pwd)/work/certs/${CERT_FOR_FQDN}
mkdir -p $WORKDIR
cd $WORKDIR

DATA="${CERT_FOR_FQDN}.cert.data"
KEY="${CERT_FOR_FQDN}.key"
CRT="${CERT_FOR_FQDN}.crt"
CA_CHAIN="${CERT_FOR_FQDN}.ca.bundle.crt"

vault write \
    -format=json pki/issue/generate-cert-role \
    common_name=${CERT_FOR_FQDN} \
    | jq .data -r > ${DATA}

jq -r '.private_key' $DATA > $KEY
jq -r '.certificate' $DATA > $CRT
jq -r '.ca_chain[]' $DATA > $CA_CHAIN

rm $DATA
