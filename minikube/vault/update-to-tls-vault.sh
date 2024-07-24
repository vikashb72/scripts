#!/usr/bin/env bash

# Set vars
export MINIKUBE_IP="$(minikube ip)"
export VAULT_K8S_NAMESPACE="vault" 
export VAULT_HELM_RELEASE_NAME="vault" 
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export WORKDIR="$(pwd)/work/upgrade-to-tls"
export KEY_SHARES=5
export KEY_THRESHOLD=3
rm -rf ${WORKDIR}
mkdir -p ${WORKDIR}
cp $(pwd)/work/non-tls/init-keys.json ${WORKDIR}/

# Generate private key
openssl genrsa -out ${WORKDIR}/vault.key 2048

# Create CSR Config
cat > ${WORKDIR}/vault-csr.conf <<EOF
[req]
default_bits = 2048
prompt = no
encrypt_key = yes
default_md = sha256
distinguished_name = kubelet_serving
req_extensions = v3_req
[ kubelet_serving ]
O = system:nodes
CN = system:node:*.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.${VAULT_SERVICE_NAME}
DNS.2 = *.${VAULT_SERVICE_NAME}.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}
DNS.3 = *.${VAULT_K8S_NAMESPACE}
IP.1 = 127.0.0.1
IP.2 = ${MINIKUBE_IP}
EOF

# Generate CSR
openssl req \
    -new \
    -key ${WORKDIR}/vault.key \
    -out ${WORKDIR}/vault.csr \
    -config ${WORKDIR}/vault-csr.conf

# Create csr yaml file for k8s
cat > ${WORKDIR}/csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
   name: vault.svc
spec:
   signerName: kubernetes.io/kubelet-serving
   expirationSeconds: 8640000
   request: $(cat ${WORKDIR}/vault.csr|base64|tr -d '\n')
   usages:
     - digital signature
     - key encipherment
     - server auth
EOF

# Send CSR to k8s
kubectl create -f ${WORKDIR}/csr.yaml

# Approve CSR in k8s
kubectl certificate approve vault.svc

# Confirm cert was issued
kubectl get csr vault.svc

# Retrieve cert
kubectl get csr vault.svc -o jsonpath='{.status.certificate}' | \
    openssl base64 -d -A -out ${WORKDIR}/vault.crt

# Retrieve k8s CA cert
kubectl config view \
    --raw \
    --minify \
    --flatten \
    -o jsonpath='{.clusters[].cluster.certificate-authority-data}' \
    | base64 -d > ${WORKDIR}/vault.ca

# Create TLS Secret
# kubectl -n vault delete secret vault-ha-tls
kubectl create secret generic vault-ha-tls \
   -n ${VAULT_K8S_NAMESPACE} \
   --from-file=vault.key=${WORKDIR}/vault.key \
   --from-file=vault.crt=${WORKDIR}/vault.crt \
   --from-file=vault.ca=${WORKDIR}/vault.ca

# Create overrides.yaml for vault (helm)
cat > ${WORKDIR}/overrides-tls.yaml <<EOF
global:
   enabled: true
   tlsDisable: false
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
   extraEnvironmentVars:
      VAULT_CACERT: /vault/userconfig/vault-ha-tls/vault.ca
      VAULT_TLSCERT: /vault/userconfig/vault-ha-tls/vault.crt
      VAULT_TLSKEY: /vault/userconfig/vault-ha-tls/vault.key
   volumes:
      - name: userconfig-vault-ha-tls
        secret:
         defaultMode: 420
         secretName: vault-ha-tls
   volumeMounts:
      - mountPath: /vault/userconfig/vault-ha-tls
        name: userconfig-vault-ha-tls
        readOnly: true
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
            api_addr = "https://vault-0.${VAULT_SERVICE_NAME}:8200"
            cluster_addr = "https://vault-0.${VAULT_SERVICE_NAME}:8200"
            ui = true
            listener "tcp" {
               tls_disable = 0
               address = "[::]:8200"
               cluster_address = "[::]:8201"
               tls_cert_file = "/vault/userconfig/vault-ha-tls/vault.crt"
               tls_key_file  = "/vault/userconfig/vault-ha-tls/vault.key"
               tls_client_ca_file = "/vault/userconfig/vault-ha-tls/vault.ca"
            }
            storage "raft" {
               path = "/vault/data"
            }
            disable_mlock = true
            service_registration "kubernetes" {}
