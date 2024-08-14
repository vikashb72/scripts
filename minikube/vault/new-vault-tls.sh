#!/usr/bin/env bash

export WORKDIR="$(pwd)/work"
export VAULT_K8S_NAMESPACE="vault"
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export MINIKUBE_IP=$(minikube ip)

cd $WORKDIR

# Check vault status (sealed etc)
STATUS=$(kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault status | \
     grep -E '^Initialized *true$|^Sealed *false' | wc -l)
export VAULT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/tls/cluster-keys.json)
export VAULT_TOKEN=$(cat ~/.vault-token)

[ ${STATUS} -ne 2 ] && echo "REQUIRES WORKING VAULT" && exit 2 

[ -z $VAULT_TOKEN ] && echo "MISSING ENV: VAULT_TOKEN" && exit 2

export VAULT_ADDR="https://$(minikube ip):30001"
export VAULT_CACERT="${WORKDIR}/tls/vault.ca"
export VAULT_CACERT=~/vault.ca

mkdir -p vault

cd vault
DATA="cert.data"

vault write -format=json \
    pki/issue/generate-cert-role \
    common_name="*.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}" \
    alt_names="*.${VAULT_SERVICE_NAME}","*.${VAULT_SERVICE_NAME}.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}","*.${VAULT_K8S_NAMESPACE}" \
    ip_sans=127.0.0.1,${MINIKUBE_IP} \
    | jq .data -r > ${DATA}

jq -r '.private_key' $DATA > vault.key
jq -r '.certificate' $DATA > vault.crt
jq -r '.ca_chain[]' $DATA > vault.ca

cp vault.ca ~/vault.ca.new

rm $DATA

kubectl -n $VAULT_K8S_NAMESPACE delete secret vault-ha-tls

# Create TLS Secret
kubectl -n $VAULT_K8S_NAMESPACE create secret generic vault-ha-tls \
   -n $VAULT_K8S_NAMESPACE \
   --from-file=vault.key=vault.key \
   --from-file=vault.crt=vault.crt \
   --from-file=vault.ca=vault.ca
