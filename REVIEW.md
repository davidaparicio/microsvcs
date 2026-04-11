# Repository Review: microsvcs

**Date:** 2026-04-11
**Reviewer:** Jacques (Claude Code)

A solid GitOps demo platform — the architecture is well-thought-out and the Kargo template system is particularly clean. But there are real issues worth addressing. Ranked by impact.

---

## Blockers

| # | Issue | Where |
|---|-------|-------|
| **B1** | **No Pod securityContext** — containers run as root with full capabilities | `k8s/base/deployment.yaml` |
| **B2** | **`:latest` tag in production** for git-sync | `k8s/overlays/production/git-sync/kustomization.yaml:16` |
| **B3** | **git-sync write lock blocks health checks** — `mu.Lock()` held during entire clone/pull, Kubernetes probes will timeout and kill the pod | `projects/git-sync/internal/sync/syncer.go:41-42` |
| **B4** | **`commit[:7]` can panic** — `getHeadCommit()` returns `""` on error, no bounds check | `projects/git-sync/internal/sync/syncer.go:68` |
| **B5** | **git-sync missing from ArgoCD ApplicationSet** — Kargo stages exist and promote, but ArgoCD never creates Applications to sync | `argocd/applicationset.yaml:13-17` |

### B1 — No Pod securityContext

Neither base deployment sets a `securityContext`. Without it, containers run as root (UID 0) with full capabilities. This is the single most impactful security gap in the configuration.

**Fix:** Add at both the pod and container levels in both base deployments:

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
```

### B2 — `:latest` tag in production

The production git-sync service runs with `newTag: latest`. Production deployments must be reproducible. A registry re-tag of `:latest` could silently change what's running without any Git commit, ArgoCD sync, or Kargo promotion.

**Fix:** Pin to a specific semver tag (e.g., `0.2.3` like staging).

### B3 — git-sync write lock blocks health checks

The `Sync` method acquires `mu.Lock()` and holds it for the entire duration of the git clone/pull + file copy operation. This blocks all concurrent reads to `IsHealthy()` and `GetStatus()` which use `mu.RLock()`. During a large repo clone, the health check endpoint will hang, and Kubernetes probes will time out, causing the pod to be killed and restarted.

**Fix:** Use a separate mutex for the status fields, or update them atomically, so health checks remain responsive during sync operations.

### B4 — `commit[:7]` can panic

```go
fmt.Printf("[%s] Sync completed successfully (commit: %s)\n",
    time.Now().Format(time.RFC3339), commit[:7])
