# =============================================================================
# spring/vault/agent.hcl — Vault Agent configuration skeleton
#
# Complete this file as part of the workshop to enable Vault Agent to
# authenticate to Vault and render secrets into a properties file.
# =============================================================================

# ---------------------------------------------------------------------------
# Vault server connection
# Vault publishes port 8200 to 127.0.0.1 on the host.
# ---------------------------------------------------------------------------
vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method "token_file" {
    config {
      token_file_path = "secrets/vault-token"
    }
  }
}
