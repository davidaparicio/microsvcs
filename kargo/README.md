# Kargo Configuration

Trunk-based development promotion pipeline for microservices.

## Promotion Flow

```
Commit (sha-*)  →  dev warehouse  →  development (auto)
Release (v*.*)  →  releases warehouse  →  staging (auto)  →  production (manual)
```

All promotions commit to the `main` branch.

| Environment | Promotion | Image Source | Trigger |
|-------------|-----------|--------------|---------|
| Development | Auto | `sha-*` tags | Every commit |
| Staging | Auto | Semver tags | Release tag |
| Production | Manual | From staging | `kargo promote` |

## Usage

```bash
# Generate manifests
./generate.sh

# Generate and apply to cluster
./generate.sh --apply

# Manually promote to production
kargo promote --stage red-production --freight <id> -n microsvcs
```

## Adding a Service

Edit `config.yaml`:

```yaml
services:
  - red
  - blue
  - green
  - yellow
  - orange  # add here
```

Then run `./generate.sh --apply`.

## Files

- `config.yaml` — single source of truth
- `generate.sh` — generates manifests into `generated/` (gitignored)
- `apply-secrets.sh` — applies registry and git credentials
- `*-credentials.yaml` — credential templates

## Prerequisites

- [yq](https://github.com/mikefarah/yq) v4+
- `kubectl` (for `--apply`)