```

If `commit` is ever an empty string, this panics with index-out-of-range.

**Fix:** Guard the slice operation:

```go
short := commit
if len(commit) > 7 {
    short = commit[:7]
}
```

### B5 — git-sync missing from ArgoCD ApplicationSet

The ApplicationSet matrix generator only includes `red`, `blue`, `green`, `yellow`. The `git-sync` service has overlays in all three environments and is listed in `kargo/config.yaml`, but ArgoCD will never create Applications for it. Kargo stages will try to promote and trigger `argocd-update`, but no ArgoCD Application exists to sync.

**Fix:** Add `git-sync` to the ApplicationSet list generator elements and add `namespace: 'git-sync-*'` to the AppProject destinations. Or if git-sync is intentionally excluded from ArgoCD, remove it from `kargo/config.yaml` to avoid generating orphan Kargo resources.

---

## Should Fix

| # | Issue | Where |
|---|-------|-------|
| **S1** | **No NetworkPolicies** — any compromised pod can reach any other pod | Entire `k8s/` tree |
| **S2** | **Hardcoded passwords and signing key** in `install.sh` | `install.sh:174, 207` |
| **S3** | **Massive code duplication across color services** — `webcolor_ff.go`, `internal/name/`, `internal/version/` are copy-pasted 4x | `projects/` |
| **S4** | **Shallow test coverage** — most tests assert struct construction (`!= nil`), not behavior | `projects/red/webcolor_ff_test.go` |
| **S5** | **git-sync sidecar patch duplicated** between dev and staging overlays (~50 lines, only `SYNC_INTERVAL` differs) | `k8s/overlays/development/red/kustomization.yaml:43-96` |
| **S6** | **Fragile JSON patch by array index** — `env/4/value` breaks silently if env vars are reordered | `k8s/overlays/development/git-sync/kustomization.yaml:23` |
| **S7** | **No PodDisruptionBudget** — production runs 3 replicas but a node drain can kill all of them | Production overlays |
| **S8** | **No `startupProbe`** — `livenessProbe.initialDelaySeconds: 5` can cause crash loops on cold starts | `k8s/base/deployment.yaml:41-52` |
| **S9** | **git client temp directory leak** — `NewClient` creates temp dirs but has no `Close()` method | `projects/git-sync/internal/git/client.go:26-28` |
| **S10** | **KARGO.md is stale** — says staging is manual (it's auto), references Docker Hub (it's Quay.io), shows old file layout | `KARGO.md` |

### S1 — No NetworkPolicies

Zero NetworkPolicy manifests in the entire `k8s/` tree. Every pod can communicate with every other pod cluster-wide. A compromised pod in `red-development` can reach pods in `blue-production`.

**Fix:** Add a default-deny ingress policy per namespace, then allow only the traffic needed (ingress controller to service port 8080).

### S2 — Hardcoded passwords and signing key

```bash
--set 'configs.secret.argocdServerAdminPassword=$2a$10$...'
--set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch
```

The bcrypt hashes and token signing key are committed to source control. While this is clearly a local Kind setup, the `tokenSigningKey` is a symmetric secret that can forge Kargo admin tokens.

**Fix:** Read the password hash and signing key from environment variables or a `.env` file, with a fallback to fail loudly.

### S3 — Massive code duplication across color services

`webcolor_ff.go`, `internal/name/name.go`, and `internal/version/version.go` are copy-pasted across all four color services. The only meaningful differences are import paths, the metrics endpoint (red only), and default config file paths. A bug fix in one requires patching all four.

**Fix:** Extract shared code into a shared library module (e.g., `projects/shared/` or a top-level `pkg/` package). Each color service should only contain its unique configuration and entry point.

### S4 — Shallow test coverage

The test file has good structure (table-driven `TestGetCircle`) but the remaining tests are essentially "can I construct structs":

- `TestTemplateRegistry_Render`: Creates a nil-template registry and asserts it's not nil
- `TestApiHandler_Request`: Creates an Echo context and asserts it's not nil, never calls the handler
- `TestPageDataStructure` and `TestSystemInfoStructure`: Verify Go struct assignment works

**Missing tests:**
- `versionHandler` (easy to test, pure JSON response)
- `healthzHandler` (trivially testable)
- `metricsHandler` (hand-rolled output is error-prone)
- `renderMetrics.record()` concurrent safety
- `name.GetHostname()` and `name.GetNamespace()`

### S5 — git-sync sidecar patch duplicated

The entire git-sync sidecar injection patch (~50 lines of YAML) is copy-pasted between development and staging overlays for the red service. Only `SYNC_INTERVAL` differs (`*/2` vs `*/5`).

**Fix:** Extract into a shared Kustomize Component (`k8s/components/git-sync-sidecar/`) and override only `SYNC_INTERVAL` per environment.

### S6 — Fragile JSON patch by array index

```yaml
path: /spec/template/spec/containers/0/env/4/value
```

Targets `SYNC_INTERVAL` by positional index. If anyone adds, removes, or reorders env vars in the base deployment, this patch silently modifies the wrong variable.

**Fix:** Use a strategic merge patch instead, or use Kustomize `replacements`.

### S7 — No PodDisruptionBudget

Production runs 3 replicas but a node drain during cluster maintenance can terminate all pods simultaneously.

**Fix:** Add a PDB with `minAvailable: 2` for production.

### S8 — No startupProbe

`livenessProbe` has `initialDelaySeconds: 5` with `periodSeconds: 10`. If the container takes longer than 5 seconds to start under load, it enters a crash loop.

**Fix:** Add a `startupProbe` with generous `failureThreshold`:

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30
  periodSeconds: 2
```

