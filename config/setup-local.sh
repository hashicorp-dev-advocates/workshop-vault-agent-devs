#!/bin/bash

set -e

mkdir -p tmp/

if [ ! -f ./tmp/k3s.token ]; then
  uuidgen > ./tmp/k3s.token
fi

export KUBECONFIG=./tmp/kubeconfig.yaml
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root-token

K3S_TOKEN=$(cat ./tmp/k3s.token) podman compose -f docker-compose.yaml up -d --build

# Wait for k3s to be ready
until kubectl get nodes; do
  echo "Kubernetes is not running, waiting 2 seconds..."
  sleep 2
done

kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n vault -f vault/service-account.yaml

bash vault/setup.sh

# ---------------------------------------------------------------------------
# Install Vault Agent Injector into the vault namespace.
#
# Only the injector is installed (server.enabled=false). It points at the
# external Vault container on the vpcbr network via externalVaultAddr so
# injected agent sidecars can reach Vault at http://10.5.0.2:8200.
# ---------------------------------------------------------------------------
helm upgrade --install vault-injector hashicorp/vault \
  --version 0.34.0 \
  --namespace vault \
  --create-namespace \
  --set server.enabled=false \
  --set injector.enabled=true \
  --set injector.externalVaultAddr=http://10.5.0.2:8200 \
  --wait