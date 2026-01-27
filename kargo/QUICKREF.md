# Kargo Quick Reference

One-page reference for common Kargo operations.

## Daily Operations

### Generate Kargo Manifests
```bash
cd kargo
./generate.sh                    # With backup
./generate.sh --no-backup        # Skip backup (faster, for CI)
./generate.sh --validate         # Validate config only
./generate.sh --dry-run          # Validate with kubectl
./generate.sh --apply            # Generate and apply to cluster
./generate.sh --verify-only      # Skip generation, only verify existing resources
```

### Apply to Cluster
```bash
kubectl apply -f kargo/generated/

# Or use the built-in apply
./generate.sh --no-backup --apply
```

### Check Status
```bash
# All stages
kargo get stages -n microsvcs

# Specific stage
kargo describe stage red-production -n microsvcs

# Watch freight
kargo get freight -n microsvcs --watch
```

### Manual Promotion (Production Only)
```bash
# Interactive
kargo promote red-production -n microsvcs

# Specific freight
kargo promote red-production --freight <freight-id> -n microsvcs
```

## Promotion Flow

```
Commit → sha-abc123 → red-dev warehouse → red-development ✅ AUTO
                                                ↓
Release → v1.2.3 → red-releases warehouse → red-staging ✅ AUTO
                                                ↓
                                          red-production ⏸️ MANUAL
```

## Configuration Changes

### Add New Service
```yaml
# config.yaml
services:
  - red
  - blue
  - green
  - yellow
  - purple  # Add this line
```
Then: `./generate.sh && kubectl apply -f generated/`

### Change Auto-Promotion
```yaml
# config.yaml
environments:
  - name: staging
    autoPromote: false  # Change true → false
```
Then: `./generate.sh && kubectl apply -f generated/`

### Update Image Tag Pattern
```yaml
# config.yaml
environments:
  - name: development
    warehouse:
      imageTagPattern: "^sha-.*"  # Modify pattern
```
Then: `./generate.sh && kubectl apply -f generated/`

## Troubleshooting

### Freight Not Discovered
```bash
# Check warehouse
kubectl describe warehouse red-dev -n microsvcs

# Check recent images in registry
curl https://hub.docker.com/v2/repositories/davidaparicio/red/tags
```

### Stage Not Promoting
```bash
# Check promotion policy
kubectl get project microsvcs -n microsvcs -o yaml

# Check stage health
kargo describe stage red-development -n microsvcs

# Check logs
kubectl logs -n microsvcs -l app.kubernetes.io/name=kargo
```

### Regenerate from Scratch
```bash
cd kargo
rm -rf generated/
./generate.sh
kubectl apply -f generated/
```

## File Reference

| File | Purpose | Commit? |
|------|---------|---------|
| `config.yaml` | Single source of truth | ✅ Yes |
| `generate.sh` | Generation script | ✅ Yes |
| `README.md` | Full documentation | ✅ Yes |
| `MIGRATION.md` | Migration guide | ✅ Yes |
| `templates/` | Reference templates | ✅ Optional |
| `generated/` | Auto-generated manifests | ❌ No (gitignored) |

## Warehouse & Stage Naming

| Service | Warehouses | Stages |
|---------|-----------|--------|
| red | `red-dev`<br>`red-releases` | `red-development`<br>`red-staging`<br>`red-production` |
| blue | `blue-dev`<br>`blue-releases` | `blue-development`<br>`blue-staging`<br>`blue-production` |
| green | `green-dev`<br>`green-releases` | `green-development`<br>`green-staging`<br>`green-production` |
| yellow | `yellow-dev`<br>`yellow-releases` | `yellow-development`<br>`yellow-staging`<br>`yellow-production` |

## Image Tag Strategy

| Warehouse Type | Tag Pattern | Examples | Use Case |
|---------------|-------------|----------|----------|
| `{service}-dev` | `^sha-.*` | `sha-abc123` | Development (every commit) |
| `{service}-releases` | `>=0.0.0` | `v1.2.3`, `2.0.0` | Staging/Prod (releases only) |

## Auto-Promotion Matrix

| Environment | Auto-Promote | Trigger |
|-------------|--------------|---------|
| Development | ✅ Yes | New sha-* tag (every commit) |
| Staging | ✅ Yes | New semver tag (releases) |
| Production | ❌ No | Manual `kargo promote` |

## Validation

| Environment | Health Checks | Smoke Tests |
|-------------|---------------|-------------|
| Development | ✅ 5m | ❌ Skip |
| Staging | ✅ 5m | ✅ 10m |
| Production | ✅ 5m | ✅ 10m |

## Common Workflows

### Scenario: New Commit to Main
```
1. CI builds image → docker.io/davidaparicio/red:sha-abc123
2. Warehouse red-dev discovers tag
3. Freight created automatically
4. Stage red-development auto-promotes ✅
5. Health check runs
6. Promotion complete
```

### Scenario: New Release
```
1. Merge release-please PR
2. CI builds image → docker.io/davidaparicio/red:v1.2.3
3. Warehouse red-releases discovers tag
4. Freight created automatically
5. Stage red-staging auto-promotes ✅
6. Health check + smoke test run
7. Promotion complete
```

### Scenario: Deploy to Production
```
1. Run: kargo promote red-production -n microsvcs
2. Select freight from staging
3. Health check + smoke test run
4. Manual approval
5. Promotion complete
```

## Emergency Commands

### Rollback Production
```bash
# List previous freight
kargo get freight -n microsvcs

# Promote to previous version
kargo promote red-production --freight <previous-freight-id> -n microsvcs
```

### Pause Auto-Promotion
```bash
# Edit config
vim config.yaml
# Change autoPromote: true → false

# Regenerate and apply
./generate.sh
kubectl apply -f generated/project.yaml
```

### Force Refresh Warehouse
```bash
kubectl delete warehouse red-dev -n microsvcs
kubectl apply -f generated/warehouses/red-dev.yaml
```

## Useful Links

- [Full Documentation](README.md)
- [Migration Guide](MIGRATION.md)
- [Kargo CLI Docs](https://docs.kargo.io/references/kargo-cli/)
- [Kargo Concepts](https://kargo.akuity.io/concepts/)
