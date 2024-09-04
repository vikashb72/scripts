#!/usr/bin/env bash

export VAULT_K8S_NAMESPACE="vault"
export VAULT_HELM_RELEASE_NAME="vault"
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export WORKDIR="$(pwd)/work/tls"
export KEY_SHARES=5
export KEY_THRESHOLD=3
export MINIKUBE_IP=$(minikube ip)

rm -rf $WORKDIR
mkdir -p $WORKDIR

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
DNS.4 = *.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}
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
spec:
   signerName: kubernetes.io/kubelet-serving
   expirationSeconds: 8640000
   request: $(cat ${WORKDIR}/vault.csr|base64|tr -d '\n')
   usages:
     - digital signature
     - key encipherment
     - server auth
EOF

kubectl delete csr vault.svc 
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

# Create vault namespace
kubectl create namespace $VAULT_K8S_NAMESPACE

kubectl -n $VAULT_K8S_NAMESPACE delete secret vault-ha-tls

# Create TLS Secret
kubectl create secret generic vault-ha-tls \
   -n $VAULT_K8S_NAMESPACE \
   --from-file=vault.key=${WORKDIR}/vault.key \
   --from-file=vault.crt=${WORKDIR}/vault.crt \
   --from-file=vault.ca=${WORKDIR}/vault.ca

kubectl create secret generic vault-ha-tls-new \
   -n $VAULT_K8S_NAMESPACE \
   --from-file=vault.key=${WORKDIR}/vault.key \
   --from-file=vault.crt=${WORKDIR}/vault.crt \
   --from-file=vault.ca=${WORKDIR}/vault.ca

./store-vault-certs-external-vault.sh
