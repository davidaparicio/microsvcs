#!/usr/bin/env bash
#
# get-env.sh - Display current deployment state for an environment
#
# Usage:
#   ./scripts/get-env.sh [environment]
#   ./scripts/get-env.sh production
#   ./scripts/get-env.sh staging
#   ./scripts/get-env.sh development
#   ./scripts/get-env.sh all

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT
readonly SERVICES=("blue" "green" "yellow" "red")
readonly ENVIRONMENTS=("development" "staging" "production")

# Function to print usage
usage() {
    cat <<EOF
${BOLD}Usage:${NC}
    $0 [environment]

${BOLD}Arguments:${NC}
    environment    Environment to query (development, staging, production, all)
                   Default: all

${BOLD}Examples:${NC}
    $0 production          # Show production versions
    $0 staging             # Show staging versions
    $0 development         # Show development versions
    $0 all                 # Show all environments (default)
    $0                     # Same as 'all'

${BOLD}Description:${NC}
    Displays the current deployed versions of all microservices in the
    specified environment by reading the Kustomize configuration files.

EOF
    exit 1
}

# Function to check if yq is installed
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is not installed${NC}" >&2
        echo "Install with: sudo snap install yq" >&2
        exit 1
    fi
}

# Function to get version for a service in an environment
get_version() {
    local service="$1"
    local env="$2"
    local kustomize_file="$REPO_ROOT/k8s/overlays/$env/$service/kustomization.yaml"

    if [[ ! -f "$kustomize_file" ]]; then
        echo "N/A"
        return
    fi

    local version
    # Use Python yq syntax (yq -r) instead of Go yq syntax (yq eval)
    version=$(yq -r '.images[0].newTag' "$kustomize_file" 2>/dev/null || echo "N/A")
    echo "$version"
}

# Function to get last deployment timestamp for a service in an environment
get_deployment_time() {
    local service="$1"
    local env="$2"
    local kustomize_file="k8s/overlays/$env/$service/kustomization.yaml"

    if [[ ! -f "$REPO_ROOT/$kustomize_file" ]]; then
        echo "N/A"
        return
    fi

    cd "$REPO_ROOT"
    local timestamp
    timestamp=$(git log -1 --format="%ar" -- "$kustomize_file" 2>/dev/null || echo "unknown")
    echo "$timestamp"
}

# Function to display environment
show_environment() {
    local env="$1"
    local env_label
    local env_color

    case "$env" in
        production)
            env_label="PRODUCTION"
            env_color="$RED"
            ;;
        staging)
            env_label="STAGING"
            env_color="$YELLOW"
            ;;
        development)
            env_label="DEVELOPMENT"
            env_color="$GREEN"
            ;;
        *)
            env_label="$env"
            env_color="$CYAN"
            ;;
    esac

    echo -e "\n${BOLD}${env_color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${env_color}  ${env_label} Environment${NC}"
    echo -e "${BOLD}${env_color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Table header
    printf "${BOLD}%-15s %-25s %-25s${NC}\n" "Service" "Version" "Last Updated"
    printf "%-15s %-25s %-25s\n" "───────────────" "─────────────────────────" "─────────────────────────"

    # Get versions for each service
    for service in "${SERVICES[@]}"; do
        local version
        local deployment_time
        local service_color

        version=$(get_version "$service" "$env")
        deployment_time=$(get_deployment_time "$service" "$env")

        # Color code by service
        case "$service" in
            blue)   service_color="$BLUE" ;;
            green)  service_color="$GREEN" ;;
            yellow) service_color="$YELLOW" ;;
            red)    service_color="$RED" ;;
            *)      service_color="$NC" ;;
        esac

        printf "${service_color}%-15s${NC} %-25s %-25s\n" "$service" "$version" "$deployment_time"
    done

    echo ""
}

# Function to show all environments
show_all_environments() {
    for env in "${ENVIRONMENTS[@]}"; do
        show_environment "$env"
    done
}

# Main function
main() {
    local environment="${1:-all}"

    # Check dependencies
    check_dependencies

    # Show help if requested
    if [[ "$environment" == "-h" ]] || [[ "$environment" == "--help" ]]; then
        usage
    fi

    # Validate environment
    if [[ "$environment" != "all" ]] && [[ ! " ${ENVIRONMENTS[*]} " =~ \ ${environment}\  ]]; then
        echo -e "${RED}Error: Invalid environment '$environment'${NC}" >&2
        echo "Valid environments: development, staging, production, all" >&2
        echo "" >&2
        usage
    fi

    # Display header
    echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  Microservices Deployment Status                         ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"

    # Show environment(s)
    if [[ "$environment" == "all" ]]; then
        show_all_environments
    else
        show_environment "$environment"
    fi

    # Show repository info
    cd "$REPO_ROOT"
    local current_branch
    local latest_commit
    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    latest_commit=$(git log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "unknown")

    echo -e "${BOLD}${CYAN}Repository Info:${NC}"
    echo -e "  Branch:  ${current_branch}"
    echo -e "  Commit:  ${latest_commit}"
    echo ""
}

# Run main function
main "$@"
