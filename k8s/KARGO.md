# Kargo Deployment Guide

Kargo manages promotions across environments for the microservices (red, blue, green, yellow).

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ GitHub Push │────>│ Build & Publish  │────>│  Quay.io    │
│  to main    │     │ (creates image)  │     │  (Registry) │
└─────────────┘     └──────────────────┘     └──────┬──────┘
                                                    │
                    ┌───────────────────────────────┘
                    │ Kargo discovers new Freight
                    v
            ┌───────────────────┐
            │ Kargo Controller  │
            │ - Warehouses      │
            │ - Stages          │
            │ - Promotions      │
            └────────┬──────────┘
                     │
                     v
            ┌───────────────────┐     ┌─────────────────┐
            │  ArgoCD           │────>│ Kubernetes      │
            │  Applications     │     │ Clusters        │
            └───────────────────┘     └─────────────────┘
```

## Installation

### 1. Install Kargo Controller

```bash
helm install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo --create-namespace
```

### 2. Generate and Apply Kargo Manifests

Manifests are generated from templates using `kargo/config.yaml` as the single source of truth.

```bash
# Generate manifests into kargo/generated/
./kargo/generate.sh

# Or generate and apply in one step
./kargo/generate.sh --apply
```

### 3. Configure Git Credentials

Create a secret for Kargo to write back to the repository:

```bash
kubectl create secret generic git-credentials \
  --namespace microsvcs \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-token>
```

## Promotion Scenarios

### 1. Auto-Promotion to Development (Automatic)

```bash
# This happens automatically when you push code changes
git commit -m "feat(red): add new endpoint"
git push origin main

# Kargo detects new image in Warehouse and auto-promotes to dev
# Check status:
kargo get freight --project microsvcs
kargo get stages --project microsvcs
```

### 2. Auto-Promotion to Staging (Automatic)

```bash
# When a new semver-tagged image is published to quay.io/davidaparicio/{svc},
# the releases Warehouse detects it and staging auto-promotes.
# Check status:
kargo get freight --project microsvcs --stage red-staging
```

### 3. Promote to Production

```bash
# First, check what's currently in staging
kargo get stages --project microsvcs | grep staging

# Promote red to production
kargo promote --project microsvcs --stage red-production

# Monitor the promotion status
kargo get promotions --project microsvcs --stage red-production
```

### 5. Promote Specific Freight Through All Stages

```bash
# Get freight ID from warehouse
FREIGHT_ID=$(kargo get freight --project microsvcs -o json | jq -r '.items[0].metadata.name')

# Promote through pipeline: dev -> staging -> production
kargo promote --project microsvcs --stage red-development --freight $FREIGHT_ID
# Wait for dev deployment...
kargo promote --project microsvcs --stage red-staging --freight $FREIGHT_ID
# Wait for staging validation...
kargo promote --project microsvcs --stage red-production --freight $FREIGHT_ID
```

## Rollback Scenario

### Rollback Production to Previous Freight

```bash
# 1. List freight history for production stage
kargo get freight --project microsvcs --stage red-production

# Example output:
# NAME          IMAGE                               AGE
# abc123def     quay.io/davidaparicio/red:3.2.0     2h    (current)
# xyz789ghi     quay.io/davidaparicio/red:3.1.0     3d    (previous)

# 2. Promote the previous freight to rollback
kargo promote --project microsvcs --stage red-production --freight xyz789ghi

# 3. Verify rollback status
kargo get promotions --project microsvcs --stage red-production

# 4. Confirm in ArgoCD
kubectl get applications -n argocd red-production -o jsonpath='{.status.sync.status}'
```

### Alternative: Rollback via Kargo UI

1. Open Kargo dashboard
2. Navigate to **microsvcs** project
3. Click on **red-production** stage
4. View freight history
5. Click **Promote** on the previous freight version
6. Confirm rollback

## Useful Commands

```bash
# View project status
kargo get project microsvcs

# View all stages
kargo get stages --project microsvcs

# View freight in a warehouse
kargo get freight --project microsvcs --warehouse red-dev
kargo get freight --project microsvcs --warehouse red-releases

# View promotion history
kargo get promotions --project microsvcs

# Watch promotions in real-time
kargo get promotions --project microsvcs --watch

# Describe a specific stage
kargo describe stage red-production --project microsvcs
```

## File Structure

```
kargo/
├── config.yaml                  # Single source of truth for all settings
├── generate.sh                  # Renders templates into generated/
├── apply-secrets.sh             # Creates credential secrets
├── templates/
│   ├── project.yaml             # Project resource template
│   ├── project-config.yaml      # Promotion policies (auto-promote settings)
│   ├── warehouse-dev.yaml       # Dev warehouse (SHA tags, NewestBuild)
│   ├── warehouse-releases.yaml  # Releases warehouse (semver, SemVer)
│   ├── stage-development.yaml   # Dev stage template
│   ├── stage-staging.yaml       # Staging stage template
│   └── stage-production.yaml    # Production stage template
└── generated/                   # Output from generate.sh (committed for transparency)
    ├── project.yaml
    ├── project-config.yaml
    ├── warehouses/
    │   ├── {svc}-dev.yaml       # Watches quay.io/davidaparicio/{svc} (SHA tags)
    │   └── {svc}-releases.yaml  # Watches quay.io/davidaparicio/{svc} (semver)
    └── stages/
        ├── {svc}-development.yaml   # Auto-promotion enabled
        ├── {svc}-staging.yaml       # Auto-promotion enabled
        └── {svc}-production.yaml    # Manual promotion
```

## Promotion Flow

| Stage | Auto-Promote | Freight Source |
|-------|--------------|----------------|
| development | Yes | `{svc}-dev` warehouse (SHA-tagged images) |
| staging | Yes | `{svc}-releases` warehouse (semver-tagged images) |
| production | No | `{svc}-releases` warehouse via staging stage |
