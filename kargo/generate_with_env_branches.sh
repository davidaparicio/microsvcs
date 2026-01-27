#!/bin/bash
set -euo pipefail

# Kargo Configuration Generator - Environment Branches Mode
# Option 2: Uses separate branches per environment (env/development, env/staging, env/production)
# Renders kustomize output to environment-specific branches
# Usage: ./generate_with_env_branches.sh [--validate] [--diff] [--apply] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
GENERATED_DIR="${SCRIPT_DIR}/generated"

# Colors (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Parse command line arguments
VALIDATE_ONLY=false
SHOW_DIFF=false
AUTO_APPLY=false
DRY_RUN=false
NO_BACKUP=false
VERIFY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --validate)
            VALIDATE_ONLY=true
            shift
            ;;
        --diff)
            SHOW_DIFF=true
            shift
            ;;
        --apply)
            AUTO_APPLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Environment Branches Mode Generator"
            echo "Creates stages that push rendered manifests to env/* branches"
            echo ""
            echo "Options:"
            echo "  --validate     Validate config.yaml syntax only"
            echo "  --diff         Show diff between current and new generated files"
            echo "  --apply        Generate and automatically apply to cluster"
            echo "  --dry-run      Validate manifests with kubectl dry-run"
            echo "  --no-backup    Skip backup of existing generated/ directory (useful for CI)"
            echo "  --verify-only  Skip generation, only run verification on existing manifests"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Required branches (create before first promotion):"
            echo "  - env/development"
            echo "  - env/staging"
            echo "  - env/production"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ Error: $1 is not installed.${NC}"
        echo "   Please install it: $2"
        exit 1
    fi
}

check_dependency "yq" "brew install yq (macOS) or https://github.com/mikefarah/yq#install"

if [ "$AUTO_APPLY" = true ] || [ "$DRY_RUN" = true ]; then
    check_dependency "kubectl" "https://kubernetes.io/docs/tasks/tools/"
fi

echo "🔧 Kargo Configuration Generator (Environment Branches Mode)"
echo "============================================================"
echo ""

# Validate config.yaml syntax
echo "🔍 Validating config.yaml..."
if ! yq eval '.' "${CONFIG_FILE}" > /dev/null 2>&1; then
    echo -e "  ${RED}❌ Error: Invalid YAML syntax in ${CONFIG_FILE}${NC}"
    exit 1
fi
echo -e "  ${GREEN}✅${NC} Valid YAML syntax"

# Check required fields
required_fields=(
    ".project"
    ".namespace"
    ".gitRepo"
    ".gitBranch"
    ".dockerRegistry"
    ".services"
    ".environments"
    ".kustomize.basePath"
)

for field in "${required_fields[@]}"; do
    if [ "$(yq eval "${field}" "${CONFIG_FILE}")" = "null" ]; then
        echo -e "  ${RED}❌ Error: Required field '${field}' is missing in ${CONFIG_FILE}${NC}"
        exit 1
    fi
done
echo -e "  ${GREEN}✅${NC} All required fields present"

if [ "$VALIDATE_ONLY" = true ]; then
    echo ""
    echo -e "${GREEN}✅ Validation complete!${NC}"
    exit 0
fi

# Skip generation if verify-only mode
if [ "$VERIFY_ONLY" = true ]; then
    echo ""
    echo -e "${BLUE}🔍 Verify-only mode: Skipping generation${NC}"
    echo ""

    # Check if generated directory exists
    if [ ! -d "${GENERATED_DIR}" ]; then
        echo -e "${RED}❌ Error: Generated directory not found at ${GENERATED_DIR}${NC}"
        echo "   Run without --verify-only first to generate manifests"
        exit 1
    fi

    # Read configuration for verification
    PROJECT=$(yq eval '.project' "${CONFIG_FILE}")
    NAMESPACE=$(yq eval '.namespace' "${CONFIG_FILE}")
fi

echo ""

