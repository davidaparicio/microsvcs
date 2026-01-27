# Kargo API Migration: v1.7 → v1.8

Quick reference table for migrating Kargo manifests from older versions to v1.8 API.

## Resource-Level Changes

| Resource | Old API Field | New API Field (v1.8) | Migration Notes |
|----------|--------------|---------------------|-----------------|
| **Project** | `spec.promotionPolicies` | *(removed)* | Promotion policies no longer configured in Project resource. Auto-promotion is now configured per-stage. |
| **Warehouse** | `spec.subscriptions[].image.imageTagPattern` | `spec.subscriptions[].image.allowTags` + `imageSelectionStrategy: Lexical` | Pattern matching now requires explicit strategy. Add quotes around pattern value. |
| **Warehouse** | `spec.subscriptions[].image.semverConstraint` | `spec.subscriptions[].image.semverConstraint` + `imageSelectionStrategy: SemVer` | Still works but requires explicit `imageSelectionStrategy`. Add quotes around constraint value. |
| **Stage** | `spec.subscriptions.warehouse` | `spec.requestedFreight[].origin.kind: Warehouse` + `sources.direct: true` | Complete API restructure to support multiple freight sources. |
| **Stage** | `spec.subscriptions.upstreamStages` | `spec.requestedFreight[].sources.stages[]` | Upstream stages now nested under `sources` in `requestedFreight`. |
| **Stage** | `spec.promotionMechanisms.gitRepoUpdates` | `spec.promotionTemplate.spec.steps` | Declarative git updates replaced with explicit step-based workflow. |
| **Stage** | `spec.verification.analysisTemplates` | `spec.verification` *(format changed)* | Verification API updated (not currently used in this config). |
| **Stage** | `spec.verification.analysisRuns` | `spec.verification` *(format changed)* | Verification API updated (not currently used in this config). |

## Warehouse: Image Selection Strategy

New **required** field in v1.8:

| Strategy | Use Case | Old Equivalent | Example |
|----------|----------|----------------|---------|
| `Lexical` | Tags with patterns (dates, commits) | `imageTagPattern: "^sha-.*"` | Development builds with commit hashes |
| `SemVer` | Semantic versioning | `semverConstraint: ">=0.0.0"` | Production releases (v1.2.3, 2.0.0) |
| `NewestBuild` | Most recent push | *(n/a)* | Latest image by push time (causes rate limiting) |
| `Digest` | Specific digest | *(n/a)* | Pin to exact image digest |

## Stage: Promotion Workflow Migration

### Old Format (v1.7)

```yaml
spec:
  subscriptions:
    warehouse: red-dev
  promotionMechanisms:
    gitRepoUpdates:
    - repoURL: https://github.com/user/repo.git
      writeBranch: main
      kustomize:
        images:
        - image: docker.io/user/red
          path: k8s/overlays/development/red
```

### New Format (v1.8) - Option 1: Trunk-Based Development (Recommended)

Single worktree approach - edits kustomization.yaml in-place on main branch:

```yaml
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: red-dev
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: git-clone
        config:
          repoURL: https://github.com/user/repo.git
          checkout:
          - branch: main
            path: ./repo
      - uses: kustomize-set-image
        config:
          path: ./repo/k8s/overlays/development/red
          images:
          - image: docker.io/user/red
            tag: ${{ imageFrom("docker.io/user/red").Tag }}
      - uses: git-commit
        config:
          path: ./repo
          message: "[dev] Updated ./${{ kustomize.path }} to use new images"
      - uses: git-push
        config:
          path: ./repo
```

### New Format (v1.8) - Option 2: Environment Branches

Separate worktrees with rendered manifests pushed to environment branches:

```yaml
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: red-dev
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: git-clone
        config:
          repoURL: https://github.com/user/repo.git
          checkout:
          - branch: main
            path: ./src
          - branch: env/development
            create: true
            path: ./out
      - uses: git-clear
        config:
          path: ./out
      - uses: kustomize-set-image
        config:
          path: ./src/k8s/overlays/development/red
          images:
          - image: docker.io/user/red
            tag: ${{ imageFrom("docker.io/user/red").Tag }}
      - uses: kustomize-build
        config:
          path: ./src/k8s/overlays/development/red
          outPath: ./out/red
      - uses: git-commit
        config:
          path: ./out
          message: "[dev] Updated ./${{ kustomize.path }} to use new images"
      - uses: git-push
        config:
          path: ./out
          targetBranch: env/development
```