### S9 — git client temp directory leak

`NewClient` creates a temp directory via `os.MkdirTemp` but never exposes a `Close()` or `Cleanup()` method. Over repeated container restarts or test runs, these accumulate.

**Fix:** Add a `Close()` method to `Client` that removes `workDir`, and call it from `main.go` via `defer`.

### S10 — KARGO.md is stale

- Says staging is "Manual promotion" (`autoPromote: false`) — actually `autoPromote: true` in `kargo/config.yaml`
- References Docker Hub — images are on Quay.io
- Shows old file layout that doesn't match `kargo/templates/` + `kargo/generated/` structure

**Fix:** Update the doc to match reality or mark it as aspirational.

---

## Nits

| # | Issue | Where |
|---|-------|-------|
| **N1** | `GetHostname` uses `os.Getenv("HOSTNAME")` instead of idiomatic `os.Hostname()` — empty on scratch containers | `projects/red/internal/name/name.go:7` |
| **N2** | `version.go` default GitCommit has a trailing `q` — not valid hex | `projects/red/internal/version/version.go:7` |
| **N3** | Inconsistent default config paths — red uses `/app/config/...`, blue uses `./...` | `projects/red/webcolor_ff.go` vs `projects/blue/webcolor_ff.go` |
| **N4** | Hand-rolled Prometheus format in metrics endpoint — no `Content-Type` header | `projects/red/webcolor_ff.go:226-238` |
| **N5** | `kindest/node:v1.35.0` referenced in Kind config doesn't exist yet | `k8s/kind-config.yaml:8` |
| **N6** | Credential `repoURL` patterns broader than needed (`https://github.com/*` vs `https://github.com/davidaparicio/*`) | `kargo/git-credentials.yaml:12` |
| **N7** | Dockerfile `-installsuffix cgo` is a no-op since Go 1.10 | `projects/*/docker/Dockerfile` |
| **N8** | `minMs` tracking conflates "never recorded" with "recorded 0ms" | `projects/red/webcolor_ff.go:48` |
| **N9** | `GetNamespace` uses unnecessary bare `{}` block scoping to reuse variable names | `projects/red/internal/name/name.go:12-24` |
| **N10** | git-sync sidecar uses `:latest` tag in dev and staging overlays — not managed by Kargo | `k8s/overlays/development/red/kustomization.yaml:48` |

---

## What's Done Well

- **Kargo template system** (`config.yaml` + `generate.sh` + `envsubst`) is clean and DRY — easy to add new services
- **ArgoCD ApplicationSet** matrix generator with conditional auto-sync via `templatePatch` is elegant
- **Progressive delivery pipeline** (dev auto -> staging auto -> prod manual) is sound
- **Multi-stage Docker builds** with pinned digests — good supply chain hygiene
- **Resource limits set everywhere** — no unbounded pods
- **Health probes on every deployment** with proper liveness/readiness differentiation
- **Pre-commit hooks** (gitleaks, golangci-lint, shellcheck) enforce quality at commit time
- **`install.sh`** is well-structured — idempotent, argument parsing, dependency checks, color output
- **Generated Kargo manifests committed to git** for PR visibility — good tradeoff
- **Comprehensive CI/CD** with CodeQL, dependency review, OSSF scorecard, and multi-arch builds
- **Feature flag integration** via GO Feature Flag is well-done with proper polling and fallback

---

## Top 3 Priorities

1. **Security contexts on deployments** — highest impact, lowest effort
2. **Extract shared Go code** — the 4x duplication is the biggest maintenance risk
3. **Fix the git-sync ArgoCD gap** — it's a broken pipeline nobody will notice until a promotion fails

---

## Refactoring Opportunities: Code Duplication

