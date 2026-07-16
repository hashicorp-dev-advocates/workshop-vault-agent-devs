# workshop-vault-agent-devs

Tutorial workspace demonstrating how to use **HashiCorp Vault Agent** to inject and live-reload
secrets into a Spring Boot application — no Vault SDK required.

The application (`payments-app`) reads all credentials from a file rendered by Vault Agent.
Two variants are covered:

| Variant | Auth method | Secret delivery |
|---------|-------------|-----------------|
| **Local** (Docker Compose) | Vault token file | Agent renders to a bind-mounted `secrets/` directory |
| **Kubernetes** (k3s + Helm) | Kubernetes service account | Vault Agent Injector writes to a Pod-shared volume via annotations |

In both cases Spring Boot imports the rendered file via `spring.config.import`. When secrets
rotate, Vault Agent re-renders the file and calls `POST /actuator/refresh` to re-bind
`@RefreshScope` beans without restarting the container.

---

## Repository layout

```
spring/
  payments-app/           Spring Boot 3 / Java 23 Maven project
    src/
    pom.xml
    Dockerfile            Multi-stage build (maven:3.9-eclipse-temurin-23 → eclipse-temurin:23-jre)
  vault/
    agent.hcl             Vault Agent config — local variant (token file auth)
    secrets.ctmpl         Consul Template → vault-secrets.properties
  kubernetes/
    serviceaccount.yaml   payments-app ServiceAccount
    deployment.yaml       Deployment with Vault Injector annotations
    service.yaml          ClusterIP Service
vault/
  setup.sh                One-shot Vault config script — local variant
  setup-k8s.sh            Vault Helm install + k8s auth config — k3s variant
  policies/
    payments-app.hcl      Vault policy (read KV + database creds)
  postgres-init.sql       Creates the payments table on first postgres start
secrets/                  Runtime secrets written by Vault Agent — git-ignored
docker-compose.yml        Local tutorial stack (5 services)
```

---

## How it works

```
┌──────────────────────────────────────┐
│  Vault (dev mode)                    │
│  ├── spring/kv/payments-app          │  KV v2 — static credentials
│  └── database/creds/payments-app     │  Dynamic short-lived PostgreSQL creds
└───────────────┬──────────────────────┘
                │  Consul Template render
                ▼
    secrets/vault-secrets.properties
    ┌─────────────────────────────────┐
    │  custom.static-secret.username  │  ← from KV v2
    │  custom.static-secret.password  │  ← from KV v2
    │  spring.datasource.username     │  ← dynamic (Vault-issued PG user)
    │  spring.datasource.password     │  ← dynamic (Vault-issued PG password)
    └─────────────────────────────────┘
                │  spring.config.import
                ▼
┌───────────────────────────────┐
│  payments-app (Spring Boot)   │
│  ExampleClient                │  @Bean @RefreshScope — rebuilt with static KV credentials
│  DataSource (HikariCP)        │  @Bean @RefreshScope — rebuilt with dynamic DB credentials
└───────────────────────────────┘
                ▲
                │  POST /actuator/refresh  (called by Vault Agent after each render)
                │  Spring re-binds @RefreshScope beans — no restart needed
```

**Two-file property split:**
- `src/main/resources/application.properties` — committed, non-secret config (datasource URL,
  actuator exposure). This is the base layer.
- `secrets/vault-secrets.properties` — git-ignored, written at runtime by Vault Agent.
  Contains only credentials. Spring merges this on top of the base layer.

---

## Local variant — Docker Compose

### Prerequisites

