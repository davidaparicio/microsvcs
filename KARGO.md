# Kargo Deployment Guide

Kargo manages promotions across environments for the microservices (red, blue, green, yellow).

## Quick tutorial video

GitOps-driven workflow powered by Kargo
* [Kargo Tutorial: Manage Multi-Environment Deployments with Argo CD (9min)](https://youtu.be/NHXBV40GFHs)
* [Multi Environment Promotions Made Simple | Akuity Webinar (56min)](https://youtu.be/bFXxvvM-jcQ)
* [How to Automate CI/CD Pipelines with Kargo (Live Demo) (34min)](https://youtu.be/2O1eQntjR-U)
* [Kargo - Multi-Stage Deployment Pipelines using GitOps - Jesse Suen / Kent Rancourt (16min)](https://youtu.be/0B_JODxyK0w)

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ GitHub Push │────>│ Build & Publish  │────>│ Docker Hub  │
│  to main    │     │ (creates image)  │     │ (Warehouse) │
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

### 2. Apply Kargo Manifests

```bash
kubectl apply -f kargo/project.yaml
kubectl apply -f kargo/warehouses/
kubectl apply -f kargo/stages/
```

### 3. Configure Credentials

#### Using Environment Variables (Recommended)

1. Create a `.env` file from the example:
   ```bash
   cp kargo/.env.example kargo/.env
   ```

2. Edit `kargo/.env` and fill in your credentials:
   ```bash
   GITHUB_USERNAME=davidaparicio
   GITHUB_PAT=ghp_your_github_pat_here
   DOCKERHUB_USERNAME=davidaparicio
   DOCKERHUB_PAT=dckr_pat_your_dockerhub_pat_here
   ```

3. Apply secrets using the script:
   ```bash
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

# Kargo detects new image in Warehouse and auto-promotes to dev
# Check status:
kargo get freight --project microsvcs
kargo get stages --project microsvcs
```

### 2. Promote Single Service to Staging

```bash
# List available freight (images) that passed development
kargo get freight --project microsvcs --stage red-development

# Promote red service to staging
kargo promote --project microsvcs --stage red-staging

# Or promote specific freight by ID
kargo promote --project microsvcs --stage red-staging --freight abc123def
```

### 3. Promote All Services to Staging (Batch)

```bash
# Promote all 4 services to staging
for service in red blue green yellow; do
  kargo promote --project microsvcs --stage ${service}-staging
done
```

### 4. Promote to Production

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
# NAME          IMAGE                           AGE
# abc123def     davidaparicio/red:sha-a1b2c3d   2h    (current)
# xyz789ghi     davidaparicio/red:sha-x7y8z9g   3d    (previous)

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
kargo get freight --project microsvcs --warehouse red

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
├── project.yaml                 # Project with promotion policies
├── warehouses/
│   ├── red.yaml                 # Watches docker.io/davidaparicio/red
│   ├── blue.yaml                # Watches docker.io/davidaparicio/blue
│   ├── green.yaml               # Watches docker.io/davidaparicio/green
│   └── yellow.yaml              # Watches docker.io/davidaparicio/yellow
└── stages/
    ├── {service}-development.yaml   # Auto-promotion enabled
    ├── {service}-staging.yaml       # Manual promotion
    └── {service}-production.yaml    # Manual promotion
```

## Promotion Flow

| Stage | Auto-Promote | Subscribes To |
|-------|--------------|---------------|
| development | Yes | Warehouse (new images) |
| staging | No | development stage |
| production | No | staging stage |

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
