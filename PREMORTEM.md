# Project Premortem: microsvcs

**Date:** 2026-06-16
**Method:** Premortem (prospective hindsight)
**Companion doc:** [`REVIEW.md`](./REVIEW.md) — a retrospective code review of the *current* state. This document is its mirror image: it imagines the *future* and asks why the project failed.

---

## What is a premortem?

A retrospective asks "what went wrong?" *after* a failure. A **premortem** asks it *before*:

> It is **June 2027**. The microsvcs platform is widely considered a failure — abandoned, breached, or quietly replaced. Looking back, it is obvious why. What happened?

By imagining failure as a certainty and working backward, we surface risks that optimism normally hides. Each scenario below is rated by **likelihood** (how plausible) and **impact** (how bad), followed by the **early warning signs** that would tell us it is happening and the **preventive action** that defuses it.

This project has two distinct failure modes, and they must not be conflated:

- **As a demo / reference platform** (its stated purpose): failure = nobody can run it, nobody trusts it, or it teaches the wrong lessons.
- **As a template someone forks into real production**: failure = it gets breached, has an outage, or silently ships broken releases.

The most dangerous risks are the ones that bridge the two — where the demo's shortcuts become a production incident the day someone takes it seriously.

---

## Risk matrix

| ID | Failure scenario | Likelihood | Impact | Class |
|----|------------------|:---------:|:------:|-------|
| F1 | The "false green" pipeline ships a broken release | High | High | 🔴 Critical |
| F2 | First real production promotion crash-loops (red config path) | High | High | 🔴 Critical |
| F3 | A security fix lands in 3 of 4 services; the 4th is breached | Med | High | 🔴 Critical |
| F4 | Compromised pod walks the cluster (root + no NetworkPolicy) | Med | High | 🟠 Major |
| F5 | Someone runs the demo as production (admin/admin, `:latest`, forged tokens) | Med | High | 🟠 Major |
| F6 | New user can't install it; adoption dies on first impression | High | Med | 🟠 Major |
| F7 | Docs drift makes the platform untrustworthy | High | Med | 🟡 Moderate |
| F8 | Deferred ArgoCD major bump becomes a forced emergency upgrade | Med | Med | 🟡 Moderate |
| F9 | Scope creep dilutes the demo into an unmaintainable grab-bag | Med | Med | 🟡 Moderate |
| F10 | Bus factor / knowledge concentration; project stalls | Med | Med | 🟡 Moderate |

---

## Critical scenarios

### F1 — The "false green" pipeline shipped a broken release

**The story we tell in 2027:** "Dev and staging were green for months. Everyone trusted them. Then a change that worked in 'staging' destroyed production — because staging had never actually deployed anything. The green was fake."

git-sync's dev and staging Kargo stages commit to Git but have **no `argocd-update` step**, and git-sync is **deliberately excluded from the ArgoCD ApplicationSet** (`argocd/applicationset.yaml` lists only red/blue/green/yellow). The stages report healthy without deploying. This is documented as a known issue today — which is exactly how known issues become incidents: they are tolerated until the day they aren't.

The deeper trap is *cultural*: a green stage that doesn't deploy teaches operators to trust a signal that means nothing. Once that trust is calibrated wrong, it transfers to every other service.

- **Likelihood: High** — the gap exists right now and is invisible by design.
- **Impact: High** — a false promotion signal is worse than a red one.
- **Early warning signs:** a Kargo stage goes green but `kubectl get pods -n git-sync-*` shows nothing changed; promotion freshness never matches the committed SHA; the production stage (which *does* have `argocd-update`) fails while dev/staging stay green.
- **Preventive action:** resolve the inconsistency in one direction — either add git-sync to the ApplicationSet and an `argocd-update` step to its stages, **or** remove git-sync from `kargo/config.yaml` entirely so no orphan stages exist. Half-wired is the failure state. (Tracks REVIEW.md **B5**.)

### F2 — The first real production promotion crash-looped

**The story:** "Red ran fine in dev and staging for a year. The first time we promoted it to a production without the git-sync sidecar, it crash-looped on startup and we couldn't figure out why — the image was 'identical' to staging."

Red's `webcolor_ff.go:84` defaults its flag file to `/app/config/demo-flags.goff.yaml`, while the image bakes the file at `/app/demo-flags.goff.yaml` (where blue/green/yellow look). Red only works because the dev/staging git-sync sidecar happens to mount config at `/app/config/`. Production has no sidecar, so red can't find its flags. **The environment is silently load-bearing for the application to boot.** This is the most insidious kind of bug: it is invisible in every environment except the one that matters.