**Date:** 2026-04-11

### Duplication Landscape

| Area | Duplicated Lines | Type | Notes |
|------|-----------------|------|-------|
| Go source (`internal/`, `webcolor_ff.go`) | ~937 | Mechanical | `internal/name`, `internal/version` 100% identical; `webcolor_ff.go` differs (red has metrics) |
| Makefiles | ~656 | Mechanical | Only version/package paths differ |
| Dockerfiles | ~144 | Mechanical | Only import paths differ |
| K8s overlays (dev/staging/prod) | ~480 | Mechanical | Only namespace/image/hostname differ |
| Kargo (generated) | ~730 | Generated | Already templated via `generate.sh` — least urgent |
| **Total** | **~3,300** | — | ~2,200 manual + ~730 generated |

GitHub Actions CI and ArgoCD ApplicationSet are already DRY. Kargo uses templates + generation. The problem is concentrated in **Go code, build files, and K8s overlays**.

### Proposition 1 — Extract shared Go packages (low risk, high value)

`internal/name/` and `internal/version/` are byte-for-byte identical across all 4 color services. Move them to a top-level `pkg/name/` and `pkg/version/` module. Each service imports from the shared location instead of owning a copy.

`webcolor_ff.go` is trickier — blue/green/yellow are identical, red adds ~73 lines of metrics. Extract a shared `pkg/webcolor/` with the common logic, and have red compose on top.

- **Effort**: small
- **Risk**: low — just import path changes
- **Saves**: ~250 lines of identical Go code, plus future drift prevention

### Proposition 2 — Single root Makefile with per-service targets (medium risk, medium value)

Replace 4 identical Makefiles with one root `Makefile` that takes `PROJECT=red` as a parameter (or auto-discovers from directory). Each `projects/<color>/` keeps a thin 3-line Makefile that delegates to the root.

Same approach for Dockerfiles — a single `Dockerfile.template` with build args.

- **Effort**: medium
- **Risk**: medium — CI references `make` per-service today
- **Saves**: ~800 lines, simplifies "fix in one must be replicated to all four"

### Proposition 3 — Consolidate K8s overlays with Kustomize components (medium risk, medium value)

The dev/staging/prod overlays for each service are copy-paste with name substitution. Kustomize `components` or a shared overlay base with per-service `namePrefix` and vars could collapse this. Needs careful testing since ArgoCD watches these paths.

- **Effort**: medium
- **Risk**: medium — ArgoCD sync paths and Kargo git commits target specific overlay directories
- **Saves**: ~480 lines

### Proposition 4 — Copier template engine (evaluated, prototype in [#147](https://github.com/davidaparicio/microsvcs/pull/147))