# Skip backup and generation if verify-only
if [ "$VERIFY_ONLY" = false ]; then
    # Backup existing generated directory if it exists
    if [ -d "${GENERATED_DIR}" ] && [ "$NO_BACKUP" = false ]; then
        BACKUP_DIR="${GENERATED_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "💾 Backing up existing generated/ to ${BACKUP_DIR##*/}"
        cp -r "${GENERATED_DIR}" "${BACKUP_DIR}"
    fi

    # Clean and recreate generated directory
    rm -rf "${GENERATED_DIR}"
    mkdir -p "${GENERATED_DIR}"/{warehouses,stages}
fi

# Only read full config if not in verify-only mode
if [ "$VERIFY_ONLY" = false ]; then
    # Read configuration
    PROJECT=$(yq eval '.project' "${CONFIG_FILE}")
    NAMESPACE=$(yq eval '.namespace' "${CONFIG_FILE}")
    GIT_REPO=$(yq eval '.gitRepo' "${CONFIG_FILE}")
    GIT_BRANCH=$(yq eval '.gitBranch' "${CONFIG_FILE}")
    DOCKER_REGISTRY=$(yq eval '.dockerRegistry' "${CONFIG_FILE}")
    KUSTOMIZE_BASE=$(yq eval '.kustomize.basePath' "${CONFIG_FILE}")

    # Read services and environments into arrays
    SERVICES=()
    while IFS= read -r service; do
        SERVICES+=("$service")
    done < <(yq eval '.services[]' "${CONFIG_FILE}")

    ENVIRONMENTS=()
    while IFS= read -r env; do
        ENVIRONMENTS+=("$env")
    done < <(yq eval '.environments[].name' "${CONFIG_FILE}")

    # Validate we have services
    if [ ${#SERVICES[@]} -eq 0 ]; then
        echo -e "${RED}❌ Error: No services defined in ${CONFIG_FILE}${NC}"
        exit 1
    fi

    # Validate we have environments
    if [ ${#ENVIRONMENTS[@]} -eq 0 ]; then
        echo -e "${RED}❌ Error: No environments defined in ${CONFIG_FILE}${NC}"
        exit 1
    fi

    echo "📋 Configuration:"
    echo "  Project: ${PROJECT}"
    echo "  Namespace: ${NAMESPACE}"
    echo "  Git: ${GIT_REPO}@${GIT_BRANCH}"
    echo "  Registry: ${DOCKER_REGISTRY}"
    echo "  Services: ${SERVICES[*]}"
    echo "  Environments: ${ENVIRONMENTS[*]}"
    echo ""
    echo -e "  ${YELLOW}⚠️  Mode: Environment Branches${NC}"
    echo "  Target branches: env/development, env/staging, env/production"
    echo ""

    # Counters for summary
    TOTAL_FILES=0
    START_TIME=$(date +%s)

    # Generate Project with promotion policies
    echo "📝 Generating project.yaml..."
cat > "${GENERATED_DIR}/project.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: ${PROJECT}
EOF

echo -e "  ${GREEN}✅${NC} Created project.yaml"
TOTAL_FILES=$((TOTAL_FILES + 1))

# Generate Warehouses (2 per service: dev + releases)
echo ""
echo "📦 Generating warehouses..."
for SERVICE in "${SERVICES[@]}"; do
    # Dev warehouse (sha-* tags)
    DEV_TAG_PATTERN=$(yq eval '.environments[] | select(.name == "development") | .warehouse.imageTagPattern' "${CONFIG_FILE}")
    DEV_DISCOVERY_LIMIT=$(yq eval '.environments[] | select(.name == "development") | .warehouse.discoveryLimit' "${CONFIG_FILE}")

    cat > "${GENERATED_DIR}/warehouses/${SERVICE}-dev.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: ${SERVICE}-dev
  namespace: ${NAMESPACE}
spec:
  subscriptions:
  - image:
      repoURL: ${DOCKER_REGISTRY}/${SERVICE}
      imageSelectionStrategy: Lexical
      allowTags: "${DEV_TAG_PATTERN}"
      discoveryLimit: ${DEV_DISCOVERY_LIMIT}
EOF
    echo -e "  ${GREEN}✅${NC} Created warehouses/${SERVICE}-dev.yaml"
    TOTAL_FILES=$((TOTAL_FILES + 1))

    # Releases warehouse (semver tags)
    RELEASES_SEMVER=$(yq eval '.environments[] | select(.name == "staging") | .warehouse.semverConstraint' "${CONFIG_FILE}")
    RELEASES_DISCOVERY_LIMIT=$(yq eval '.environments[] | select(.name == "staging") | .warehouse.discoveryLimit' "${CONFIG_FILE}")

    cat > "${GENERATED_DIR}/warehouses/${SERVICE}-releases.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: ${SERVICE}-releases
  namespace: ${NAMESPACE}
spec:
  subscriptions:
  - image:
      repoURL: ${DOCKER_REGISTRY}/${SERVICE}
      imageSelectionStrategy: SemVer
      semverConstraint: "${RELEASES_SEMVER}"
      discoveryLimit: ${RELEASES_DISCOVERY_LIMIT}
EOF
    echo -e "  ${GREEN}✅${NC} Created warehouses/${SERVICE}-releases.yaml"
    TOTAL_FILES=$((TOTAL_FILES + 1))
done

# Generate Stages (3 per service: dev, staging, production)
# Option 2: Environment branches approach
# Uses separate branches (env/development, env/staging, env/production)
# Renders kustomize output to environment-specific branches
echo ""
echo "🎯 Generating stages (Environment Branches mode)..."
for SERVICE in "${SERVICES[@]}"; do
    # Development stage - pushes to env/development branch
    cat > "${GENERATED_DIR}/stages/${SERVICE}-development.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${SERVICE}-development
  namespace: ${NAMESPACE}
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: ${SERVICE}-dev
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: git-clone
        config:
          repoURL: ${GIT_REPO}
          checkout:
          - branch: ${GIT_BRANCH}
            path: ./src
          - branch: env/development
            create: true
            path: ./out
      - uses: git-clear
        config:
          path: ./out
      - uses: kustomize-set-image
        config:
          path: ./src/${KUSTOMIZE_BASE}/development/${SERVICE}
          images:
          - image: ${DOCKER_REGISTRY}/${SERVICE}
            tag: \${{ imageFrom("${DOCKER_REGISTRY}/${SERVICE}").Tag }}
      - uses: kustomize-build
        config:
          path: ./src/${KUSTOMIZE_BASE}/development/${SERVICE}
          outPath: ./out/${SERVICE}
      - uses: git-commit
        config:
          path: ./out
          message: '[dev] ${SERVICE} use \${{ imageFrom("${DOCKER_REGISTRY}/${SERVICE}").Tag }}'
      - uses: git-push
        config:
          path: ./out
          targetBranch: env/development
EOF

    echo -e "  ${GREEN}✅${NC} Created stages/${SERVICE}-development.yaml"
    TOTAL_FILES=$((TOTAL_FILES + 1))

    # Staging stage - pushes to env/staging branch
    cat > "${GENERATED_DIR}/stages/${SERVICE}-staging.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${SERVICE}-staging
  namespace: ${NAMESPACE}
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: ${SERVICE}-releases
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: git-clone
        config:
          repoURL: ${GIT_REPO}
          checkout:
          - branch: ${GIT_BRANCH}
            path: ./src
          - branch: env/staging
            create: true
            path: ./out
      - uses: git-clear
        config:
          path: ./out
      - uses: kustomize-set-image
        config:
          path: ./src/${KUSTOMIZE_BASE}/staging/${SERVICE}
          images:
          - image: ${DOCKER_REGISTRY}/${SERVICE}
            tag: \${{ imageFrom("${DOCKER_REGISTRY}/${SERVICE}").Tag }}
      - uses: kustomize-build
        config:
          path: ./src/${KUSTOMIZE_BASE}/staging/${SERVICE}
          outPath: ./out/${SERVICE}
      - uses: git-commit
        config:
          path: ./out
          message: '[stg] ${SERVICE} use \${{ imageFrom("${DOCKER_REGISTRY}/${SERVICE}").Tag }}'
      - uses: git-push
        config:
          path: ./out
          targetBranch: env/staging
EOF

    echo -e "  ${GREEN}✅${NC} Created stages/${SERVICE}-staging.yaml"
    TOTAL_FILES=$((TOTAL_FILES + 1))

    # Production stage - pushes to env/production branch
    cat > "${GENERATED_DIR}/stages/${SERVICE}-production.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${SERVICE}-production
  namespace: ${NAMESPACE}
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: ${SERVICE}-releases
    sources:
      stages:
      - ${SERVICE}-staging
  promotionTemplate:
    spec:
      steps:
      - uses: git-clone
        config:
          repoURL: ${GIT_REPO}
          checkout:
          - branch: ${GIT_BRANCH}
            path: ./src
          - branch: env/production
            create: true
            path: ./out
      - uses: git-clear
        config:
          path: ./out
      - uses: kustomize-set-image
        config:
          path: ./src/${KUSTOMIZE_BASE}/production/${SERVICE}
          images:
          - image: ${DOCKER_REGISTRY}/${SERVICE}
            tag: \${{ imageFrom("${DOCKER_REGISTRY}/${SERVICE}").Tag }}
      - uses: kustomize-build
        config:
          path: ./src/${KUSTOMIZE_BASE}/production/${SERVICE}
          outPath: ./out/${SERVICE}
      - uses: git-commit
        config:
          path: ./out
          message: '[prd] ${SERVICE} use \${{ imageFrom("${DOCKER_REGISTRY}/${SERVICE}").Tag }}'
      - uses: git-push
        config:
          path: ./out
          targetBranch: env/production
EOF

    echo -e "  ${GREEN}✅${NC} Created stages/${SERVICE}-production.yaml"
    TOTAL_FILES=$((TOTAL_FILES + 1))
done

    echo ""
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo -e "${GREEN}✨ Generation complete!${NC}"
    echo ""
    echo "📊 Summary:"
    echo "  - 1 Project manifest"
    echo "  - $(find "${GENERATED_DIR}/warehouses" -name "*.yaml" -type f | wc -l | tr -d ' ') Warehouse manifests"
    echo "  - $(find "${GENERATED_DIR}/stages" -name "*.yaml" -type f | wc -l | tr -d ' ') Stage manifests"
    echo -e "  - ${TOTAL_FILES} total files generated in ${DURATION}s"
    echo ""
    echo "📁 Output directory: ${GENERATED_DIR}"
    echo ""
    echo -e "${YELLOW}⚠️  Important: Create environment branches before first promotion:${NC}"
    echo "   git checkout --orphan env/development && git commit --allow-empty -m 'init' && git push -u origin env/development"
    echo "   git checkout --orphan env/staging && git commit --allow-empty -m 'init' && git push -u origin env/staging"
    echo "   git checkout --orphan env/production && git commit --allow-empty -m 'init' && git push -u origin env/production"
    echo "   git checkout ${GIT_BRANCH}"
    echo ""
fi

# Show diff if requested
if [ "$SHOW_DIFF" = true ]; then
    echo "📊 Differences (if any changes detected):"
    echo ""
    if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
        git diff --no-index --color=always /dev/null "${GENERATED_DIR}" 2>/dev/null || true
    else
        echo "Generated files:"
        find "${GENERATED_DIR}" -name "*.yaml" -type f | sort
    fi
    echo ""
fi

# Dry-run validation
if [ "$DRY_RUN" = true ]; then
    echo "🧪 Validating with kubectl dry-run..."
    if kubectl apply --dry-run=client -f "${GENERATED_DIR}/" &> /dev/null; then
        echo -e "  ${GREEN}✅${NC} All manifests are valid"
    else
        echo -e "  ${RED}❌ Validation failed:${NC}"
        kubectl apply --dry-run=client -f "${GENERATED_DIR}/"
        exit 1
    fi
    echo ""
fi

# Verification or Auto-apply section
if [ "$VERIFY_ONLY" = true ] || [ "$AUTO_APPLY" = true ]; then
    if [ "$AUTO_APPLY" = true ]; then
        echo -e "${BLUE}🚀 Applying to cluster...${NC}"
        echo ""

        # Apply project first
        echo "  📝 Applying project..."
        kubectl apply -f "${GENERATED_DIR}/project.yaml"

        # Apply warehouses
        echo "  📦 Applying warehouses..."
        kubectl apply -f "${GENERATED_DIR}/warehouses/"

        # Apply stages
        echo "  🎯 Applying stages..."
        kubectl apply -f "${GENERATED_DIR}/stages/"

        echo ""
        echo -e "${GREEN}✅ All resources applied successfully!${NC}"
        echo ""
    fi

    # Verification
    echo "🔍 Verification:"
    kubectl get project "${PROJECT}" -n "${NAMESPACE}" 2>/dev/null || true
    kubectl get warehouses -n "${NAMESPACE}" 2>/dev/null || true
    echo ""
    echo "📊 Stage status:"
    if command -v kargo &> /dev/null; then
        kargo get stages -n "${NAMESPACE}" || kubectl get stages -n "${NAMESPACE}"
    else
        kubectl get stages -n "${NAMESPACE}"
    fi
else
    echo "Next steps:"
    echo "  1. Review generated files in ${GENERATED_DIR}/"
    echo -e "  2. Validate: ${YELLOW}./generate_with_env_branches.sh --dry-run${NC}"
    echo "  3. Create env branches (see commands above)"
    echo "  4. Apply to cluster: kubectl apply -f ${GENERATED_DIR}/"
    echo "  5. Verify: kargo get stages -n ${NAMESPACE}"
    echo ""
    echo -e "💡 Tip: Use '${YELLOW}./generate_with_env_branches.sh --apply${NC}' to generate and apply in one step"
fi
