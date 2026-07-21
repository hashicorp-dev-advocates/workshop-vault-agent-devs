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
- id: hbinlrbtmwqg
  title: Maven
  type: terminal
  hostname: sandbox
  workdir: /root/workshop-vault-agent-devs/spring/payments-app
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

In the **Terminal** tab, start Vault Agent directly using the vault CLI.

```shell
cd /root/workshop-vault-agent-devs
vault agent -config=spring/vault/agent.hcl
```

You should see Vault Agent authenticate, request database credentials from the `writer` role,
and render the secrets file.

Run the application
===

In the **Maven** tab, start the Spring Boot application.

```shell
cd /root/workshop-vault-agent-devs/spring/payments-app
SPRING_CONFIG_IMPORT="file:/root/workshop-vault-agent-devs/secrets/vault-secrets.properties" mvn spring-boot:run
```

When the application starts you will see both beans initialize with Vault-issued credentials:

```shell,nocopy
rebuild database secrets: v-token-pa-writer-mgt7yCDuG5IEmmqwLEwW-1784663884,-keoae6IfwKHLHQ2fzgw
rebuild ExampleClient with static-secret username: nic
```

Test the application
===

In the **API Request** tab, make a request to create a new payment.

```shell
curl -s localhost:8080/payments \
  -H "content-type: application/json" \
  -d '{"reference":"REF999","amount":42.00,"currency":"USD","status":"PENDING"}'
```

List the payments.

```shell
curl localhost:8080/payments
```

It should return the previously created payment.

```shell,nocopy
[{"id":1,"reference":"REF001","amount":100.00,"currency":"USD","status":"PENDING","created_at":"..."}]
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
HikariPool-1 - Starting...
HikariPool-1 - Added connection org.postgresql.jdbc.PgConnection@7e053201
HikariPool-1 - Start completed.
HikariPool-1 - Shutdown initiated...
HikariPool-1 - Shutdown completed.
Refreshed keys : [spring.datasource.username, spring.datasource.password]
rebuild database secrets: v-token-pa-writer-Yxij3FDse9iC4PPpSvD2-1784663994,CEfXwG-ol4IdLObeG3Yy
HikariPool-2 - Starting...
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
