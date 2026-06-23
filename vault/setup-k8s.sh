#!/usr/bin/env bash
# =============================================================================
# vault/setup-k8s.sh
#
# Deploys and configures Vault on a local k3s cluster for the payments-app
# Kubernetes tutorial variant.
#
# What this script does:
#   1. Adds the HashiCorp Helm repo and installs Vault in dev mode with the
#      Agent Injector enabled
#   2. Waits for Vault and the injector to be ready
#   3. Configures Vault inside the pod (same secrets engines + policy as
#      vault/setup.sh, adapted for in-cluster hostnames)
#   4. Enables the Kubernetes auth method and creates a payments-app role
#
# Prerequisites:
#   - k3s is running and kubectl is configured to target it
#   - helm v3 is installed
#   - A PostgreSQL pod/service is running in the cluster (see note at bottom)
#   - VAULT_K8S_NAMESPACE — Kubernetes namespace for Vault (default: vault)
#   - APP_NAMESPACE       — namespace where payments-app runs (default: default)
#   - POSTGRES_HOST       — in-cluster hostname of the postgres service
#                           (default: postgres.default.svc.cluster.local)
#
# Usage:
#   bash vault/setup-k8s.sh
# =============================================================================

set -euo pipefail

log() { echo "[vault/setup-k8s.sh] $*"; }

VAULT_K8S_NAMESPACE="${VAULT_K8S_NAMESPACE:-vault}"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres.default.svc.cluster.local}"

# ---------------------------------------------------------------------------
# 1. Add the HashiCorp Helm repository
# ---------------------------------------------------------------------------
log "Adding HashiCorp Helm repo ..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# ---------------------------------------------------------------------------
# 2. Install Vault via Helm in dev mode with the Agent Injector enabled
#
#    server.dev.enabled=true  — starts Vault unsealed with root token "root";
#                               suitable for tutorials only, not production.
#    injector.enabled=true    — deploys the Vault Agent Injector webhook which
#                               intercepts Pod creation and automatically injects
#                               a Vault Agent sidecar based on annotations.
# ---------------------------------------------------------------------------
log "Installing Vault Helm chart (dev mode + injector) in namespace ${VAULT_K8S_NAMESPACE} ..."
kubectl create namespace "${VAULT_K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install vault hashicorp/vault \
  --namespace "${VAULT_K8S_NAMESPACE}" \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "injector.enabled=true" \
  --wait

# ---------------------------------------------------------------------------
# 3. Wait for the Vault pod and injector to be fully ready
# ---------------------------------------------------------------------------
log "Waiting for Vault server pod to be ready ..."
kubectl rollout status statefulset/vault \
  --namespace "${VAULT_K8S_NAMESPACE}" \
  --timeout=120s

log "Waiting for Vault Agent Injector deployment to be ready ..."
kubectl rollout status deployment/vault-agent-injector \
  --namespace "${VAULT_K8S_NAMESPACE}" \
  --timeout=120s

# ---------------------------------------------------------------------------
# 4. Configure Vault inside the pod
#
#    All vault CLI commands are run via "kubectl exec" so no local Vault CLI
#    or port-forward is required. The dev root token is "root".
# ---------------------------------------------------------------------------
VAULT_EXEC="kubectl exec -n ${VAULT_K8S_NAMESPACE} vault-0 -- env VAULT_TOKEN=root"

log "Enabling KV v2 secrets engine at spring/kv/ ..."
${VAULT_EXEC} vault secrets enable -path=spring/kv kv-v2 \
  || log "spring/kv already enabled, skipping."

log "Writing static secrets to spring/kv/data/payments-app ..."
${VAULT_EXEC} vault kv put spring/kv/payments-app \
  custom.StaticSecret.username="nic" \
  custom.StaticSecret.password="H@rdT0Gu3ss"

log "Enabling database secrets engine ..."
${VAULT_EXEC} vault secrets enable database \
  || log "database secrets engine already enabled, skipping."

log "Configuring PostgreSQL plugin connection ..."
${VAULT_EXEC} vault write database/config/payments-app \
  plugin_name="postgresql-database-plugin" \
  connection_url="postgresql://{{username}}:{{password}}@${POSTGRES_HOST}:5432/payments?sslmode=disable" \
  allowed_roles="payments-app" \
  username="postgres" \
  password="postgres"

log "Creating payments-app database role ..."
${VAULT_EXEC} vault write database/roles/payments-app \
  db_name="payments-app" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE payments TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.payments TO \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"

log "Writing and applying payments-app policy ..."
# Write the policy HCL inline — no file mount needed when using kubectl exec.
${VAULT_EXEC} vault policy write payments-app - <<'EOF'
path "spring/kv/data/payments-app" {
  capabilities = ["read"]
}
path "spring/kv/metadata/payments-app" {
  capabilities = ["read"]
}
path "database/creds/payments-app" {
  capabilities = ["read"]
}
EOF

# ---------------------------------------------------------------------------
# 5. Enable the Kubernetes auth method
#
#    Vault uses the Kubernetes API to verify that a requesting Pod's service
#    account JWT is valid. The injector presents this JWT automatically when
#    the sidecar authenticates on the Pod's behalf.
# ---------------------------------------------------------------------------
log "Enabling Kubernetes auth method ..."
${VAULT_EXEC} vault auth enable kubernetes \
  || log "Kubernetes auth already enabled, skipping."

log "Configuring Kubernetes auth method ..."
${VAULT_EXEC} vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# ---------------------------------------------------------------------------
# 6. Create the payments-app Vault role for Kubernetes auth
#
#    This role binds together:
#      - The Kubernetes service account "payments-app"
#      - The namespace where the app runs
#      - The Vault policy that grants access to the secrets
#
#    When Vault Agent (injected by the injector) authenticates, it presents
#    the Pod's service account JWT. Vault validates it against this role and
#    returns a token scoped to the payments-app policy.
# ---------------------------------------------------------------------------
log "Creating Kubernetes auth role for payments-app ..."
${VAULT_EXEC} vault write auth/kubernetes/role/payments-app \
  bound_service_account_names="payments-app" \
  bound_service_account_namespaces="${APP_NAMESPACE}" \
  policies="payments-app" \
  ttl="1h"

log ""
log "Vault k8s setup complete."
log ""
log "Next steps:"
log "  1. Build and push the payments-app image (or use a local registry with k3s):"
log "     docker build -t payments-app:latest ./spring/payments-app"
log "     # For k3s local registry: k3s ctr images import <(docker save payments-app:latest)"
log "  2. Apply the Kubernetes manifests:"
log "     kubectl apply -f spring/kubernetes/"
log "  3. Watch the Pod start up with the injected Vault Agent sidecar:"
log "     kubectl get pods -w"
log "  4. Test the app:"
log "     kubectl port-forward svc/payments-app 8080:8080"
log "     curl http://localhost:8080/payments"
