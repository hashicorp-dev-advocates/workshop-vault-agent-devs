---
slug: add-database-configuration
id: nnttyhcupqmq
type: challenge
title: Dynamic Secrets - Add database configuration
teaser: Configure Vault's database secrets engine to connect to PostgreSQL.
notes:
- type: text
  contents: |-
    Unlike static secrets, dynamic secrets require Vault to connect directly to
    the target system so it can create and revoke credentials on your behalf.

    The database secrets engine needs a root connection to PostgreSQL — not for
    the application to use, but for Vault itself to manage credentials.
tabs:
- id: cfajdqfnbgix
  title: Terminal
  type: terminal
  hostname: sandbox
- id: vxb3pletflzq
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

The database secrets engine requires connection information to PostgreSQL so it can
create and revoke dynamic credentials on demand.

The connection URL uses Vault template placeholders for the root credentials:

```
postgresql://{{username}}:{{password}}@hostname:port/database?sslmode=disable
```

> [!NOTE]
> The `{{username}}` and `{{password}}` placeholders are Vault syntax — they are
> substituted with the root credentials at runtime and never exposed to applications.

Configure the database connection
===

Configure the database secrets engine with a connection to the PostgreSQL database
at `10.5.0.3:5432`. Use the `postgresql-database-plugin`, allow roles `writer` and `reader`,
and set the root username and password to `postgres`.

You can find more details at: https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault write database/config/payments-app \
  plugin_name="postgresql-database-plugin" \
  connection_url="postgresql://{{username}}:{{password}}@10.5.0.3:5432/payments?sslmode=disable" \
  allowed_roles="writer,reader" \
  username="postgres" \
  password="postgres"
```
</details>

<details>
<summary><b>Verify</b></summary>
After configuring the database, verify using the following:

```shell
vault read database/config/payments-app
```
</details>

Now configure roles that grant specific permissions for writing and reading from the database.
