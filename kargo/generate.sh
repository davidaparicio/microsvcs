#!/bin/bash
set -euo pipefail

# Kargo manifest generator — renders templates/ with config.yaml values into generated/
# Usage: ./generate.sh [--apply]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.yaml"
TEMPLATES="${SCRIPT_DIR}/templates"
OUT="${SCRIPT_DIR}/generated"

command -v yq &>/dev/null || { echo "Error: yq is required. https://github.com/mikefarah/yq#install"; exit 1; }
command -v envsubst &>/dev/null || { echo "Error: envsubst is required (part of gettext)."; exit 1; }

# Read config into environment variables
export PROJECT=$(yq -r '.project' "$CONFIG")
export NAMESPACE=$(yq -r '.namespace' "$CONFIG")
export GIT_REPO=$(yq -r '.gitRepo' "$CONFIG")
export GIT_BRANCH=$(yq -r '.gitBranch' "$CONFIG")
export REGISTRY=$(yq -r '.dockerRegistry' "$CONFIG")
export KUSTOMIZE_BASE=$(yq -r '.kustomizeBasePath' "$CONFIG")

export DEV_PATTERN=$(yq -r '.environments[] | select(.name == "development") | .warehouse.imageTagPattern' "$CONFIG")
export DEV_STRATEGY=$(yq -r '.environments[] | select(.name == "development") | .warehouse.imageSelectionStrategy' "$CONFIG")
export DEV_LIMIT=$(yq -r '.environments[] | select(.name == "development") | .warehouse.discoveryLimit' "$CONFIG")

export REL_SEMVER=$(yq -r '.environments[] | select(.name == "staging") | .warehouse.semverConstraint' "$CONFIG")
export REL_STRATEGY=$(yq -r '.environments[] | select(.name == "staging") | .warehouse.imageSelectionStrategy' "$CONFIG")
export REL_LIMIT=$(yq -r '.environments[] | select(.name == "staging") | .warehouse.discoveryLimit' "$CONFIG")

export DEV_AUTO_PROMOTE=$(yq -r '.environments[] | select(.name == "development") | .autoPromote' "$CONFIG")
export STG_AUTO_PROMOTE=$(yq -r '.environments[] | select(.name == "staging") | .autoPromote' "$CONFIG")
export PRD_AUTO_PROMOTE=$(yq -r '.environments[] | select(.name == "production") | .autoPromote' "$CONFIG")

# The read -r -d '' -a approach works on Bash 3.2 (macOS default). 
# Alternatively, you could change the shebang to #!/usr/bin/env bash
# & install Bash 4+ via brew install bash, but the portable fix is simpler.
# mapfile -t SERVICES < <(yq -r '.services[]' "$CONFIG")
IFS=$'\n' read -r -d '' -a SERVICES < <(yq -r '.services[]' "$CONFIG" && printf '\0')

echo "Generating Kargo manifests for: ${SERVICES[*]}"

rm -rf "$OUT"
mkdir -p "$OUT"/{warehouses,stages,analysis}

# Render a template file, substituting only our variables (leaves ${{ ... }} Kargo expressions alone)
VARS='${PROJECT} ${NAMESPACE} ${GIT_REPO} ${GIT_BRANCH} ${REGISTRY} ${KUSTOMIZE_BASE} ${SVC} ${DEV_PATTERN} ${DEV_STRATEGY} ${DEV_LIMIT} ${REL_SEMVER} ${REL_STRATEGY} ${REL_LIMIT} ${DEV_AUTO_PROMOTE} ${STG_AUTO_PROMOTE} ${PRD_AUTO_PROMOTE}'

render() {
  envsubst "$VARS" < "$1" > "$2"
}

# Project
render "$TEMPLATES/project.yaml" "$OUT/project.yaml"
render "$TEMPLATES/project-config.yaml" "$OUT/project-config.yaml"

# Shared resources
render "$TEMPLATES/analysis-http-check.yaml" "$OUT/analysis/http-check.yaml"

# Per-service resources
for SVC in "${SERVICES[@]}"; do
  export SVC
  render "$TEMPLATES/warehouse-dev.yaml"      "$OUT/warehouses/${SVC}-dev.yaml"
  render "$TEMPLATES/warehouse-releases.yaml"  "$OUT/warehouses/${SVC}-releases.yaml"
  render "$TEMPLATES/stage-development.yaml"   "$OUT/stages/${SVC}-development.yaml"
  render "$TEMPLATES/stage-staging.yaml"       "$OUT/stages/${SVC}-staging.yaml"
  render "$TEMPLATES/stage-production.yaml"    "$OUT/stages/${SVC}-production.yaml"
done

WAREHOUSES=$(find "$OUT/warehouses" -name '*.yaml' | wc -l | tr -d ' ')
STAGES=$(find "$OUT/stages" -name '*.yaml' | wc -l | tr -d ' ')
ANALYSIS=$(find "$OUT/analysis" -name '*.yaml' | wc -l | tr -d ' ')
echo "Generated: 1 project, 1 project-config, ${WAREHOUSES} warehouses, ${STAGES} stages, ${ANALYSIS} analysis templates → ${OUT}/"

# Optional: apply directly
if [[ "${1:-}" == "--apply" ]]; then
  command -v kubectl &>/dev/null || { echo "Error: kubectl is required"; exit 1; }
  kubectl apply -f "$OUT/project.yaml"
  kubectl apply -f "$OUT/project-config.yaml"
  kubectl apply -f "$OUT/warehouses/"
  kubectl apply -f "$OUT/analysis/"
  kubectl apply -f "$OUT/stages/"
  echo "Applied to cluster."
fi
