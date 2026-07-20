---
slug: static-secrets-inject
id: 5v8isniood5z
type: challenge
title: Static Secrets - Add @RefreshScope to reload the secret
teaser: Annotate the ExampleClient bean so it reloads when Vault Agent triggers a
  refresh.
notes:
- type: text
  contents: |-
    When Vault Agent re-renders the secrets file, it calls `POST /actuator/refresh`.
    Spring Cloud Context receives that request and destroys any bean annotated with
    `@RefreshScope`, then recreates it with the new property values on the next access.

    Without `@RefreshScope`, the bean is created once at startup and never updated —
    even if the underlying properties file changes. The application would continue using
    stale credentials until it restarts.
tabs:
- id: to5ktzq6sls8
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
- id: hvwo40xahhho
  title: Terminal
  type: terminal
  hostname: sandbox
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Open `spring/payments-app/src/main/java/com/hashicorp/workshop/paymentsapp/PaymentsAppApplication.java`
in the **Code** tab.

The `exampleClient` bean is defined without `@RefreshScope`:

```java,nocopy
@Bean
ExampleClient exampleClient(AppProperties properties) {
    log.info("rebuild ExampleClient with static-secret username: "
            + properties.getStaticSecret().getUsername());
    return new ExampleClient(properties);
}
```

Add @RefreshScope to the ExampleClient bean
===

Add the `@RefreshScope` annotation to the `exampleClient` bean method, and add the
`import org.springframework.cloud.context.config.annotation.RefreshScope;` import at the top of the file.

When Vault Agent re-renders `vault-secrets.properties` with a rotated KV secret and calls
`POST /actuator/refresh`, Spring will destroy the old `ExampleClient` and create a new one
with the updated `custom.static-secret.*` property values.

<details>
<summary><b>Solution</b></summary>

```java
import org.springframework.cloud.context.config.annotation.RefreshScope;

// omitted for clarity

@Bean
@RefreshScope
ExampleClient exampleClient(AppProperties properties) {
    log.info("rebuild ExampleClient with static-secret username: "
            + properties.getStaticSecret().getUsername());
    return new ExampleClient(properties);
}
```
</details>

Next, start Vault Agent and the application to test the full live-reload flow.