- **Likelihood: High** — it is a latent defect waiting for the exact promotion path that exercises it.
- **Impact: High** — production outage on a service that "passed" every prior gate.
- **Early warning signs:** red works in dev/staging but only there; any config that differs between red and the other three colors; a production manifest that lacks something dev/staging silently provide.
- **Preventive action:** make red's default path match the baked-in location (`./demo-flags.goff.yaml`) so it boots without the sidecar; add a test/CI check that each service starts from its own image with **no** sidecar. (Tracks CLAUDE.md "Red config path divergence" + REVIEW.md **N3**.)

### F3 — A security fix landed in 3 of 4 services; the 4th was breached

**The story:** "We patched the vulnerability the day it dropped. We just missed one service. That's the one that got popped."

`webcolor_ff.go`, `internal/name/`, and `internal/version/` are near-identical across all four color services (~937 duplicated lines), and red has extra metrics code that has *already* drifted (the config-path bug in F2). CLAUDE.md states the rule plainly: "A fix in one must be replicated to all four." That is a process that depends on a human remembering, under pressure, four times in a row. Eventually someone won't.

- **Likelihood: Med** — every duplicated fix is a coin flip; do it enough times and drift is certain.
- **Impact: High** — partial patching is a classic incident root cause.
- **Early warning signs:** a PR touches `webcolor_ff.go` in some but not all services; diffs between the four `internal/` trees grow; "we'll backport later" appears in review.
- **Preventive action:** extract the identical code into a shared `pkg/` module so there is exactly one place to fix (REVIEW.md Proposition 1). Until then, add a CI check that fails when the shared files diverge across services. (Tracks REVIEW.md **S3**.)

---

## Major scenarios

### F4 — A compromised pod walked the entire cluster

**The story:** "One service had a dependency CVE. Because every pod ran as root with no network isolation, that single foothold reached everything — including `blue-production`."

The base deployments set **no `securityContext`** (containers run as UID 0 with full capabilities) and there are **zero NetworkPolicies** in the `k8s/` tree, so every pod can reach every other pod cluster-wide. These two together turn any single-pod compromise into full lateral movement.

- **Likelihood: Med** — depends on an initial foothold, but the blast radius is maximal.
- **Impact: High** — cross-environment, cross-service breach.
- **Early warning signs:** `securityContext` still absent at the next security review; new namespaces added with no accompanying NetworkPolicy; image scans flagging base-image CVEs that linger.
- **Preventive action:** add pod/container `securityContext` (runAsNonRoot, drop ALL caps, readOnlyRootFilesystem) and a default-deny NetworkPolicy per namespace. (Tracks REVIEW.md **B1, S1**.)

### F5 — Someone ran the demo as production

**The story:** "A team forked the repo, ran `install.sh`, pointed real traffic at it, and never changed a thing. admin/admin, a committed token-signing key, and `:latest` in production did the rest."

