# Project Review — microsvcs

**Date:** 2026-07-03
**Reviewer:** Claude Fable 5 (Claude Code)
**Scope:** Full repository — all Go services, k8s/ArgoCD/Kargo config, CI workflows. Builds, tests, and kustomize rendering were validated, not just read.

**TLDR:** The platform is in good shape overall — all five Go services build and pass tests, the Kargo template system is clean, and the supply-chain CI (cosign, SLSA, Trivy, pinned actions) is genuinely strong. But there is one **new broken thing**: none of the three git-sync kustomize overlays actually build. And most of the issues from the April `REVIEW.md` self-assessment are still open, including all the security ones. Two newer additions (`color/` and `order-svc`) live outside the CI/docs umbrella entirely.

---

## New findings (not in the April REVIEW.md)

### 1. All git-sync overlays fail to render — verified broken

`k8s/overlays/{development,staging,production}/git-sync/kustomization.yaml` reference individual files (`../../../base/git-sync-deployment.yaml`). Kustomize's load restrictor forbids file references outside the kustomization root, so `kubectl kustomize` errors out in all three environments (verified: `development/git-sync FAILED`, `staging/git-sync FAILED`, `production/git-sync FAILED`). The color overlays are fine because they reference the `../../../base` *directory*.

This means even if git-sync were uncommented in the ApplicationSet to fix the known "false green" issue, ArgoCD would immediately fail to render it.

**Fix:** Move the three git-sync manifests into `k8s/base/git-sync/` with their own `kustomization.yaml` and reference the directory.

### 2. Images are pushed before the blocking vulnerability scan

In `.github/workflows/build-and-publish.yaml`, the build step pushes (including `:latest`) at line 182, and the `exit-code: 1` Trivy scan runs after (line 193). A CRITICAL finding fails the job but the vulnerable image is already public and `:latest` already moved — and Kargo's dev warehouse will happily promote the `sha-*` tag.

There are also **two Trivy steps scanning the same image**, pinned to two different action versions (v0.31.0 at line 194, v0.30.0 at line 224) — the second (SARIF) one looks like a merge leftover.

**Fix:** Build with `load: true`, scan, then push. Consolidate to one Trivy version producing both formats.

### 3. `color/` is a fifth copy of the color service with a dead workflow

The tracked root-level `color/` dir duplicates the whole service (module `github.com/davidaparicio/color`, own release-please manifest, own CHANGELOG). Its `color/.github/workflows/release.yaml` **can never run** — GitHub only executes workflows from the repo root's `.github/workflows/`.

