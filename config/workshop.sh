#!/bin/bash
# =============================================================================
# config/workshop.sh — Workshop solve script
#
# Running this script applies the complete working configuration for the
# Vault Agent workshop. Use it to skip ahead to the fully-wired state, or
# as a reference for what each challenge asks participants to produce.
#
# Run from the repository root:
#   bash config/workshop.sh
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Applying complete workshop solution from ${REPO_ROOT}"

# -----------------------------------------------------------------------------
# 0. Vault secrets engines and configuration
#    vault/setup.sh (vault-init) only applies the policy and token so that
#    the workshop challenges (01–02, 07–09) remain meaningful exercises.
#    This block replays those challenge steps so the solve script produces a
#    fully-wired environment in one pass.
# -----------------------------------------------------------------------------
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root-token}"

echo "  [0a] Enabling KV v2 secrets engine at spring/kv/ ..."
vault secrets enable -path=spring/kv kv-v2 2>/dev/null || echo "       spring/kv already enabled, skipping."

echo "  [0b] Writing static secrets to spring/kv/payments-app ..."
vault kv put spring/kv/payments-app \
  "custom.static-secret.username=nic" \
  "custom.static-secret.password=${CUSTOM_SECRET}"

echo "  [0c] Enabling database secrets engine ..."
vault secrets enable database 2>/dev/null || echo "       database engine already enabled, skipping."

echo "  [0d] Configuring PostgreSQL database plugin connection ..."
vault write database/config/payments-app \
  plugin_name="postgresql-database-plugin" \
  connection_url="postgresql://{{username}}:{{password}}@10.5.0.3:5432/payments?sslmode=disable" \
  allowed_roles="writer,reader" \
  username="postgres" \
  password="${PG_PASSWORD}"

echo "  [0e] Creating writer database role ..."
vault write database/roles/writer \
  db_name="payments-app" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE payments TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.payments TO \"{{name}}\";
    GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO \"{{name}}\";
  " \
  default_ttl="1m" \
  max_ttl="2m"

echo "  [0f] Creating reader database role ..."
vault write database/roles/reader \
  db_name="payments-app" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE payments TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT ON TABLE public.payments TO \"{{name}}\";
    GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"

echo "    configured Vault secrets engines and database roles"

# -----------------------------------------------------------------------------
# 1. spring/vault/agent.hcl
#    Adds template_config and template blocks to the existing vault{} + auto_auth{}
#    skeleton. This is the output of challenges 03 (static) and 10 (dynamic).
# -----------------------------------------------------------------------------
cat > "${REPO_ROOT}/spring/vault/agent.hcl" << 'EOF'
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

template_config {
  static_secret_render_interval = "1m"
}

# ---------------------------------------------------------------------------
# Auto-auth: token file method
#
# Vault Agent reads the token from secrets/vault-token (relative to the
# working directory). This file is written by vault-init before vault agent
# is started. The token is scoped to the payments-app policy and cannot
# access any other Vault paths.
# ---------------------------------------------------------------------------
auto_auth {
  method "token_file" {
    config {
      path = "secrets/vault-token"
    }
  }
}

# ---------------------------------------------------------------------------
# Template: render vault-secrets.properties from Vault secrets
#
# source      : the Consul Template file that defines the output format
# destination : written to the secrets/ directory; Spring Boot reads
#               this file via spring.config.import
# error_on_missing_key : agent exits with an error if a secret key referenced
#               in the template does not exist — prevents silent partial renders
# command     : called after every successful render; triggers Spring Boot's
#               live-reload endpoint so @RefreshScope beans are re-bound with
#               the latest credentials without a container restart
# ---------------------------------------------------------------------------
template {
  source               = "spring/vault/secrets.ctmpl"
  destination          = "secrets/vault-secrets.properties"
  error_on_missing_key = true

  # payments-app must be running before this succeeds. The || true means
  # Vault Agent does not abort on command failure — the file is already written.
  # /actuator/refresh requires Content-Type: application/json.
  command = "wget -q --header='Content-Type: application/json' --post-data='{}' http://localhost:8080/actuator/refresh -O /dev/null || true"
}
EOF
echo "    wrote spring/vault/agent.hcl"

# -----------------------------------------------------------------------------
# 2. spring/vault/secrets.ctmpl
#    Adds the database/creds/writer block to the existing KV skeleton.
#    This is the output of challenge 10 (extend template for dynamic secrets).
# -----------------------------------------------------------------------------
cat > "${REPO_ROOT}/spring/vault/secrets.ctmpl" << 'EOF'
{{- /* spring/vault/secrets.ctmpl — Consul Template skeleton
   Complete this file as part of the workshop to render Vault secrets
   into /secrets/vault-secrets.properties.
*/ -}}

