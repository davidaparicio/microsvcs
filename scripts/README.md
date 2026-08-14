# Scripts

Utility scripts for managing the microservices deployment.

## show-env.sh

Display the current deployment state of all microservices across environments.

### Usage

```bash
./scripts/show-env.sh [environment]
```

### Arguments

- `environment` - Environment to query (optional)
  - `development` - Show development versions
  - `staging` - Show staging versions
  - `production` - Show production versions
  - `all` - Show all environments (default)

### Examples

```bash
# Show production versions
./scripts/show-env.sh production

# Show staging versions
./scripts/show-env.sh staging

# Show development versions
./scripts/show-env.sh development

# Show all environments (same as no argument)
./scripts/show-env.sh all
./scripts/show-env.sh
```

### Sample Output

```
╔══════════════════════════════════════════════════════════╗
║  Microservices Deployment Status                        ║
╚══════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PRODUCTION Environment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Service         Version                   Last Updated
─────────────── ───────────────────────── ─────────────────────────
blue            2.1.3                     2 hours ago
green           1.4.8                     3 days ago
yellow          2.2.0                     1 day ago
red             3.0.8                     2 weeks ago

Repository Info:
  Branch:  main
  Commit:  abc123 - feat(blue): add feature (10 minutes ago)
```

### Requirements

- `yq` - YAML processor
  ```bash
  pip install yq
  ```

- `git` - Version control (for commit history)

### How It Works

The script reads the Kustomize configuration files in `k8s/overlays/{env}/{service}/kustomization.yaml` to determine what version is currently deployed in each environment.

It also uses `git log` to show when each service was last updated in each environment.

---

## get-env.sh

Checkout service code to match deployed versions in an environment.

### Usage

```bash
./scripts/get-env.sh [environment|reset]
```

### Arguments

- `environment` - Environment to match
  - `development` - Checkout code matching development
  - `staging` - Checkout code matching staging
  - `production` - Checkout code matching production
- `reset` - Reset all services to main branch

### Examples

```bash
# Checkout code matching production
./scripts/get-env.sh production

# Checkout code matching staging
./scripts/get-env.sh staging

# Reset all services to main branch
./scripts/get-env.sh reset
```

### What It Does

This script checks out the **actual source code** for each microservice to match the versions currently deployed in the specified environment.

**Perfect for debugging!** You can see the exact code running in production, staging, or development.

### How It Works

1. Reads the Kustomize configuration files to determine deployed versions
2. For each service, finds the corresponding Git tag (e.g., `blue/2.1.3`)
3. Checks out that specific version in the `projects/{service}/` directory
4. Shows a summary of what was checked out

### Sample Output

```
╔══════════════════════════════════════════════════════════╗
║  Checking out code for PRODUCTION environment           ║
╚══════════════════════════════════════════════════════════╝

→ Checking out blue to 2.1.3 (ref: blue/2.1.3)
✓ Successfully checked out blue to 2.1.3

→ Checking out green to 1.4.8 (ref: green/1.4.8)
✓ Successfully checked out green to 1.4.8

→ Checking out yellow to 2.2.0 (ref: yellow/2.2.0)
✓ Successfully checked out yellow to 2.2.0

→ Checking out red to 3.0.8 (ref: red/3.0.8)
✓ Successfully checked out red to 3.0.8

Summary:
  ✓ Success: 4

Current service versions:
  blue: a1b2c3d (detached)
  green: e4f5g6h (detached)
  yellow: i7j8k9l (detached)
  red: m0n1o2p (detached)

Note: Your working directory has been modified.
      Run ./scripts/get-env.sh reset to return to main branch.
```

### Requirements

- `yq` - YAML processor
  ```bash
  pip install yq
  ```

- `git` - Version control

### Safety Features

- **Checks for uncommitted changes** before proceeding
- **Shows clear warnings** when modifying working directory
- **Easy reset** to return to main branch

### Common Workflow

```bash
# 1. See what's deployed in production
./scripts/show-env.sh production

# 2. Checkout production code for debugging
./scripts/get-env.sh production

# 3. Debug the issue in projects/blue/
cd projects/blue
# ... investigate ...

# 4. Reset back to main when done
./scripts/get-env.sh reset
```

---

## curl_envs.sh

Smoke-test all services across every environment with a single `curl` call per endpoint.

### Usage

```bash
# Uses NodePort 30080 by default (kind cluster mapping)
./scripts/curl_envs.sh

# Override the port
INGRESS_PORT=80 ./scripts/curl_envs.sh
```

### What It Does

Hits the `/version` endpoint of every color service (red, blue, green, yellow) in
development, staging, and production, printing the response inline.

### Requirements

- `curl`
- A running kind cluster with ingress-nginx on port 30080 (see `k8s/kind-config.yaml`)

---

## Creating Convenient Aliases

You can add these aliases to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
# Add to your shell profile

# Show environment status
alias show-env='./scripts/show-env.sh'
alias show-env-prod='./scripts/show-env.sh production'
alias show-env-stg='./scripts/show-env.sh staging'
alias show-env-dev='./scripts/show-env.sh development'

# Get environment code
alias get-env='./scripts/get-env.sh'
alias get-env-prod='./scripts/get-env.sh production'
alias get-env-stg='./scripts/get-env.sh staging'
alias get-env-dev='./scripts/get-env.sh development'
alias get-env-reset='./scripts/get-env.sh reset'
```

Then use them like:

```bash
# Show versions
show-env prod        # Show production versions
show-env stg         # Show staging versions
show-env dev         # Show development versions
show-env             # Show all environments

# Checkout code
get-env prod         # Checkout production code
get-env stg          # Checkout staging code
get-env reset        # Reset to main
```

Or make them global commands:

```bash
# Create symlinks in your PATH
sudo ln -s "$(pwd)/scripts/show-env.sh" /usr/local/bin/show-env
sudo ln -s "$(pwd)/scripts/get-env.sh" /usr/local/bin/get-env

# Now use from anywhere
show-env production
get-env production
get-env reset
```
