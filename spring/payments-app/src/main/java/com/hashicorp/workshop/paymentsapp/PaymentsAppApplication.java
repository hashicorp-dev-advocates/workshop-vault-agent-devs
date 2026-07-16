package com.hashicorp.workshop.paymentsapp;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
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
// Exclude DataSource auto-configuration so our @RefreshScope DataSource
// bean is the sole DataSource definition — prevents a conflicting bean error.
@SpringBootApplication(exclude = {DataSourceAutoConfiguration.class})
@EnableConfigurationProperties(AppProperties.class)
public class PaymentsAppApplication {

    private final Log log = LogFactory.getLog(getClass());

    public static void main(String[] args) {
        SpringApplication.run(PaymentsAppApplication.class, args);
    }

    /**
     * Constructs a HikariCP {@link DataSource} from dynamic PostgreSQL credentials
     * rendered by Vault Agent. Annotated with {@code @RefreshScope} so that Spring
     * destroys and recreates this bean — closing the old connection pool and opening
     * a new one — each time {@code POST /actuator/refresh} is called.
     */
    @Bean
    @RefreshScope
    DataSource dataSource(
            @Value("${spring.datasource.url}") String url,
            @Value("${spring.datasource.username}") String username,
            @Value("${spring.datasource.password}") String password) {
        log.info("rebuild DataSource with username: " + username);

        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(url);
        config.setUsername(username);
        config.setPassword(password);
        // Keep the pool small for the tutorial environment.
        config.setMaximumPoolSize(5);
        config.setMinimumIdle(1);
        config.setConnectionTimeout(10_000);
        config.setIdleTimeout(60_000);
        return new HikariDataSource(config);
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