{{- /* -------------------------------------------------------------------------
   Static secrets from KV v2.
   .Data.data is used because KV v2 wraps values under a nested "data" key.
   ------------------------------------------------------------------------- */ -}}
{{ with secret "spring/kv/data/payments-app" -}}
custom.static-secret.username={{ index .Data.data "custom.static-secret.username" }}
custom.static-secret.password={{ index .Data.data "custom.static-secret.password" }}
{{ end -}}

{{- /* -------------------------------------------------------------------------
   Dynamic writer credentials from the database secrets engine.
   Short TTL (1m/2m) — Vault Agent re-renders frequently; the DataSource
   @RefreshScope bean is replaced with a new pool on each refresh.
   ------------------------------------------------------------------------- */ -}}
{{ with secret "database/creds/writer" -}}
spring.datasource.username={{ .Data.username }}
spring.datasource.password={{ .Data.password }}
{{ end -}}
EOF
echo "    wrote spring/vault/secrets.ctmpl"

# -----------------------------------------------------------------------------
# 3. spring/payments-app/src/main/resources/application.properties
#    Removes hardcoded credentials, adds spring.config.import, exposes
#    the refresh actuator endpoint.
#    This is the output of challenge 04 (configure Spring to import file).
# -----------------------------------------------------------------------------
cat > "${REPO_ROOT}/spring/payments-app/src/main/resources/application.properties" << 'EOF'
# =============================================================================
# Application base configuration — safe defaults, committed to source control.
#
# This file contains everything EXCEPT credentials. Credentials are written by
# Vault Agent to /vault/secrets/vault-secrets.properties and imported below.
#
# Spring merges the two files: keys defined here act as defaults; any key also
# present in vault-secrets.properties is overridden by the secrets file value.
# Keys only in vault-secrets.properties (username, password) are simply added.
#
# No "optional:" prefix on spring.config.import — the app fast-fails at startup
# with ConfigDataLocationNotFoundException if Vault Agent has not yet rendered
# the secrets file.
# =============================================================================

spring.application.name=payments-app

# ---------------------------------------------------------------------------
# Import the credentials file rendered by Vault Agent.
# ---------------------------------------------------------------------------
spring.config.import=file:/vault/secrets/vault-secrets.properties

# ---------------------------------------------------------------------------
# Actuator: expose /actuator/refresh.
# Vault Agent POSTs to this endpoint after each re-render so @RefreshScope
# beans are re-bound with the latest credentials without a restart.
# ---------------------------------------------------------------------------
management.endpoints.web.exposure.include=refresh,health

# ---------------------------------------------------------------------------
# DataSource — non-secret connection defaults.
# Credentials (username / password) come from vault-secrets.properties.
# ---------------------------------------------------------------------------
spring.datasource.url=jdbc:postgresql://postgres:5432/payments
EOF
echo "    wrote application.properties"

# -----------------------------------------------------------------------------
# 4. PaymentsAppApplication.java
#    Adds @RefreshScope to both beans and the import.
#    This is the combined output of challenges 05 (ExampleClient) and
#    11 (DataSource).
# -----------------------------------------------------------------------------
cat > "${REPO_ROOT}/spring/payments-app/src/main/java/com/hashicorp/workshop/paymentsapp/PaymentsAppApplication.java" << 'EOF'
package com.hashicorp.workshop.paymentsapp;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.boot.jdbc.DataSourceBuilder;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.context.annotation.Bean;

import javax.sql.DataSource;

/**
 * Entry point for the payments-app.
 *
 * <p>This application deliberately has no dependency on Spring Cloud Vault,
 * Spring Vault, or any Vault SDK. Secrets are provided exclusively via a
 * properties file rendered by Vault Agent, imported through
 * {@code spring.config.import} in application.properties.
 *
 * <p>Live secret reload is achieved by:
 * <ol>
 *   <li>Vault Agent re-rendering the secrets file when a lease renews or a
 *       secret rotates.</li>
 *   <li>Vault Agent calling {@code POST /actuator/refresh} after each
 *       successful render.</li>
 *   <li>Spring Cloud Context re-binding all {@code @RefreshScope} beans
 *       with the updated property values.</li>
 * </ol>
 *
 * <p>{@code @RefreshScope} beans must be defined here (in the main application
 * class) so that Spring's proxy-based refresh mechanism can destroy and recreate
 * them. Defining {@code @RefreshScope} on a {@code @ConfigurationProperties}
 * class alone does not trigger recreation on refresh.
 */
