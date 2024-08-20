#!/usr/bin/env bash

export VAULT_ADDR=$EXTERNAL_VAULT_ADDR
export VAULT_TOKEN=$EXTERNAL_VAULT_TOKEN
vault login $VAULT_TOKEN

# Configs
export NFS_SERVER="192.168.0.21"
export NFS_PATH="/data/nfs"
export EXTERNAL_VAULT="http://192.168.0.22:8200"
export ENV='minikube'

WORKDIR=$(pwd)/work

rm -rf ${WORKDIR}
mkdir -p $WORKDIR
cd $WORKDIR

# Delete old and start fresh
minikube stop
minikube delete
minikube start \
    --nodes=4 \
    --cni=flannel \
    --driver=docker \
    --container-runtime=containerd \
    --wait=all

export MINIKUBE_IP=$(minikube ip)

# Wait for flannel pods
echo "Waiting for flannel pods to startup"
kubectl wait -n kube-flannel pods -l app=flannel \
    --for condition=Ready --timeout=30s

# Install nfs-provisioning
helm install -n nfs-provisioning nfs-subdir-external-provisioner \
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

# create namespaces
kubectl create namespace argocd
kubectl create namespace external-secrets

# Clone repo
git clone git@github.com:vikashb72/argocd.git
# Create the Chart.lock and charts/argo-cd-<version>.tgz files. 
# The .tgz file is only required for the initial installation 
helm dep update argocd/charts/argo-cd/

# Install argocd
helm install -n argocd argo-cd argocd/charts/argo-cd --wait

ARGO_ADM_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o \
    jsonpath="{.data.password}" | base64 -d)
echo $ARGO_ADM_PASS > argod.adm.pw

helm template argocd/charts/root-app/ | kubectl -n argocd apply -f -

echo "Waiting for external-secrets pods to startup"
for waiting in $(seq 1 1 6)
do
    kubectl wait -n external-secrets pods \
        -l app.kubernetes.io/instance=external-secrets \
        --for condition=Ready --timeout=120s || sleep 10
done

# Authentication Token:
TOKEN=$(vault token create -policy="${ENV}-external-secret-operator-policy" \
    -format=json | jq -r '.auth.client_token')

kubectl -n external-secrets \
    create secret generic vault-token \
    --from-literal=token="${TOKEN}"

kubectl -n external-secrets get secrets

# Create ClusterSecretStore
cat > ClusterSecretStore.yml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
  namespace: external-secrets
spec:
  provider:
    vault:
      server: "${EXTERNAL_VAULT}"
      path: "env/${ENV}"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: "token"
EOF
kubectl -n external-secrets apply -f ClusterSecretStore.yml
kubectl -n external-secrets get clustersecretstore

# Genrate random password
PG_PASS=$(openssl rand -base64 24)
# Save it in vault
vault kv put env/${ENV}/postgress \
    POSTGRES_USER=pguser \
    POSTGRES_PASSWORD="${PG_PASS}"

# External Secret (Example)
cat > ExternalSecret-postgress.yaml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-secret
  namespace: external-secrets
spec:
  refreshInterval: "90s" 
  secretStoreRef: 
    name: vault-backend
    kind: ClusterSecretStore
  target: 
    name: postgres-secret 
    creationPolicy: Owner 
  data: 
    - secretKey: POSTGRES_USER 
      remoteRef: 
        key: env/${ENV}/postgres
        property: POSTGRES_USER 
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: env/${ENV}/postgres
        property: POSTGRES_PASSWORD
EOF
kubectl -n external-secrets apply -f ExternalSecret-postgress.yaml
kubectl -n external-secrets get externalsecret
kubectl -n external-secrets get externalsecrets
kubectl -n external-secrets describe secret postgres-secret

