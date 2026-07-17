---
slug: configure-spring-static
id: t94cyfuzwlll
type: challenge
title: Static Secrets - Configure Spring to import the secrets file
teaser: Update application.properties to import the file rendered by Vault Agent.
notes:
- type: text
  contents: |-
    Vault Agent renders secrets into a `.properties` file on disk.
    Spring Boot's `spring.config.import` feature can import that file at startup
    and merge it with the base `application.properties`.

    This means your application properties stay in two layers:
    - **Base layer** (`application.properties`) — committed to source control, contains
      non-secret config such as datasource URL, application name, and actuator settings.
    - **Secrets layer** (`vault-secrets.properties`) — written at runtime by Vault Agent,
      contains only credentials. Never committed to source control.
tabs:
- id: gatd4ky51iw3
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
- id: rt2s99bix2re
  title: Terminal
  type: terminal
  hostname: sandbox
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Open `spring/payments-app/src/main/resources/application.properties` in the **Code** tab.

The file currently has hardcoded database credentials and only exposes the `health` actuator endpoint.

```properties,nocopy
spring.datasource.username=postgres
spring.datasource.password=postgres
management.endpoints.web.exposure.include=health
```

Remove the hardcoded credentials and import the Vault Agent file
===

1. Remove the hardcoded `spring.datasource.username` and `spring.datasource.password` lines.

2. Add `spring.config.import` to tell Spring Boot where to find the secrets file rendered by Vault Agent.

```properties
spring.config.import=file:/vault/secrets/vault-secrets.properties
```

> [!NOTE]
> There is no `optional:` prefix on this import. If the file does not exist when the application starts,
> Spring Boot will refuse to start with a `ConfigDataLocationNotFoundException`. This is intentional —
> it guarantees Vault Agent has rendered the secrets before the application comes up.

Expose the refresh actuator endpoint
===

3. Change `management.endpoints.web.exposure.include` to expose the `refresh` endpoint in addition to `health`.

```properties
management.endpoints.web.exposure.include=refresh,health
```

Vault Agent calls `POST /actuator/refresh` after every successful render. Without this endpoint
exposed, the live-reload command in `agent.hcl` will fail silently.

<details>
<summary><b>Solution</b></summary>

```properties
spring.application.name=payments-app

spring.config.import=file:/vault/secrets/vault-secrets.properties

management.endpoints.web.exposure.include=refresh,health

spring.datasource.url=jdbc:postgresql://postgres:5432/payments
```
</details>

Next, add `@RefreshScope` to the application beans so they reload when Vault Agent triggers a refresh.
