# Kubernetes Deployment — payments-app

Both variants (Docker Compose and Kubernetes) run from the same `docker-compose.yaml`.
Vault and PostgreSQL are external to the k3s cluster — they run as compose services on
the `vpcbr` bridge network (10.5.0.0/16). Only the **Vault Agent Injector** is installed
into k3s, pointed at the Vault container via `externalVaultAddr=http://10.5.0.2:8200`.

---

## Architecture

```
docker-compose (vpcbr 10.5.0.0/16)
├── vault          10.5.0.2:8200   ← Vault 1.21.4, dev mode
├── database       10.5.0.3:5432   ← PostgreSQL 16
├── vault-init                     ← configures KV, DB engine, policy, token
├── vault-agent                    ← renders vault-secrets.properties (Compose variant)
├── payments-app   port 8080       ← Spring Boot (Docker Compose variant)
├── k3s server     10.5.0.4:6443
└── k3s agent      10.5.0.5

k3s cluster (same vpcbr network)
├── vault namespace
│   ├── vault-auth SA + ClusterRoleBinding  ← token reviewer for Kubernetes auth
│   └── vault-agent-injector (Helm)         ← injector only, externalVaultAddr=10.5.0.2:8200
└── default namespace
    └── payments-app Deployment + Service   ← NodePort 30080, Vault sidecar injected
```

---

## Manifest inventory

| File | Kind | Name | Purpose |
|------|------|------|---------|
| `serviceaccount.yaml` | ServiceAccount + Secret | `payments-app` | Identity for Vault Kubernetes auth |
| `deployment.yaml` | Deployment | `payments-app` | Spring Boot app; Vault addr `10.5.0.2`, DB at `10.5.0.3` |
| `service.yaml` | Service (NodePort) | `payments-app` | Exposes port 8080 on nodePort 30080 |

> **No in-cluster database.** PostgreSQL runs in docker-compose at `10.5.0.3:5432` and is
> reachable from k3s pods via the shared `vpcbr` network.

---

## Deployment

### Prerequisites

- `podman` and `podman compose`
- `helm` v3
- `kubectl`

### One-command setup

```bash
mkdir -p tmp secrets
chmod 777 secrets/
bash config/setup-local.sh
```

`config/setup-local.sh` does everything in order:

1. Generates `./tmp/k3s.token` (once) and starts the full compose stack
2. Waits for k3s to be ready (`./tmp/kubeconfig.yaml` written by k3s server)
3. Creates the `vault` namespace and applies `vault/service-account.yaml`
4. Runs `vault/setup.sh` locally — configures KV, database engine, policy, **and**
   Kubernetes auth (because `KUBECONFIG` is set at this point)
5. Installs only the Vault Agent Injector via Helm:
   ```
   server.enabled=false
   injector.externalVaultAddr=http://10.5.0.2:8200
   ```

### Deploy application manifests

```bash
export KUBECONFIG=./tmp/kubeconfig.yaml

kubectl apply -f spring/kubernetes/

# Watch the Pod start — you will see vault-agent-init then vault-agent sidecar
kubectl get pods -w
```

---

## Accessing both variants

### Docker Compose variant (port 8080)

```bash
curl http://localhost:8080/actuator/health
curl http://localhost:8080/payments
curl http://localhost:8080/payments/secret
```

### Kubernetes variant (NodePort 30080)

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
curl http://${NODE_IP}:30080/actuator/health
curl http://${NODE_IP}:30080/payments
```

Or port-forward:

```bash
kubectl port-forward svc/payments-app 8081:8080
curl http://localhost:8081/payments
```

---

## Verifying Vault secret injection (Kubernetes variant)

```bash
# Confirm the injected agent rendered the secrets file
kubectl exec deployment/payments-app -c payments-app -- \
  cat /vault/secrets/vault-secrets.properties

# Show static KV secret (for live-reload testing)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
curl http://${NODE_IP}:30080/payments/secret
```

---

## Reset

```bash
# Tear down everything
podman compose down -v
rm -rf tmp/ secrets/vault-token secrets/vault-secrets.properties

# Remove k3s resources (if cluster still running)
kubectl delete -f spring/kubernetes/ --ignore-not-found
helm uninstall vault-injector -n vault --ignore-not-found
kubectl delete namespace vault --ignore-not-found
```
