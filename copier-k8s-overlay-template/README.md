# copier-k8s-overlay-template

A [Copier](https://github.com/copier-org/copier) template for Kustomize overlays.

It generates the three `kustomization.yaml` files
(`development / staging / production`) for a single microservice from one
template, eliminating the per-service, per-environment copy-paste.

## Structure generated

```
k8s/overlays/
├── development/<service_name>/kustomization.yaml
├── staging/<service_name>/kustomization.yaml
└── production/<service_name>/kustomization.yaml
```

## Prerequisites

```sh
pip install copier
```

## Add overlays for a new service

```sh
# From the repo root — destination is the overlays directory
copier copy ./copier-k8s-overlay-template k8s/overlays \
  --answers-file k8s/overlays/.copier-answers-purple.yml
```

## Update overlays after a template change

```sh
copier update k8s/overlays --answers-file k8s/overlays/.copier-answers-blue.yml
copier update k8s/overlays --answers-file k8s/overlays/.copier-answers-red.yml
copier update k8s/overlays --answers-file k8s/overlays/.copier-answers-green.yml
copier update k8s/overlays --answers-file k8s/overlays/.copier-answers-yellow.yml
```

## Update image tags

Image tags change frequently (every build / release). Rather than running
`copier update`, edit the relevant `.copier-answers-<service>.yml` file and
re-run the update command — Copier will merge the new tag into the rendered
files automatically.

## Template variables

| Variable | Default | Description |
|---|---|---|
| `service_name` | _(required)_ | Microservice name, e.g. `blue` |
| `org` | `davidaparicio` | Registry namespace |
| `domain_suffix` | `127.0.0.1.nip.io` | Base domain for ingress hosts |
| `dev_image_tag` | `sha-latest` | Dev image tag (short SHA) |
| `staging_image_tag` | `0.1.0` | Staging image tag (semver) |
| `production_image_tag` | `0.1.0` | Production image tag (semver) |

## Resource tiers

The template encodes the environment-specific resource defaults:

| Environment | Replicas | Mem req/lim | CPU req/lim |
|---|---|---|---|
| development | 1 | 32 Mi / 64 Mi | 50 m / 100 m |
| staging | 2 | 64 Mi / 128 Mi | 100 m / 250 m |
| production | 3 | 128 Mi / 256 Mi | 200 m / 500 m |
