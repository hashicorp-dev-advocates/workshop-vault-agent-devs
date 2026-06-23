# Policy: payments-app
#
# Grants the payments-app the minimum permissions it needs to read secrets:
#   - Static secrets from the KV v2 store (API keys, endpoint config)
#   - Dynamic PostgreSQL credentials from the database secrets engine
#
# This policy is applied to both:
#   - The local Vault token used by Vault Agent (docker-compose variant)
#   - The Kubernetes auth role bound to the payments-app service account (k3s variant)

# KV v2: read static secrets for the payments-app
# The "data/" prefix is required for KV v2 read operations.
path "spring/kv/data/payments-app" {
  capabilities = ["read"]
}

# KV v2: allow the agent to read metadata (needed for change detection / templating)
path "spring/kv/metadata/payments-app" {
  capabilities = ["read"]
}

# Database secrets engine: generate dynamic PostgreSQL credentials
path "database/creds/payments-app" {
  capabilities = ["read"]
}
