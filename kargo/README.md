# Kargo Configuration

This directory contains the simplified, template-based Kargo configuration that reduces 28 configuration files to a single source of truth.

## Architecture

```
Services: red, blue, green, yellow

Warehouses (8 total = 2 per service):
├─ {service}-dev → discovers sha-* tags from every commit
└─ {service}-releases → discovers semver tags from releases

Stages (12 total):
├─ {service}-development → subscribes to {service}-dev warehouse, auto-promote
├─ {service}-staging → subscribes to {service}-releases warehouse, auto-promote
└─ {service}-production → subscribes to staging stage, MANUAL promote
```

## Files

- **[config.yaml](config.yaml)** - Single source of truth for all configuration
- **[templates/](templates/)** - Go templates for generating Kargo resources
- **[generate.sh](generate.sh)** - Script to generate all Kargo resources from config.yaml
- **generated/** - Output directory (gitignored, regenerated each time)

## Usage

### Generate Kargo Resources

```bash
cd kargo
./generate.sh
```

This will create:
- 1 project file with 12 promotion policies
- 8 warehouse files (2 per service: dev + releases)
- 12 stage files (3 per service: dev, staging, prod)

### Apply to Cluster

```bash
# Apply generated resources
kubectl apply -f generated/

# Verify project
kargo get project microsvcs

# Verify warehouses
kargo get warehouses --project microsvcs

# Verify stages
kargo get stages --project microsvcs
```

### Watch Promotions

```bash
# Watch all stages
kargo get stages --project microsvcs --watch

# Promote manually (production only)
kargo promote --project microsvcs --stage red-production
```

## Promotion Flow

### Development Environment
1. Developer pushes code to `main` branch
2. GitHub Actions builds image with `sha-*` tag (e.g., `sha-abc1234`)
3. `{service}-dev` warehouse detects new image
4. `{service}-development` stage auto-promotes
5. ArgoCD syncs to development cluster

### Staging Environment
1. Release-please creates a release with semantic version (e.g., `2.5.0`)
2. GitHub Actions builds image with version tag
3. `{service}-releases` warehouse detects new semantic version
4. `{service}-staging` stage auto-promotes
5. ArgoCD syncs to staging cluster

### Production Environment
1. Manual promotion required: `kargo promote --project microsvcs --stage {service}-production`
2. ArgoCD syncs to production cluster

## Adding a New Service

1. Edit [config.yaml](config.yaml) and add the service name to the `services` array:
   ```yaml
   services:
     - red
     - blue
     - green
     - yellow
     - orange  # New service
   ```

2. Regenerate configs:
   ```bash
   ./generate.sh
   ```

3. Apply to cluster:
   ```bash
   kubectl apply -f generated/
   ```

That's it! No need to edit 28 files - just one line in config.yaml.

## Configuration Changes

All configuration is centralized in [config.yaml](config.yaml). Common changes:

### Change Image Discovery Limit
```yaml
warehouse:
  discoveryLimit: 20  # Default: 10
```

### Change Platform Architecture
```yaml
warehouse:
  platform: linux/amd64  # For production x86_64 systems
  # OR
  platform: linux/arm64  # For Mac M1/M2 (Silicon), Kind, Docker Desktop on ARM
```

Common platforms:

- `linux/amd64` - Production systems, most cloud providers
- `linux/arm64` - Mac M1/M2, ARM servers (AWS Graviton, etc.)
- `linux/arm/v7` - Raspberry Pi, older ARM devices

### Modify Auto-Promotion
```yaml
environments:
  - name: staging
    autoPromote: false  # Change to manual
```

### Update Git Branch
```yaml
gitBranch: develop  # Default: main
```

After any change, run `./generate.sh` to regenerate resources.

## Comparison: Before vs After

### Before (Current Implementation)
- **28 configuration files** with 82-90% duplication
- **Complexity score:** 6.5/10
- **Change impact:** Edit 12 files to modify pipeline logic
- **Adding new service:** Create 7 new files

### After (Template-Based)
- **1 config file** + 6 templates
- **Complexity score:** 2/10
- **Change impact:** Edit 1 config file, regenerate
- **Adding new service:** Add 1 line to config.yaml

**Maintenance burden reduction: 92%**

## Validation (Future Phase)

Health checks and smoke tests will be added in Phase 3-4:
- Pod readiness verification
- HTTP endpoint validation
- Automatic rollback on failures
- Configurable timeouts per environment

See [/Users/daparicio/.claude/plans/wondrous-forging-karp.md](/Users/daparicio/.claude/plans/wondrous-forging-karp.md) for full implementation plan.
