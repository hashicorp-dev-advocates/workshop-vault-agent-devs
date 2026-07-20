---
slug: dynamic-secrets-inject
id: 7odwo6jz69eh
type: challenge
title: Dynamic Secrets - Add @RefreshScope to reload the DataSource
teaser: Annotate the DataSource bean so it reconnects with fresh credentials when
  the lease rotates.
notes:
- type: text
  contents: |-
    When Vault Agent re-renders `vault-secrets.properties` with a new database
    username and password and calls `POST /actuator/refresh`, Spring must tear down
    the old connection pool and build a new one with the fresh credentials.

    This only happens if the `DataSource` bean is annotated with `@RefreshScope`.
    Without it, the application keeps using the original credentials until they
    expire — at which point every database query will fail.
tabs:
- id: jmr6pyfmo507
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
- id: dfing64x1m01
  title: Terminal
  type: terminal
  hostname: sandbox
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Open `spring/payments-app/src/main/java/com/hashicorp/workshop/paymentsapp/PaymentsAppApplication.java`
in the **Code** tab.

The `dataSource` bean is currently defined without `@RefreshScope`:

```java,nocopy
@Bean
DataSource dataSource(DataSourceProperties properties) {
    log.info("rebuild DataSource with username: " + properties.getUsername());
    return DataSourceBuilder
            .create()
            .url(properties.getUrl())
            .username(properties.getUsername())
            .password(properties.getPassword())
            .build();
}
```

Add @RefreshScope to the DataSource bean
===

Add the `@RefreshScope` annotation to the `dataSource` bean method. If the `RefreshScope`
import is not already present, add it:

```java
import org.springframework.cloud.context.config.annotation.RefreshScope;
```

When Vault Agent re-renders the secrets file with new database credentials and calls
`POST /actuator/refresh`, Spring will:

1. Destroy the old `DataSource` bean (closing the connection pool)
2. Recreate it with the new `spring.datasource.username` and `spring.datasource.password`
3. The application immediately reconnects to the database with the fresh credentials

<details>
<summary><b>Solution</b></summary>

```java
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
```
</details>

Next, start the full stack and observe the application automatically reconnect when credentials rotate.
