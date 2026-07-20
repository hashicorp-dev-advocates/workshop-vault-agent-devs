---
slug: create-database-roles
id: 9l1byqbc0krz
type: challenge
title: Dynamic Secrets - Create Vault roles to access database
teaser: Define writer and reader roles that control the permissions and TTL of generated
  credentials.
notes:
- type: text
  contents: |-
    A Vault role defines what SQL is run when credentials are generated, and how long
    those credentials live. When Vault Agent requests credentials, it uses a specific role —
    the role determines what the database user is allowed to do.

    Short TTLs force frequent rotation. Vault Agent handles this automatically:
    it renews leases, re-renders the template with fresh credentials, and triggers
    `POST /actuator/refresh` so the application reconnects without a restart.
tabs:
- id: dpihlax48h9p
  title: Terminal
  type: terminal
  hostname: sandbox
- id: tn0kkehqk4xi
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Create a Vault role to write to the database
===

Create a `writer` role for the application to insert and update records in the `payments` table.
Set a short TTL of 1 minute default and 2 minute maximum — this forces frequent rotation
and demonstrates live credential refresh.

> [!NOTE]
> This TTL is intentionally short for workshop purposes. Production TTLs should be longer.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault write database/roles/writer \
  db_name="payments-app" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE payments TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.payments TO \"{{name}}\";
    GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO \"{{name}}\";
  " \
  default_ttl="1m" \
  max_ttl="2m"
```
</details>

<details>
<summary><b>Verify</b></summary>
Verify by generating credentials with the writer role:

```shell
vault read database/creds/writer
```

```shell,nocopy
Key                Value
---                -----
lease_id           database/creds/writer/x9fpwRltEqD4Gq45HZgPtU1i
lease_duration     1m
lease_renewable    true
password           H-K3EPsHkXX0TAw1tHB2
username           v-token-writer-SKafQcVrz91Lu3BDxeGi-1736435705
```
</details>

Create a Vault role to read from the database
===

Create a `reader` role for read-only access to the `payments` table.
Set a longer TTL of 1 hour default and 24 hour maximum — suitable for humans
querying the database to debug issues.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault write database/roles/reader \
  db_name="payments-app" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE payments TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT ON TABLE public.payments TO \"{{name}}\";
    GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"
```
</details>

<details>
<summary><b>Verify</b></summary>
Verify by generating credentials with the reader role and querying the database:

```shell
vault read database/creds/reader
```

```shell,nocopy
Key                Value
---                -----
lease_id           database/creds/reader/SbwFzRsPeB3IcSi8ecyrMgjk
lease_duration     1h
lease_renewable    true
password           YYkQlEhlaYg9oZ9p-pl6
username           v-token-reader-vGcR3xsXCrCLPC5ALo33-1736436171
```

Copy the username and password to query the `payments` table directly:

```shell
PGPASSWORD=<password> psql -h 10.5.0.3 -U <username> payments --command 'select * from payments;'
```
</details>

Next, extend the Consul Template to render database credentials into the properties file.
