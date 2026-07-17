# =============================================================================
# spring/vault/agent.hcl — Vault Agent configuration skeleton
#
# Complete this file as part of the workshop to enable Vault Agent to
# authenticate to Vault and render secrets into a properties file.
# =============================================================================

# ---------------------------------------------------------------------------
# Vault server connection
# "vault" is the Docker Compose service name resolved via Docker's internal DNS.
# ---------------------------------------------------------------------------
vault {
  address = "http://vault:8200"
}

auto_auth {
  method "token_file" {
    config {
      # Vault 2.x renamed this key from "path" to "token_file_path".
      token_file_path = "/secrets/vault-token"
    }
  }
}
