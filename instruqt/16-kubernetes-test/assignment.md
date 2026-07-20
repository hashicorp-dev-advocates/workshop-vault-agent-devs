---
slug: kubernetes-test
id: 3yfjmyhposeu
type: challenge
title: Kubernetes - Deploy and test the application
teaser: Apply the Kubernetes manifests and verify the Vault Agent Injector delivers
  secrets to the Pod.
notes:
- type: text
  contents: |-
    For other patterns for accessing Vault from Kubernetes, check out:

    - [Vault Agent Injector tutorial](https://developer.hashicorp.com/vault/tutorials/kubernetes/agent-kubernetes)
    - [Vault Secrets Operator](https://developer.hashicorp.com/vault/tutorials/integrate-kubernetes-hcp-vault-dedicated/kubernetes-vso-hcp-vault)
tabs:
- id: c1vl4yfr8mrf
  title: Terminal
  type: terminal
  hostname: sandbox
- id: rnq4xdvlxa6y
  title: API Request
  type: terminal
  hostname: sandbox
- id: uc2890xtndlw
  title: Code
  type: code
  hostname: sandbox
  path: /root/workshop-vault-agent-devs
difficulty: ""
timelimit: 0
enhanced_loading: null
---

Deploy the application
===

Apply all Kubernetes manifests in the **Terminal** tab.

```shell
kubectl apply -f spring/kubernetes/
```

This creates the `payments-app` ServiceAccount, Deployment, and Service.
The Vault Agent Injector webhook intercepts the Deployment and automatically adds:

- An `initContainer` (`vault-agent-init`) that renders secrets before the app starts
- A sidecar container (`vault-agent`) that keeps leases renewed and re-renders on rotation

Check that the Pod starts successfully.

```shell
kubectl get pods -l app=payments-app
```

After a minute or two the pod should be running with two containers (app + vault-agent sidecar).

```shell,nocopy
NAME                           READY   STATUS    RESTARTS   AGE
payments-app-6468f7c94b-p6zg9  2/2     Running   0          43s
```

Verify secret injection
===

Check the application logs to confirm both beans initialised with Vault-issued credentials.

```shell
kubectl logs -l app=payments-app -c payments-app
```

```shell,nocopy
rebuild DataSource with username: v-kubernet-writer-AbCdEfGh-1736557753
rebuild ExampleClient with static-secret username: nic
```

Test the application
===

The Service is exposed as a NodePort on port 30080. Make requests in the **API Request** tab.

List payments:

```shell
curl localhost:30080/payments
```

```shell,nocopy
[{"id":1,"reference":"REF001","amount":100.00,"currency":"USD","status":"PENDING","created_at":"..."}]
```

Create a payment:

```shell
curl -s localhost:30080/payments \
  -H "content-type: application/json" \
  -d '{"reference":"REF-K8S","amount":99.00,"currency":"USD","status":"PENDING"}'
```

Verify credential rotation
===

Wait about one minute and watch the sidecar container logs for a re-render:

```shell
kubectl logs -l app=payments-app -c vault-agent -f
```

After the `writer` role TTL expires, the sidecar re-renders the credentials file and calls
`/actuator/refresh`. The application log will show:

```shell,nocopy
rebuild DataSource with username: v-kubernet-writer-XyZaBcDe-1736557854
```

Make a second request to confirm the application is still serving traffic.

```shell
curl localhost:30080/payments
```

Summary
===

In this section, you learned how to:

1. Enable Vault's Kubernetes authentication method.
2. Create a Vault policy and role for the `payments-app` service account.
3. Add the Vault Agent Injector annotations to inject and live-reload secrets in Kubernetes.
4. Deploy and verify the application receives credentials from the Vault Agent sidecar.
