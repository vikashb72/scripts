#!/usr/bin/env bash

# Defaults
NFS_SERVER="192.168.0.21"
NFS_PATH="/data/nfs"
VAULT_K8S_NAMESPACE="vault"
VAULT_HELM_RELEASE_NAME="vault"
VAULT_SERVICE_NAME="vault-internal"
K8S_CLUSTER_NAME="cluster.local"
WORKDIR="$(pwd)/work"
KEY_SHARES=5
KEY_THRESHOLD=3


ARGUMENT_LIST=(
  "nfs-path"
  "nfs-server"
  "k8s-cluster-name"
  "vault-namespace"
  "vault-release-name"
  "vault-service-name"
  "vault-key-shares"
  "vault-key-threshold"
)


# read arguments
opts=$(getopt \
  --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
  --name "$(basename "$0")" \
  --options "" \
  -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nfs-server)
      NFS_SERVER=$2
      shift 2
      ;;
    --nfs-path)
      NFS_PATH=$2
      shift 2
      ;;
    --k8s-cluster-name)
      K8S_CLUSTER_NAME=$2
      shift 2
      ;;
    --vault-namespace)
      VAULT_K8S_NAMESPACE=$2
      shift 2
      ;;
    --vault-release-name)
      VAULT_HELM_RELEASE_NAME=$2
      shift 2
      ;;
    --vault-service-name)
      VAULT_SERVICE_NAME=$2
      shift 2
      ;;
    --vault-key-shares)
      KEY_SHARES=$2
      shift 2
      ;;
    --vault-key-threshold)
      KEY_THRESHOLD=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cat <<EOF
# Defaults
NFS_SERVER              = $NFS_SERVER
NFS_PATH                = $NFS_PATH
VAULT_K8S_NAMESPACE     = $VAULT_K8S_NAMESPACE
VAULT_HELM_RELEASE_NAME = $VAULT_HELM_RELEASE_NAME
VAULT_SERVICE_NAME      = $VAULT_SERVICE_NAME
K8S_CLUSTER_NAME        = $K8S_CLUSTER_NAME
WORKDIR                 = $WORKDIR
KEY_SHARES              = $KEY_SHARES
KEY_THRESHOLD           = $KEY_THRESHOLD
EOF
