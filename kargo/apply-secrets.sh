#!/bin/bash
set -euo pipefail

# Script to apply Kargo secrets using environment variables from .env file
# https://blog.stephane-robert.info/docs/outils/projets/envsubst/
# https://blog.filador.ch/en/posts/kargo-deploy-from-one-environment-to-another-with-gitops/
# https://docs.kargo.io/user-guide/security/managing-credentials/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please create it from .env.example and fill in your credentials:"
    echo "  cp $SCRIPT_DIR/.env.example $SCRIPT_DIR/.env"
    exit 1
fi

# Check if envsubst is installed
if ! command -v envsubst &> /dev/null; then
    echo "Error: envsubst is not installed"
    echo "Install it with: apt-get install gettext-base (Debian/Ubuntu) or brew install gettext (macOS)"
    exit 1
fi

# Load environment variables from .env file
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Verify required variables are set
required_vars=("GITHUB_USERNAME" "GITHUB_PAT" "DOCKERHUB_USERNAME" "DOCKERHUB_PAT")
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set in .env file"
        exit 1
    fi
done

echo "Applying Kargo secrets with credentials from .env..."

# Ensure namespace exists with Kargo project label
if ! kubectl get namespace microsvcs &> /dev/null; then
    echo "- Creating namespace microsvcs..."
    kubectl create namespace microsvcs
fi
kubectl label namespace microsvcs kargo.akuity.io/project=true --overwrite &> /dev/null

# Apply git credentials
echo "- Applying GitHub credentials..."
envsubst < "${SCRIPT_DIR}/git-credentials.yaml" | kubectl apply -f -

# Apply DockerHub credentials
echo "- Applying DockerHub credentials..."
envsubst < "${SCRIPT_DIR}/dockerhub-credentials.yaml" | kubectl apply -f -

echo "✓ Secrets applied successfully!"
echo ""
echo "Verify with:"
echo "  kubectl get secrets -n microsvcs github-creds dockerhub-creds"
