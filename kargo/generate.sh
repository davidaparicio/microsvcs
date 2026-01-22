#!/bin/bash
set -euo pipefail

# Kargo Configuration Generator
# Generates all Kargo resources from config.yaml using templates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
OUTPUT_DIR="${SCRIPT_DIR}/generated"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kargo Configuration Generator ===${NC}"

# Check dependencies
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}Error: yq is not installed${NC}"
    echo "Install with: brew install yq"
    exit 1
fi

# Validate config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Error: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Clean and recreate output directories
echo -e "${BLUE}Cleaning output directory...${NC}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/warehouses" "${OUTPUT_DIR}/stages"

# Parse config
PROJECT=$(yq e '.project' "$CONFIG_FILE")
NAMESPACE=$(yq e '.namespace' "$CONFIG_FILE")
GIT_REPO=$(yq e '.gitRepo' "$CONFIG_FILE")
GIT_BRANCH=$(yq e '.gitBranch' "$CONFIG_FILE")
DOCKER_REGISTRY=$(yq e '.dockerRegistry' "$CONFIG_FILE")
DISCOVERY_LIMIT=$(yq e '.warehouse.discoveryLimit' "$CONFIG_FILE")
PLATFORM=$(yq e '.warehouse.platform' "$CONFIG_FILE")

# Get services array
SERVICES=($(yq e '.services[]' "$CONFIG_FILE"))

# Get environment configs
DEV_AUTO_PROMOTE=$(yq e '.environments[] | select(.name == "development") | .autoPromote' "$CONFIG_FILE")
DEV_IMAGE_TAG_PATTERN=$(yq e '.environments[] | select(.name == "development") | .imageTagPattern' "$CONFIG_FILE")
STAGING_AUTO_PROMOTE=$(yq e '.environments[] | select(.name == "staging") | .autoPromote' "$CONFIG_FILE")
STAGING_SEMVER=$(yq e '.environments[] | select(.name == "staging") | .semverConstraint' "$CONFIG_FILE")
PROD_AUTO_PROMOTE=$(yq e '.environments[] | select(.name == "production") | .autoPromote' "$CONFIG_FILE")

echo -e "${BLUE}Configuration:${NC}"
echo "  Project: $PROJECT"
echo "  Namespace: $NAMESPACE"
echo "  Services: ${SERVICES[*]}"
echo "  Git Repo: $GIT_REPO"
echo "  Git Branch: $GIT_BRANCH"
echo "  Platform: $PLATFORM"
echo ""

# Generate project.yaml with promotion policies
echo -e "${GREEN}Generating project.yaml...${NC}"
cat > "${OUTPUT_DIR}/project.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: ${PROJECT}
spec:
  promotionPolicies:
EOF

for service in "${SERVICES[@]}"; do
    cat >> "${OUTPUT_DIR}/project.yaml" <<EOF
    - stage: ${service}-development
      autoPromotionEnabled: ${DEV_AUTO_PROMOTE}
    - stage: ${service}-staging
      autoPromotionEnabled: ${STAGING_AUTO_PROMOTE}
    - stage: ${service}-production
      autoPromotionEnabled: ${PROD_AUTO_PROMOTE}
EOF
done

echo "  ✓ Created project.yaml with $((${#SERVICES[@]} * 3)) promotion policies"

# Generate warehouses (2 per service: dev + releases)
echo -e "${GREEN}Generating warehouses...${NC}"
for service in "${SERVICES[@]}"; do
    # Dev warehouse (sha-* tags)
    cat > "${OUTPUT_DIR}/warehouses/${service}-dev.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: ${service}-dev
  namespace: ${NAMESPACE}
spec:
  subscriptions:
    - image:
        repoURL: ${DOCKER_REGISTRY}/${service}
        imageSelectionStrategy: NewestBuild
        platform: ${PLATFORM}
        discoveryLimit: ${DISCOVERY_LIMIT}
        tagSelection:
          allowTags:
            - ${DEV_IMAGE_TAG_PATTERN}
EOF
    echo "  ✓ Created ${service}-dev.yaml (sha-* tags)"

    # Releases warehouse (semantic versions)
    cat > "${OUTPUT_DIR}/warehouses/${service}-releases.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: ${service}-releases
  namespace: ${NAMESPACE}
spec:
  subscriptions:
    - image:
        repoURL: ${DOCKER_REGISTRY}/${service}
        semverConstraint: "${STAGING_SEMVER}"
        platform: ${PLATFORM}
        discoveryLimit: ${DISCOVERY_LIMIT}
EOF
    echo "  ✓ Created ${service}-releases.yaml (semver tags)"
done

# Generate stages (3 per service: dev, staging, prod)
echo -e "${GREEN}Generating stages...${NC}"
for service in "${SERVICES[@]}"; do
    # Development stage (subscribes to dev warehouse)
    cat > "${OUTPUT_DIR}/stages/${service}-development.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${service}-development
  namespace: ${NAMESPACE}
spec:
  subscriptions:
    warehouse: ${service}-dev
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: ${GIT_REPO}
        writeBranch: ${GIT_BRANCH}
        kustomize:
          images:
            - image: ${DOCKER_REGISTRY}/${service}
              path: k8s/overlays/development/${service}
    argoCDAppUpdates:
      - appName: ${service}-development
        appNamespace: argocd
EOF
    echo "  ✓ Created ${service}-development.yaml"

    # Staging stage (subscribes to releases warehouse)
    cat > "${OUTPUT_DIR}/stages/${service}-staging.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${service}-staging
  namespace: ${NAMESPACE}
spec:
  subscriptions:
    warehouse: ${service}-releases
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: ${GIT_REPO}
        writeBranch: ${GIT_BRANCH}
        kustomize:
          images:
            - image: ${DOCKER_REGISTRY}/${service}
              path: k8s/overlays/staging/${service}
    argoCDAppUpdates:
      - appName: ${service}-staging
        appNamespace: argocd
EOF
    echo "  ✓ Created ${service}-staging.yaml"

    # Production stage (subscribes to upstream staging)
    cat > "${OUTPUT_DIR}/stages/${service}-production.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${service}-production
  namespace: ${NAMESPACE}
spec:
  subscriptions:
    upstreamStages:
      - name: ${service}-staging
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: ${GIT_REPO}
        writeBranch: ${GIT_BRANCH}
        kustomize:
          images:
            - image: ${DOCKER_REGISTRY}/${service}
              path: k8s/overlays/production/${service}
    argoCDAppUpdates:
      - appName: ${service}-production
        appNamespace: argocd
EOF
    echo "  ✓ Created ${service}-production.yaml"
done

# Summary
echo ""
echo -e "${GREEN}=== Generation Complete ===${NC}"
echo "Generated files:"
echo "  1 project file: ${OUTPUT_DIR}/project.yaml"
echo "  $((${#SERVICES[@]} * 2)) warehouses: ${OUTPUT_DIR}/warehouses/"
echo "  $((${#SERVICES[@]} * 3)) stages: ${OUTPUT_DIR}/stages/"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Review generated files in: ${OUTPUT_DIR}/"
echo "  2. Apply to cluster: kubectl apply -f ${OUTPUT_DIR}/"
echo "  3. Verify: kargo get stages --project ${PROJECT}"
