# Simplified Independent Microservice Release Management

> Trunk-based development with independent service releases, GitOps, and feature flags

## Table of Contents

- [Overview](#overview)
- [Core Principles](#core-principles)
- [Architecture](#architecture)
- [Workflows](#workflows)
- [Daily Operations](#daily-operations)

---

## Overview

This system enables **independent release cycles** for microservices in a monorepo, using:

- **Trunk-Based Development**: All development on `main` branch (no release branches)
- **Tag-Based Releases**: Git tags mark releases (e.g., `blue/2.1.3`)
- **Independent Versioning**: Each service releases at its own pace
- **Immutable Artifacts**: Build once, promote through environments
- **GitOps**: Kustomize files = single source of truth
- **Feature Flags**: Decouple deployment from feature activation

### Key Goals

✅ **Easy to understand**: One branch, one tag scheme, one manifest per service
✅ **Efficient**: Automated DEV deployment, manual staging/production with approval
✅ **Elegant**: No branch proliferation, no dual manifests, clean git history
✅ **Human-readable**: Version numbers in Kustomize files, clear git tags

---

## Core Principles

### 1. Single Branch Model

```
main branch (only branch needed)
    ↓
  All development happens here
    ↓
  Tags mark releases: blue/2.1.3, green/1.5.0, etc.
```

**Benefits:**
- No release branches to maintain
- No GitOps branches needed
- Simple mental model
- Clean git history

### 2. Tag-Based Releases

```
{service}/{version}

Examples:
  blue/2.1.3
  green/1.5.0
  yellow/2.2.0
  red/3.0.8
```

**Single, consistent naming scheme** - no confusion with multiple tag types.

### 3. Independent Service Releases

Each service releases at its own pace:

```yaml
# Production can have completely different versions
production:
  blue:    2.1.3  (latest release)
  green:   1.4.8  (stable, no changes needed)
  yellow:  2.2.0  (recent update)
  red:     3.0.8  (quarterly releases)
```

### 4. Build Once, Deploy Many

```
main → Commit → CI builds image:sha-abc123
                     ↓
                 Tag latest
                     ↓
           Auto-deploy to DEV (sha-abc123)
                     ↓
           Manual promote to STG (2.1.3) ← Same artifact
                     ↓
           Manual promote to PRD (2.1.3) ← Same artifact
```

### 5. Single Source of Truth

**Kustomize files are the ONLY manifest:**

```yaml
# k8s/overlays/production/blue/kustomization.yaml
images:
- name: davidaparicio/blue
  newTag: "2.1.3"  # ← Human-readable version
```

No separate `release-manifests/` directory. ArgoCD reads directly from Kustomize files.

### 6. Environment Progression

```
DEV (automatic)  →  STG (manual)  →  PRD (manual + approval)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Git Repository (single main branch)                    │
│                                                          │
│  main ──●──●──●──●──●──●──●                             │
│          ↑     ↑     ↑                                  │
│     blue/2.1.3 │  yellow/2.2.0                          │
│           green/1.5.0                                    │
│                                                          │
│  k8s/overlays/{env}/{service}/kustomization.yaml        │
│    ↑ Single source of truth ↑                           │
└──────────────────────────────────────────────────────────┘
         │
         ▼
  ┌─────────────┐
  │  ArgoCD     │  Watches main branch
  │  (per env)  │  Auto-syncs every 3 min
  └─────────────┘
         │
         ▼
  ┌─────────────┐
  │ K8s Cluster │  DEV / STG / PRD
  └─────────────┘
```

**Key Components:**

1. **Services**: `blue`, `green`, `yellow`, `red` (independent Go microservices)
2. **Environments**: `development`, `staging`, `production`
3. **Kustomize Overlays**: `k8s/overlays/{env}/{service}/kustomization.yaml` (12 files total)
4. **ArgoCD ApplicationSet**: Generates 12 applications (4 services × 3 environments)
5. **GitHub Actions**: 3 workflows (auto-deploy-dev, promote-staging, promote-production)

---

## Workflows

### Workflow 1: Daily Development (Automatic DEV Deployment)

```bash
# Developer commits to main
cd projects/blue/
vim internal/version/version.go
git add .
git commit -m "feat(blue): add payment method"
git push origin main
```

**What happens automatically:**

1. **CI builds image** (`.github/workflows/build-on-commit.yaml`):
   - Detects `blue` service changed
   - Builds Docker image: `davidaparicio/blue:sha-abc123`
   - Tags as `latest`
   - Pushes to Docker Hub

2. **Auto-deploy to DEV** (`.github/workflows/deploy-dev-auto.yaml`):
   - Detects `blue` changed
   - Waits for image `sha-abc123` to be available
   - Updates `k8s/overlays/development/blue/kustomization.yaml`
   - Changes `newTag` to `sha-abc123`
   - Commits to `main` branch

3. **ArgoCD syncs**:
   - Detects change in kustomization file
   - Deploys to DEV cluster within 3 minutes

**Developer verifies in DEV**, then proceeds to staging promotion if tests pass.

---

### Workflow 2: Promote to Staging (Manual)

**Trigger:** GitHub Actions UI → "Promote to Staging" workflow

**Inputs:**
- Service: `blue`
- Version: `2.1.3` (or leave empty to auto-increment)

**Steps:**

1. **Get current DEV image SHA**:
   - Reads `k8s/overlays/development/blue/kustomization.yaml`
   - Extracts current `newTag` (e.g., `sha-abc123`)

2. **Create version tag**:
   - Creates Git tag: `blue/2.1.3`
   - Pushes to repository

3. **Retag Docker image**:
   - Pulls `davidaparicio/blue:sha-abc123`
   - Tags as `davidaparicio/blue:2.1.3`
   - Pushes version tag to Docker Hub

4. **Update staging kustomization**:
   - Edits `k8s/overlays/staging/blue/kustomization.yaml`
   - Changes `newTag` to `2.1.3`
   - Commits to `main` branch

5. **ArgoCD syncs staging cluster**

**Result:** Version `2.1.3` deployed to staging, ready for testing.

---

### Workflow 3: Promote to Production (Manual + Approval)

**Trigger:** GitHub Actions UI → "Promote to Production" workflow

**Inputs:**
- Service: `blue`
- Version: `2.1.3`

**Steps:**

1. **Validate** (automatic):
   - Verifies version `2.1.3` exists in staging
   - Checks staging deployment age (warns if < 24 hours)
   - Verifies Git tag `blue/2.1.3` exists

2. **Approve** (manual gate):
   - Uses GitHub Environment protection
   - Requires approval from authorized reviewers
   - Shows staging age and version details

3. **Promote** (automatic after approval):
   - Retags image: `davidaparicio/blue:2.1.3` → `davidaparicio/blue:prd-2.1.3`
   - Updates `k8s/overlays/production/blue/kustomization.yaml`
   - Changes `newTag` to `2.1.3`
   - Commits to `main` with deployment record
   - Creates milestone tag: `release-prd-20250119`

4. **ArgoCD syncs production cluster**

**Result:** Version `2.1.3` deployed to production with full audit trail.

---

### Workflow 4: Hotfix

**Scenario:** Critical bug found in production (`blue 2.1.3`)

```bash
# 1. Fix on main (no branching needed!)
git checkout main
git commit -m "fix(blue): critical payment bug"
git push

# 2. CI automatically builds new image

# 3. Promote to staging first (always test!)
gh workflow run promote-staging.yaml \
  -f service=blue \
  -f version=2.1.4

# 4. Test in staging

# 5. Promote to production
gh workflow run promote-production.yaml \
  -f service=blue \
  -f version=2.1.4
```

**No cherry-picking needed!** Just create a new version tag and follow normal promotion flow.

---

## Daily Operations

### Check What's Deployed

```bash
# Check development
yq eval '.images[0].newTag' k8s/overlays/development/blue/kustomization.yaml

# Check staging
yq eval '.images[0].newTag' k8s/overlays/staging/blue/kustomization.yaml

# Check production
yq eval '.images[0].newTag' k8s/overlays/production/blue/kustomization.yaml
```

**Or check all services in one environment:**

```bash
for service in blue green yellow red; do
  echo "$service: $(yq eval '.images[0].newTag' k8s/overlays/production/$service/kustomization.yaml)"
done
```

### List Available Versions

```bash
# List all versions for blue service
git tag -l "blue/*" | sort -V

# List recent releases (all services)
git tag -l "*/[0-9]*" | sort -V | tail -20
```

### Rollback in Production

**Option 1: Update kustomization file**

```bash
# Edit production kustomization
vim k8s/overlays/production/blue/kustomization.yaml

# Change newTag to previous version
# newTag: "2.1.2"  # rollback from 2.1.3

git add k8s/overlays/production/blue/kustomization.yaml
git commit -m "rollback(production): blue 2.1.3 → 2.1.2"
git push

# ArgoCD auto-syncs within 3 minutes
```

**Option 2: Use promote-production workflow**

```bash
# Simply promote the previous version
gh workflow run promote-production.yaml \
  -f service=blue \
  -f version=2.1.2
```

### Monitor Deployments

```bash
# Watch ArgoCD applications
kubectl get applications -n argocd

# Check sync status
argocd app list

# View application details
argocd app get blue-production
```

---

## Key Files Reference

### Repository Structure

```
microsvcs/
├── projects/               # Service source code
│   ├── blue/
│   ├── green/
│   ├── yellow/
│   └── red/
├── k8s/
│   ├── base/              # Shared Kubernetes manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   └── kustomization.yaml
│   └── overlays/          # Environment-specific configs
│       ├── development/   # DEV environment (auto-deployed)
│       │   ├── blue/kustomization.yaml
│       │   ├── green/kustomization.yaml
│       │   ├── yellow/kustomization.yaml
│       │   └── red/kustomization.yaml
│       ├── staging/       # STG environment (manual promotion)
│       │   ├── blue/kustomization.yaml
│       │   ├── green/kustomization.yaml
│       │   ├── yellow/kustomization.yaml
│       │   └── red/kustomization.yaml
│       └── production/    # PRD environment (manual + approval)
│           ├── blue/kustomization.yaml
│           ├── green/kustomization.yaml
│           ├── yellow/kustomization.yaml
│           └── red/kustomization.yaml
├── argocd/
│   ├── applicationset.yaml  # Generates 12 applications (4 services × 3 envs)
│   └── project.yaml         # ArgoCD project configuration
└── .github/workflows/
    ├── ci.yaml                       # Quality gates (build and test)
    ├── build-on-commit.yaml          # Build images on every commit
    ├── build-on-release.yaml         # Build versioned releases
    ├── deploy-dev-auto.yaml          # Auto-deploy to DEV
    ├── deploy-staging-manual.yaml    # Manual promotion to STG
    └── deploy-production-manual.yaml # Manual promotion to PRD (with approval)
```

### Kustomization File Structure

```yaml
# k8s/overlays/production/blue/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: blue-production
namePrefix: blue-

images:
- name: davidaparicio/blue
  newTag: "2.1.3"  # ← VERSION (single source of truth)

resources:
- ../../../base

patches:
- patch: |-
    - op: replace
      path: /spec/replicas
      value: 3
  target:
    kind: Deployment
- patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/memory
      value: "128Mi"
  target:
    kind: Deployment
```

---

## Comparison: Original vs. Simplified

| Aspect | Original Design | Simplified Design |
|--------|----------------|-------------------|
| **Branches** | `main` + `release/*` + `gitops/*` (9+ branches) | `main` only (1 branch) |
| **Source of Truth** | `release-manifests/*.yaml` + kustomization | Kustomization only |
| **Tag Scheme** | 3 schemes (`build:`, `service/`, `release-prd-`) | 1 scheme (`service/version`) |
| **Hotfix Process** | Cherry-pick to release branch | New tag on main |
| **Mental Model** | Complex (multiple branch types) | Simple (tags mark releases) |
| **Files Per Promotion** | 2 (manifest + kustomize) | 1 (kustomization) |
| **Human Readability** | Check multiple places | Single kustomization file |
| **Git History** | Cluttered with gitops updates | Clean development history |

---

## Summary

### What Makes This System Simple

1. **One branch** - All work on `main`, no release branches, no gitops branches
2. **One tag scheme** - `service/version` for everything
3. **One manifest** - Kustomize files are the single source of truth
4. **One workflow pattern** - Same promotion flow for all services

### What Makes This System Efficient

1. **Automated DEV** - Zero manual steps for development environment
2. **Manual gates** - Staging and production require explicit promotion
3. **Parallel CI** - Each service builds independently
4. **Fast rollback** - Just update one file and commit

### What Makes This System Elegant

1. **No branch proliferation** - Single `main` branch keeps git history clean
2. **No dual manifests** - One file per service per environment
3. **Clear separation** - DEV (automatic) vs. STG/PRD (manual)
4. **Audit trail** - Git tags + commits = complete deployment history

### What Makes This System Human-Readable

1. **Version visibility** - `newTag: "2.1.3"` in kustomization files
2. **Consistent naming** - `blue/2.1.3`, `green/1.5.0`, etc.
3. **Clear file structure** - `k8s/overlays/{env}/{service}/kustomization.yaml`
4. **Simple commands** - Standard git and kubectl operations

---

**Remember**: The goal is **independent service releases** with complete visibility and reproducibility. Each service moves at its own pace, with feature flags coordinating cross-service changes when needed.

**Getting Started:**

1. Commit changes to a service in `projects/`
2. Watch it auto-deploy to DEV
3. Promote to staging when ready: GitHub Actions → "Promote to Staging"
4. Test in staging
5. Promote to production when validated: GitHub Actions → "Promote to Production"
6. Approve the deployment

That's it!
