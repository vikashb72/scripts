#!/usr/bin/env bash

# Configs
export NFS_SERVER="192.168.0.21"
export NFS_PATH="/data/nfs"
export VAULT_K8S_NAMESPACE="vault"
export VAULT_HELM_RELEASE_NAME="vault"
export VAULT_SERVICE_NAME="vault-internal"
export K8S_CLUSTER_NAME="cluster.local"
export WORKDIR="$(pwd)/work"
export KEY_SHARES=5
export KEY_THRESHOLD=3

# Delete old and start fresh
rm -f ~/.vault-token
rm -rf $WORKDIR && mkdir -p $WORKDIR
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
