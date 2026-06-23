package com.hashicorp.workshop.paymentsapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.cloud.context.config.annotation.RefreshScope;

/**
 * Binds the static credentials stored in Vault's KV v2 secrets engine
 * (path: {@code spring/kv/data/payments-app}) to typed Java properties.
 *
 * <p>Vault Agent renders these into the imported secrets file as:
 * <pre>
 *   custom.static-secret.username=nic
 *   custom.static-secret.password=H@rdT0Gu3ss
 * </pre>
 *
 * <p>Spring {@code @ConfigurationProperties} requires kebab-case prefixes.
 * The property keys in the secrets file use the same kebab-case convention.
 *
 * <p>{@code @RefreshScope} ensures that when Vault Agent calls
 * {@code POST /actuator/refresh} after a secret rotation, Spring destroys
 * and recreates this bean with the latest values from the refreshed
 * {@link org.springframework.core.env.Environment}.
 */
@RefreshScope
@ConfigurationProperties(prefix = "custom.static-secret")
public class StaticSecretConfig {

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
