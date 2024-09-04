#!/usr/bin/env bash

WORKDIR=$(pwd)/work/tls
export VAULT_K8S_NAMESPACE="vault"

# Get ROOT_TOKEN
export VAULT_ROOT_TOKEN=$(jq -r ".root_token" \
    ${WORKDIR}/cluster-keys.json)
export VAULT_ADDR="https://$(minikube ip):30001"
export VAULT_CACERT="${WORKDIR}/vault.ca"

# Login to vault-0
vault login $VAULT_ROOT_TOKEN

cat > /tmp/snapshot.policy.hcl <<EOF
path "/sys/storage/raft/snapshot"
{
  capabilities = ["read"]
}
EOF

vault policy write snapshots /tmp/snapshot.policy.hcl
rm /tmp/snapshot.policy.hcl

K8S_HOST=$(kubectl config view --minify | grep server | awk '{ print $2 }')
K8S_CACERT=$(kubectl config view --raw --minify --flatten \
    -o jsonpath='{.clusters[].cluster.certificate-authority-data}' \
    | base64 --decode)
JWT=$(kubectl -n $VAULT_K8S_NAMESPACE get secrets vault-auth-secret \
    -o 'go-template={{ .data.token }}' | base64 --decode)

vault write auth/kubernetes/config \
    token_reviewer_jwt="${JWT}" \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert="${K8S_CACERT}"

vault write auth/kubernetes/role/vault-raft-snapshot-agent \
    bound_service_account_names=vault-raft-snapshot-agent  \
    bound_service_account_namespaces=${VAULT_K8S_NAMESPACE} \
    policies=snapshots \
    ttl=24h
