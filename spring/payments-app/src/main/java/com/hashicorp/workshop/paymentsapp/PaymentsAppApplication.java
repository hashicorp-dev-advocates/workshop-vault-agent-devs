package com.hashicorp.workshop.paymentsapp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

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
 */
// Exclude DataSource auto-configuration so our @RefreshScope DataSourceConfig
// bean is the sole DataSource definition — prevents a conflicting bean error.
@SpringBootApplication(exclude = {DataSourceAutoConfiguration.class})
@ConfigurationPropertiesScan
public class PaymentsAppApplication {

    public static void main(String[] args) {
        SpringApplication.run(PaymentsAppApplication.class, args);
    }
}
