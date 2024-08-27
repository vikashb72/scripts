#!/usr/bin/env bash

# Configs
export NFS_SERVER="192.168.0.21"
export NFS_PATH="/data/nfs"
export EXTERNAL_VAULT="http://192.168.0.22:8200"
export ENV='minikube'
export VAULT_ADDR=$EXTERNAL_VAULT_ADDR
export VAULT_TOKEN=$EXTERNAL_VAULT_TOKEN

vault login $VAULT_TOKEN || exit
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
    --insecure-registry "192.168.0.0/24" \
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

# Clone repo
git clone git@github.com:vikashb72/gitops.git

# Create the Chart.lock and charts/argo-cd-<version>.tgz files. 
# The .tgz file is only required for the initial installation 
helm dep update gitops/charts/argo-cd/

# Install argocd
helm install -n argocd argo-cd gitops/charts/argo-cd \
    --create-namespace=true \
    --wait

ARGO_ADM_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o \
    jsonpath="{.data.password}" | base64 -d)
echo $ARGO_ADM_PASS > argocd.adm.pw

# Store Argo ESO Bootstrap INFO
BOOSTRAP_TOKEN=$(vault kv get -format=json kv/minikube/argo/bootstrap \
    | jq -r '.data.data.token')
kubectl -n argocd create secret generic argo-boostrap-eso-vault \
    --from-literal=addr=${EXTERNAL_VAULT_ADDR} \
    --from-literal=token=${BOOSTRAP_TOKEN} \
    --from-literal=path="${ENV}/vault/transit/seal"

kubectl -n argocd get secrets

helm template gitops/umbrella-chart | kubectl -n argocd apply -f -

echo "Waiting for external-secrets pods to startup"
for waiting in $(seq 1 1 6)
do
    kubectl wait -n external-secrets pods \
        -l app.kubernetes.io/instance=external-secrets \
        --for condition=Ready --timeout=120s || sleep 10
done
