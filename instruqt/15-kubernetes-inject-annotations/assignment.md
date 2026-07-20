---
slug: kubernetes-inject-annotations
id: pnxxkphztgrq
type: challenge
title: Kubernetes - Add the live-reload annotation
teaser: Add the agent-inject-command annotation so Vault Agent triggers Spring Boot
  to reload secrets.
notes:
- type: text
  contents: |
    The Vault Agent Injector configures the sidecar entirely through Pod annotations.
    Most annotations tell the injector *what* to render and *where* to put the file.

    One annotation closes the live-reload loop: `agent-inject-command`. Without it,
    Vault Agent renders the secrets file and renews leases — but the Spring Boot
    application is never notified that new credentials are available. It keeps using
    the original credentials until the lease expires and queries start failing.

    Adding the command annotation tells Vault Agent to call `POST /actuator/refresh`
    after every successful render, triggering Spring Cloud Context to rebuild all
    `@RefreshScope` beans with the new property values.

    For more on pod annotations, review the [Vault Agent Injector documentation](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector/annotations).
tabs:
- id: lzdtg5o0xyyv
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
- id: ne4w0q6x0jjd
  title: Terminal
  type: terminal
  hostname: sandbox
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Open `spring/kubernetes/deployment.yaml` in the **Code** tab.

The deployment already has the Vault Agent Injector annotations that:

- Enable injection (`agent-inject: "true"`)
- Set the Vault address and role
- Define what secrets to render and the Consul Template body
- Revoke credentials on Pod shutdown

Review the annotations already present
===

```yaml,nocopy
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/vault-addr: "http://10.5.0.2:8200"
vault.hashicorp.com/role: "payments-app"
vault.hashicorp.com/template-static-secret-render-interval: "1m"
vault.hashicorp.com/agent-inject-secret-vault-secrets.properties: "spring/kv/data/payments-app"
vault.hashicorp.com/agent-inject-template-vault-secrets.properties: |
  {{- with secret "spring/kv/data/payments-app" }}
  ...
  {{- end }}
vault.hashicorp.com/agent-revoke-on-shutdown: "true"
```

The missing annotation — add the refresh command
===

Without the `agent-inject-command` annotation, Vault Agent renders fresh credentials into
`/vault/secrets/vault-secrets.properties` but never tells the Spring Boot application to reload them.
The application continues using stale credentials until the lease expires and database queries fail.

Add the following annotation to the `annotations:` block in `deployment.yaml`:

```yaml
vault.hashicorp.com/agent-inject-command-vault-secrets.properties: >-
  wget -q --header="Content-Type: application/json" --post-data="{}" http://127.0.0.1:8080/actuator/refresh -O /dev/null || true
```

- The annotation name suffix (`-vault-secrets.properties`) must match the secret file name
- `wget` is used because `curl` is not in the Vault Agent container image
- `|| true` prevents a failed refresh from blocking the next re-render

<details>
<summary><b>Solution</b></summary>

Add the annotation to the `annotations:` block in `spring/kubernetes/deployment.yaml`:

```yaml
vault.hashicorp.com/agent-inject-command-vault-secrets.properties: >-
  wget -q --header="Content-Type: application/json" --post-data="{}" http://127.0.0.1:8080/actuator/refresh -O /dev/null || true
```
</details>

Next, deploy the application and verify it receives Vault-injected credentials.
