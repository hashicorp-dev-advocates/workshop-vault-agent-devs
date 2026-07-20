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
config/
  setup-local.sh          One-command setup for both variants (compose + k3s)
spring/
  payments-app/           Spring Boot 3 / Java 23 Maven project
    src/
    pom.xml
    Dockerfile            Multi-stage build (maven:3.9-eclipse-temurin-23 → eclipse-temurin:23-jre)
  vault/
    agent.hcl             Vault Agent config — local variant (token file auth)
    secrets.ctmpl         Consul Template → vault-secrets.properties
  kubernetes/
    serviceaccount.yaml   payments-app ServiceAccount + token Secret
    deployment.yaml       Deployment with Vault Injector annotations
    service.yaml          NodePort Service (port 30080)
vault/
  setup.sh                Vault config script — KV, database engine, policy, k8s auth
  service-account.yaml    vault-auth ServiceAccount + ClusterRoleBinding (for k8s auth TokenReview)
  policies/
    payments-app.hcl      Vault policy (read KV + database creds)
  postgres-init.sql       Creates the payments table on first postgres start
secrets/                  Runtime secrets written by Vault Agent — git-ignored
docker-compose.yaml       Full tutorial stack (vault, postgres, vault-init, vault-agent, payments-app, k3s)
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
│  DataSource                   │  @Bean @RefreshScope — rebuilt with dynamic DB credentials
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
export VAULT_TOKEN=root-token

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

## Kubernetes variant — k3s + Vault Agent Injector

The Kubernetes variant uses the same `payments-app` container image. Vault Agent is injected
automatically by the **Vault Agent Injector** based on Pod annotations — no `agent.hcl` file
is authored manually.

### Prerequisites

- [Podman](https://podman.io) 5+ and `podman compose`
- `kubectl`
- `helm` v3 (`brew install helm`)

### One-command setup

```bash
mkdir -p tmp secrets
chmod 777 secrets/
bash config/setup-local.sh
```

`config/setup-local.sh` does everything in order:

1. Generates `./tmp/k3s.token` (once) and starts the full compose stack
2. Waits for k3s to be ready (`./tmp/kubeconfig.yaml` written by the k3s server container)
3. Creates the `vault` namespace and applies `vault/service-account.yaml`
4. Runs `vault/setup.sh` locally — configures KV, database engine, policy, **and**
   Kubernetes auth (because `KUBECONFIG` is set)
5. Installs only the Vault Agent Injector via Helm (`hashicorp/vault` chart, `server.enabled=false`,
   `injector.externalVaultAddr=http://10.5.0.2:8200`)

### Deploy application manifests

```bash
export KUBECONFIG=./tmp/kubeconfig.yaml

kubectl apply -f spring/kubernetes/

# Watch the Pod start — you will see vault-agent-init then vault-agent sidecar
kubectl get pods -w
```

### Test

```bash
# NodePort — reachable at the k3s node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
curl http://${NODE_IP}:30080/actuator/health
curl http://${NODE_IP}:30080/payments
curl http://${NODE_IP}:30080/payments/secret

# Or port-forward
kubectl port-forward svc/payments-app 8081:8080
curl http://localhost:8081/payments
```

### Verify secret injection

```bash
# Confirm the injected agent rendered the secrets file
kubectl exec deployment/payments-app -c payments-app -- \
  cat /vault/secrets/vault-secrets.properties
```

### Reset

```bash
# Tear down everything
podman compose down -v
rm -rf tmp/ secrets/vault-token secrets/vault-secrets.properties

# Remove k3s resources (if cluster still running)
kubectl delete -f spring/kubernetes/ --ignore-not-found
helm uninstall vault-injector -n vault --ignore-not-found
kubectl delete namespace vault --ignore-not-found
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

---

## Instruqt Workshop

This repository backs the **[Using Vault Agent for Applications](https://play.instruqt.com/hashicorp-field-ops/tracks/workshop-apps-vault-agent)** Instruqt track.

The track walks participants through a **red-green-refactor** approach: each challenge starts
from a deliberately broken starting state and asks participants to add exactly the piece that
makes it work.

### Challenge map

| # | Challenge | What participant does |
|---|-----------|-----------------------|
| 01 | Enable KV secrets engine | `vault secrets enable -path=spring/kv -version=2 kv` |
| 02 | Add static secret | Write `custom.static-secret.*` keys to `spring/kv/payments-app` |
| 03 | Configure Vault Agent | Fill in `template_config` + `template` blocks in `agent.hcl`; write `secrets.ctmpl` |
| 04 | Configure Spring (static) | Add `spring.config.import` + expose `refresh` actuator; remove hardcoded creds |
| 05 | Add `@RefreshScope` to `ExampleClient` | Annotate the `exampleClient` bean method |
| 06 | Test static secrets | Run Vault Agent + app; update KV secret; observe live-reload |
| 07 | Enable database secrets engine | `vault secrets enable database` |
| 08 | Add database configuration | Configure PostgreSQL plugin + rotate root credentials |
| 09 | Create database roles | Create `writer` and `reader` Vault database roles |
| 10 | Extend template for dynamic secrets | Add `database/creds/writer` block to `secrets.ctmpl` |
| 11 | Add `@RefreshScope` to `DataSource` | Annotate the `dataSource` bean method |
| 12 | Test dynamic secrets | Run Vault Agent + app; observe credential rotation via log |
| 13 | Kubernetes — configure authentication | Verify k8s auth method is enabled + Injector is installed |
| 14 | Kubernetes — control access | Write `payments-app` policy + Vault Kubernetes auth role |
| 15 | Kubernetes — add live-reload annotation | Add `agent-inject-command` annotation to `deployment.yaml` |
| 16 | Kubernetes — test application | `kubectl apply`; verify 2/2 running; call `/payments` endpoint |

### Solve script

`config/workshop.sh` applies the **complete working state** of every file that participants
modify during the track. Run it to skip ahead to the fully-wired state:

```bash
bash config/workshop.sh
```

The script writes:
- `spring/vault/agent.hcl` — full Vault Agent config with `template_config` + `template`
- `spring/vault/secrets.ctmpl` — KV + dynamic database credential blocks
- `spring/payments-app/src/main/resources/application.properties` — `spring.config.import` + actuator
- `spring/payments-app/src/main/java/…/PaymentsAppApplication.java` — both beans with `@RefreshScope`
- `spring/kubernetes/deployment.yaml` — full Vault Injector annotation set including `agent-inject-command`

### Instruqt track structure

```
instruqt/
  track.yml                         Track metadata (slug: workshop-apps-vault-agent)
  config.yml                        Sandbox environment config (KUBECONFIG, VAULT_ADDR, etc.)
  track_scripts/setup-sandbox       Global setup: installs toolchain, clones repo, starts infra
  01-enable-kv-secrets-engine/
  02-add-static-secret/
  …
  16-kubernetes-test/
```

Each challenge directory contains:
- `assignment.md` — the Instruqt challenge definition (front-matter + instructions)
- `check-sandbox` — bash script run when participant clicks **Check** (uses `fail-message`)
- `setup-sandbox` *(some challenges)* — bash script that pre-populates files for the red state
- `cleanup-sandbox` *(test challenges)* — stops `vault-agent` and the Spring process between challenges

