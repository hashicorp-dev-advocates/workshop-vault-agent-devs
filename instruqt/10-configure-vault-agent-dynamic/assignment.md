---
slug: configure-vault-agent-dynamic
id: adltphxffu54
type: challenge
title: Dynamic Secrets - Extend Vault Agent template for database credentials
teaser: Add the database/creds/writer block to secrets.ctmpl so Vault Agent renders
  dynamic credentials.
notes:
- type: text
  contents: |-
    The Consul Template in `secrets.ctmpl` currently only renders static KV secrets.
    To deliver dynamic database credentials, you need to add a second block that
    calls the database secrets engine.

    Vault Agent will request a fresh set of credentials from the `database/creds/writer`
    path, write them into the properties file, and re-render automatically before
    the lease expires. Each render triggers `POST /actuator/refresh` so the application
    reconnects to the database with the new credentials — without a restart.
tabs:
- id: gyvyksxbqaax
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
- id: fnnqbxnxkjro
  title: Terminal
  type: terminal
  hostname: sandbox
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Open `spring/vault/secrets.ctmpl` in the **Code** tab.

The template currently renders only the static KV secret:

```hcl,nocopy
{{ with secret "spring/kv/data/payments-app" -}}
custom.static-secret.username={{ index .Data.data "custom.static-secret.username" }}
custom.static-secret.password={{ index .Data.data "custom.static-secret.password" }}
{{ end -}}
```

Add the dynamic database credentials block
===

Append a second `{{ with secret }}` block to request credentials from the `database/creds/writer`
path and render them as `spring.datasource.username` and `spring.datasource.password`.

```hcl
{{ with secret "database/creds/writer" -}}
spring.datasource.username={{ .Data.username }}
spring.datasource.password={{ .Data.password }}
{{ end -}}
```

- `.Data.username` and `.Data.password` are the Vault-generated credentials for the `writer` role
- Unlike KV v2, database credentials are at the top level of `.Data` — no nested `data` key
- Vault Agent holds the lease and re-renders before it expires, replacing the credentials in the file

<details>
<summary><b>Solution</b></summary>

The complete `secrets.ctmpl`:

```hcl
{{- /* spring/vault/secrets.ctmpl */ -}}

{{ with secret "spring/kv/data/payments-app" -}}
custom.static-secret.username={{ index .Data.data "custom.static-secret.username" }}
custom.static-secret.password={{ index .Data.data "custom.static-secret.password" }}
{{ end -}}

{{ with secret "database/creds/writer" -}}
spring.datasource.username={{ .Data.username }}
spring.datasource.password={{ .Data.password }}
{{ end -}}
```
</details>

Next, add `@RefreshScope` to the `DataSource` bean so it reconnects when the credentials rotate.
