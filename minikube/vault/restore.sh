#!/usr/bin/env bash

# This token will become irrelevant
NEW_ROOT_TOKEN=$(jq -r '.root_token' work/non-tls/init-keys.json)

# get all pods
PODS=$(kubectl -n vault get pods \
    -l app.kubernetes.io/name=vault \
    --no-headers \
    -o custom-columns=":metadata.name")

# Must be done on all the pods
for pod in $PODS
do
   # Remove any stored login token
   kubectl -n vault exec ${pod} -- rm -f /home/vault/.vault-token
   # Login
   kubectl -n vault exec ${pod} -- vault login ${NEW_ROOT_TOKEN}
done

# Find the active POD
ACTIVE_POD=$(kubectl -n vault get pods \
    -l app.kubernetes.io/name=vault \
    --selector="vault-active=true" \
    --no-headers \
    -o custom-columns=":metadata.name")

# upload backup
kubectl -n vault cp work.bak/test.raft.snap ${ACTIVE_POD}:/tmp/
# force installation
kubectl -n vault exec ${ACTIVE_POD} -- \
       vault operator raft snapshot restore -force /tmp/test.raft.snap
# Clean up
kubectl -n vault exec ${ACTIVE_POD} -- rm -f /tmp/test.raft.snap

# get  original unseal keys
VAULT_UNSEAL_KEYS=$(jq -r ".unseal_keys_b64[]" \
   work.bak/non-tls/init-keys.json | head -n 3)

# Unseal vault pods
for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
do
    for pod in $PODS
    do
        kubectl exec -n vault ${pod} -- \
            vault operator unseal $VAULT_UNSEAL_KEY
    done
done

VAULT_ROOT_TOKEN=$(jq -r ".root_token" work.bak/non-tls/init-keys.json)

kubectl -n vault exec ${ACTIVE_POD} -- rm -f /home/vault/.vault-token
sleep 10
kubectl -n vault exec ${ACTIVE_POD} -- vault login $VAULT_ROOT_TOKEN

kubectl -n vault exec ${ACTIVE_POD} -- vault kv get kv/backup_date
