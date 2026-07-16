package com.hashicorp.workshop.paymentsapp;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Typed binding for static KV v2 credentials sourced from Vault Agent.
 *
 * <p>Vault Agent renders these into the imported secrets file as:
 * <pre>
 *   custom.static-secret.username=nic
 *   custom.static-secret.password=H@rdT0Gu3ss
 * </pre>
 *
 * <p>This class is registered via {@code @EnableConfigurationProperties} on the
 * main application class so that Spring refreshes it as part of the context
 * refresh cycle triggered by {@code POST /actuator/refresh}.
 */
@ConfigurationProperties(prefix = "custom")
public class AppProperties {

    private StaticSecret staticSecret = new StaticSecret();

    public StaticSecret getStaticSecret() {
        return staticSecret;
    }

    public void setStaticSecret(StaticSecret staticSecret) {
        this.staticSecret = staticSecret;
    }

    public static class StaticSecret {
        private String username;
        private String password;

        public String getUsername() {
            return username;
        }

        public void setUsername(String username) {
            this.username = username;
        }

        public String getPassword() {
            return password;
        }

        public void setPassword(String password) {
            this.password = password;
        }
    }
}
