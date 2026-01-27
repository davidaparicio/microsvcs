# Kargo Configuration

This directory contains the Kargo configuration for managing GitOps promotion workflows across development, staging, and production environments.

## Overview

We use a **template-based generation system** to maintain a single source of truth and eliminate configuration duplication. This follows the KISS (Keep It Simple, Stupid) methodology to ensure all developers can easily understand the promotion workflow.

### Architecture

```
┌─────────────┐
│ config.yaml │  ← Single source of truth
└──────┬──────┘
       │
       │ ./generate.sh
       ↓
┌─────────────────────────────────────┐
│      generated/ (gitignored)        │
├─────────────────────────────────────┤
│ • project.yaml                      │
│ • warehouses/                       │
│   - {service}-dev.yaml              │
│   - {service}-releases.yaml         │
│ • stages/                           │
│   - {service}-development.yaml      │
│   - {service}-staging.yaml          │
│   - {service}-production.yaml       │
└─────────────────────────────────────┘
```

## Promotion Flow

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Development  │───▶│   Staging    │───▶│ Production   │
│   (auto)     │    │   (auto)     │    │  (manual)    │
└──────────────┘    └──────────────┘    └──────────────┘
       ▲                    ▲
       │                    │
       │                    │
┌──────┴──────┐    ┌────────┴────────┐
│ sha-* tags  │    │ semver releases │
│  (commits)  │    │  (v1.2.3, etc)  │
└─────────────┘    └─────────────────┘
```

### Promotion Policies

| Environment | Auto-Promote | Image Source | Trigger |
|-------------|--------------|--------------|---------|
| Development | ✅ Yes | `sha-*` tags | Every commit to `main` |
| Staging | ✅ Yes | Semantic versions | Release-please creates tag |
| Production | ❌ Manual | Upstream (staging) | Manual approval via `kargo promote` |

## Files

### Source Files (Committed to Git)

- **`config.yaml`** - Single source of truth for all Kargo configuration
- **`generate.sh`** - Script to generate Kargo resources from config.yaml
- **`templates/`** - Go-style templates (for reference, not actively used by generate.sh)

### Generated Files (Gitignored)

- **`generated/`** - All Kargo manifests generated from config.yaml
  - `project.yaml` - Promotion policies for all stages
  - `warehouses/*.yaml` - Image discovery (2 per service: dev + releases)
  - `stages/*.yaml` - Stage definitions (3 per service: dev, staging, prod)

## Quick Start

### Prerequisites

- [yq](https://github.com/mikefarah/yq) v4+ installed
  ```bash
  # macOS
  brew install yq

  # Linux
  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
  ```

### Generate Kargo Resources

```bash
cd kargo
./generate.sh
```

This will:
1. Read configuration from `config.yaml`
2. Generate 21 Kargo manifests in `generated/`
   - 1 Project (promotion policies)
   - 8 Warehouses (2 per service)
   - 12 Stages (3 per service)

### Apply to Cluster

```bash
# Apply all resources
kubectl apply -f generated/

# Or apply selectively
kubectl apply -f generated/project.yaml
kubectl apply -f generated/warehouses/
kubectl apply -f generated/stages/
```

### Verify Deployment

```bash
# Quick verification (checks project, warehouses, and stages)
./generate.sh --verify-only

# Or manually check individual resources
kubectl get project -n microsvcs
kubectl get warehouses -n microsvcs
kargo get stages -n microsvcs

# Watch freight propagation
kargo get freight -n microsvcs --watch
```

## Configuration

### Adding a New Service

1. Edit `config.yaml`:
   ```yaml
   services:
     - red
     - blue
     - green
     - yellow
     - orange  # New service
   ```

2. Regenerate:
   ```bash
   ./generate.sh
   ```

3. Apply:
   ```bash
   kubectl apply -f generated/
   ```

This automatically creates:
- 2 warehouses: `orange-dev`, `orange-releases`
- 3 stages: `orange-development`, `orange-staging`, `orange-production`
- Promotion policies for all 3 stages

### Changing Promotion Behavior

Edit the `environments` section in `config.yaml`:

```yaml
environments:
  - name: staging
    autoPromote: false  # Change to manual promotion
    warehouse:
      type: releases
      semverConstraint: ">=1.0.0"  # Only promote versions >= 1.0.0
```

Then regenerate and apply.

### Image Tag Patterns

We use two warehouse types per service:

**Dev Warehouse** (`{service}-dev`):
```yaml
imageTagPattern: "^sha-.*"
```
Discovers: `sha-abc123`, `sha-def456`, etc.
Use case: Development environment gets every commit

**Releases Warehouse** (`{service}-releases`):
```yaml
semverConstraint: ">=0.0.0"
```
Discovers: `v1.2.3`, `2.0.0`, etc.
Use case: Staging gets only releases created by release-please

## Manual Promotion to Production

Production requires manual approval:

```bash
# List available freight
kargo get freight -n microsvcs

# Promote specific freight to production
kargo promote \
  --stage red-production \
  --freight <freight-id> \
  -n microsvcs

# Or use interactive mode
kargo promote red-production -n microsvcs
```

## Validation

Each stage includes:

### Health Checks
- Enabled in all environments
- Timeout: 5 minutes
- Verifies service health before marking promotion successful

### Smoke Tests
- Enabled in staging and production only
- Skipped in development for faster feedback
- Script: `scripts/smoke-test.sh`
- Timeout: 10 minutes

## Maintenance

### Updating Configuration

1. **Edit** `config.yaml` (single source of truth)
2. **Generate** with `./generate.sh`
3. **Review** changes in `generated/`
4. **Apply** to cluster: `kubectl apply -f generated/`

### Backup Current Configuration

Before major changes:

```bash
# Backup current generated files
cp -r generated/ generated.backup/

# If needed, restore
kubectl apply -f generated.backup/
```

### CI/CD Integration

The generation step should be integrated into your CI/CD pipeline to ensure consistency:

```yaml
# Example GitHub Actions workflow
- name: Generate Kargo manifests
  run: |
    cd kargo
    ./generate.sh --no-backup --dry-run

- name: Apply to cluster (production)
  if: github.ref == 'refs/heads/main'
  run: |
    cd kargo
    ./generate.sh --no-backup --apply
```

**CI/CD Best Practices:**
- Use `--no-backup` to skip backup creation (saves time and disk space)
- Use `--dry-run` to validate manifests before applying
- Use `--validate` in PR checks to catch config errors early
- Combine `--no-backup --apply` for automatic deployment

## Troubleshooting

### Freight Not Promoting

```bash
# Check warehouse subscriptions
kubectl describe warehouse <service>-dev -n microsvcs

# Check stage status
kargo describe stage <service>-development -n microsvcs

# Check freight
kargo get freight -n microsvcs
```

### Image Not Discovered

Verify tag pattern matches your images:

```bash
# List recent tags in Docker registry
curl https://hub.docker.com/v2/repositories/davidaparicio/red/tags

# Check warehouse discovers images
kubectl get warehouse red-dev -n microsvcs -o yaml
```

### Generation Script Fails

```bash
# Verify yq installation
yq --version

# Check config.yaml syntax
yq eval '.' config.yaml

# Run with verbose output
bash -x ./generate.sh
```

## Comparison: Before vs After

### Before (28 files, 6.5/10 complexity)
- 12 stage files (82% duplication)
- 4 warehouse files (75% duplication)
- 12 Kustomize overlays (90% duplication)
- Manual editing required for every change

### After (1 config file + generation script)
- 1 `config.yaml` (single source of truth)
- 1 `generate.sh` (automated generation)
- 92% reduction in maintenance burden
- Complexity: 2.5/10

## Additional Resources

- [Kargo Documentation](https://kargo.akuity.io/)
- [Original Implementation Plan](../.claude/plans/wondrous-forging-karp.md)
- [Kargo CLI Guide](https://docs.kargo.io/references/kargo-cli/)

## Support

For questions or issues:
1. Check the [troubleshooting section](#troubleshooting)
2. Review generated files in `generated/`
3. Consult the [Kargo documentation](https://kargo.akuity.io/)
