---
slug: enable-database-secrets-engine
id: 6gqw5qnjbjay
type: challenge
title: Dynamic Secrets - Enable Vault's database secrets engine
teaser: Mount Vault's database secrets engine to generate short-lived PostgreSQL credentials.
notes:
- type: text
  contents: |
    In this section of the workshop, you will learn how to use Vault Agent to
    deliver dynamic database credentials to your Spring Boot application.

    In this section, you will:

    1. Enable Vault's database secrets engine.
    2. Add a database configuration for Vault to generate usernames and passwords on demand.
    3. Create Vault roles that define permissions and TTLs for the generated credentials.
    4. Extend the Consul Template to render dynamic credentials into the properties file.
    5. Add `@RefreshScope` to the `DataSource` bean so it reconnects with fresh credentials.
- type: text
  contents: |
    HashiCorp Vault stores and manages your secrets. It can handle two main types of secrets:

    1. Static secrets - you manually write them into Vault as keys and values and handle their rotation.
    2. Dynamic secrets - Vault automatically generates a secret with an expiration date. When the secret expires, Vault deletes it.

    With dynamic secrets, Vault creates a unique username and password for each request.
    When the lease expires, Vault automatically revokes the credentials from the database —
    so stale credentials cannot accumulate even if a client crashes.
tabs:
- id: xi3yr6v3ymn1
  title: Terminal
  type: terminal
  hostname: sandbox
- id: mfyd4xw5sxjy
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Dynamic secrets expire after a certain period of time. Vault deletes the credential on
your behalf. The [database secrets engine](https://developer.hashicorp.com/vault/docs/secrets/databases) generates dynamic credentials (username and password)
for a variety of databases including PostgreSQL, MySQL, and MongoDB.

Enable the database secrets engine
===

Enable the database secrets engine at the path `database` in Vault.
You must mount secrets engines before Vault can issue secrets on your behalf.

You can find the details in this documentation: https://developer.hashicorp.com/vault/docs/secrets/databases.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault secrets enable database
```
</details>

<details>
<summary><b>Verify</b></summary>
After mounting the secrets engine, verify that you've created the secrets engine using the following:

```shell
vault secrets list
```
</details>

After you've mounted the database secrets engine, configure it to connect to the PostgreSQL database.
