# Kargo Deployment Guide

Kargo manages automated promotions across environments for the microservices (red, blue, green, yellow).

**GitOps-based progressive deployment** with:
- ✅ Automated development & staging promotions
- ✅ Manual production promotions
- ✅ Full audit trail via git commits
- ✅ Template-driven configuration for easy service additions

## Quick Start

```bash
# 1. Install the platform (Kind cluster + ArgoCD + Kargo)
./install.sh

# 2. Access the dashboards
# ArgoCD: http://localhost:31443 (admin/admin)
# Kargo:  http://localhost:31444 (admin/admin)

# 3. Trigger a deployment
git commit -m "feat(red): new feature" && git push
# Development auto-promotes → Staging auto-promotes → Production manual

# 4. Promote to production
kargo promote --project microsvcs --stage red-production
```

## Tutorial Videos

GitOps-driven workflow powered by Kargo
* [Kargo Tutorial: Manage Multi-Environment Deployments with Argo CD (9min)](https://youtu.be/NHXBV40GFHs)
* [Multi Environment Promotions Made Simple | Akuity Webinar (56min)](https://youtu.be/bFXxvvM-jcQ)
* [How to Automate CI/CD Pipelines with Kargo (Live Demo) (34min)](https://youtu.be/2O1eQntjR-U)
* [Kargo - Multi-Stage Deployment Pipelines using GitOps - Jesse Suen / Kent Rancourt (16min)](https://youtu.be/0B_JODxyK0w)

## Color demo

Before going to the [Kargo presentation](https://kargo.io/), if you need to test the project: it's a kind of [stefanprodan/podinfo](https://github.com/stefanprodan/podinfo) but with a [feature flag ability](https://trunkbaseddevelopment.com/feature-flags/).

```bash
❯ cd color && PORT=8080 NAMESPACE=red make run
Running...

Server: 	Color - Community
Version: 	v1.0.0
Git commit: 	a0c993da39b2136e50054280268f0074017826b4
Built: 		2026-01-27T15:30:15+0100

Starting HTTP server (darwin/arm64) listening on port 8080.
⇨ http server started on [::]:8080
```

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ GitHub Push │────>│ Build & Publish  │────>│  Quay.io    │
│  to main    │     │ (creates image)  │     │ (Registry)  │
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
#### Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml

#### Wait for cert-manager to be ready
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s

helm install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo --create-namespace \
  --set api.adminAccount.passwordHash='$2a$10$TtuLC4oHmFARjcja/Zx/Q.nbOeeMUrmh7O.Vgb/HkndJgV3dPl9bu' \
  --set api.adminAccount.tokenSigningKey="sdlqffxl4dH73BHZGCo8GhMh7u2/ueHk5lJB0raC1OY="
```

### 2. Generate and Apply Kargo Manifests

Manifests are generated from templates using `kargo/config.yaml` as the single source of truth.

```bash
# Generate manifests into kargo/generated/
./kargo/generate.sh

# Or generate and apply in one step
./kargo/generate.sh --apply
```

This renders the templates for all services (red, blue, green, yellow) and produces:
- 1 project + 1 project-config
- 8 warehouses (2 per service: `{svc}-dev` + `{svc}-releases`)
- 12 stages (3 per service: development, staging, production)

### 3. Configure Credentials

**Note**: If you used `./install.sh` for installation, credentials are automatically applied if `kargo/.env` exists. This section is for manual credential management or updates.

#### Using Environment Variables (Recommended)

1. Create a `.env` file from the example:
   ```bash
   cp kargo/.env.example kargo/.env
   ```

2. Edit `kargo/.env` and fill in your credentials:
   ```bash
   GITHUB_USERNAME=davidaparicio
   GITHUB_PAT=ghp_your_github_pat_here
   QUAY_USERNAME=davidaparicio
   QUAY_PAT=your_quay_pat_here
   ```

3. Apply secrets:
   ```bash
   # Option 1: Automatically applied by install.sh if .env exists
   ./install.sh

   # Option 2: Apply manually (useful for updating credentials)
   ./kargo/apply-secrets.sh
   ```

#### Manual Creation (Alternative)

##### Git Credentials
```bash
kubectl create secret generic github-creds \
  --namespace microsvcs \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-token>
```

##### DockerHub Credentials
```bash
kubectl create secret generic dockerhub-creds \
  --namespace microsvcs \
  --from-literal=username=<dockerhub-username> \
  --from-literal=password=<dockerhub-pat>
```

## Promotion Scenarios

### 1. Auto-Promotion to Development (Automatic)

```bash
# This happens automatically when you push code changes
git commit -m "feat(red): add new endpoint"
git push origin main

# Kargo detects new SHA-tagged image in the dev Warehouse and auto-promotes
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

### 3. Promote to Production (Manual)

```bash
# First, check what's currently in staging
kargo get stages --project microsvcs | grep staging

# Promote red to production
kargo promote --project microsvcs --stage red-production

# Monitor the promotion status
kargo get promotions --project microsvcs --stage red-production
```

### 4. Promote All Services to Production (Batch)

```bash
# Promote all 4 services to production
for service in red blue green yellow; do
  kargo promote --project microsvcs --stage ${service}-production
done
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

## Emergency Rollback Runbook

If a production deployment causes issues, follow this procedure:

### 1. Identify the Bad Deployment

```bash
# Check current freight on the affected stage
kargo get freight --project microsvcs --stage <service>-production
# Note the current freight name (e.g., abc123def) and the previous one (e.g., xyz789ghi)
```

### 2. Roll Back Immediately

```bash
# Promote the previous known-good freight
kargo promote --project microsvcs --stage <service>-production --freight <previous-freight-id>
```

### 3. Verify the Rollback

```bash
# Watch promotion status until it succeeds
kargo get promotions --project microsvcs --stage <service>-production --watch

# Confirm ArgoCD sync is healthy
kubectl get applications -n argocd <service>-production -o jsonpath='{.status.health.status}'

# Confirm pods are running the expected image
kubectl get pods -n <service>-production -o jsonpath='{.items[*].spec.containers[*].image}'
```

### 4. Roll Back All Services (if needed)

```bash
for service in red blue green yellow; do
  PREV=$(kargo get freight --project microsvcs --stage ${service}-production -o json | jq -r '.items[1].metadata.name')
  if [ -n "$PREV" ] && [ "$PREV" != "null" ]; then
    kargo promote --project microsvcs --stage ${service}-production --freight "$PREV"
    echo "Rolled back ${service}-production to freight $PREV"
  fi
done
```

### 5. Post-Incident

- Investigate the root cause before re-promoting
- The bad freight remains in history; do not re-promote it until the fix is verified in staging

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
├── git-credentials.yaml         # Git credentials template
├── quay-credentials.yaml        # Quay.io credentials template
├── templates/
│   ├── project.yaml             # Project resource template
│   ├── project-config.yaml      # Promotion policies (auto-promote settings)
│   ├── warehouse-dev.yaml       # Dev warehouse (SHA tags, NewestBuild)
│   ├── warehouse-releases.yaml  # Releases warehouse (semver, SemVer)
│   ├── stage-development.yaml   # Dev stage template
│   ├── stage-staging.yaml       # Staging stage template
│   └── stage-production.yaml    # Production stage template
└── generated/                   # Output from generate.sh (NOW COMMITTED to git for transparency!)
    ├── project.yaml             # The actual resources deployed to cluster
    ├── project-config.yaml      # These are visible in PRs for review
    ├── warehouses/
    │   ├── {svc}-dev.yaml       # Watches quay.io/davidaparicio/{svc} (SHA tags)
    │   └── {svc}-releases.yaml  # Watches quay.io/davidaparicio/{svc} (semver)
    └── stages/
        ├── {svc}-development.yaml
        ├── {svc}-staging.yaml
        └── {svc}-production.yaml
```

## How the Template System Works

The Kargo configuration uses a **template-driven approach** to avoid repetition:

1. **Single Source of Truth**: `kargo/config.yaml` defines all services and environments
2. **Templates**: `kargo/templates/*.yaml` contain parameterized Kargo resources
3. **Generation**: `kargo/generate.sh` renders templates into actual manifests
4. **Version Controlled**: Generated manifests are committed to git for transparency

### Adding a New Service

To add a new service (e.g., "orange"):

1. Edit `kargo/config.yaml`:
   ```yaml
   services:
     - red
     - blue
     - green
     - yellow
     - orange  # add here
   ```

2. Regenerate manifests:
   ```bash
   cd kargo && ./generate.sh
   ```

3. Review the generated files (now visible in git):
   ```bash
   git diff generated/
   ```

4. Apply to cluster:
   ```bash
   ./generate.sh --apply
   ```

This creates 5 resources for the new service:
- 2 warehouses (orange-dev, orange-releases)
- 3 stages (orange-development, orange-staging, orange-production)

**Why templates?** Since services are added frequently (monthly+), templates automate the process and prevent errors from manual copy-paste.

## Warehouses

Each service has two warehouses:

| Warehouse | Image Selection | Tag Pattern | Purpose |
|-----------|----------------|-------------|---------|
| `{svc}-dev` | NewestBuild | `^sha-.*` | Tracks commit-based builds for development |
| `{svc}-releases` | SemVer | `>=0.0.0` | Tracks versioned releases for staging/production |

## Promotion Flow

| Stage | Auto-Promote | Freight Source |
|-------|--------------|----------------|
| development | Yes | `{svc}-dev` warehouse (SHA-tagged images) |
| staging | Yes | `{svc}-releases` warehouse (semver-tagged images) |
| production | No | `{svc}-releases` warehouse via staging stage |

## Troubleshooting

### Error: "does not permit mutation by Kargo Stage"

If you see this error during promotions:
```
error getting Argo CD Application "xxx" in namespace "argocd":
Argo CD Application "xxx" does not permit mutation by Kargo Stage
```

**Solution:** ArgoCD Applications need the Kargo authorization annotation.

1. Check if your ApplicationSet has the annotation in the template:
   ```bash
   kubectl get applicationset microsvcs -n argocd -o yaml | grep "kargo.akuity.io/authorized-stage"
   ```

2. The ApplicationSet should have this in the template metadata:
   ```yaml
   annotations:
     kargo.akuity.io/authorized-stage: 'microsvcs:{{.project}}-{{.env}}'
   ```

3. If missing, reapply the ApplicationSet:
   ```bash
   kubectl apply -f argocd/applicationset.yaml
   ```

4. Verify the Applications got the annotation (wait a few seconds for propagation):
   ```bash
   kubectl get application blue-development -n argocd -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/authorized-stage}'
   # Should output: microsvcs:blue-development
   ```

### DockerHub Credentials Not Being Used

If your DockerHub PAT shows no usage in the dashboard:

1. Ensure the DockerHub credentials secret is created:
   ```bash
   kubectl get secret dockerhub-creds -n microsvcs
   ```

2. Check the secret has the correct labels and annotations:
   ```bash
   kubectl get secret dockerhub-creds -n microsvcs -o yaml | grep "kargo.akuity.io"
   ```

   Should show:
   - Label: `kargo.akuity.io/cred-type: image`
   - Annotation: `kargo.akuity.io/repo-url-pattern: "docker.io/*"`

3. If missing, apply the credentials:
   ```bash
   ./kargo/apply-secrets.sh
   ```
