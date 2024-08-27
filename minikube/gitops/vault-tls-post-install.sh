#!/usr/bin/env bash

export VAULT_K8S_NAMESPACE="vault"
export VAULT_HELM_RELEASE_NAME="vault"
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export WORKDIR="$(pwd)/work/tls"
export KEY_SHARES=5
export KEY_THRESHOLD=3
export MINIKUBE_IP=$(minikube ip)

# Wait for Initialized pods
echo "Waiting for vault pods to initialise"
sleep 10
kubectl wait -n $VAULT_K8S_NAMESPACE pods \
    -l app.kubernetes.io/name=vault  \
    --for condition=PodReadyToStartContainers --timeout=120s
kubectl wait -n $VAULT_K8S_NAMESPACE pods \
    -l app.kubernetes.io/name=vault  \
    --for condition=PodScheduled --timeout=120s
kubectl wait -n $VAULT_K8S_NAMESPACE pods \
    -l app.kubernetes.io/name=vault \
    --for condition=Initialized --timeout=120s

# Initialise vault-0 (params need adjusting)
sleep 2
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault operator init \
    -key-shares=${KEY_SHARES} \
    -key-threshold=${KEY_THRESHOLD} \
    -format=json > ${WORKDIR}/cluster-keys.json

# Get Unseal Key(s)
VAULT_UNSEAL_KEYS=$(jq -r ".unseal_keys_b64[]" \
    ${WORKDIR}/cluster-keys.json | head -n $KEY_THRESHOLD)
VAULT_ROOT_TOKEN=$(jq -r ".root_token" \
    ${WORKDIR}/cluster-keys.json)

# Unseal vault-0
for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
do
    kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
        vault operator unseal $VAULT_UNSEAL_KEY
done

# Login to vault-0
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault login $VAULT_ROOT_TOKEN

# Get list of vault server pods
VAULT_PODS=$(kubectl -n $VAULT_K8S_NAMESPACE get pods \
    -l app.kubernetes.io/name=vault \
    --no-headers -o custom-columns=":metadata.name" | \
    grep -v vault-0)

for pod in $VAULT_PODS
do
    # create script
    cat > ${WORKDIR}/join-raft.sh <<EOF
vault operator raft join -address=https://${pod}.vault-internal:8200 \
    -leader-ca-cert="\$(cat /vault/userconfig/vault-ha-tls/vault.ca)" \
    -leader-client-cert="\$(cat /vault/userconfig/vault-ha-tls/vault.crt)" \
    -leader-client-key="\$(cat /vault/userconfig/vault-ha-tls/vault.key)"\
    https://vault-0.vault-internal:8200
EOF

    # copy script
    kubectl -n $VAULT_K8S_NAMESPACE cp ${WORKDIR}/join-raft.sh \
        ${pod}:/tmp/join-raft.sh

    # execute script
    kubectl exec -n $VAULT_K8S_NAMESPACE -it ${pod} -- \
        /bin/sh /tmp/join-raft.sh

    # Unseal vault pod
    for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
    do
        kubectl exec -n $VAULT_K8S_NAMESPACE ${pod} -- \
            vault operator unseal $VAULT_UNSEAL_KEY
    done
done

# get cluster root token
export CLUSTER_ROOT_TOKEN=$(cat ${WORKDIR}/cluster-keys.json | \
     jq -r ".root_token")

# Login to vault-0 with root token
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault login $CLUSTER_ROOT_TOKEN

# List the raft peers
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault operator raft list-peers

# Print the HA status
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- vault status

# Enable the Kubernetes auth method
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault auth enable kubernetes

# Enable the approle auth method
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault auth enable approle

# Enable the kv-v2 secrets engine
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault secrets enable -path=kv kv-v2

# generate random password
API_PASS=$(openssl rand -base64 24)

# Create a secret at the path secret/tls/apitest
# with a username and a password
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault kv put kv/tls/apitest username="apiuser" \
    password="${API_PASS}"

# Check secret in secret/tls/apitest
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault kv get kv/tls/apitest

kubectl -n $VAULT_K8S_NAMESPACE get service vault
