package com.hashicorp.workshop.paymentsapp.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;

/**
 * Constructs a HikariCP {@link DataSource} from properties rendered by Vault Agent.
 *
 * <p>Vault Agent writes dynamic PostgreSQL credentials to the secrets file as:
 * <pre>
 *   spring.datasource.username=v-token-payments-xxxx
 *   spring.datasource.password=A1B2-xxxx
 *   spring.datasource.url=jdbc:postgresql://postgres:5432/payments
 * </pre>
 *
 * <p>Because this bean is annotated with {@code @RefreshScope}, Spring will
 * destroy and recreate it — closing the old connection pool and opening a new
 * one with the refreshed credentials — each time {@code POST /actuator/refresh}
 * is called. This is the core of the live-reload pattern: no restart required.
 *
 * <p><strong>Note:</strong> HikariCP is Spring Boot's default connection pool.
 * The explicit bean definition here (rather than relying on auto-configuration)
 * is necessary so that {@code @RefreshScope} can control the bean lifecycle.
 */
@Configuration
public class DataSourceConfig {

    @Bean
    @RefreshScope
    public DataSource dataSource(
            @Value("${spring.datasource.url}") String url,
            @Value("${spring.datasource.username}") String username,
            @Value("${spring.datasource.password}") String password) {

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
}