> **Note:** Option 2 requires creating environment branches before first promotion:
>
> ```bash
> git checkout --orphan env/development && git commit --allow-empty -m 'init' && git push -u origin env/development
> ```

## Promotion Steps Reference

Mapping from old declarative format to new step-based format:

| Old Mechanism | New Step | Purpose | Configuration |
| ------------- | -------- | ------- | ------------- |
| `gitRepoUpdates.repoURL` | `git-clone` | Clone repository | `repoURL`, `checkout[].branch`, `checkout[].path` |
| *(implicit)* | `git-clear` | Clear output directory (Option 2 only) | `path` |
| `gitRepoUpdates.kustomize.images` | `kustomize-set-image` | Update image references | `path`, `images[].image`, `images[].tag` |
| *(implicit)* | `kustomize-build` | Build Kustomize manifests (Option 2 only) | `path`, `outPath` |
| *(implicit)* | `git-commit` | Commit changes | `path`, `message` |
| `gitRepoUpdates.writeBranch` | `git-push` | Push to branch | `path`, `targetBranch` (optional) |

### Required Fields (v1.8)

| Step | Required Field | Example |
| ---- | -------------- | ------- |
| `kustomize-set-image` | `images[].tag` | `${{ imageFrom("docker.io/user/red").Tag }}` |
| `git-commit` | `message` | `"[dev] Updated ./${{ kustomize.path }} to use new images"` |

> **Warning:** `messageFromSteps` is **NOT supported** in v1.8. Use `message` with Kargo expressions instead.

## Stage: Freight Sources

| Old Subscription Type | New requestedFreight Configuration | Use Case |
| --------------------- | ---------------------------------- | -------- |
| `subscriptions.warehouse: foo` | `origin.kind: Warehouse` + `sources.direct: true` | Get freight directly from warehouse |
| `subscriptions.upstreamStages: [foo]` | `origin.kind: Warehouse` + `sources.stages: [foo]` | Get freight from upstream stage (production pattern) |

### Example: Production Stage with Upstream

**Old Format:**

```yaml
spec:
  subscriptions:
    upstreamStages:
    - name: red-staging
```

**New Format:**

```yaml
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: red-releases
    sources:
      stages:
      - red-staging
```

## Breaking Changes Summary

1. **Project resource** no longer controls auto-promotion (moved to per-stage configuration)
2. **Stage subscriptions** completely redesigned - **NOT backward compatible**
3. **Promotion mechanisms** replaced with declarative step-based system
4. **Image tag patterns** require explicit selection strategy
5. **Warehouse fields** require quoted string values for patterns and constraints

## Migration Checklist

- [ ] Add `imageSelectionStrategy` to all Warehouse subscriptions
- [ ] Quote all `allowTags` and `semverConstraint` values
- [ ] Convert Stage `subscriptions` to `requestedFreight` format
- [ ] Rewrite Stage `promotionMechanisms` as `promotionTemplate.spec.steps`
- [ ] Remove `spec.promotionPolicies` from Project resources
- [ ] Update Stage freight sources (`direct: true` or `stages: []`)
- [ ] Test promotion workflow in development environment
- [ ] Verify auto-promotion behavior for each stage

## Additional Resources

- [Kargo v1.8 Documentation](https://docs.kargo.io/)
- [Working with Stages](https://docs.kargo.io/user-guide/how-to-guides/working-with-stages/)
- [Promotion Templates Reference](https://docs.kargo.io/user-guide/reference-docs/promotion-templates/)
- [Promotion Steps Reference](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/)
- [Kargo Quickstart Template](https://github.com/akuity/kargo-quickstart-template)

## Automated Migration

This repository uses an automated generation system that handles the API migration:

```bash
cd kargo
./generate.sh --no-backup
kubectl apply -f generated/
```

All manifests are generated from [config.yaml](config.yaml) using the correct v1.8 API format.
