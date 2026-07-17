---
slug: add-static-secret
id: 4fbnlh1pnveo
type: challenge
title: Static Secrets - Add a secret to Vault
teaser: Store a secret in Vault's key-value secrets engine.
notes:
- type: text
  contents: |-
    A secret is simply a collection of keys and values that are stored at a specific path.

    Vault has a number of secrets engines, which you mount at various API paths to store
    and manage secrets.  You can write and read a secret from Vault.

    For secrets that you manage manually, you can write them to the key-value secrets engine.
tabs:
- id: xm9gla4lal8u
  title: Terminal
  type: terminal
  hostname: sandbox
- id: xfdwmofj9pxo
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

You can write any arbitrary set of keys and values into a secret managed by Vault's key-value secrets engine.

You can find the details in this documentation: https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2#writing-reading-arbitrary-data

Add a static secret with username and password
===

Create a secret at the path `spring/kv/payments-app` with two keys and values.

1. A username, `custom.static-secret.username=nic`
1. A password, `custom.static-secret.password=H@rdT0Gu3ss`

The keys use dot-notation matching Spring application property names. Vault Agent will render
them directly into a `.properties` file that Spring Boot can import.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault kv put spring/kv/payments-app \
  "custom.static-secret.username=nic" \
  "custom.static-secret.password=H@rdT0Gu3ss"
```
</details>

<details>
<summary><b>Verify</b></summary>
After adding the secret, verify that you can read the secret using the following:

```shell
vault kv get spring/kv/payments-app
```
</details>

Next, configure Vault Agent to read the secret and render it into a properties file.
