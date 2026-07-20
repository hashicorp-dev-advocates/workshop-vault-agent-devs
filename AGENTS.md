# AGENTS.md — workspace guide for AI agents

## Repository purpose

Demonstrates how to use **HashiCorp Vault Agent** to inject and live-reload secrets into a
Spring Boot application without the Vault SDK. Both variants run from a single
`docker-compose.yaml`: the Docker Compose variant uses a standalone Vault Agent, and the
Kubernetes variant deploys the app into an in-compose k3s cluster with the Vault Agent Injector.

## Key directories

| Path | Purpose |
|------|---------|
| `config/` | Setup scripts — `setup-local.sh` is the single entry-point for both variants; `workshop.sh` is the workshop solve script |
| `spring/payments-app/` | Spring Boot 3 / Java 23 Maven project + Dockerfile |
| `spring/vault/` | Vault Agent config (`agent.hcl`) and Consul Template (`secrets.ctmpl`) — local variant only |
| `spring/kubernetes/` | Kubernetes manifests — see table below for full inventory |
| `vault/` | Vault setup script, policy, Kubernetes ServiceAccount manifest |
| `secrets/` | Runtime secrets written by Vault Agent — **git-ignored, never commit** |
| `tmp/` | Runtime k3s kubeconfig and token — **git-ignored, never commit** |
| `.github/workflows/` | GitHub Actions CI/CD workflows |

### docker-compose.yaml service overview

| Service | Fixed IP | Role |
|---------|----------|------|
| `vault` | 10.5.0.2 | HashiCorp Vault 1.21.4, dev mode, token `root-token` |
| `database` | 10.5.0.3 | PostgreSQL 16, database `payments` |
| `vault-init` | 10.5.0.6 | One-shot: runs `vault/setup.sh` to configure secrets engines + policy |
| `vault-agent` | 10.5.0.7 | Renders `vault-secrets.properties`; calls `/actuator/refresh` on change |
| `payments-app` | 10.5.0.8 | Spring Boot app (Docker Compose variant), port 8080 |
| `server` | 10.5.0.4 | k3s server node; writes kubeconfig to `./tmp/kubeconfig.yaml` |
| `agent` | 10.5.0.5 | k3s agent node |

All services share the `vpcbr` bridge network (10.5.0.0/16) so k3s pods can reach Vault
at `http://10.5.0.2:8200` and PostgreSQL at `10.5.0.3:5432` directly.

### `spring/kubernetes/` manifest inventory

| File | Kind | Name | Notes |
|------|------|------|-------|
| `serviceaccount.yaml` | ServiceAccount + Secret | `payments-app` | Identity used by the Vault Agent Injector to authenticate via Kubernetes auth |
| `deployment.yaml` | Deployment | `payments-app` | Spring Boot app; connects to database at `10.5.0.3:5432` (compose service) |
| `service.yaml` | Service (NodePort) | `payments-app` | Exposes app on nodePort `30080`; reachable at `http://<node-ip>:30080` |

### Kubernetes deployment

`config/setup-local.sh` is the single entry-point for both variants:

```bash
mkdir -p tmp secrets && chmod 777 secrets/
bash config/setup-local.sh
```

The script: starts the compose stack, waits for k3s, creates the `vault` namespace and applies
`vault/service-account.yaml`, runs `vault/setup.sh` locally (which configures Vault **and**
Kubernetes auth because `KUBECONFIG` is set), then installs only the Vault Agent Injector via
Helm (`server.enabled=false`, `injector.externalVaultAddr=http://10.5.0.2:8200`).

After the script completes, deploy the app manifests:

```bash
kubectl apply -f spring/kubernetes/
```

See `spring/kubernetes/README.md` for full instructions.

## CI/CD workflows

### `.github/workflows/payments-app-spring.yml`

Builds and publishes `ghcr.io/<owner>/payments-app-spring` to GitHub Container Registry.

- **Triggers**: push / PR to `main` (path-filtered to `spring/payments-app/**`), published
  release, `workflow_dispatch`
- **Push behaviour**: images are pushed on `push` and `release` events only; PRs build but
  do not push
- **Tags**: full SHA, branch name, PR number, semver (on release), `latest` (on release only)
- **Platforms**: `linux/amd64` and `linux/arm64`
- **Auth**: `GITHUB_TOKEN` — no additional secrets required

## Security notes

- `secrets/` is bind-mounted at runtime and must never be committed. It is listed in `.gitignore`.
- `tmp/` contains the k3s kubeconfig and token — also git-ignored, never commit.
- The Dockerfile runs the JVM as UID 1001 (non-root).
- Vault dev mode (`VAULT_DEV_ROOT_TOKEN_ID=root-token`) is used for the tutorial only — never use
  dev mode or a hardcoded root token in production.

## Conventions

- Container runtime: **Podman** (not Docker). Use `podman compose` and `podman build`.
- Tests skip during image build (`-DskipTests`) because they require a live database and
  secrets file.
- Secrets are never hardcoded. All credentials come from Vault Agent at runtime.

## Workshop starting state

The `main` branch holds the **workshop starting state** — a deliberately incomplete
configuration that participants build up challenge by challenge:

| File | Starting state | Goal |
|------|---------------|------|
| `spring/vault/agent.hcl` | `vault {}` + `auto_auth {}` — missing `template_config` + `template` | Add `template_config` + `template` blocks |
| `spring/vault/secrets.ctmpl` | KV static secret block only — `database/creds/writer` block missing | Add `database/creds/writer` block |
| `spring/payments-app/src/main/resources/application.properties` | Hardcoded `username=postgres` / `password=postgres`; `management.endpoints.web.exposure.include=health` only | Add `spring.config.import`, expose `refresh` actuator |
| `PaymentsAppApplication.java` | `@Bean` without `@RefreshScope` on both beans | Add `@RefreshScope` to both beans |
| `spring/kubernetes/deployment.yaml` | All `vault.hashicorp.com/` annotations present **except** `agent-inject-command-vault-secrets.properties` (a `# TODO:` comment marks the gap) | Add the missing `agent-inject-command-vault-secrets.properties` annotation to trigger `POST /actuator/refresh` on every re-render |

### Workshop solve script

`config/workshop.sh` applies the **complete working configuration** in one step — use it
to skip ahead or verify the final state. It writes all five files above as heredocs.

```bash
bash config/workshop.sh
```

