---
slug: static-secrets-test
id: casyw3i0jmgu
type: challenge
title: Static Secrets - Test application with Vault Agent
teaser: Start Vault Agent and the application, then test live secret reload.
notes:
- type: text
  contents: For more resources on using Vault Agent to inject secrets into applications,
    check out the [Vault Agent documentation](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent).
tabs:
- id: tmnosluxyr8b
  title: Terminal
  type: terminal
  hostname: sandbox
- id: hbinlrbtmwqg
  title: Maven
  type: terminal
  hostname: sandbox
  workdir: /root/workshop-vault-agent-devs/spring/payments-app
- id: gtyglrrrdgno
  title: API Request
  type: terminal
  hostname: sandbox
- id: e5yxjpnbfvsp
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Your application will do the following when it runs:

1. Vault Agent authenticates to Vault using the token written to `secrets/vault-token`
1. Vault Agent renders `spring/vault/secrets.ctmpl` → `secrets/vault-secrets.properties`
1. Spring Boot imports the rendered file via `spring.config.import`
1. When Vault Agent re-renders after a secret rotation, it calls `POST /actuator/refresh`
1. Spring destroys and recreates all `@RefreshScope` beans with the new property values

Start Vault Agent
===

In the **Terminal** tab, start Vault Agent using Docker Compose.
Vault Agent will authenticate, render the secrets file, and then watch for changes.

```shell
cd /root/workshop-vault-agent-devs
K3S_TOKEN=$(cat ./tmp/k3s.token) docker-compose up vault-agent
```

You should see Vault Agent render the secrets file and log something like:

```shell,nocopy
agent: (runner) rendered "/spring/vault/secrets.ctmpl" => "/secrets/vault-secrets.properties"
agent: (runner) executing command "[\"wget -q --header='Content-Type: application/json' --post-data='{}' http://payments-app:8080/actuator/refresh -O /dev/null || true\"]" from "/spring/vault/secrets.ctmpl" => "/secrets/vault-secrets.properties"
```

Run the application
===

In the **Maven** tab, start the Spring Boot application with Maven.
The application imports the rendered secrets file on startup.

```shell
cd /root/workshop-vault-agent-devs/spring/payments-app
SPRING_CONFIG_IMPORT="file:/root/workshop-vault-agent-devs/secrets/vault-secrets.properties" mvn spring-boot:run
```

When the application starts you will see it load the static secret:

```shell,nocopy
rebuild ExampleClient with static-secret username: nic
```

Test the application
===

In the **API Request** tab, make a request to get the static secret.

```shell
curl localhost:8080/payments/secret
```

The request returns the username and password from Vault.

```shell,nocopy
{"username":"nic","password":"H@rdT0Gu3ss"}
```

Rotate the secret and verify live reload
===

In the **API Request** tab, update the password in Vault.

```shell
vault kv put spring/kv/payments-app \
  "custom.static-secret.username=nic" \
  "custom.static-secret.password=Sec0ndVersion"
```

Within one minute, Vault Agent detects the change, re-renders the secrets file, and calls
`POST /actuator/refresh`. Watch the application log in the **Terminal** tab — you will see:

```shell,nocopy
rebuild ExampleClient with static-secret username: nic
```

Make a second request in the **API Request** tab to confirm the new password is live.

```shell
curl localhost:8080/payments/secret
```

```shell,nocopy
{"username":"nic","password":"Sec0ndVersion"}
```

Summary
===

In this section, you learned how to:

1. Enable Vault's key-value secrets engine.
2. Add a static secret to Vault.
3. Configure Vault Agent to render the secret into a properties file.
4. Configure Spring Boot to import the rendered file.
5. Add `@RefreshScope` to reload beans when the secret rotates.
