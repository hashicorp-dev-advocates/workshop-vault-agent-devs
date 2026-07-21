---
slug: dynamic-secrets-test
id: p0dtsz6n6oyx
type: challenge
title: Dynamic Secrets - Test application with Vault Agent
teaser: Start the full stack and observe automatic credential rotation without a restart.
notes:
- type: text
  contents: For more resources on using Vault Agent to inject secrets into applications,
    check out [Vault Agent documentation](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent).
tabs:
- id: xfd9dizuscit
  title: Terminal
  type: terminal
  hostname: sandbox
- id: tc4fbseyo7sw
  title: API Request
  type: terminal
  hostname: sandbox
- id: urpqdzfvtp74
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Your application will do the following when it runs:

1. Vault Agent authenticates to Vault and renders both static and dynamic credentials
1. Spring Boot imports the rendered file — `spring.datasource.*` credentials come from Vault
1. When the database lease approaches expiry, Vault Agent re-renders with fresh credentials
1. Vault Agent calls `POST /actuator/refresh` — Spring tears down the old connection pool and reconnects

Start Vault Agent
===

In the **Terminal** tab, start Vault Agent.

```shell
cd /root/workshop-vault-agent-devs
docker-compose up vault-agent
```

You should see Vault Agent authenticate, request database credentials from the `writer` role,
and render the secrets file.

Run the application
===

In the **API Request** tab, start the Spring Boot application.

```shell
cd /root/workshop-vault-agent-devs/spring/payments-app
mvn spring-boot:run
```

When the application starts you will see both beans initialise with Vault-issued credentials:

```shell,nocopy
rebuild DataSource with username: v-token-writer-AbCdEfGh-1736449174
rebuild ExampleClient with static-secret username: nic
```

Test the application
===

In the **API Request** tab, make a request to list payments.

```shell
curl localhost:8080/payments
```

```shell,nocopy
[{"id":1,"reference":"REF001","amount":100.00,"currency":"USD","status":"PENDING","created_at":"..."}]
```

Make a request to create a new payment.

```shell
curl -s localhost:8080/payments \
  -H "content-type: application/json" \
  -d '{"reference":"REF999","amount":42.00,"currency":"USD","status":"PENDING"}'
```

Observe credential rotation
===

The `writer` role has a 1-minute TTL. After about one minute, watch the **Terminal** tab.
Vault Agent will log a re-render and call `/actuator/refresh`:

```shell,nocopy
vault-agent  | [INFO] (runner) rendered "(dynamic)" -> "/secrets/vault-secrets.properties"
```

The application log will show the `DataSource` being rebuilt:

```shell,nocopy
rebuild DataSource with username: v-token-writer-XyZaBcDe-1736449274
```

Make a second request in the **API Request** tab to confirm the application keeps serving
requests seamlessly with the new credentials.

```shell
curl localhost:8080/payments
```

Summary
===

In this section, you learned how to:

1. Enable Vault's database secrets engine.
2. Configure a database connection and create `writer` / `reader` roles.
3. Extend the Consul Template to render dynamic database credentials.
4. Add `@RefreshScope` to the `DataSource` bean to reconnect on credential rotation.
