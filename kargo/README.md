# Kargo Configuration

> **📖 For complete documentation, see [KARGO.md](../KARGO.md) at the repository root.**

This directory contains the Kargo configuration using a template-driven approach.

## Quick Reference

```bash
# Generate manifests from templates
./generate.sh

# Generate and apply to cluster
./generate.sh --apply

# Apply credentials
./apply-secrets.sh  # requires .env file

# Promote to production (manual)
kargo promote --project microsvcs --stage red-production
```

## Directory Structure

- **`config.yaml`** — Single source of truth (services, environments, image patterns)
- **`generate.sh`** — Renders templates into `generated/` manifests
- **`templates/`** — Parameterized Kargo resource templates
- **`generated/`** — **Actual deployed resources** (committed to git for transparency)
- **`apply-secrets.sh`** — Applies git and registry credentials
- **`*-credentials.yaml`** — Credential templates (require .env file)

## Important Notes

⚠️ **Do not edit `generated/` files directly** - they are auto-generated from templates.

To make changes:
1. Edit `config.yaml` (for services/environments) OR `templates/` (for resource structure)
2. Run `./generate.sh` to regenerate
3. Review the diff: `git diff generated/`
4. Apply if needed: `./generate.sh --apply`

✅ **Generated files are version controlled** for transparency in PRs and easier debugging.

## Prerequisites

- [yq](https://github.com/mikefarah/yq) v4+ (for template rendering)
- `envsubst` from gettext (for variable substitution)
- `kubectl` (for applying to cluster)

## See Also

- [KARGO.md](../KARGO.md) - Complete deployment guide
- [install.sh](../install.sh) - Full platform installation script
