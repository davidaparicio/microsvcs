# copier-microservice-template

A [Copier](https://github.com/copier-org/copier) template for GoColor microservices.

It eliminates boilerplate duplication across `red`, `blue`, `green`, and `yellow` by
keeping the following files in a single, authoritative template:

| Template file | Rendered output |
|---|---|
| `template/Makefile.jinja` | `Makefile` |
| `template/docker/Dockerfile.jinja` | `docker/Dockerfile` |
| `template/.dockerignore` | `.dockerignore` |
| `template/go.mod.jinja` | `go.mod` |

Only the handful of values that genuinely differ per service (name, module path,
author, Go/image versions) are parameterised.

## Prerequisites

```sh
pip install copier
```

## Scaffold a new service

```sh
# From the repo root
copier copy ./copier-microservice-template projects/purple
```

Copier will ask the questions defined in `copier.yaml` and render all template
files into `projects/purple/`.  The answers are saved to
`projects/purple/.copier-answers.yml` so future updates are non-interactive.

## Update an existing service

When the template changes (e.g. a new Makefile target, a Go image bump), propagate
the change to every service with a single command per service:

```sh
copier update projects/red
copier update projects/blue
copier update projects/green
copier update projects/yellow
```

Copier diffs the re-rendered template against the working tree and only touches
lines that changed, so service-specific customisations are preserved.

## Template variables

| Variable | Default | Description |
|---|---|---|
| `service_name` | _(required)_ | Service name, e.g. `red` |
| `org` | `davidaparicio` | GitHub org / Quay.io namespace |
| `module_root` | `github.com/{{ org }}/microsvcs/projects` | Go module path prefix |
| `author_name` | `David Aparicio` | Author full name |
| `author_email` | `david.aparicio@free.fr` | Author email |
| `go_version` | `1.25.5` | Go toolchain version in `go.mod` |
| `go_image_version` | `1.26-alpine3.23` | golang Docker image tag |
| `go_image_digest` | _(pinned SHA)_ | golang image digest for reproducible builds |
| `year` | `2026` | Copyright year |
