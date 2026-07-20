---
slug: kubernetes-configure-authentication
id: o1hfyvgix4wm
type: challenge
title: Kubernetes - Enable Kubernetes authentication
teaser: Enable Vault's Kubernetes authentication method so Pods can authenticate using
  their service account.
notes:
- type: text
  contents: |
    In this section of the workshop, you will learn how to deploy your application
    to Kubernetes with the Vault Agent Injector.

    In this section, you will:

    1. Enable Vault's Kubernetes authentication method.
    2. Create a Vault policy and role for the payments-app service account.
    3. Add Vault Agent Injector annotations to the Kubernetes Deployment.
    4. Deploy and verify the application runs with Vault-injected secrets.
- type: text
  contents: |
    The Vault Agent Injector is a Kubernetes mutating admission webhook. When a Pod
    is created with the right annotations, it automatically injects two containers:

    1. **vault-agent-init** (initContainer) — authenticates to Vault, renders the
       secrets file once, then exits. The app container only starts after this completes.
    2. **vault-agent** (sidecar) — keeps leases renewed, re-renders when secrets
       rotate, and calls `POST /actuator/refresh` on the app.

    No `agent.hcl` file is needed — the injector builds the Vault Agent configuration
    entirely from Pod annotations.
tabs:
- id: kvb7iyd26yyo
  title: Terminal
  type: terminal
  hostname: sandbox
- id: qoryfqxrqnuy
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

In the previous sections, you tested your application locally using Vault Agent running as a
Docker Compose service with token file authentication.

When running in Kubernetes, the Vault Agent Injector uses the Pod's Kubernetes service account
JWT to authenticate to Vault — no static token required. Vault verifies the JWT against the
Kubernetes API and issues a scoped Vault token.

Verify Kubernetes authentication method
===

The `setup-sandbox` for this challenge has already configured the Kubernetes auth method and
installed the Vault Agent Injector via Helm. Verify the configuration is in place.

```shell
vault read auth/kubernetes/config
```

The output includes the Kubernetes API host, CA certificate, and token reviewer JWT.

```shell,nocopy
Key                        Value
---                        -----
kubernetes_host            https://10.5.0.4:6443
token_reviewer_jwt_set     true
...
```

Verify the Vault Agent Injector is running in the `vault` namespace.

```shell
kubectl get pods -n vault
```

```shell,nocopy
NAME                                           READY   STATUS    RESTARTS   AGE
vault-injector-agent-injector-...              1/1     Running   0          1m
```

Next, create a Vault policy and role to grant the `payments-app` service account access to secrets.
