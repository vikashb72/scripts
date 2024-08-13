#!/usr/bin/env bash

# Configs
export NFS_SERVER="192.168.0.21"
export NFS_PATH="/data/nfs"

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

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Install prometheus
helm install prometheus prometheus-community/prometheus \
    --namespace metrics --create-namespace --wait
