# AGENTS.md — workspace guide for AI agents

## Repository purpose

Demonstrates how to use **HashiCorp Vault Agent** to inject and live-reload secrets into a
Spring Boot application without the Vault SDK. Two variants are covered: Docker Compose (local)
and Kubernetes (k3s + Vault Agent Injector).

## Key directories

| Path | Purpose |
|------|---------|
| `spring/payments-app/` | Spring Boot 3 / Java 23 Maven project + Dockerfile |
| `spring/vault/` | Vault Agent config (`agent.hcl`) and Consul Template (`secrets.ctmpl`) |
| `spring/kubernetes/` | Kubernetes manifests (ServiceAccount, Deployment, Service) |
| `vault/` | Vault setup scripts and policies |
| `secrets/` | Runtime secrets written by Vault Agent — **git-ignored, never commit** |
| `.github/workflows/` | GitHub Actions CI/CD workflows |

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

- `secrets/` is bind-mounted at runtime and must never be committed. It is listed in
  `.gitignore`.
- The Dockerfile runs the JVM as UID 1001 (non-root).
- Vault dev mode (`VAULT_DEV_ROOT_TOKEN_ID=root`) is used for the tutorial only — never use
  dev mode or a hardcoded root token in production.

## Conventions

- Container runtime: **Podman** (not Docker). Use `podman compose` and `podman build`.
- Tests skip during image build (`-DskipTests`) because they require a live database and
  secrets file.
- Secrets are never hardcoded. All credentials come from Vault Agent at runtime.
