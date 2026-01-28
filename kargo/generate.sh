#!/bin/bash
set -euo pipefail

# Kargo manifest generator — reads config.yaml, writes generated/
# Usage: ./generate.sh [--apply]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.yaml"
OUT="${SCRIPT_DIR}/generated"

# Check dependencies
command -v yq &>/dev/null || { echo "Error: yq is required. https://github.com/mikefarah/yq#install"; exit 1; }

# Read config
PROJECT=$(yq '.project' "$CONFIG")
NAMESPACE=$(yq '.namespace' "$CONFIG")
GIT_REPO=$(yq '.gitRepo' "$CONFIG")
GIT_BRANCH=$(yq '.gitBranch' "$CONFIG")
REGISTRY=$(yq '.dockerRegistry' "$CONFIG")
KUSTOMIZE_BASE=$(yq '.kustomizeBasePath' "$CONFIG")

mapfile -t SERVICES < <(yq '.services[]' "$CONFIG")

echo "Generating Kargo manifests for: ${SERVICES[*]}"

rm -rf "$OUT"
mkdir -p "$OUT"/{warehouses,stages}

# --- Project ---
cat > "$OUT/project.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: ${PROJECT}
EOF

# --- Per-service resources ---
for SVC in "${SERVICES[@]}"; do

  # Warehouse: dev (sha-* tags)
  DEV_PATTERN=$(yq '.environments[] | select(.name == "development") | .warehouse.imageTagPattern' "$CONFIG")
  DEV_STRATEGY=$(yq '.environments[] | select(.name == "development") | .warehouse.imageSelectionStrategy' "$CONFIG")
  DEV_LIMIT=$(yq '.environments[] | select(.name == "development") | .warehouse.discoveryLimit' "$CONFIG")

  cat > "$OUT/warehouses/${SVC}-dev.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: ${SVC}-dev
  namespace: ${NAMESPACE}
spec:
  subscriptions:
  - image:
      repoURL: ${REGISTRY}/${SVC}
      imageSelectionStrategy: ${DEV_STRATEGY}
      allowTags: "${DEV_PATTERN}"
      discoveryLimit: ${DEV_LIMIT}
EOF

  # Warehouse: releases (semver tags)
  REL_SEMVER=$(yq '.environments[] | select(.name == "staging") | .warehouse.semverConstraint' "$CONFIG")
  REL_STRATEGY=$(yq '.environments[] | select(.name == "staging") | .warehouse.imageSelectionStrategy' "$CONFIG")
  REL_LIMIT=$(yq '.environments[] | select(.name == "staging") | .warehouse.discoveryLimit' "$CONFIG")

  cat > "$OUT/warehouses/${SVC}-releases.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: ${SVC}-releases
  namespace: ${NAMESPACE}
spec:
  subscriptions:
  - image:
      repoURL: ${REGISTRY}/${SVC}
      imageSelectionStrategy: ${REL_STRATEGY}
      semverConstraint: "${REL_SEMVER}"
      discoveryLimit: ${REL_LIMIT}
EOF

  # Helper: generate a stage with git-clone → kustomize-set-image → git-commit → git-push
  gen_stage() {
    local name=$1 env=$2 freight_yaml=$3
    cat > "$OUT/stages/${name}.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
spec:
  requestedFreight:
${freight_yaml}
  promotionTemplate:
    spec:
      steps:
      - uses: git-clone
        config:
          repoURL: ${GIT_REPO}
          checkout:
          - branch: ${GIT_BRANCH}
            path: ./repo
      - uses: kustomize-set-image
        config:
          path: ./repo/${KUSTOMIZE_BASE}/${env}/${SVC}
          images:
          - image: ${REGISTRY}/${SVC}
            tag: \${{ imageFrom("${REGISTRY}/${SVC}").Tag }}
      - uses: git-commit
        config:
          path: ./repo
          message: '[${env:0:3}] ${SVC} use \${{ imageFrom("${REGISTRY}/${SVC}").Tag }}'
      - uses: git-push
        config:
          path: ./repo
EOF
  }

  # Stage: development (direct from dev warehouse, auto-promote)
  gen_stage "${SVC}-development" "development" "  - origin:
      kind: Warehouse
      name: ${SVC}-dev
    sources:
      direct: true"

  # Stage: staging (direct from releases warehouse, auto-promote)
  gen_stage "${SVC}-staging" "staging" "  - origin:
      kind: Warehouse
      name: ${SVC}-releases
    sources:
      direct: true"

  # Stage: production (from staging, manual promote)
  gen_stage "${SVC}-production" "production" "  - origin:
      kind: Warehouse
      name: ${SVC}-releases
    sources:
      stages:
      - ${SVC}-staging"

done

WAREHOUSES=$(find "$OUT/warehouses" -name '*.yaml' | wc -l | tr -d ' ')
STAGES=$(find "$OUT/stages" -name '*.yaml' | wc -l | tr -d ' ')
echo "Generated: 1 project, ${WAREHOUSES} warehouses, ${STAGES} stages → ${OUT}/"

# Optional: apply directly
if [[ "${1:-}" == "--apply" ]]; then
  command -v kubectl &>/dev/null || { echo "Error: kubectl is required"; exit 1; }
  kubectl apply -f "$OUT/project.yaml"
  kubectl apply -f "$OUT/warehouses/"
  kubectl apply -f "$OUT/stages/"
  echo "Applied to cluster."
fi