[Copier](https://github.com/copier-org/copier) is a project templating tool with a native **update mechanism** — it propagates template changes to already-generated projects via 3-way merge, preserving per-project customizations. That's exactly the "fix in one must be replicated to all four" problem.

A Copier template for the color services would look like:

```text
template/
├── copier.yml              # questions: color, has_metrics, config_path...
├── webcolor_ff.go.jinja
├── internal/name/name.go
├── internal/version/version.go
├── Makefile.jinja
└── docker/Dockerfile.jinja
```

**PR [#147](https://github.com/davidaparicio/microsvcs/pull/147)** (`claude/reduce-duplication-copier-eVqcG`) is an open prototype implementing this approach with two templates:

- **`copier-microservice-template/`** — renders `Makefile`, `Dockerfile`, `.dockerignore`, and `go.mod` from a single parameterized source (8 questions: service name, org, module root, Go version, etc.)
- **`copier-k8s-overlay-template/`** — generates all three kustomization.yaml overlays (dev/staging/prod) per service from one template (5 questions: service name, domain suffix, image tags per env)

The PR also extracts a shared `projects/Makefile.common` (173 lines) and reduces each service Makefile from ~165 lines to a 5-line stub with `include` — a **73% reduction** (660 -> 180 lines). Each service gets a `.copier-answers.yml`, and K8s overlays get per-service `.copier-answers-<color>.yml` files.

**What the PR covers:**

| Area | Before | After |
|------|--------|-------|
| Makefiles | 4 x 165 lines (copy-paste) | 1 x 173 (common) + 4 x 5 (stubs) |
| Dockerfiles | 4 x 36 lines (copy-paste) | Jinja template + answers |
| K8s overlays | Copy-paste per env per service | Template + per-service answers |

**What the PR does NOT cover:** Go source files (`webcolor_ff.go`, `internal/`) — the highest-value duplication remains untouched.

**Pros:**

- Solves the propagation problem directly — fix shared logic once, run `copier update` per service
- Handles the "95% identical, 5% different" case well via Jinja conditionals (red's metrics block)
- Each service gets a `.copier-answers.yml` tracking which template version it was generated from
- **Proven by prototype** — PR #147 demonstrates the approach works for Makefiles and K8s overlays

**Cons:**

- **Adds a generation step to a monorepo** — the template becomes the source of truth, editing generated Go files directly is now wrong. Every contributor must learn this workflow change.
- **Overkill for identical files** — `internal/name/` and `internal/version/` are byte-for-byte identical. A shared `pkg/` import (proposition 1) solves this with zero tooling.
- **Jinja in Go files breaks IDE support** — no syntax highlighting, no `gopls`, no `go vet` on `.go.jinja` templates.
- **Merge conflicts on direct edits** — if someone edits a generated file (and they will), `copier update` creates `.rej` files, adding a resolution workflow on top of git.
- **Yet another tool** — the stack is already Go + Kustomize + ArgoCD + Kargo + Kind + GitHub Actions. Adding a Python-based templating tool for 4 services is a high tool-to-service ratio.

**Verdict1:** The Makefile.common extraction in PR #147 is valuable regardless of Copier adoption (proposition 2 achieves the same). The Copier layer on top is the right tool for **many independent repos** generated from a common template (e.g., 50 microservices across separate git repos). For 4 services in a monorepo, native Go modules + parameterized Makefiles (propositions 1-2) give 90% of the benefit with zero new tooling. **Keep Copier in the back pocket** for if/when the repo grows to 10+ services or spawns separate repos.

**Verdict2: Copier doesn't earn its complexity at this scale.** Here's what it's actually templating vs what already has native solutions:

| Templated by Copier | Native alternative | Winner |
|----------------------|--------------------|--------|
| Makefiles (5-line stubs) | `Makefile.common` + `include` — no template engine needed | Native |
| Dockerfiles (1 line differs) | Single `Dockerfile` with `--build-arg SERVICE=red` | Native |
| `go.mod` | Should diverge per service as deps evolve — templating fights Go modules | Native |
| K8s overlays | Kustomize components solve this without a second templating layer | Native |
| Go source files | **Not covered by PR #147** — and this is where Jinja works worst (breaks IDE) | N/A |

Copier adds a Python dependency, `.copier-answers.yml` in every directory, a new contributor workflow, and `.rej` file resolution — to template files that either have simpler native solutions or aren't being templated at all.

**Actionable outcome for PR [#147](https://github.com/davidaparicio/microsvcs/pull/147):**

1. **Cherry-pick commit `e4c5496`** (`Makefile.common` extraction) — that's solid, standalone work worth merging
2. **Close the rest of the PR** as superseded by propositions 1-2
3. **Revisit Copier** if service count hits 10+ or services move to separate repos

### Recommended Order

1. **Proposition 1** first — safest, most impactful, directly addresses the known issue of "a fix in one must be replicated to all four"
2. **Proposition 2** next — cherry-pick `Makefile.common` from PR #147, add `Dockerfile` build args
3. **Proposition 3** last — highest blast radius (ArgoCD + Kargo path dependencies), defer until 1 and 2 are stable
4. **Proposition 4** — deferred. Copier is a scaling tool, and 4 services in a monorepo isn't the scale where it earns its complexity
