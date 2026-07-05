# Microservices Platform

![ArgoCD](https://img.shields.io/badge/ArgoCD-8.1.4-blue?logo=argo&logoColor=white)
![Kargo](https://img.shields.io/badge/Kargo-1.8.9-green)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-326CE5?logo=kubernetes&logoColor=white)
![Go](https://img.shields.io/badge/Go-1.23-00ADD8?logo=go&logoColor=white)
[![Plumber Score](https://score.getplumber.io/github.com/davidaparicio/microsvcs.svg)](https://score.getplumber.io/github.com/davidaparicio/microsvcs)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)

A **GitOps-based microservices platform** with progressive deployment automation powered by ArgoCD and Kargo.

## What Is This?

This project demonstrates a complete CI/CD pipeline for microservices with:

- 🚀 **Automated Deployments**: Push code → Build image → Auto-deploy to dev/staging
- 🎯 **Progressive Delivery**: Dev (auto) → Staging (auto) → Production (manual approval)
- 📦 **Multi-Environment**: Separate development, staging, and production deployments
- 🔄 **GitOps**: All configuration in Git, full audit trail for deployments
- 🛡️ **Safe Rollbacks**: Git-based rollback via `git revert` or Kargo promotion history
- 📊 **Template-Driven**: Add new services quickly using configuration templates

### Projects

Interesting projects from [Dockerlabs](https://github.com/collabnix/dockerlabs):
* [webcolor](https://github.com/jpetazzo/color) from [Jérôme Petazzoni](https://github.com/jpetazzo)
* [Dockercoins v2](https://github.com/jpetazzo/container.training/tree/main/dockercoins), classic [Dockercoins](https://github.com/dockersamples/dockercoins/)
* [Voting-App](https://github.com/dockersamples/example-voting-app) with the [documentation](https://dockerlabs.collabnix.com/play-with-docker/example-voting-app/)
  * used in the [Docker BirthDay 2021](https://bday2021.play-with-docker.com/) like [Voting-App](https://bday2021.play-with-docker.com/voting-app/), thanks to [PWD / play-with-docker](https://labs.play-with-docker.com/)
* [salaboy/pizza](https://github.com/salaboy/pizza), the Cloud-Native Pizza Store, a fork of [pizza-quarkus](https://github.com/mcruzdev/pizza-quarkus)|[quarkus-dapr?](https://github.com/salaboy/quarkus-dapr) with [Testcontainers](https://testcontainers.com/)/[Dapr](https://dapr.io/)/[Microcks](https://microcks.io/) like the video ["Simplifier les tests d'applications cloud natives avec Dapr et Microcks - Laurent Broudoux"](https://youtu.be/jKl8xOtTP1I), [Accélérer vos livraisons d'API avec Microcks DevoxxFR23](https://youtu.be/3qLzj2rTFmA)
* [salaboy/pizza-vibe](https://github.com/salaboy/pizza-vibe), the same Cloud-Native Pizza Store, but vibecoded in Go

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) v3+

### Installation (5 minutes)

```bash
# 1. Clone the repository
git clone https://github.com/davidaparicio/microsvcs.git
cd microsvcs

# 2. Install the platform (creates Kind cluster + ArgoCD + Kargo)
./install.sh

# 3. Wait for installation to complete (~3-5 minutes)
# The script will automatically:
# - Create a Kind cluster named "microsvcs"
# - Install cert-manager, Ingress NGINX, ArgoCD, Argo Rollouts, Kargo
# - Deploy all 4 microservices (red, blue, green, yellow)
# - Configure automated promotion pipelines
```

### Access the Dashboards

Once installation completes:

| Service | URL | Credentials |
|---------|-----|-------------|
| **ArgoCD** | http://localhost:31443 | admin / admin |
| **Kargo** | http://localhost:31444 | admin / admin |

### Verify Deployment

```bash
# Check all applications are synced
kubectl get applications -n argocd

# Check running pods
kubectl get pods --all-namespaces | grep -E '(red|blue|green|yellow)'

# Test a service
curl http://red.dev.127.0.0.1.nip.io
```

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Code Change │────>│ GitHub Actions   │────>│  Quay.io    │
│ (git push)  │     │ (Build & Push)   │     │ (Registry)  │
└─────────────┘     └──────────────────┘     └──────┬──────┘
                                                    │
                    ┌───────────────────────────────┘
                    │ Kargo detects new image
                    v
            ┌────────────────────┐
            │ Kargo Stages       │
            │                    │
            │ Development ✓ AUTO │ sha-* tags, newest build
            │     ↓              │
            │ Staging ✓ AUTO     │ semver tags, auto-promote
            │     ↓              │
            │ Production ⏸ MANUAL│ manual approval required
            └────────┬───────────┘
                     │ Commits to git: [env] service use tag
                     v
            ┌───────────────────┐     ┌─────────────────┐
            │  ArgoCD           │────>│ Kubernetes      │
            │  (auto-sync)      │     │ Deployments     │
            └───────────────────┘     └─────────────────┘
```

### Deployment Flow

1. **Developer pushes code** to `main` branch
2. **GitHub Actions builds** Docker image with SHA tag (e.g., `sha-abc123`)
3. **Kargo dev warehouse detects** new image
4. **Development auto-promotes** → updates `k8s/overlays/development/{service}/kustomization.yaml`
5. **Git commit** created: `[dev] {service} use sha-abc123`
6. **ArgoCD auto-syncs** → deploys to development namespace
7. **Release tag** triggers semver image build (e.g., `3.2.0`)
8. **Staging auto-promotes** → similar flow to development
9. **Production requires manual** promotion via Kargo UI or CLI

## Common Operations

### Promote to Production

```bash
# Via CLI
kargo promote --project microsvcs --stage red-production

# Or use Kargo UI at http://localhost:31444
```

### Add a New Service

1. Edit [`kargo/config.yaml`](kargo/config.yaml):
   ```yaml
   services:
     - red
     - blue
     - green
     - yellow
     - orange  # add new service
   ```

2. Generate and apply Kargo manifests:
   ```bash
   cd kargo && ./generate.sh --apply
   ```

3. Add Kubernetes overlays for the new service:
   ```bash
   # Copy an existing service as a template
   cp -r k8s/overlays/development/red k8s/overlays/development/orange
   cp -r k8s/overlays/staging/red k8s/overlays/staging/orange
   cp -r k8s/overlays/production/red k8s/overlays/production/orange

   # Update image names and namespaces in kustomization.yaml files
   ```

### Rollback a Service

```bash
# Option 1: Rollback via git (recommended for GitOps)
git revert <commit-hash>
git push

# Option 2: Rollback via Kargo promotion history
kargo get freight --project microsvcs --stage red-production
kargo promote --project microsvcs --stage red-production --freight <previous-freight-id>
```

### View Deployment Status

```bash
# ArgoCD applications
kubectl get apps -n argocd

# Kargo stages
kargo get stages --project microsvcs

# Service versions across environments
./scripts/show-env.sh
```

## Project Structure

```
.
├── projects/           # Go microservices (red, blue, green, yellow)
│   ├── red/
│   ├── blue/
│   ├── green/
│   └── yellow/
├── k8s/
│   ├── base/           # Shared Kubernetes resources
│   └── overlays/       # Environment-specific configurations
│       ├── development/
│       ├── staging/
│       └── production/
├── argocd/             # ArgoCD configuration
│   ├── project.yaml
│   └── applicationset.yaml
├── kargo/              # Kargo promotion pipeline config
│   ├── config.yaml     # Single source of truth
│   ├── generate.sh     # Template renderer
│   ├── templates/      # Kargo resource templates
│   └── generated/      # Actual deployed manifests (version controlled)
├── .github/workflows/  # CI/CD pipelines
│   ├── ci.yaml
│   └── build-and-publish.yaml
└── install.sh          # One-command platform installation

```

## Documentation

- **[KARGO.md](KARGO.md)** - Complete Kargo deployment guide (scenarios, troubleshooting, architecture)
- **[kargo/README.md](kargo/README.md)** - Kargo configuration quick reference
- **[install.sh](install.sh)** - Installation script (well-commented)

## Services

| Service | Description | Port |
|---------|-------------|------|
| **Red** | Demo microservice with color API | 8080 |
| **Blue** | Demo microservice with color API | 8080 |
| **Green** | Demo microservice with color API | 8080 |
| **Yellow** | Demo microservice with color API | 8080 |

Each service is a simple Go HTTP server that demonstrates:
- Health checks (`/healthz`, `/readyz`)
- Version information (`/version`)
- Feature flags (color-specific behavior)

## Technology Stack

- **Kubernetes**: Container orchestration (via Kind locally)
- **ArgoCD**: GitOps continuous delivery
- **Kargo**: Progressive deployment automation
- **Argo Rollouts**: Advanced deployment strategies (canary, blue-green)
- **Kustomize**: Kubernetes configuration management
- **cert-manager**: TLS certificate management
- **Ingress NGINX**: Ingress controller
- **Quay.io**: Container registry
- **GitHub Actions**: CI/CD pipelines
- **Go**: Microservice implementation language

## Development

### Build a Service Locally

```bash
cd projects/red
make build
make run  # or PORT=8080 NAMESPACE=red make run
```

### Run Tests

```bash
cd projects/red
make test
```

### Build Docker Image

```bash
cd projects/red
make docker-build TAG=my-test-tag
```

## Configuration

### Environment Variables

Services use these environment variables:

- `PORT` - HTTP server port (default: 8080)
- `NAMESPACE` - Service namespace/color (red, blue, green, yellow)
- `LOG_LEVEL` - Logging level (debug, info, warn, error)

### Kargo Credentials

To enable Kargo promotions, configure credentials:

```bash
# 1. Copy the example
cp kargo/.env.example kargo/.env

# 2. Edit kargo/.env with your credentials
# GITHUB_USERNAME=your-username
# GITHUB_PAT=ghp_your_token
# QUAY_USERNAME=your-username
# QUAY_PAT=your_quay_token

# 3. Apply secrets
./kargo/apply-secrets.sh
```

## Troubleshooting

### Applications Not Syncing

```bash
# Check ArgoCD application status
kubectl get apps -n argocd

# View application details
kubectl describe app red-development -n argocd

# Force sync
kubectl patch app red-development -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Kargo Promotion Failures

```bash
# Check Kargo stage status
kargo get stages --project microsvcs

# View promotion logs
kargo get promotions --project microsvcs --stage red-development

# Check ArgoCD authorization annotation
kubectl get app red-development -n argocd -o jsonpath='{.metadata.annotations.kargo\.akuity\.io/authorized-stage}'
```

### Clean Restart

```bash
# Delete the cluster
kind delete cluster --name microsvcs

# Reinstall
./install.sh
```

## Contributing

Contributions are welcome! This project is designed as a learning platform for GitOps and progressive delivery.

## License

Apache 2.0

## Resources

- [Kargo Documentation](https://kargo.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Argo Rollouts Documentation](https://argoproj.github.io/rollouts/)
- [GitOps Principles](https://opengitops.dev/)

---

**Built with ❤️ by [David Aparicio](https://github.com/davidaparicio)**
