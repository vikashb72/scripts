#!/usr/bin/env bash

# Configs
export NFS_SERVER="192.168.0.21"
export NFS_PATH="/data/nfs"
WORKDIR=$(pwd)/work

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

# create namespace for argocd
kubectl create namespace argocd

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