@SpringBootApplication
@EnableConfigurationProperties(AppProperties.class)
public class PaymentsAppApplication {

    private final Log log = LogFactory.getLog(getClass());

    public static void main(String[] args) {
        SpringApplication.run(PaymentsAppApplication.class, args);
    }

    /**
     * Constructs a {@link DataSource} from the {@code spring.datasource.*} properties
     * rendered by Vault Agent. Annotated with {@code @RefreshScope} so that Spring
     * destroys and recreates this bean — closing the old connection pool and opening
     * a new one — each time {@code POST /actuator/refresh} is called.
     */
    @Bean
    @RefreshScope
    DataSource dataSource(DataSourceProperties properties) {
        log.info("rebuild DataSource with username: " + properties.getUsername());
        return DataSourceBuilder
                .create()
                .url(properties.getUrl())
                .username(properties.getUsername())
                .password(properties.getPassword())
                .build();
    }

    /**
     * Constructs an {@link ExampleClient} from static KV v2 credentials
     * rendered by Vault Agent. Annotated with {@code @RefreshScope} so that
     * Spring destroys and recreates this bean with fresh credentials each time
     * {@code POST /actuator/refresh} is called.
     */
    @Bean
    @RefreshScope
    ExampleClient exampleClient(AppProperties properties) {
        log.info("rebuild ExampleClient with static-secret username: "
                + properties.getStaticSecret().getUsername());
        return new ExampleClient(properties);
    }
}
EOF
echo "    wrote PaymentsAppApplication.java"

# -----------------------------------------------------------------------------
# 5. spring/kubernetes/deployment.yaml
#    Adds the full Vault Agent Injector annotation set.
#    This is the combined output of challenges 15 and 16 (Kubernetes section).
# -----------------------------------------------------------------------------
cat > "${REPO_ROOT}/spring/kubernetes/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-app
  namespace: default
  labels:
    app: payments-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payments-app
  template:
    metadata:
      labels:
        app: payments-app
      annotations:
        # -----------------------------------------------------------------
        # Vault Agent Injector annotations
        #
        # These annotations are read by the Vault Agent Injector webhook
        # when this Pod is created. The injector automatically:
        #   - Adds a vault-agent-init initContainer to render the secrets
        #     file before the app container starts
        #   - Adds a vault-agent sidecar container to keep leases renewed
        #     and re-render the file when secrets rotate
        # -----------------------------------------------------------------

        # Enable injection for this Pod.
        vault.hashicorp.com/agent-inject: "true"

        # Address of the external Vault server (running in docker-compose on
        # the vpcbr network at fixed IP 10.5.0.2).
        vault.hashicorp.com/vault-addr: "http://10.5.0.2:8200"

        # The Vault role to authenticate as.
        vault.hashicorp.com/role: "payments-app"
        vault.hashicorp.com/template-static-secret-render-interval: "1m"

        # Tell the injector to inject a secret rendered to a file named
        # "vault-secrets.properties" inside /vault/secrets/.
        vault.hashicorp.com/agent-inject-secret-vault-secrets.properties: "spring/kv/data/payments-app"

        # Consul Template body — credentials only.
        vault.hashicorp.com/agent-inject-template-vault-secrets.properties: |
          {{- with secret "spring/kv/data/payments-app" }}
          custom.static-secret.username={{ index .Data.data "custom.static-secret.username" }}
          custom.static-secret.password={{ index .Data.data "custom.static-secret.password" }}
          {{- end }}
          {{- with secret "database/creds/writer" }}
          spring.datasource.username={{ .Data.username }}
          spring.datasource.password={{ .Data.password }}
          {{- end }}

        # After each successful re-render, call /actuator/refresh so Spring
        # re-binds @RefreshScope beans without restarting the container.
        vault.hashicorp.com/agent-inject-command-vault-secrets.properties: >-
          wget -q --header="Content-Type: application/json" --post-data="{}" http://127.0.0.1:8080/actuator/refresh -O /dev/null || true

        # Revoke the dynamic DB lease when the Pod shuts down.
        vault.hashicorp.com/agent-revoke-on-shutdown: "true"

    spec:
      serviceAccountName: payments-app

      containers:
        - name: payments-app
          image: ghcr.io/hashicorp-dev-advocates/payments-app-spring:1.0.0-spring
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_CONFIG_IMPORT
              value: "file:/vault/secrets/vault-secrets.properties"
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://10.5.0.3:5432/payments"
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 15
EOF
echo "    wrote spring/kubernetes/deployment.yaml"

echo ""
echo "==> Workshop solution applied. All files are in their working state."
