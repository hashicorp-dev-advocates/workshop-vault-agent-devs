#!/bin/sh
# =============================================================================
# vault/setup.sh
#
# Configures a dev-mode Vault server for the Spring Boot payments-app tutorial.
# Works for both the Docker Compose variant and the Kubernetes (k3s) variant.
#
# What this script does:
#   1. Writes and applies the payments-app Vault policy
#   2. Creates a Vault token scoped to that policy (Docker Compose variant)
#   3. Configures Kubernetes auth (only when KUBECONFIG is set — k3s variant)
#
# NOTE: The secrets engines (KV v2, database) and their configuration are NOT
# set up here. Participants configure them as part of the workshop challenges
# (challenges 01–02 for KV, challenges 07–09 for the database engine).
# The workshop solve script (config/workshop.sh) handles those steps when
# skipping ahead.
#
# Prerequisites:
#   - VAULT_ADDR   must be set (e.g. http://127.0.0.1:8200)
#   - VAULT_TOKEN  must be set to the root / admin token
#   - The "secrets/" directory must exist and be writable (Docker Compose path)
#
# Usage (from repo root):
#   export VAULT_ADDR=http://127.0.0.1:8200
#   export VAULT_TOKEN=root-token
#   bash vault/setup.sh
# =============================================================================

set -eu

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[vault/setup.sh] $*"; }

# Resolve the secrets directory (injected as SECRETS_DIR by docker-compose).
SECRETS_DIR="${SECRETS_DIR:-secrets}"

# Wait until Vault is reachable and unsealed before continuing.
wait_for_vault() {
  log "Waiting for Vault to be ready..."
  until vault status 2>/dev/null | grep -q "Sealed.*false"; do
    sleep 2
  done
  log "Vault is ready."
}

# ---------------------------------------------------------------------------
# 0. Wait for Vault
# ---------------------------------------------------------------------------
wait_for_vault

# ---------------------------------------------------------------------------
# 1. Write and apply the payments-app Vault policy
#
#    The policy file (vault/policies/payments-app.hcl) is the single source
#    of truth for what paths the payments-app identity is allowed to access.
#    It is applied both here (for the token-based local variant) and in
#    the Kubernetes auth section below (for the k3s variant).
# ---------------------------------------------------------------------------
# Resolve the policy file path relative to this script so it works whether
# the script is run from the repo root or from inside a container where the
# vault/ directory is bind-mounted at /vault.
# Use $0 instead of BASH_SOURCE — compatible with sh (BusyBox/ash) used in
# the hashicorp/vault container image.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
log "Applying payments-app policy ..."
vault policy write payments-app "${SCRIPT_DIR}/policies/payments-app.hcl"

# ---------------------------------------------------------------------------
# 2. Create a Vault token scoped to the payments-app policy
#
#    This token is used exclusively by Vault Agent in the Docker Compose
#    variant. It is written to secrets/vault-token, which is bind-mounted
#    into the vault-agent container. The token has a long TTL (768h = 32 days)
#    which is acceptable for a dev/tutorial environment.
#
#    In production you would use a more constrained auth method (AppRole,
#    Kubernetes, AWS IAM, etc.) instead of a static token.
# ---------------------------------------------------------------------------
log "Creating payments-app Vault token ..."
# Use vault's built-in "-field" flag to extract the token directly —
# avoids any dependency on jq which is not present in the vault image.
TOKEN=$(vault token create \
  -policy="payments-app" \
  -ttl="768h" \
  -display-name="payments-app-agent" \
  -field=token)

echo "${TOKEN}" > "${SECRETS_DIR}/vault-token"
log "Token written to ${SECRETS_DIR}/vault-token"

log "Vault setup complete."
log ""
log "Summary:"
log "  Policy            : payments-app"
log "  Agent token file  : ${SECRETS_DIR}/vault-token"
log ""
log "NOTE: KV v2 and database secrets engines are configured by workshop"
log "      participants (challenges 01-02, 07-09) or by config/workshop.sh."

# ---------------------------------------------------------------------------
# 3. Configure Kubernetes auth (k3s variant only)
#
#    This section runs only when KUBECONFIG is set, which happens when
#    vault/setup-k8s.sh calls this script on the host. When the script runs
#    inside the vault-init Docker Compose container, KUBECONFIG is not set and
#    this section is skipped entirely — preserving the Docker Compose behaviour.
#
#    The vault-auth ServiceAccount (vault/service-account.yaml) must already
#    be applied to the cluster before this section runs. It provides the
#    token and CA certificate Vault uses to verify incoming Pod JWTs via the
#    Kubernetes TokenReview API.
# ---------------------------------------------------------------------------
if [ -n "${KUBECONFIG:-}" ]; then
  log "KUBECONFIG is set — configuring Kubernetes auth for k3s variant ..."

  log "Enabling Kubernetes auth method ..."
  vault auth enable kubernetes || log "Kubernetes auth already enabled, skipping."

  log "Extracting vault-auth SA token and CA from cluster ..."
  mkdir -p tmp/
  kubectl get secret -n vault vault-k8s-auth-secret -o jsonpath='{.data.token}' \
    | base64 -d > tmp/k8s.token
  kubectl get secret -n vault vault-k8s-auth-secret -o jsonpath='{.data.ca\.crt}' \
    | base64 -d > tmp/k8s.crt

  log "Configuring Kubernetes auth method ..."
  vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat tmp/k8s.token)" \
    kubernetes_host="https://10.5.0.4:6443" \
    kubernetes_ca_cert=@tmp/k8s.crt

  log "Creating Kubernetes auth role for payments-app ..."
  vault write auth/kubernetes/role/payments-app \
    bound_service_account_names="payments-app" \
    bound_service_account_namespaces="default" \
    policies="payments-app" \
    ttl="1h"

  log "Kubernetes auth configured."
  log "  Auth method : auth/kubernetes"
  log "  k3s API     : https://10.5.0.4:6443"
  log "  Role        : payments-app (SA: payments-app, namespace: default)"
fi
