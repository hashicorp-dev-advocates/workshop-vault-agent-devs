# workshop-vault-agent-devs

Tutorial workspace demonstrating how to use **HashiCorp Vault Agent** to inject and live-reload
secrets into a Spring Boot application — no Vault SDK required.

Two variants are provided:

| Variant | Auth method | How secrets are delivered |
|---------|-------------|--------------------------|
| **Local (Docker Compose)** | Vault token (file) | Vault Agent renders a file to a shared bind-mount |
| **Kubernetes (k3s)** | Kubernetes service account | Vault Agent Injector annotates the Pod |

In both cases Spring Boot picks up the rendered `application.properties` via
`spring.config.import`, and `@RefreshScope` beans are re-bound without a restart when Vault
Agent calls `POST /actuator/refresh` after each re-render.

---

## Repository layout

```
spring/
  payments-app/         Spring Boot 3 / Java 23 Maven project
  vault/                Vault Agent config (local variant only)
  kubernetes/           Kubernetes manifests (k3s + Injector variant)
vault/
  setup.sh              Vault server setup — local Docker Compose variant
  setup-k8s.sh          Vault server setup — k3s / Helm variant
  policies/
    payments-app.hcl    Vault policy for the payments-app
  postgres-init.sql     Creates the payments table on first postgres start
secrets/                Runtime secrets written by Vault Agent (git-ignored)
docker-compose.yml      Local tutorial stack
```

---

## Local variant (Docker Compose)

### Prerequisites

- [Podman](https://podman.io) with `docker-compose` as the external compose provider
  (Podman 5+ on macOS via Homebrew includes this automatically)

### First-time setup

```bash
# Podman runs containers rootless — the secrets/ directory must be
# world-writable so the vault-init container can write vault-token into it.
chmod 777 secrets/
```

### Start the stack

```bash
podman compose up
```

Services start in this order:

```
postgres → vault → vault-init → vault-agent → payments-app
```

`payments-app` will not start until Vault Agent has written
`secrets/application.properties`. If it starts without that file it
fast-fails — this is intentional.

### Test it

```bash
# List payments (proves DB credentials work)
curl http://localhost:8080/payments

# Show current static secrets (use this to verify live-reload)
curl http://localhost:8080/payments/config
```

### Test live-reload

Update a static secret in Vault and watch the app pick it up without restarting:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

vault kv put spring/kv/payments-app \
  custom.StaticSecret.username="updated-user" \
  custom.StaticSecret.password="new-password"

# Vault Agent re-renders the file and calls /actuator/refresh automatically.
# Within a few seconds the new values appear:
curl http://localhost:8080/payments/config
```

### Reset

```bash
podman compose down -v
rm -f secrets/vault-token secrets/vault-secrets.properties
```

---

## Kubernetes variant (k3s + Vault Agent Injector)

### Prerequisites

- [k3s](https://k3s.io) running locally
- `kubectl` configured to target the k3s cluster
- `helm` v3
- A PostgreSQL instance running in the cluster (e.g. deployed via Helm or a simple Deployment
  using the same `postgres:16` image and `vault/postgres-init.sql`)

### Deploy

```bash
# 1. Set up Vault (installs Helm chart + configures secrets engines + k8s auth)
bash vault/setup-k8s.sh

# 2. Build the image and import it into k3s
docker build -t payments-app:latest ./spring/payments-app
k3s ctr images import <(docker save payments-app:latest)

# 3. Apply manifests
kubectl apply -f spring/kubernetes/

# 4. Watch the Pod start (you'll see the vault-agent-init and vault-agent containers)
kubectl get pods -w
```

### Test it

```bash
kubectl port-forward svc/payments-app 8080:8080

curl http://localhost:8080/payments
curl http://localhost:8080/payments/config
```

---

## How the secret injection works

```
┌─────────────────────────────────────┐
│  Vault                              │
│  ├── spring/kv/payments-app         │  Static credentials (KV v2)
│  └── database/creds/payments-app    │  Dynamic PostgreSQL credentials
└──────────────┬──────────────────────┘
               │ render template
               ▼
       /vault/secrets/application.properties
               │ spring.config.import
               ▼
┌──────────────────────────┐
│  payments-app            │
│  @RefreshScope beans     │  ◄── POST /actuator/refresh (called by Vault Agent)
│  DataSource (HikariCP)   │
└──────────────────────────┘
```

1. **Vault Agent** (or the Injector sidecar) authenticates to Vault and renders the
   `secrets.ctmpl` template into `application.properties`.
2. **Spring Boot** imports that file at startup via `spring.config.import`.
3. When a lease expires or a secret rotates, Vault Agent re-renders the file and calls
   `POST /actuator/refresh`.
4. **Spring Cloud Context** re-binds all `@RefreshScope` beans — the `DataSource` pool is
   replaced with a new one using the fresh credentials. No restart needed.
