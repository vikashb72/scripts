#!/usr/bin/env bash

export VAULT_K8S_NAMESPACE="vault"
export WORKDIR="$(pwd)/work/tls"
export VAULT_ADDR=$EXTERNAL_VAULT_ADDR
export ENV='minikube'

#kubectl -n $VAULT_K8S_NAMESPACE get secret vault-ha-tls -o json | \
kubectl -n $VAULT_K8S_NAMESPACE get secret vault-ha-tls-new -o json | \
    jq -r '.data | to_entries | map({key: .key, value: (.value | @base64d)}) | from_entries' \
    > ${WORKDIR}/vault-ha-tls.json

export VAULT_ADDR=$EXTERNAL_VAULT_ADDR
vault login $EXTERNAL_VAULT_TOKEN || exit

vault kv put kv/${ENV}/vault/tls @${WORKDIR}/vault-ha-tls.json
vault kv get kv/${ENV}/vault/tls
kubectl -n $VAULT_K8S_NAMESPACE delete secret vault-ha-tls-new
