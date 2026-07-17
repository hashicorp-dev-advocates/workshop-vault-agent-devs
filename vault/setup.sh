#!/bin/sh
# =============================================================================
# vault/setup.sh
#
# Configures a dev-mode Vault server for the Spring Boot payments-app tutorial.
# Works for both the Docker Compose variant and the Kubernetes (k3s) variant.
#
# What this script does:
#   1. Enables KV v2 secrets engine at "spring/kv/"
#   2. Writes sample static secrets for the payments-app
#   3. Enables the database secrets engine at "database/"
#   4. Configures the PostgreSQL plugin (fixed IP 10.5.0.3)
#   5. Creates a "payments-app" database role with short-lived credentials
#   6. Writes and applies the payments-app Vault policy
#   7. Creates a Vault token scoped to that policy (Docker Compose variant)
#   8. Configures Kubernetes auth (only when KUBECONFIG is set — k3s variant)
#
# Prerequisites:
#   - VAULT_ADDR   must be set (e.g. http://127.0.0.1:8200)
#   - VAULT_TOKEN  must be set to the root / admin token
#   - The "database" service must be reachable at 10.5.0.3:5432
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
# 1. Enable KV v2 secrets engine at "spring/kv/"
#
#    KV v2 is the versioned key-value store. Mounting it under "spring/kv/"
#    namespaces secrets by application runtime, keeping Spring and .NET secrets
#    separate from each other and from the database engine.
# ---------------------------------------------------------------------------
log "Enabling KV v2 secrets engine at spring/kv/ ..."
vault secrets enable -path=spring/kv kv-v2 || log "spring/kv already enabled, skipping."

# ---------------------------------------------------------------------------
# 2. Write sample static secrets for the payments-app
#
#    These simulate real application secrets such as a downstream payment
#    processor API key and base URL. Vault Agent will render these into the
#    application.properties file consumed by Spring Boot.
# ---------------------------------------------------------------------------
log "Writing static secrets to spring/kv/data/payments-app ..."
vault kv put spring/kv/payments-app \
  "custom.static-secret.username=nic" \
  "custom.static-secret.password=H@rdT0Gu3ss"

# ---------------------------------------------------------------------------
# 3. Enable the database secrets engine at "database/"
#
#    The database secrets engine generates dynamic, short-lived credentials
#    for PostgreSQL. Each time Vault Agent renders the template it receives a
#    fresh username/password pair; Vault automatically revokes them when the
#    lease expires, so stale credentials cannot accumulate.
# ---------------------------------------------------------------------------
log "Enabling database secrets engine at database/ ..."
vault secrets enable database || log "database secrets engine already enabled, skipping."

# ---------------------------------------------------------------------------
# 4. Configure the PostgreSQL plugin
#
#    The connection URL uses the Docker Compose service name "postgres" as the
#    hostname. "{{username}}" and "{{password}}" are Vault template placeholders
#    that are replaced with the rotation credentials at runtime.
#
#    The "postgres" superuser is used here only for credential management
#    (creating/revoking dynamic users). Applications never receive these creds.
# ---------------------------------------------------------------------------
log "Configuring PostgreSQL database plugin connection ..."
vault write database/config/payments-app \
  plugin_name="postgresql-database-plugin" \
  connection_url="postgresql://{{username}}:{{password}}@10.5.0.3:5432/payments?sslmode=disable" \
  allowed_roles="payments-app" \
  username="postgres" \
  password="postgres"

# NOTE: Root credential rotation is skipped in this dev/tutorial environment.
# In a production setup you would run:
#   vault write -force database/rotate-root/payments-app
# after verifying the connection, so that Vault is the only party that knows
# the management password going forward.

# ---------------------------------------------------------------------------
# 5. Create the "payments-app" database role
#
#    - creation_statements: SQL run when a new dynamic user is created.
#      Grants only the permissions the application needs (SELECT, INSERT,
#      UPDATE, DELETE on the payments schema).
#    - default_ttl: credentials live for 1 hour before Vault tries to renew.
#    - max_ttl: hard ceiling of 24 hours; after this Vault revokes the creds
#      and Vault Agent renders new ones, triggering /actuator/refresh.
# ---------------------------------------------------------------------------
log "Creating payments-app database role ..."
vault write database/roles/payments-app \
  db_name="payments-app" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE payments TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.payments TO \"{{name}}\";
    GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"

# ---------------------------------------------------------------------------
# 6. Write and apply the payments-app Vault policy
#
#    The policy file (vault/policies/payments-app.hcl) is the single source
#    of truth for what paths the payments-app identity is allowed to access.
#    It is applied both here (for the token-based local variant) and in
#    setup-k8s.sh (for the Kubernetes auth variant).
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
# 7. Create a Vault token scoped to the payments-app policy
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
log "  KV v2 path        : spring/kv/payments-app  (custom.static-secret.username / .password)"
log "  Database role     : database/roles/payments-app"
log "  Policy            : payments-app"
log "  Agent token file  : ${SECRETS_DIR}/vault-token"

# ---------------------------------------------------------------------------
# 8. Configure Kubernetes auth (k3s variant only)
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
