package com.hashicorp.workshop.paymentsapp;

/**
 * Pretend external client that is initialized with static credentials
 * from Vault's KV v2 secrets engine.
 *
 * <p>In a real application this might be an HTTP client, SDK, or
 * third-party library that must be reconstructed whenever its credentials
 * rotate. Here it simply holds the {@link AppProperties} so the tutorial
 * can demonstrate that the bean is rebuilt with fresh values after
 * {@code POST /actuator/refresh}.
 */
class ExampleClient {
    private final AppProperties properties;

    ExampleClient(AppProperties properties) {
        this.properties = properties;
    }

    public AppProperties getProperties() {
        return properties;
    }
}
