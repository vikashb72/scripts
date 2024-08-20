#!/usr/bin/env bash

VAULT_ROOT_TOKEN=$(jq -r ".root_token" ~/.vault.init.keys)
vault login $VAULT_ROOT_TOKEN

# Enable secrets
vault secrets enable -path=kv kv-v2
vault secrets enable -path=env kv-v2
vault secrets enable transit

# Enable auth methods
vault auth enable kubernetes
vault auth enable approle
# vault auth enable github
#
#  The GitHub auth method allows users to authenticate using a GitHub
#  personal access token. Users can generate a personal access token from the
#  settings page on their GitHub account.
#
#  Authenticate using a GitHub token:
#
#      $ vault login -method=github token=abcd1234
#
#
# Write auth configs
#vault write auth/github/config organization=vikashb72

# Create kubernetes roles
for role in minikube k8s k3s dev uat testing prod
do
    # role
    vault write auth/kubernetes/role/${role}-external-secret-operator \
        bound_service_account_names=external-secrets \
        bound_service_account_namespaces=external-secrets \
        policies=dev-external-secret-operator-policy \
        ttl=24h

    # policy
    vault policy write ${role}-external-secret-operator-policy -<<EOT
path "env/data/${role}/*" {
  capabilities = ["read"]
}
EOT

    vault write -f transit/keys/autounseal-${role}

    vault policy write ${role}-autounseal -<<EOT
path "transit/encrypt/autounseal-${role}" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal-${role}" {
   capabilities = [ "update" ]
}
EOT
   echo "Create a token:"
   echo "\$token=\$(vault token create -policy=${role}-external-secret-operator-policy -format=json | jq -r '.auth.client_token')"
   echo "Store token:"
   echo "vault kv put env/${role}/vault/transit/seal token=\$token"

   vault kv put env/${role}/postgres POSTGRES_USER=admin POSTGRES_PASSWORD=12345

done

cat <<EOT
# Get the jwt from k8s
\$jwt=\$(kubectl get secret vault-token -o json | jq -r '.data.token')

# Store in vault
vault write auth/kubernetes/login \
    role=dev-external-secret-operator \
    jwt=\$jwt iss=https://kubernetes.default.svc.cluster.local
EOT

# audit file for debuging
vault audit enable file file_path=/opt/vault/audit.log