- [Podman](https://podman.io) 5+ (macOS: `brew install podman`)  
  Podman uses `docker-compose` as its external compose provider — no Docker Desktop needed.

### First-time setup

```bash
# Clone the repo and set permissions on the secrets directory.
# Podman runs containers rootless so the bind-mounted secrets/ directory
# must be world-writable for vault-init to write the token file into it.
chmod 777 secrets/
```

### Start the stack

```bash
podman compose up
```

Services start in strict dependency order:

```
postgres ──healthy──▶ vault ──healthy──▶ vault-init ──completed──▶ vault-agent ──healthy──▶ payments-app
```

`payments-app` will not start until Vault Agent has rendered `secrets/vault-secrets.properties`.
If the file is absent at startup the app fast-fails on `spring.config.import` — this is
intentional. Start the full stack and let the dependency chain do its job.

### Test the endpoints

```bash
# Health check
curl http://localhost:8080/actuator/health

# List payments — proves dynamic DB credentials are valid
curl http://localhost:8080/payments

# Create a payment
curl -X POST http://localhost:8080/payments \
  -H "Content-Type: application/json" \
  -d '{"reference":"PAY-001","amount":99.99,"currency":"USD","status":"PENDING"}'

# Show current static KV secret values — use this to observe live-reload
curl http://localhost:8080/payments/secret
```

### Test live secret reload

Update the static KV secret in the running Vault and watch Spring pick it up without a restart:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

vault kv put spring/kv/payments-app \
  "custom.static-secret.username=new-user" \
  "custom.static-secret.password=new-password"

# Vault Agent detects the change, re-renders vault-secrets.properties,
# and calls POST /actuator/refresh automatically.
# Within a few seconds the new values appear:
curl http://localhost:8080/payments/secret
```

### Inspect the rendered secrets file

Because `secrets/` is a host bind-mount you can inspect the rendered file directly:

```bash
cat secrets/vault-secrets.properties
```

### Reset between runs

```bash
podman compose down -v
rm -f secrets/vault-token secrets/vault-secrets.properties
```

---

## CI/CD — GitHub Actions

The workflow [`payments-app-spring`](.github/workflows/payments-app-spring.yml) builds and
publishes the Spring payments-app container image to the **GitHub Container Registry (GHCR)**.

### Triggers

| Event | Condition | Behaviour |
|-------|-----------|-----------|
| `push` tag matching `v*` | — | build + push |
| `pull_request` to `main` | files under `spring/payments-app/**` changed | build only (no push) |
| `workflow_dispatch` | — | manual trigger, build + push |

### Image tags

| Tag pattern | Produced when |
|-------------|---------------|
| `sha-<full-sha>` | every tag push |
| `1.2.3`, `1.2`, `1` | semver tag (e.g. `v1.2.3`) |
| `latest` | every tag push |
| `pr-<number>` | pull request |

### Registry and permissions

The image is pushed to `ghcr.io/<owner>/payments-app-spring`. The workflow uses the
auto-provided `GITHUB_TOKEN` — no additional secrets are required.

### Multi-platform builds

Images are built for both `linux/amd64` and `linux/arm64` via Docker Buildx with GitHub
Actions cache (`type=gha`) to speed up repeated builds.

---

## Kubernetes variant — k3s + Vault Agent Injector

The Kubernetes variant uses the same `payments-app` container image. Vault Agent is injected
automatically by the **Vault Agent Injector** based on Pod annotations — no `agent.hcl` file
is authored manually.

### Prerequisites

- [k3s](https://k3s.io) running locally (`curl -sfL https://get.k3s.io | sh -`)
- `kubectl` configured to target the k3s cluster
- `helm` v3 (`brew install helm`)
- A PostgreSQL pod/service running in the cluster  
  (deploy using `postgres:16` and `vault/postgres-init.sql` as the init script)

### Deploy

```bash
# 1. Install Vault via Helm (dev mode + injector) and configure secrets engines + k8s auth
bash vault/setup-k8s.sh

# 2. Build the payments-app image and import it into k3s
podman build -t payments-app:latest ./spring/payments-app
k3s ctr images import <(podman save payments-app:latest)

# 3. Apply Kubernetes manifests
kubectl apply -f spring/kubernetes/

# 4. Watch the Pod start — you will see vault-agent-init then vault-agent sidecar
kubectl get pods -w
```

### Test

```bash
kubectl port-forward svc/payments-app 8080:8080

curl http://localhost:8080/actuator/health
curl http://localhost:8080/payments
curl http://localhost:8080/payments/secret
```

---

## Vault secrets reference

| Path | Engine | Contents |
|------|--------|----------|
| `spring/kv/data/payments-app` | KV v2 | `custom.static-secret.username`, `custom.static-secret.password` |
| `database/creds/payments-app` | Database | Dynamic PostgreSQL `username` + `password` (1h TTL) |

Policy file: `vault/policies/payments-app.hcl`  
Database role: `database/roles/payments-app` — grants `SELECT, INSERT, UPDATE, DELETE` on
`public.payments` and `USAGE, SELECT` on `public.payments_id_seq` only.

---

## Spring Boot application structure

```
PaymentsAppApplication        Entry point — @Bean @RefreshScope DataSource and ExampleClient
AppProperties                 @ConfigurationProperties(prefix="custom") — binds static KV credentials
ExampleClient                 Pretend external client rebuilt on refresh with latest static credentials
Payment                       Record mapped to the public.payments table
PaymentsController            GET /payments, POST /payments, GET /payments/secret
```

Key properties in `src/main/resources/application.properties`:

```properties
# Imports the Vault-rendered secrets file (no "optional:" — fast-fail if absent)
spring.config.import=file:/vault/secrets/vault-secrets.properties

# Exposes /actuator/refresh (called by Vault Agent) and /actuator/health
management.endpoints.web.exposure.include=refresh,health
```
