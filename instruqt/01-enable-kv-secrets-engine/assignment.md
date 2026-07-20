---
slug: enable-kv-secrets-engine
id: xq6zzp0pyiea
type: challenge
title: Static Secrets - Enable Vault's key-value secrets engine
teaser: Mount Vault's key-value secrets engine to store static secrets.
notes:
- type: text
  contents: |
    In this section of the workshop, you will learn how to use Vault Agent to
    inject static secrets into your Spring Boot application — without any Vault SDK.

    In this first section, you will:

    1. Enable Vault's key-value secrets engine.
    2. Add a static secret (username and password) to Vault.
    3. Configure Vault Agent to render the secret into a properties file.
    4. Configure Spring Boot to import the rendered file.
    5. Update the application to refresh and inject the static secret.
- type: text
  contents: |
    HashiCorp Vault stores and manages your secrets. It can handle two main types of secrets:

    1. Static secrets - you manually write them into Vault as keys and values and handle their rotation.
    2. Dynamic secrets - Vault automatically generates a secret with an expiration date. When the secret expires, Vault deletes it.

    Besides storing secrets, Vault supports different methods of authentication.

    1. User authentication - Once Vault verifies your identity, it provides a token for future requests.
    1. Machine authentication - Once Vault verifies a service or machine identity, it provides a token for future requests.
tabs:
- id: qzeuvymabeea
  title: Terminal
  type: terminal
  hostname: sandbox
- id: d6o6wdv3y1cu
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

You manually manage a static secret by getting a set of credentials from a third-party service
and storing it in Vault. Vault supports static secrets using the key-value secrets engine.
If you need to rotate the secret, you must get a new set of credentials from the third-party service
and update Vault with a new version of the secret.

This guide will walk you through setting up the key-value secrets engine and
storing a secret in Vault for an application to use.

Enable the key-value secrets engine
===

Enable the key-value version 2 secrets engine at the path `spring/kv` in Vault.
You must mount secrets engines before you can add secrets.

You can find the details in this documentation: https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/setup.

> [!NOTE]
> You need to enable the engine at the path `spring/kv`. This requires defining the path with `-path=spring/kv`.
> You also need to use key-value version 2, which supports versioning and metadata.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault secrets enable -path=spring/kv -version=2 kv
```
</details>

<details>
<summary><b>Verify</b></summary>
After mounting the secrets engine, verify that you've created the secrets engine using the following:

```shell
vault secrets list
```
</details>

After you've mounted the key-value secrets engine, let's create a secret for the application to use.