Its only live role appears to be that dev/staging git-sync sidecars pull `color/demo-flags.goff.yaml` as the flag source (which is a nice trick — flag flips don't trigger CI since CI filters on `projects/**`). Everything else in there is dead weight that worsens the already-known duplication problem (now 5 copies, not 4). Not mentioned in CLAUDE.md's repo structure.

**Fix:** Strip it down to just the flag file plus a README explaining why it exists; delete the dead workflow and release-please manifest.

### 4. `order-svc` exists in a CI/CD blind spot

Not in either workflow's project matrix, not in dependabot, not in release-please, not in CLAUDE.md. The code itself is decent — parameterized queries throughout, proper transaction with `defer tx.Rollback`, graceful shutdown, and `poc.md` shows the breaking migration is intentional pedagogy.

Notes if it's staying:
- Add a dependabot `gomod` entry and mention it in CLAUDE.md.
- It handles money as `float64` against `NUMERIC(10,2)` columns — the `math.Round(...*100)/100` in `internal/handlers/orders.go:159` is the tell; integer cents or a decimal type would be cleaner.
- `CreateOrder` reads product prices without any stock check or row lock.

### 5. Dependabot gaps

No `github-actions` ecosystem entry — every action is SHA-pinned (good) but nothing updates those pins. No `order-svc` entry. Meanwhile the vestigial `color/` gets two entries.

### 6. `detect-changes` breaks silently on force-push/first push

Both workflows diff against `github.event.before`, which is the zero SHA in those cases; the `git diff` fails and the pipeline silently builds nothing. `dorny/paths-filter` or a fallback to `HEAD~1` fixes it.

### 7. Smaller items

- `commonLabels` is deprecated in every kustomization (warnings on every render) — mechanical `kustomize edit fix`.
- Pre-commit hooks are badly stale: golangci-lint `v1.52.2` (CI uses the v2-era action) and gitleaks `v8.16.3` — local checks no longer match CI behavior.
- Dockerfiles build with `golang:1.26-alpine` while `go.mod` says 1.25.8 and CI pins `'1.25'` — three different toolchains for one binary.
- CLAUDE.md says every color service exposes `GET /readyz` — none do (only `/`, `/version`, `/healthz`, `/metrics`; the k8s readiness probe correctly targets `/healthz`, so only the doc is wrong).
- `.plumber.yaml` configures `gitlab:` controls, but this repo's CI is GitHub Actions — worth double-checking the Plumber run is actually evaluating anything.

---

## Status of the April REVIEW.md findings

**Fixed:** B2 (git-sync prod now pinned to `0.2.3`) and N5 (kind node `v1.35.1` exists).

**Everything else is still open.** The ones to stop deferring:

- **B1 — still no `securityContext` anywhere** (`k8s/base/deployment.yaml`, `git-sync-deployment.yaml`). Containers run as root with full caps. Still the highest-value, lowest-effort fix in the repo.
- **B3/B4/S9 — git-sync concurrency and panic bugs unchanged:** `internal/sync/syncer.go:41` still holds the write lock across the whole clone/pull so probes hang during sync; `syncer.go:68` still does `commit[:7]` unguarded (any future path returning a short/empty commit panics); `internal/git/client.go` still leaks its temp workdir with no `Close()`.
- **S2 — `install.sh:175,210-211`** still hardcodes admin bcrypt hashes and the Kargo `tokenSigningKey` (`iwishtowashmyirishwristwatch`), which can forge admin tokens on any cluster installed from this script.
- **S6 — fragile index patches spread:** git-sync production overlay patches `env/4/value` to change `SYNC_INTERVAL`; one reordering of env vars in the base and it silently rewrites the wrong variable.
- **S3 — duplication got worse**, not better (the `color/` copy). The REVIEW.md analysis and PR #147 verdict were sound; proposition 1 (shared `pkg/`) still hasn't happened. `version.go` even still carries the invalid-hex `q` typo in all copies.
- S1 (no NetworkPolicies), S4 (assert-not-nil tests), S5 (sidecar patch duplicated), S7 (no PDB), S8 (no startupProbe), S10/KARGO.md staleness — all unchanged.

---

## Secrets check

`kargo/.env` contains live GitHub/DockerHub/Quay tokens, but it is properly gitignored and **has never been committed** (verified against full history). The credential YAMLs are `${VAR}` templates — fine. The committed Postgres password in `k8s/db-postgresql.yaml:65` is a documented demo value with a `.gitleaksignore` entry — acceptable for a local Kind demo. No rotation needed.

---

## What's working well

- Builds, tests, and vet are green across git-sync, red, and order-svc.
- The Kargo `config.yaml` → `generate.sh` → committed `generated/` pipeline remains the best part of the repo — `envsubst` with an explicit variable allowlist so Kargo's `${{ }}` expressions survive is a nice touch.
- The ApplicationSet matrix with `templatePatch` for conditional auto-sync is elegant.
- The publish pipeline's cosign keyless signing + SLSA provenance + scoped build caches + hardened runners on every job is above-average supply-chain hygiene for a demo repo.
- `install.sh` is genuinely robust — idempotent, graceful degradation when `.env` is missing, clear next-steps output.

---

## Top 3 priorities

1. **Fix the git-sync overlay structure** (finding 1) — it's the only thing verifiably *broken*, and it blocks fixing the known git-sync/ArgoCD gap.
2. **Add securityContexts** (B1) — ten lines of YAML in two base files.
3. **Reorder the publish pipeline to scan-then-push** (finding 2) and dedupe the Trivy steps — right now the gate doesn't gate.
