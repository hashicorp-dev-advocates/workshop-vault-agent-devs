---
slug: kubernetes-control-access
id: telxx0cohmpn
type: challenge
title: Kubernetes - Configure workload access to Vault
teaser: Write a Vault policy and role that grants the payments-app service account
  access to secrets.
notes:
- type: text
  contents: |
    Vault uses policies to define what paths a token can access and what operations
    it can perform. A Kubernetes auth role links a policy to a specific service account
    in a specific namespace.

    When the Vault Agent Injector injects a sidecar into a Pod, the injected agent
    authenticates using the Pod's service account JWT and receives a token scoped
    to the policy attached to that role.
tabs:
- id: rb0ty6vegzca
  title: Terminal
  type: terminal
  hostname: sandbox
- id: n2sygooguwem
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Add a policy to Vault
===

Create a policy named `payments-app` that grants read access to the KV static secrets
and the dynamic database credentials.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault policy write payments-app - <<EOF
path "spring/kv/data/payments-app" {
  capabilities = ["read"]
}

path "spring/kv/metadata/payments-app" {
  capabilities = ["read"]
}

path "database/creds/writer" {
  capabilities = ["read"]
}

path "database/creds/reader" {
  capabilities = ["read"]
}
EOF
```
</details>

<details>
<summary><b>Verify</b></summary>

```shell
vault policy read payments-app
```
</details>

Link the policy to a Vault role
===

Create a Vault Kubernetes auth role named `payments-app` that binds the policy to the
`payments-app` service account in the `default` namespace.

<details>
<summary><b>Solution</b></summary>
Run the following command in the <b>Terminal</b> tab.

```shell
vault write auth/kubernetes/role/payments-app \
  bound_service_account_names="payments-app" \
  bound_service_account_namespaces="default" \
  policies="payments-app" \
  ttl="1h"
```
</details>

<details>
<summary><b>Verify</b></summary>

```shell
vault read auth/kubernetes/role/payments-app
```
</details>

Next, add the Vault Agent Injector annotations to the Kubernetes Deployment.
