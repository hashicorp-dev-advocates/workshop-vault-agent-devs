---
slug: configure-vault-agent
id: p81sptnusjqf
type: challenge
title: Static Secrets - Configure Vault Agent
teaser: Author the Vault Agent configuration to authenticate to Vault and render secrets
  into a file.
notes:
- type: text
  contents: |-
    [Vault Agent](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent) is a client-side daemon that runs alongside your application.
    Instead of your application calling Vault's API directly, Vault Agent does it on your behalf.

    Vault Agent:
    1. Authenticates to Vault using a configured auth method.
    2. Fetches secrets and renders them into a file using Consul Template syntax.
    3. Calls a command after each successful render — in this workshop, that command
       triggers Spring Boot's live-reload endpoint so secrets update without a restart.

    Your application reads a plain `.properties` file. It has no Vault dependency at all.
tabs:
- id: d7fuwxvqfu9w
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
- id: l4nek0wdjkaa
  title: Terminal
  type: terminal
  hostname: sandbox
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Vault Agent is configured through two files:

- `spring/vault/agent.hcl` — tells the agent how to authenticate and what to render
- `spring/vault/secrets.ctmpl` — a Consul Template file that defines the rendered output

Open both files in the **Code** tab. The skeleton is already in place.

Configure the template rendering interval
===

Open `spring/vault/agent.hcl` in the **Code** tab.

Add a `template_config` block to set how often Vault Agent re-renders static secrets.
The `static_secret_render_interval` controls the polling interval for KV secrets,
which do not have a Vault-managed lease.

```hcl
template_config {
  static_secret_render_interval = "1m"
}
```

Configure the template block
===

Add a `template` block that tells Vault Agent where to read the template from,
where to write the rendered output, and what command to run after a successful render.

```hcl
template {
  source               = "/spring/vault/secrets.ctmpl"
  destination          = "/secrets/vault-secrets.properties"
  error_on_missing_key = true
  command = "wget -q --header='Content-Type: application/json' --post-data='{}' http://payments-app:8080/actuator/refresh -O /dev/null || true"
}
```

- `source` — the Consul Template file Vault Agent will render
- `destination` — the output file Spring Boot will import
- `error_on_missing_key` — fails loudly if a secret key is missing, preventing silent partial renders
- `command` — called after every successful render; triggers Spring Boot's `/actuator/refresh`
  so `@RefreshScope` beans are re-bound with fresh credentials without a container restart

<details>
<summary><b>Solution</b></summary>

```hcl
vault {
  address = "http://vault:8200"
}

template_config {
  static_secret_render_interval = "1m"
}

auto_auth {
  method "token_file" {
    config {
      token_file_path = "/secrets/vault-token"
    }
  }
}

template {
  source               = "/spring/vault/secrets.ctmpl"
  destination          = "/secrets/vault-secrets.properties"
  error_on_missing_key = true
  command = "wget -q --header='Content-Type: application/json' --post-data='{}' http://payments-app:8080/actuator/refresh -O /dev/null || true"
}
```
</details>

Write the Consul Template for static secrets
===

Open `spring/vault/secrets.ctmpl` in the **Code** tab.

The template already reads static credentials from the KV v2 engine.
Review the syntax — `.Data.data` is required because KV v2 wraps values under a nested `data` key.

```hcl
{{ with secret "spring/kv/data/payments-app" -}}
custom.static-secret.username={{ index .Data.data "custom.static-secret.username" }}
custom.static-secret.password={{ index .Data.data "custom.static-secret.password" }}
{{ end -}}
```

This renders into a `.properties` file Spring Boot can import directly.
No code changes to the application are needed for the template itself.

Next, configure the Spring Boot application to import the rendered file.
