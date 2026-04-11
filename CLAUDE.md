# microsvcs

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
- **GitOps**: ArgoCD (sync) + Kargo (promotion: dev -> staging -> prod)
- **K8s**: Kind (local), Kustomize overlays per environment
- **CI/CD**: GitHub Actions -> Quay.io registry
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

1. Push to `main` -> GitHub Actions builds image with SHA tag
2. Kargo detects new image -> auto-promotes dev -> staging
3. Production promotion requires **manual approval** via Kargo UI/CLI

## Local Dashboards

| Tool    | URL                      | Credentials |
|---------|--------------------------|-------------|
| ArgoCD  | http://localhost:31443   | admin/admin |
| Kargo   | http://localhost:31444   | admin/admin |

## Kargo Config

`kargo/config.yaml` is the single source of truth for services and environments.
Run `kargo/generate.sh` to regenerate manifests in `kargo/generated/`.

## Known Issues

### Red config path divergence
Red's `webcolor_ff.go:84` defaults to `/app/config/demo-flags.goff.yaml` while blue/green/yellow use `./demo-flags.goff.yaml`. All services bake the file into the image at `/app/demo-flags.goff.yaml`. Red works in dev/staging (git-sync sidecar mounts at `/app/config/`) but crashes in production without the sidecar.

### git-sync not in ArgoCD
git-sync is intentionally excluded from `argocd/applicationset.yaml` (commented out). Kargo stages exist and report healthy for dev/staging, but this is a false green — those stages only commit to git without an `argocd-update` step, so nothing actually deploys. Production stage fails because it does have `argocd-update`.

### Code duplication across color services
`webcolor_ff.go`, `internal/name/`, `internal/version/` are nearly identical across all 4 color services. Red has extra metrics code. A fix in one must be replicated to all four.

### ArgoCD major version pending
ArgoCD chart is at 8.1.4, latest is 9.5.0. Major bump deferred until migration notes are reviewed.
