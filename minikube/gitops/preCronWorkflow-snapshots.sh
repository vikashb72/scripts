#!/usr/bin/env bash
VAULT_NS="vault"

cat > /tmp/policy-snapshot.hc1 <<EOT
path "/sys/storage/raft/snapshot"
{
  capabilities = ["read"]
}
EOT
kubectl -n ${VAULT_NS} cp /tmp/policy-snapshot.hc1 \
    vault-0:/tmp/policy-snapshot.hc1

kubectl -n ${VAULT_NS} exec vault-0 -- \
    vault policy write raft-snapshot /tmp/policy-snapshot.hc1

token=$(kubectl -n ${VAULT_NS} exec vault-0 -- \
    vault token create -policy=raft-snapshot -format=json | \
    jq -r '.auth.client_token')

#kubectl -n argocd delete secret raft-snapshot-token
kubectl -n argocd create secret generic raft-snapshot-token \
   --from-literal=token=${token}

exit