`install.sh` hardcodes `admin/admin` and a committed `tokenSigningKey` (which can forge Kargo admin tokens), production git-sync runs `newTag: latest` (a registry re-tag silently changes what's running with no Git trace), and the Kind node version `v1.35.0` is referenced as if real. These are all fine *for a local demo* — and that is the trap. Demos that look production-shaped get used as production by someone who didn't read the fine print.

- **Likelihood: Med** — "it worked in the demo" is one of the most common paths to a real incident.
- **Impact: High** — credential compromise, non-reproducible deploys.
- **Early warning signs:** issues/discussions asking "how do I expose this publicly?"; forks with the default credentials untouched; `:latest` still pinned in any production overlay.
- **Preventive action:** make demo-vs-production boundaries loud — a prominent "NOT PRODUCTION READY" banner, fail-loud if default secrets are detected outside Kind, pin all production tags to semver. (Tracks REVIEW.md **B2, S2, N5**.)

### F6 — A new user couldn't install it, and adoption died on first impression

**The story:** "People tried `./install.sh`, it errored out, and they closed the tab. A demo that doesn't run on the first try has no second try."

A reference platform lives or dies on its first-run experience. Known landmines: `kindest/node:v1.35.0` doesn't exist yet (REVIEW.md **N5**), version drift between badges (README says ArgoCD 8.1.4 / Go 1.23 / K8s 1.31 while CLAUDE.md says Go 1.25), and the multi-tool dependency chain (Docker + Kind + kubectl + Helm + cert-manager + NGINX + ArgoCD + Rollouts + Kargo) where any single upstream change breaks the script. The value of this project *is* that it runs in five minutes; the day it doesn't, the project is effectively dead even if the code is fine.

- **Likelihood: High** — pinned-but-nonexistent versions and long tool chains rot quickly.
- **Impact: Med** — no breach, but the project's entire purpose evaporates.
- **Early warning signs:** install.sh failures in issues; stale version pins; no CI job that actually runs `install.sh` end to end.
- **Preventive action:** a CI job (or scheduled workflow) that runs `install.sh` against a real Kind cluster and asserts the dashboards come up; pin Kind to a node image that exists; reconcile version claims across README/CLAUDE.md/badges.

---

## Moderate scenarios

### F7 — Documentation drift made the platform untrustworthy

KARGO.md is already stale (says staging is manual when it's auto; references Docker Hub when images are on Quay.io; shows an old file layout — REVIEW.md **S10**). README badges disagree with CLAUDE.md on Go/ArgoCD versions. For a project whose *product is its documentation*, drift is not cosmetic — it is the failure. Once a reader catches one doc lying, they stop trusting all of them.

- **Likelihood: High** — docs drift unless tied to a check.
- **Impact: Med** — erodes the credibility the demo exists to build.
- **Preventive action:** treat docs as code — reconcile KARGO.md with `kargo/config.yaml`, single-source version numbers, and add the most drift-prone facts to a doc-lint or test.

### F8 — The deferred ArgoCD upgrade became a forced emergency

ArgoCD is pinned at 8.1.4 with 9.5.0 available; the major bump is "deferred until migration notes are reviewed" (CLAUDE.md). Deferred upgrades don't disappear — they compound. The longer the gap, the more breaking changes accumulate, until a CVE or a dropped API forces the upgrade on a bad day instead of a planned one.

- **Likelihood: Med** — deferral is the default, and defaults win.
- **Impact: Med** — a painful, rushed migration; possible downtime.
- **Preventive action:** time-box the deferral (e.g., review migration notes within one release cycle), and let Dependabot surface the gap rather than letting it go silent.

### F9 — Scope creep diluted the demo into an unmaintainable grab-bag

The repo has grown past its "four color services" core: `order-svc` (Postgres, 10 migrations, handlers), a PostgreSQL StatefulSet, and a recently *removed* `sreportal` tool (`df947e4`). Each addition is reasonable alone, but a demo that tries to demonstrate everything demonstrates nothing, and the maintenance surface grows faster than the (apparently single-maintainer) capacity to keep it green.

- **Likelihood: Med** — the commit history already shows the pattern (wip → fix → remove).
- **Impact: Med** — the clear teaching value blurs; half-finished pieces signal neglect.
- **Preventive action:** define what is *core* vs *experimental*; quarantine experiments behind a clear label or separate directory; be willing to delete (as was done with sreportal).

### F10 — Bus factor: the project stalled when attention moved on

This is a personal/portfolio platform with heavy reliance on AI-assisted review (REVIEW.md, CLAUDE.md). That is efficient, but it concentrates context in one person plus tooling. If that attention moves elsewhere, the deferred upgrades (F8), drift (F7), and known issues (F1–F3) have no one to catch them, and the project decays from "demo" to "abandoned."

- **Likelihood: Med** — typical for single-maintainer projects.
- **Impact: Med** — slow decline rather than a bang.
- **Preventive action:** encode knowledge in CI checks rather than prose (so the project defends itself), keep CLAUDE.md current as the onboarding contract, and keep the core small enough for one person to own.

---

## The five things to do first

If only a handful of preventive actions get taken, take these — they each defuse a 🔴/🟠 scenario at low cost:

1. **Resolve the false-green pipeline (F1):** wire git-sync into ArgoCD *or* remove it from Kargo. No half-states.
2. **Fix red's config path (F2):** default to the baked-in location and CI-test that every service boots from its own image with no sidecar.
3. **Add `securityContext` + default-deny NetworkPolicy (F4):** highest security impact, lowest effort.
4. **De-duplicate shared Go code into `pkg/` (F3):** make "fix it once" the default instead of "remember to fix it four times."
5. **CI-run `install.sh` end to end (F6):** protect the five-minute first-run that the whole project depends on.

## The single most likely epitaph

> "Everything was green, so we trusted it — right up until the one thing that was actually running broke."

Three of the top scenarios (F1, F2, F3) share a root cause: **a signal that says "fine" without verifying it.** A stage that's green without deploying, a service that boots only because the environment quietly props it up, a fix that's "done" in three places out of four. The cheapest insurance this project can buy is to make its green signals *mean something* — by turning each tolerated known issue into either a fix or a failing test, before it turns into the story we tell in 2027.
