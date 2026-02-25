# CLAUDE.md

## Project Overview

GitOps microservices platform demonstrating progressive delivery with ArgoCD and Kargo.

## Repository Structure

```
projects/          # Go microservices (red, blue, green, yellow, git-sync)
k8s/               # Kubernetes manifests (Kustomize: base + dev/staging/prod overlays)
argocd/            # ArgoCD ApplicationSet + project config
kargo/             # Kargo progressive delivery (config.yaml is the single source of truth)
scripts/           # Utility scripts
install.sh         # One-command local platform setup (Kind + ArgoCD + Kargo)
```

## Tech Stack

- **Language**: Go 1.25 with Echo v4 HTTP framework
- **GitOps**: ArgoCD (sync) + Kargo (promotion: dev → staging → prod)
- **K8s**: Kind (local), Kustomize overlays per environment
- **CI/CD**: GitHub Actions → Quay.io registry
- **Feature flags**: GO Feature Flag

## Common Commands

Each service under `projects/<name>/`:

```bash
make run            # Run locally on :8080
make test           # Run tests
make lint           # Lint
make check-format   # Check formatting
make sec            # Security checks (gosec, govulncheck)
make compile        # Build binary
make dockerbuild    # Build Docker image
```

Full platform:

```bash
./install.sh        # Create Kind cluster + ArgoCD + Kargo (~5 min)
```

## Key Endpoints (each color service)

- `GET /` — HTML UI (colored boxes)
- `GET /healthz` — liveness probe
- `GET /readyz` — readiness probe

## Deployment Flow

1. Push to `main` → GitHub Actions builds image with SHA tag
2. Kargo detects new image → auto-promotes dev → staging
3. Production promotion requires **manual approval** via Kargo UI/CLI

## Local Dashboards

| Tool    | URL                      | Credentials |
|---------|--------------------------|-------------|
| ArgoCD  | http://localhost:31443   | admin/admin |
| Kargo   | http://localhost:31444   | admin/admin |

## Kargo Config

`kargo/config.yaml` is the single source of truth for services and environments.
Run `kargo/generate.sh` to regenerate manifests in `kargo/generated/`.
