# Git-Sync Microservice

A lightweight Go-based git-sync service that periodically syncs files from a git repository to a local directory. Designed to run as both a standalone service and as a sidecar container in Kubernetes.

## Features

- Periodic git synchronization using cron scheduling
- Shallow clones for efficiency (depth=1)
- Health check endpoints for Kubernetes probes
- Metrics endpoint for monitoring
- Configurable via environment variables
- Pure Go implementation (no external git binary required)
- Minimal container footprint (scratch-based image)

## Configuration

All configuration is done via environment variables:

### Required

- `GIT_REPO_URL` - Git repository URL to sync from

### Optional

- `GIT_BRANCH` - Branch to sync (default: `main`)
- `GIT_SOURCE_PATH` - Path within the repository to sync (default: `/`)
- `TARGET_PATH` - Local directory to sync files to (default: `/data`)
- `SYNC_INTERVAL` - Cron format sync interval (default: `*/5 * * * *` - every 5 minutes)
- `SYNC_ONCE` - Run once and exit (default: `false`)
- `PORT` - Health check server port (default: `8080`)

## Endpoints

- `GET /healthz` - Returns 204 if healthy, 503 if not
- `GET /readyz` - Returns JSON readiness status
- `GET /metrics` - Returns JSON metrics (sync count, errors, last sync time, etc.)
- `GET /version` - Returns version information

## Usage

### Standalone

```bash
docker run -it --rm \
  -e GIT_REPO_URL=https://github.com/your/repo.git \
  -e GIT_BRANCH=main \
  -e TARGET_PATH=/data \
  -v /local/path:/data \
  quay.io/davidaparicio/git-sync:latest
```

### Kubernetes Sidecar

```yaml
containers:
- name: app
  image: your-app:latest
  volumeMounts:
  - name: config
    mountPath: /app/config
    readOnly: true

- name: git-sync
  image: quay.io/davidaparicio/git-sync:latest
  env:
  - name: GIT_REPO_URL
    value: "https://github.com/your/config-repo.git"
  - name: TARGET_PATH
    value: "/shared/config"
  volumeMounts:
  - name: config
    mountPath: /shared/config

volumes:
- name: config
  emptyDir: {}
```

## Development

### Build

```bash
make compile
```

### Run Locally

```bash
GIT_REPO_URL=https://github.com/davidaparicio/microsvcs.git \
TARGET_PATH=/tmp/sync \
make run
```

### Test

Run unit tests (fast):
```bash
make test
```

Run E2E tests (requires network access):
```bash
go test -v ./internal/sync -run TestE2E
```

Run all tests including E2E:
```bash
go test -v ./...
```

### Docker Build

```bash
make dockerbuild
```

## E2E Tests

The project includes comprehensive end-to-end tests that validate real-world sync scenarios:

### TestE2E_SyncDemoFlags
Syncs the `color/demo-flags.goff.yaml` file from the microsvcs repository and validates:
- ✅ Feature flag percentage values (`green_var: 5`, `red_var: 10`, `default_var: 35`)
- ✅ Disable flag is `false`
- ✅ All 11 color variations are present
- ✅ File content matches expected structure

### TestE2E_SyncSpecificFile
Tests syncing a single file (README.md) instead of a directory.

### TestE2E_MultipleSyncs
Validates that multiple sync operations work correctly with both clone and pull operations.

## License

Apache-2.0
