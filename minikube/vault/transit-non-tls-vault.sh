#!/usr/bin/env bash

# Configs
export WORKDIR="$(pwd)/work/non-tls"

export NFS_SERVER="192.168.0.5"
export NFS_PATH="/data/nfs"
export VAULT_K8S_NAMESPACE="vault"
export VAULT_HELM_RELEASE_NAME="vault"
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export KEY_SHARES=5
export KEY_THRESHOLD=3

# Delete old and start fresh
rm -f ~/.vault-token
rm -rf ${WORKDIR} && mkdir -p ${WORKDIR}
minikube stop
minikube delete
minikube start \
    --nodes=4 \
    --cni=flannel \
    --driver=docker \
    --container-runtime=containerd \
    --wait=all

minikube addons enable registry

export MINIKUBE_IP=$(minikube ip)

# Wait for flannel pods
echo "Waiting for flannel pods to startup"
kubectl wait -n kube-flannel pods -l app=flannel \
    --for condition=Ready --timeout=30s

# Install nfs-provisioning
helm install \
    -n nfs-provisioning \
    nfs-subdir-external-provisioner \
    nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --create-namespace=true \
    --set "nfs.server=${NFS_SERVER}" \
    --set "nfs.path=${NFS_PATH}" \
    --set "storageClass.defaultClass=true" \
    --wait 

# Wait for pods
echo "Waiting for nfs-provisioning pods to startup"
kubectl wait -n nfs-provisioning pods \
    -l app=nfs-subdir-external-provisioner \
    --for condition=Ready \
    --timeout=30s

# create vault-config.yml
cat > ${WORKDIR}/vault-config.yml <<EOF
global:
  enabled: true
  tlsDisable: true
  namespace: ${VAULT_K8S_NAMESPACE}
ui:
  enabled: true
  serviceType: NodePort
  serviceNodePort: 30001
  externalIPs:
    - ${MINIKUBE_IP}
injector:
  enabled: true
server:
  dataStorage:
    storageClass: nfs-client
  standalone:
    enabled: false
  affinity: ""
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        cluster_name = "vault-integrated-storage"
        ui = true
        listener "tcp" {
          address = "[::]:8200"
          cluster_address = "[::]:8201"
          tls_disable = "true"
          http_read_timeout = "600s"
        }
        storage "raft" {
          path  = "/vault/data/"
        }
        seal "transit" {
          address = "http://192.168.0.22:8200"
          token= "<token>"
          disable_renewal = "false"
          key_name = "autounseal"
          mount_path = "transit/"
          tls_skip_verify = "true"
        }

        service_registration "kubernetes" {}
        #disable_mlock = true
EOF

# Install vault
helm install -n ${VAULT_K8S_NAMESPACE} \
    ${VAULT_HELM_RELEASE_NAME} hashicorp/vault \
    -f ${WORKDIR}/vault-config.yml \
    --create-namespace=true \
    --wait

# Wait for Initialized pods
echo "Waiting for vault pods to initialise"
kubectl wait -n ${VAULT_K8S_NAMESPACE} pods \
    -l app.kubernetes.io/name=vault  \
    --for condition=PodReadyToStartContainers \
    --timeout=120s

# Initialise vault
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault operator init \
    -format=json > ${WORKDIR}/init-keys.json

# Store keys
#VAULT_UNSEAL_KEYS=$(jq -r ".unseal_keys_b64[]" \
#    ${WORKDIR}/init-keys.json | \
#    head -n $KEY_THRESHOLD)
VAULT_ROOT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/init-keys.json)

# Unseal vault-0
#for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
#do
#    kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
#        vault operator unseal $VAULT_UNSEAL_KEY
#done

# Login to vault-0
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault login $VAULT_ROOT_TOKEN

cat > ${WORKDIR}/policy.hcl <<EOF
# This need to be tightened
# Read system health check
path "sys/health"
{
  capabilities = ["read", "sudo"]
}

# Enable key/value secrets engine at the kv-v2 path
path "sys/mounts/kv-v2" {
  capabilities = ["update"]
}

# Manage secrets engines
path "sys/mounts/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "patch"]
}

# List existing secrets engines.
path "sys/mounts"
{
  capabilities = ["read", "list", "create"]
}

# Write and manage secrets in key/value secrets engine
path "kv-v2/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Create policies to permit apps to read secrets
path "sys/policies/acl/*"
{
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage auth methods broadly across Vault
path "auth/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create, update, and delete auth methods
path "sys/auth/*"
{
  capabilities = ["create", "update", "delete", "sudo"]
}

# List auth methods
path "sys/auth"
{
  capabilities = ["read"]
}

# Create tokens for verification & test
path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

# List, create, update, and delete key/value secrets
path "secret*"
{
  capabilities = ["create", "read", "update", "delete", "list", "patch"]
}

path "configs*"
{
  capabilities = ["create", "read", "update", "delete", "list", "patch"]
}

# Work with pki secrets engine
path "pki*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch"]
}
EOF

# Add policy
kubectl -n ${VAULT_K8S_NAMESPACE} \
    cp ${WORKDIR}/policy.hcl vault-0:/tmp/policy.hcl
kubectl exec vault-0 -n ${VAULT_K8S_NAMESPACE} -- \
    vault policy write admin /tmp/policy.hcl

# Get list of vault server pods
VAULT_PODS=$(kubectl -n ${VAULT_K8S_NAMESPACE} get pods \
     -l app.kubernetes.io/name=vault \
     --no-headers -o custom-columns=":metadata.name" | \
     grep -v vault-0)

for pod in $VAULT_PODS
do
    # Join pod to raft 
    kubectl exec -n ${VAULT_K8S_NAMESPACE} ${pod} \
         -- vault operator raft join \
        http://vault-0.vault-internal:8200

    # Unseal pod
    #for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
    #do
    #    kubectl exec -n ${VAULT_K8S_NAMESPACE} ${pod} -- \
    #        vault operator unseal $VAULT_UNSEAL_KEY
    #done
done

# Enable k8s auth
kubectl exec vault-0 -n ${VAULT_K8S_NAMESPACE} -- \
    vault auth enable kubernetes

# Enable secrets kv-v2
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault secrets enable -path=kv kv-v2

# Add test secret
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault kv put kv/initial/non-tls/key tkey="test1234567890"

# Verify Key
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault kv get kv/initial/non-tls/key 

# Display vault
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault operator raft list-peers
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- vault status

# Sample Secrets 
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault kv put kv/configs/example \
    url=odriod.local \
    username=odroid-admin \
    password=2k6jW7z.Lx9akRporPa.0Zlw 

kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
   vault kv put kv/test-version version=1 stage=dev

kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
   vault kv put kv/test-version version=2 stage=dev

kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
   vault kv patch kv/test-version version=3

kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
   vault kv get --version=2 kv/test-version 
