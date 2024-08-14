#!/usr/bin/env bash

# Set vars
export MINIKUBE_IP="$(minikube ip)"
export VAULT_K8S_NAMESPACE="vault" 
export WORKDIR="$(pwd)/work/tls"
export KEY_SHARES=5
export KEY_THRESHOLD=3

# Wait for Initialized pods
echo "Waiting for vault pods to initialise"
kubectl wait -n ${VAULT_K8S_NAMESPACE} pods \
    -l  app.kubernetes.io/name=vault \
    --for condition=PodReadyToStartContainers \
    --timeout=120s

# Get Tokens
VAULT_UNSEAL_KEYS=$(jq -r ".unseal_keys_b64[]" \
    ${WORKDIR}/cluster-keys.json | head -n $KEY_THRESHOLD)
VAULT_ROOT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/cluster-keys.json)

# Get list of vault server pods
VAULT_PODS=$(kubectl -n ${VAULT_K8S_NAMESPACE} get pods \
     -l app.kubernetes.io/name=vault \
     --no-headers -o custom-columns=":metadata.name" )

for pod in $VAULT_PODS
do
    # Unseal vault pod
    for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
    do
        kubectl exec -n ${VAULT_K8S_NAMESPACE} ${pod} -- \
            vault operator unseal $VAULT_UNSEAL_KEY
    done
done

# Login to Pods
for pod in $VAULT_PODS
do
    # Login to vault
    kubectl exec -n ${VAULT_K8S_NAMESPACE} ${pod} -- \
        vault login $VAULT_ROOT_TOKEN
done
