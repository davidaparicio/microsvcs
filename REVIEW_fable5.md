# Project Review — microsvcs

**Reviewer:** Claude Fable 5 (Claude Code)
**Round 1:** 2026-07-03 — full repository review
**Round 2:** 2026-07-05 — post-remediation re-check + deeper pass (Makefiles, scripts, ArgoCD project, docs)
**Scope:** All Go services, k8s/ArgoCD/Kargo config, CI workflows. Builds, tests, kustomize rendering, and hardened-container runtime behavior were validated, not just read.

**TLDR (as of round 2):** The three top-priority fixes from round 1 are merged to `main` (git-sync overlays render, securityContexts everywhere, scan-then-push CI), and the open-PR backlog was consolidated: all 21 dependabot bumps + PR #114 landed via #217, with 8 stale feature PRs reviewed and rejected for cause. What remains open: the `color/` duplicate directory, the dependabot gaps, the CI Go-version mismatch introduced by the dependency bumps, and the long-standing items from the April REVIEW.md (git-sync concurrency bugs, install.sh secrets, NetworkPolicies, shallow tests).

---

## Fix tracker

| Finding | Status |
|---|---|
| 1. git-sync overlays fail kustomize load restrictor | ✅ Fixed (`bbeadaa`) — all 15 overlays render |
| 2. Images pushed before blocking Trivy scan + duplicate Trivy steps | ✅ Fixed (`efdab4e`) — build→scan→push, single SARIF gate |
| B1 (April). No securityContext | ✅ Fixed (`f038700`) — pod+container on both bases and the red sidecar, runtime-verified under `--read-only --user 65534 --cap-drop ALL` |
| 3. `color/` fifth duplicate with dead workflow | ⬜ Open |
| 4. order-svc CI/CD blind spot | ⬜ Open (no CI matrix entry, no dependabot, no release-please, absent from CLAUDE.md) |
| 5. Dependabot gaps (`github-actions` ecosystem, order-svc) | ⬜ Open — note the action pins (checkout v7, gitleaks v3) had to be bumped by hand, which is exactly what the missing ecosystem entry would automate |
| 6. `detect-changes` breaks on zero SHA (force-push/first push) | ⬜ Open |
| 7a. `commonLabels` deprecated | ⬜ Open (warning on every render) |
| 7b. Pre-commit hooks stale (golangci-lint v1.52.2, gitleaks v8.16.3) | ⬜ Open — now further out of sync with CI's gitleaks-action v3 |
| 7c. Toolchain drift across go.mod / CI / Dockerfile | ✅ Fixed — Dockerfile digest refreshed in #217; CI now uses `go-version-file` (see R2-1) |
| 7d. CLAUDE.md claims `/readyz` on color services | ⬜ Open (only `/`, `/version`, `/healthz`, `/metrics` exist; probes correctly use `/healthz`) |
| 7e. `.plumber.yaml` configures `gitlab:` controls on a GitHub repo | ⬜ Open |
| PR backlog (30 open PRs) | ✅ Consolidated via [#217](https://github.com/davidaparicio/microsvcs/pull/217) (merged 2026-07-03); #174/#188 merged individually after |

---

## Round 2 — new findings (2026-07-05)

### R2-1. CI Go version now mismatches the modules (medium) — ✅ fixed 2026-07-07

The #217 dependency bumps raised the color modules' `go` directive to **1.26.4** (required by go-feature-flag 1.55.0), and the Dockerfile digest was refreshed to match. But `ci.yaml` still pins `go-version: '1.25'` in all three jobs. It doesn't fail — Go's auto-toolchain downloads 1.26.4 on every run — but that's a silent per-job toolchain download and a version pin that no longer means what it says.

**Fix applied:** all three `ci.yaml` jobs now use `go-version-file: projects/${{ matrix.project }}/go.mod`, so CI always follows each module's declared toolchain (actionlint-validated).

### R2-2. Makefile has broken targets, copy-pasted 5× (low)

In `projects/{red,blue,green,yellow}/Makefile` and `color/Makefile`:

- `goreleaser:` runs `go run github.com/goreleaser/v2@v2.3.2` — wrong module path (the v2 module is `github.com/goreleaser/goreleaser/v2`); the target fails as written.
- `hack:` runs `examples/slowloris/main.go`, which doesn't exist anywhere in the repo.
- `check-editorconfig:` uses `$(shell PWD)` — that executes a command named `PWD` (not the variable), yielding an empty volume path; should be `$(CURDIR)`.
- Header says "Creative Commons 4.0 by-nc" while `license ?= MIT` a few lines below.

None block the used targets (`compile/test/lint/sec` are fine — CI passes), but every defect exists in five copies. More weight for the shared-Makefile extraction (April S3/proposition 2).

### R2-3. The repo requires two incompatible `yq`s (low)

`scripts/get-env.sh` and `scripts/show-env.sh` use Python yq (jq syntax; one says `pip install yq`, the other `snap install yq`), while `kargo/generate.sh` requires mikefarah Go yq. Same command name, different tools — whichever one is on PATH breaks the other consumer. Worth standardizing on Go yq (the kargo dependency) and porting the two scripts' `.images[0].newTag` queries.

### R2-4. Housekeeping (low)

- `scripts/show-env.sh` header comment says `get-env.sh` (copy-paste).
- **PR #114 still shows open** on GitHub even though its commit merged via #217 — GitHub didn't auto-detect; close manually. The other 8 rejected feature PRs (#86, #111–#113, #116–#118, #147, #166) also remain open with documented reasons in #217.
- `KARGO.md:414` still references a `docker.io/*` repo-url-pattern (registry is Quay) — part of the April S10 staleness.
- `argocd/project.yaml` whitelists `HorizontalPodAutoscaler`, which nothing deploys — harmless, but it invites a base-level HPA like rejected PR #116's, which would fight Kargo-managed replicas.

### R2-5. Verified healthy in round 2 (no action)

- `kargo/generate.sh` output is **in sync** with `kargo/generated/` — no drift between config and committed manifests.
- All 15 overlays render post-merge; rendered output keeps image pins, `SYNC_INTERVAL` patches, and securityContexts intact.
- All 7 Go modules build and test green on the bumped dependency set.
- `scripts/get-env.sh` / `show-env.sh` logic is sound (uncommitted-changes guard, SHA/semver/latest tag resolution).
- `projects/git-sync/internal/config/config.go` is clean.

---

## Round 1 findings (2026-07-03) — detail

*(statuses per the tracker above)*

### 1. All git-sync overlays fail to render — ✅ fixed

`k8s/overlays/{development,staging,production}/git-sync/kustomization.yaml` referenced individual files (`../../../base/git-sync-deployment.yaml`). Kustomize's load restrictor forbids file references outside the kustomization root, so all three environments failed to render — meaning even if git-sync were uncommented in the ApplicationSet, ArgoCD would fail. Fixed by moving the manifests into `k8s/base/git-sync/` with their own kustomization (matching the color-service structure) and referencing the directory.

### 2. Images pushed before the blocking vulnerability scan — ✅ fixed

`build-and-publish.yaml` pushed (including `:latest`) before the `exit-code: 1` Trivy scan, so a CRITICAL finding failed the job after the vulnerable image was public — and Kargo's dev warehouse would auto-promote the `sha-*` tag. There were also two Trivy steps at two different pinned versions scanning the same image. Fixed: amd64 build with `load: true` → single Trivy scan (SARIF + `exit-code: 1`, upload on `if: always()`) → multi-arch push from cache → cosign + SLSA only after a clean scan.

### 3. `color/` is a fifth copy of the color service with a dead workflow — ⬜ open

Tracked root-level `color/` duplicates the whole service (module `github.com/davidaparicio/color`, own release-please manifest/CHANGELOG). Its `color/.github/workflows/release.yaml` can never run — GitHub only executes workflows from the repo root. Its only live role: dev/staging git-sync sidecars pull `color/demo-flags.goff.yaml` as the flag source (deliberately outside CI's `projects/**` path filter, so flag flips don't trigger builds). Recommendation stands: strip to the flag file + README; delete the dead workflow and release-please manifest.

### 4. `order-svc` exists in a CI/CD blind spot — ⬜ open

Not in either workflow's matrix, dependabot, release-please, or CLAUDE.md. Code quality is fine for a PoC (parameterized queries, transaction with rollback, graceful shutdown; the breaking migration is intentional pedagogy per `poc.md`). Money as `float64` against `NUMERIC(10,2)` (`orders.go:159`'s rounding is the tell) and no stock check/row lock in `CreateOrder`.

