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
		log.info("rebuild database secrets: " +
				properties.getUsername() +
				"," +
				properties.getPassword()
		);

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
