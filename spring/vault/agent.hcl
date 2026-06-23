# =============================================================================
# spring/vault/agent.hcl
#
# Vault Agent configuration for the local (Docker Compose) variant.
#
# Flow:
#   1. Agent authenticates using the token written to /secrets/vault-token
#      by vault-init (vault/setup.sh).
#   2. Agent renders secrets.ctmpl → /secrets/application.properties whenever
#      a secret changes or a lease is renewed.
#   3. After each successful render, agent POSTs to /actuator/refresh so
#      Spring Boot re-binds all @RefreshScope beans without restarting.
#
# This file is bind-mounted read-only into the vault-agent container at
# /spring/vault/agent.hcl (see docker-compose.yml).
# =============================================================================

# ---------------------------------------------------------------------------
# Vault server connection
# "vault" is the Docker Compose service name resolved via Docker's internal DNS.
# ---------------------------------------------------------------------------
vault {
  address = "http://vault:8200"
}

# ---------------------------------------------------------------------------
# Auto-auth: token file method
#
# Vault Agent reads the token from /secrets/vault-token. This file is written
# by vault-init before vault-agent starts (enforced by depends_on in
# docker-compose.yml). The token is scoped to the payments-app policy and
# cannot access any other Vault paths.
#
# In production, replace this with a stronger auth method such as AppRole or
# the platform-native method for your environment (AWS IAM, GCP, etc.).
# ---------------------------------------------------------------------------
auto_auth {
  method "token_file" {
    config {
      # Vault 2.x renamed this key from "path" to "token_file_path".
      token_file_path = "/secrets/vault-token"
    }
  }
}

# ---------------------------------------------------------------------------
# Template: render application.properties from Vault secrets
#
# source      : the Consul Template file that defines the output format
# destination : written to the shared secrets bind-mount; Spring Boot reads
#               this file via spring.config.import
# error_on_missing_key : agent exits with an error if a secret key referenced
#               in the template does not exist — prevents silent partial renders
# command     : called after every successful render; triggers Spring Boot's
#               live-reload endpoint so @RefreshScope beans are re-bound with
#               the latest credentials without a container restart
# ---------------------------------------------------------------------------
template {
  source      = "/spring/vault/secrets.ctmpl"
  destination = "/secrets/vault-secrets.properties"
  error_on_missing_key = true

  # payments-app must be running before this succeeds. The || true means
  # Vault Agent does not retry the full template render on command failure —
  # the file is already written; the app will pick it up on next refresh cycle.
  # wget is used because curl is not available in the hashicorp/vault image.
  # /actuator/refresh requires Content-Type: application/json.
  command = "wget -q --header='Content-Type: application/json' --post-data='{}' http://payments-app:8080/actuator/refresh -O /dev/null || true"
}
