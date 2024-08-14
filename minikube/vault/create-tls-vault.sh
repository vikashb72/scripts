#!/usr/bin/env bash

# Configs
export NFS_SERVER="192.168.0.21"
export NFS_PATH="/data/nfs"
export VAULT_K8S_NAMESPACE="vault"
export VAULT_HELM_RELEASE_NAME="vault"
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export WORKDIR="$(pwd)/work/tls"
export KEY_SHARES=5
export KEY_THRESHOLD=3

# Delete old instances and start fresh
minikube delete
minikube start \
    --nodes=4 \
    --cni=flannel \
    --driver=docker \
    --container-runtime=containerd \
    --wait=all

rm -rf $WORKDIR ; mkdir -p $WORKDIR

# Get minikube ip
export MINIKUBE_IP=$(minikube ip)

# Wait for flannel pods
echo "Waiting for flannel pods to startup"
kubectl wait -n kube-flannel pods -l app=flannel \
    --for condition=Ready --timeout=30s

# Install nfs provisioning
helm install -n nfs-provisioning nfs-subdir-external-provisioner \
    nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --create-namespace=true \
    --set "nfs.server=${NFS_SERVER}" \
    --set "nfs.path=${NFS_PATH}" \
    --set "storageClass.defaultClass=true" \
    --wait

# Wait for pods
echo "Waiting for nfs-provisioning pods to startup"
kubectl wait -n nfs-provisioning pods -l \
    app=nfs-subdir-external-provisioner  --for condition=Ready \
    --timeout=90s

# Generate private key
openssl genrsa -out ${WORKDIR}/vault.key 2048

## Create the root key
#openssl ecparam -out rootCA.key -name prime256v1 -genkey
#
## Encrypt Root key
#openssl pkcs8 -topk8 -in rootCA.key -out rootCA.pem
#
## Create public key
#openssl ec -in rootCA.pem -pubout -out public.pem

# Generate the Certificate Signing Request (CSR).
#openssl req -new -sha256 -key rootCA.key -out rootCA.csr -config extfile.cnf

# Sign CSR
#openssl req -new -key rootCA.key -out rootCA.csr -config extfile.cnf

# Generate the Root Certificate.
#openssl x509 -req -sha256 -days 3650 -in rootCA.csr \
#    -signkey rootCA.key -out rootCA.crt

# Create vault namespace
kubectl -n $VAULT_K8S_NAMESPACE create namespace $VAULT_K8S_NAMESPACE

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
openssl req -new -sha256 -key ${WORKDIR}/vault.key \
    -out ${WORKDIR}/vault.csr -config ${WORKDIR}/vault-csr.conf

# Create csr yaml file for k8s
cat > ${WORKDIR}/csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
   name: vault.svc
   namespace: ${VAULT_K8S_NAMESPACE}
spec:
   signerName: kubernetes.io/kubelet-serving
   expirationSeconds: 315360000
   request: $(cat ${WORKDIR}/vault.csr|base64|tr -d '\n')
   usages:
     - digital signature
     - key encipherment
     - server auth
EOF

# Send CSR to k8s
kubectl -n $VAULT_K8S_NAMESPACE create -f ${WORKDIR}/csr.yaml

# Approve CSR in k8s
kubectl -n $VAULT_K8S_NAMESPACE certificate approve vault.svc

# Confirm cert was issued
kubectl -n $VAULT_K8S_NAMESPACE get csr vault.svc

# Retrieve cert
kubectl -n $VAULT_K8S_NAMESPACE get csr vault.svc -o jsonpath='{.status.certificate}' | \
    openssl base64 -d -A -out ${WORKDIR}/vault.crt

# Retrieve k8s CA cert
kubectl -n $VAULT_K8S_NAMESPACE config view \
    --raw \
    --minify \
    --flatten \
    -o jsonpath='{.clusters[].cluster.certificate-authority-data}' \
    | base64 -d > ${WORKDIR}/vault.ca

cp ${WORKDIR}/vault.ca ~/vault.ca

# Create TLS Secret
kubectl -n $VAULT_K8S_NAMESPACE create secret generic vault-ha-tls \
   -n $VAULT_K8S_NAMESPACE \
   --from-file=vault.key=${WORKDIR}/vault.key \
   --from-file=vault.crt=${WORKDIR}/vault.crt \
   --from-file=vault.ca=${WORKDIR}/vault.ca

# Create overrides.yaml for vault (helm)
cat > ${WORKDIR}/overrides.yaml <<EOF
global:
   enabled: true
   tlsDisable: false
csi:
  enabled: false
injector:
   enabled: true
ui:
   enabled: true
   serviceType: NodePort
   serviceNodePort: 30001
   externalIPs:
      - $MINIKUBE_IP
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

# Deploy vault via helm with overrides
helm install -n $VAULT_K8S_NAMESPACE $VAULT_HELM_RELEASE_NAME \
    hashicorp/vault -f ${WORKDIR}/overrides.yaml \
    --wait

# Wait for Initialized pods
echo "Waiting for vault pods to initialise"
kubectl wait -n $VAULT_K8S_NAMESPACE pods \
    -l app.kubernetes.io/name=vault  \
    --for condition=PodReadyToStartContainers --timeout=120s

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

echo $CLUSTER_ROOT_TOKEN > ~/.vault-token

# Login to vault-0 with root token
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault login $CLUSTER_ROOT_TOKEN

# List the raft peers
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault operator raft list-peers

# Print the HA status
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- vault status

# Enable the kv-v2 secrets engine
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault secrets enable -path=secret kv-v2

# Create a secret at the path secret/tls/apitest
# with a username and a password
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault kv put secret/tls/apitest username="apiuser" \
    password="supersecret"

# Check secret in secret/tls/apitest
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault kv get secret/tls/apitest

kubectl -n $VAULT_K8S_NAMESPACE get service vault

cat <<EOF 
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- \
    vault login \$VAULT_ROOT_TOKEN
curl --cacert $WORKDIR/vault.ca \
    --header "X-Vault-Token: \$VAULT_ROOT_TOKEN" \
    https://${MINIKUBE_IP}:30001/v1/secret/data/tls/apitest \
    | jq .data.data
EOF


#helm repo add prometheus-community \
#    https://prometheus-community.github.io/helm-charts
#helm install prometheus prometheus-community/prometheus \
#    --namespace metrics \
#    --create-namespace \
#    --wait