EOF
# https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-tls

# Remove non tls instance
helm delete -n ${VAULT_K8S_NAMESPACE} ${VAULT_HELM_RELEASE_NAME} --wait

# Deploy tls vault via helm with overrides
helm install -n ${VAULT_K8S_NAMESPACE} ${VAULT_HELM_RELEASE_NAME} \
    hashicorp/vault -f ${WORKDIR}/overrides-tls.yaml \
    --wait 

# Wait for Initialized pods
echo "Waiting for vault pods to initialise"
kubectl wait -n ${VAULT_K8S_NAMESPACE} pods \
    -l  app.kubernetes.io/name=vault \
    --for condition=PodReadyToStartContainers \
    --timeout=120s

# Get Tokens
VAULT_UNSEAL_KEYS=$(jq -r ".unseal_keys_b64[]" \
    ${WORKDIR}/init-keys.json | head -n $KEY_THRESHOLD)
VAULT_ROOT_TOKEN=$(jq -r ".root_token" ${WORKDIR}/init-keys.json)

sleep 15
# Unseal vault-0
for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
do
    kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
        vault operator unseal $VAULT_UNSEAL_KEY
done

# Get list of vault server pods
VAULT_PODS=$(kubectl -n ${VAULT_K8S_NAMESPACE} get pods \
     -l app.kubernetes.io/name=vault \
     --no-headers -o custom-columns=":metadata.name" | \
     grep -v vault-0)

for pod in $VAULT_PODS
do
    # create script
    cat > ${WORKDIR}/join-raft.sh <<EOF
vault operator raft join -address=https://${pod}.${VAULT_SERVICE_NAME}:8200 \
    -leader-ca-cert="\$(cat /vault/userconfig/vault-ha-tls/vault.ca)" \
    -leader-client-cert="\$(cat /vault/userconfig/vault-ha-tls/vault.crt)" \
    -leader-client-key="\$(cat /vault/userconfig/vault-ha-tls/vault.key)"\
    https://vault-0.${VAULT_SERVICE_NAME}:8200
EOF
    # copy script
    kubectl -n ${VAULT_K8S_NAMESPACE} cp ${WORKDIR}/join-raft.sh \
        ${pod}:/tmp/join-raft.sh

    # execute script
    kubectl exec -n ${VAULT_K8S_NAMESPACE} -it ${pod} -- \
        /bin/sh /tmp/join-raft.sh

    # Unseal pod
    for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
    do
        kubectl exec -n ${VAULT_K8S_NAMESPACE} ${pod} -- \
            vault operator unseal $VAULT_UNSEAL_KEY
    done
done

# Remove token
sleep 15
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    /bin/rm -f /home/vault/.vault-token

# Login to Active Pod
sleep 10
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault login $VAULT_ROOT_TOKEN

for pod in $VAULT_PODS
do
    # Remove Token
    kubectl exec -n ${VAULT_K8S_NAMESPACE} -it ${pod} -- \
        /bin/rm -f /home/vault/.vault-token

    # Login to vault
    kubectl exec -n ${VAULT_K8S_NAMESPACE} ${pod} -- \
        vault login $VAULT_ROOT_TOKEN
done

# Add policy 
cat > ${WORKDIR}/policy.hcl <<EOF
# This needs to be tightened
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

kubectl -n ${VAULT_K8S_NAMESPACE} \
  cp ${WORKDIR}/policy.hcl vault-0:/tmp/policy.hcl
kubectl exec vault-0 -n ${VAULT_K8S_NAMESPACE} -- \
    vault policy write admin /tmp/policy.hcl

# enable secrets kv-v2
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault secrets enable -path=secret kv-v2

# Verify Key
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault kv get secret/initial/non-tls/key

# Display vault
kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- \
    vault operator raft list-peers

kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- vault status