### 5. Dependabot gaps — ⬜ open

No `github-actions` ecosystem entry (all actions SHA-pinned but nothing updates the pins — the recent manual checkout-v7/gitleaks-v3 bumps prove the cost), no order-svc gomod entry, while the vestigial `color/` gets two entries.

### 6. `detect-changes` breaks silently on force-push/first push — ⬜ open

Both workflows diff against `github.event.before` (zero SHA in those cases); the diff fails and the pipeline silently builds nothing. Use `dorny/paths-filter` or fall back to `HEAD~1`.

### 7. Smaller items — ⬜ open except toolchain (see R2-1)

- `commonLabels` deprecated in every kustomization.
- Pre-commit hooks stale: golangci-lint v1.52.2, gitleaks v8.16.3 — local checks diverge from CI.
- CLAUDE.md claims `GET /readyz` on color services — none register it (probes correctly target `/healthz`; doc-only error). CLAUDE.md structure also omits `order-svc` and `color/`.
- `.plumber.yaml` configures `gitlab:` controls but CI is GitHub Actions — verify the Plumber run evaluates anything.

---

## Open-PR review & consolidation (2026-07-03 → merged)

All 30 open PRs were reviewed. **Included in [#217](https://github.com/davidaparicio/microsvcs/pull/217)** (merged): the 21 dependabot bumps — applied via `go get` because they were mutually inconsistent (goff 1.55/echo 4.15.4 require x/net ≥ 0.56.0, superseding the seven 0.55.0 PRs) — plus **#114** (CA certificates in scratch images). The bumps forced a refresh of the pinned `golang:1.26-alpine3.23` digest (1.26.0 → 1.26.4), which is also why several dependabot PRs had unstable CI.

**Excluded for cause** (still open; suggest closing):

- **#112, #166** — superseded by `f038700`; #166 lacks the `/tmp` emptyDir and would crash-loop git-sync; targets a file that no longer exists.
- **#113** — `../resourcequota.yaml` references trip the kustomize load restrictor (same bug class as finding 1); would break every overlay.
- **#116** — HPA (min 2) and PDB in the base fight Kargo-managed replicas and block node drains in 1-replica dev.
- **#86** — Rollout pod templates carry none of the securityContext hardening; Deployment→Rollout is an architecture decision.
- **#111** — landing service not in the ApplicationSet; predates hardening.
- **#117, #118** — right ideas (S2 install.sh secrets, runbook) but conflict with today's tree; redo fresh.
- **#147** — per REVIEW.md's standing verdict: cherry-pick `Makefile.common`, don't adopt Copier at this scale.

---

## Status of the April REVIEW.md findings (as of round 2)

**Fixed:** B1 (securityContexts, `f038700`), B2 (git-sync prod pinned), N5 (kind image exists).

**Fixed 2026-07-06/07 (in working tree):**

- **B3/B4/S9 — git-sync bugs:** `Sync` now serializes on a dedicated `syncMu` and takes the status lock only to update fields (probes answer instantly mid-clone, regression-tested); `shortCommit()` guards the log slice; `Client.Close()`/`Syncer.Close()` remove the temp workdir (deferred in main). Verified with `-race`, e2e clone tests, and a hardened-container run.
- **S2 — `install.sh` secrets:** admin password hashes are now overridable via env or `kargo/.env` (defaults remain bcrypt("admin") for the throwaway demo cluster); the Kargo `tokenSigningKey` is **randomly generated per install** unless explicitly pinned — the forgeable fixed key is gone. Verified with stubbed kind/kubectl/helm runs: key differs across installs, overrides propagate, shellcheck clean.

**Still open, in priority order:**

- **S1 — no NetworkPolicies** anywhere.
- **S6 — env-var patches by array index** (`env/4/value`) in git-sync overlays; base env order is now load-bearing.
- **S3 — code duplication**, still 5 copies including `color/`; round-2 Makefile defects (R2-2) add weight.
- S4 (assert-not-nil tests — unchanged, 5 test funcs of which 4 assert construction), S5 (sidecar patch duplicated dev/staging), S7 (no PDB), S8 (no startupProbe), S10 (KARGO.md staleness, incl. `docker.io` reference).

---

## Secrets check (round 1, still current)

`kargo/.env` holds live GitHub/DockerHub/Quay tokens but is gitignored and has **never been committed** (verified against full history). Credential YAMLs are `${VAR}` templates. The committed Postgres demo password in `k8s/db-postgresql.yaml:65` is documented and gitleaks-ignored — acceptable for a local Kind demo. No rotation needed.

---

## What's working well

- Kargo `config.yaml` → `generate.sh` → committed `generated/` pipeline (verified drift-free in round 2); `envsubst` with an explicit variable allowlist so Kargo `${{ }}` expressions survive.
- ApplicationSet matrix with `templatePatch` for conditional auto-sync.
- Supply-chain CI: cosign keyless + SLSA provenance + scoped build caches + hardened runners — now with the scan actually gating publication.
- `install.sh`: idempotent, graceful degradation, clear next steps.
- Hardened runtime posture verified end-to-end: color service and git-sync both run correctly as uid 65534 with read-only rootfs and no capabilities.
- Responsive maintenance: round-1 top-3 fixes landed within hours, plus proactive follow-ups (checkout v7, gitleaks-action v3).

---

## Top 3 remaining priorities

1. ~~**git-sync correctness bugs (B3/B4/S9)**~~ ✅ fixed 2026-07-06 (see April-findings status above).
2. ~~**`install.sh` secrets (S2)**~~ ✅ fixed 2026-07-07 (see April-findings status above).
3. ~~**CI Go version (R2-1)**~~ ✅ fixed 2026-07-07 — all three jobs use `go-version-file`.

All three priorities are done. Next candidates: NetworkPolicies (S1), the `color/` cleanup (finding 3), and the dependabot gaps (finding 5).
