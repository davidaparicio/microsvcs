# Red - WebColor Microservice

A colorful web server microservice for Kubernetes demonstrations with feature flag support.

> Part of the [microsvcs](../../README.md) project - See [projects overview](../README.md) for information about all color variants.

## Overview

This is the **red variant** of the base [color](../../color) project, configured to predominantly display red colored user boxes (80% red, 20% grey by default). It demonstrates feature flag capabilities using [GO Feature Flag](https://gofeatureflag.org/) to dynamically control color distribution across 2500 simulated users.

## What It Does

The server serves an HTML page that displays:

- A grid of 2500 colored boxes representing different users
- System information (hostname, OS, architecture, namespace, pod color)
- Color distribution controlled by feature flags in real-time

The pod color is extracted from the Kubernetes hostname pattern `${HOSTNAME%%-*}`, so a pod named `red-xxxxyyyyzzzz-abcde` will display as "red" in the namespace/pod color indicator.

## Features

- **Feature Flag Integration**: Uses GO Feature Flag for dynamic color distribution
- **Real-time Updates**: Polls feature flag configuration every second
- **2500 Simulated Users**: Each user can have a different color based on targeting rules
- **Kubernetes-Aware**: Automatically detects pod name and namespace
- **Lightweight**: Built with Echo framework, minimal dependencies
- **Cloud Native**: Designed for containerized deployments

## Configuration

The color distribution is controlled by [demo-flags.goff.yaml](demo-flags.goff.yaml):

```yaml
color-box:
  defaultRule:
    percentage:
      red_var: 80      # 80% of users see red boxes
      default_var: 20  # 20% see grey boxes (default)
```

You can customize targeting rules to:

- Target specific user IDs
- Use query patterns for user segmentation
- Adjust percentage distribution across multiple colors

## Quick Start

### Run Locally

```bash
make run
```

The server will start on port 8080 (or PORT environment variable).

### Build

```bash
make compile
```

Binary will be created at `bin/red`.

### Docker

```bash
make dockerfull
```

This builds and runs the container, exposing port 8080.

## Development

### Prerequisites

- Go 1.25.5 or later
- Docker (for containerized builds)
- golangci-lint (for linting)

### Available Make Targets

```bash
make help           # Show all available commands
make compile        # Build the binary
make test           # Run tests
make lint           # Run linter
make format         # Format code with gofmt
make benchmark      # Run benchmarks
make sec            # Security checks (gosec, govulncheck)
make goreleaser     # Build with goreleaser
```

For more development details, see the [projects overview](../README.md).

## Project Structure

```text
.
├── webcolor_ff.go           # Main application entry point
├── internal/
│   ├── version/             # Version information
│   └── name/                # Hostname and namespace utilities
├── assets/
│   ├── view/template.html   # HTML template
│   ├── css/style.css        # Styling
│   └── js/script.js         # Client-side JavaScript
├── docker/Dockerfile        # Container image definition
└── demo-flags.goff.yaml     # Feature flag configuration
```

## Architecture

### Color Variants

This is one of four color variants in the microservices demo:

- **[red](../red)** - Red themed variant (current project) - v2.1.2
- **[blue](../blue)** - Blue themed variant - v2.1.3
- **[green](../green)** - Green themed variant - v2.1.2
- **[yellow](../yellow)** - Yellow themed variant - v2.1.2
- **[color](../../color)** - Base project (template)

Each variant is an independent microservice with its own versioning, feature flags, and deployment configuration.

## Kubernetes Deployment

### Quick Deploy

Deploy to development environment:

```bash
# From repository root
kubectl apply -k k8s/overlays/development/red
```

### GitOps with ArgoCD

For GitOps deployment with ArgoCD, see the [main README](../../README.md#kubernetes-deployment) and [argocd](../../argocd) directory.

The ArgoCD ApplicationSet automatically deploys this service across multiple environments.

## Integration Points

### Feature Flag Server

The service polls `demo-flags.goff.yaml` every second for configuration changes. For production, consider using:

- GO Feature Flag Relay Proxy
- Remote configuration storage (S3, HTTP, etc.)
- Centralized flag management UI

### Observability

Each request displays:

- **System Info**: Hostname, OS, architecture
- **Kubernetes Metadata**: Namespace, pod name, pod color
- **Request Details**: Client IP, path
- **User Distribution**: Visual grid showing color assignments

### Ingress

When deployed to Kubernetes, the service is accessible via ingress at:

- Development: `http://red.development.local`
- Staging: `http://red.staging.local`
- Production: `http://red.production.local`

Configure `/etc/hosts` or DNS accordingly.

## Version

**Current version**: 2.1.2

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Related Documentation

- [Projects Overview](../README.md) - Information about all color variants
- [Main Project README](../../README.md) - Overall project documentation
- [Kubernetes Manifests](../../k8s) - Deployment configurations
- [ArgoCD Setup](../../argocd) - GitOps configurations
- [Color Base Project](../../color) - Template for all variants

## License

MIT License - Copyright (c) 2026 David Aparicio

Modified from the original [webcolor](https://github.com/jpetazzo/color) project by Jérôme Petazzoni.

## Credits

- **Original Concept**: [Jérôme Petazzoni](https://github.com/jpetazzo/color)
- **Modified by**: [David Aparicio](https://github.com/davidaparicio)
- **Feature Flags**: [GO Feature Flag](https://gofeatureflag.org/)
