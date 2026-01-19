#!/usr/bin/env bash
#
# get-env.sh - Checkout service code to match deployed versions
#
# Usage:
#   ./scripts/get-env.sh [environment]       # Checkout code for environment
#   ./scripts/get-env.sh reset               # Reset all services to main branch
#   ./scripts/get-env.sh production          # Checkout production versions
#   ./scripts/get-env.sh staging             # Checkout staging versions
#   ./scripts/get-env.sh development         # Checkout development versions

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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SERVICES=("blue" "green" "yellow" "red")
readonly ENVIRONMENTS=("development" "staging" "production")

# Function to print usage
usage() {
    cat <<EOF
${BOLD}Usage:${NC}
    $0 [environment|reset]

${BOLD}Arguments:${NC}
    environment    Environment to match (development, staging, production)
    reset          Reset all services to main branch

${BOLD}Examples:${NC}
    $0 production          # Checkout code matching production
    $0 staging             # Checkout code matching staging
    $0 development         # Checkout code matching development
    $0 reset               # Reset all services to main branch

${BOLD}Description:${NC}
    Checks out the actual source code for each microservice to match
    the versions currently deployed in the specified environment.

    This is useful for debugging - you can see the exact code that's
    running in production, staging, or development.

    The script reads the Kustomize configuration files to determine
    which version/tag is deployed, then restores that version's files
    for each service directory independently.

${BOLD}Warning:${NC}
    This will modify your working directory. Make sure you have no
    uncommitted changes before running this command.

EOF
    exit 1
}

# Function to check if yq is installed
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is not installed${NC}" >&2
        echo "Install with: pip install yq" >&2
        exit 1
    fi
}

# Function to check for uncommitted changes
check_uncommitted_changes() {
    cd "$REPO_ROOT"

    if [[ -n $(git status --porcelain projects/) ]]; then
        echo -e "${RED}Error: Uncommitted changes found in projects/${NC}" >&2
        echo "Please commit or stash your changes first." >&2
        git status --short projects/ >&2
        exit 1
    fi
}

# Function to get version for a service in an environment
get_version() {
    local service="$1"
    local env="$2"
    local kustomize_file="$REPO_ROOT/k8s/overlays/$env/$service/kustomization.yaml"

    if [[ ! -f "$kustomize_file" ]]; then
        echo ""
        return
    fi

    local version
    version=$(yq -r '.images[0].newTag' "$kustomize_file" 2>/dev/null || echo "")
    echo "$version"
}

# Function to find git reference for a version
find_git_ref() {
    local service="$1"
    local version="$2"

    cd "$REPO_ROOT"

    # Handle SHA tags (sha-abc123) - remove 'sha-' prefix
    if [[ "$version" =~ ^sha-(.+)$ ]]; then
        local sha="${BASH_REMATCH[1]}"
        echo "$sha"
        return
    fi

    # Handle 'latest' tag
    if [[ "$version" == "latest" ]]; then
        echo "main"
        return
    fi

    # Handle version tags (2.1.3 -> blue/2.1.3)
    local tag="${service}/${version}"

    # Check if tag exists
    if git rev-parse "$tag" >/dev/null 2>&1; then
        echo "$tag"
        return
    fi

    # Try old format: blue-v2.1.3
    local old_tag="${service}-v${version}"
    if git rev-parse "$old_tag" >/dev/null 2>&1; then
        echo "$old_tag"
        return
    fi

    # Fallback to version as-is
    echo "$version"
}

# Function to restore service files from a specific git reference
restore_service() {
    local service="$1"
    local version="$2"
    local service_dir="projects/$service"

    if [[ -z "$version" ]]; then
        echo -e "${YELLOW}⚠  Skipping $service (no version found)${NC}"
        return 0
    fi

    cd "$REPO_ROOT"

    if [[ ! -d "$service_dir" ]]; then
        echo -e "${RED}✗  Service directory not found: $service_dir${NC}"
        return 1
    fi

    # Find the appropriate git reference
    local git_ref
    git_ref=$(find_git_ref "$service" "$version")

    echo -e "${CYAN}→  Restoring $service to ${BOLD}$version${NC}${CYAN} (ref: $git_ref)${NC}"

    # Verify the git reference exists
    if ! git rev-parse "$git_ref" >/dev/null 2>&1; then
        echo -e "${RED}✗  Git reference not found: $git_ref${NC}"
        echo -e "${YELLOW}   Trying to find commit with service changes...${NC}"

        # Try to find a commit that matches this version in the service's CHANGELOG
        local commit
        commit=$(git log --all --grep="$service.*$version" --format="%H" -1 2>/dev/null || echo "")

        if [[ -n "$commit" ]]; then
            git_ref="$commit"
            echo -e "${GREEN}✓  Found commit: ${commit:0:7}${NC}"
        else
            echo -e "${RED}✗  Could not find any reference for $service $version${NC}"
            return 1
        fi
    fi

    # Restore files from that reference
    if git restore --source="$git_ref" -- "$service_dir" 2>/dev/null; then
        echo -e "${GREEN}✓  Successfully restored $service to $version${NC}"

        # Show what was restored
        local commit_info
        commit_info=$(git log "$git_ref" -1 --format="%h - %s" -- "$service_dir" 2>/dev/null || echo "unknown")
        echo -e "${CYAN}   Last commit: $commit_info${NC}"
        return 0
    else
        echo -e "${RED}✗  Failed to restore $service from $git_ref${NC}"
        return 1
    fi
}

# Function to reset all services to current HEAD
reset_services() {
    echo -e "\n${BOLD}${CYAN}Resetting all services to current branch ($(git branch --show-current))...${NC}\n"

    cd "$REPO_ROOT"

    local success_count=0
    local fail_count=0

    for service in "${SERVICES[@]}"; do
        local service_dir="projects/$service"

        if [[ -d "$service_dir" ]]; then
            echo -e "${CYAN}→  Resetting $service${NC}"

            if git restore -- "$service_dir" 2>/dev/null; then
                echo -e "${GREEN}✓  Reset $service${NC}"
                success_count=$((success_count + 1))
            else
                echo -e "${RED}✗  Failed to reset $service${NC}"
                fail_count=$((fail_count + 1))
            fi
        fi
    done

    echo ""
    echo -e "${BOLD}${CYAN}Summary:${NC}"
    echo -e "  ${GREEN}✓ Success: $success_count${NC}"

    if [[ $fail_count -gt 0 ]]; then
        echo -e "  ${RED}✗ Failed: $fail_count${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}All services reset to current branch!${NC}\n"
}

# Function to checkout environment
checkout_environment() {
    local env="$1"

    echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  Restoring code for ${env^^} environment                 ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}\n"

    local success_count=0
    local fail_count=0

    for service in "${SERVICES[@]}"; do
        local version
        version=$(get_version "$service" "$env")

        if restore_service "$service" "$version"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        echo ""
    done

    # Summary
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}Summary:${NC}"
    echo -e "  ${GREEN}✓ Success: $success_count${NC}"

    if [[ $fail_count -gt 0 ]]; then
        echo -e "  ${RED}✗ Failed: $fail_count${NC}"
    fi

    echo ""
    echo -e "${BOLD}${CYAN}Current service versions in working directory:${NC}"

    cd "$REPO_ROOT"
    for service in "${SERVICES[@]}"; do
        local service_dir="projects/$service"

        # Get the version from the service's internal version file if it exists
        local displayed_version="unknown"
        if [[ -f "$service_dir/internal/version/version.go" ]]; then
            displayed_version=$(grep 'Version = ' "$service_dir/internal/version/version.go" | cut -d'"' -f2 2>/dev/null || echo "unknown")
        fi

        local service_color
        case "$service" in
            blue)   service_color="$BLUE" ;;
            green)  service_color="$GREEN" ;;
            yellow) service_color="$YELLOW" ;;
            red)    service_color="$RED" ;;
            *)      service_color="$NC" ;;
        esac

        local env_version
        env_version=$(get_version "$service" "$env")

        echo -e "  ${service_color}${service}${NC}: ${env_version} (code version: ${displayed_version})"
    done

    echo ""
    echo -e "${YELLOW}${BOLD}Note:${NC} Your working directory has been modified."
    echo -e "       Files in ${BOLD}projects/*/${NC} now match ${BOLD}$env${NC} environment."
    echo -e "       Run ${BOLD}$0 reset${NC} to return to current branch state."
    echo ""
}

# Main function
main() {
    local command="${1:-}"

    # Check dependencies
    check_dependencies

    # Show help if requested
    if [[ "$command" == "-h" ]] || [[ "$command" == "--help" ]] || [[ -z "$command" ]]; then
        usage
    fi

    # Handle reset command
    if [[ "$command" == "reset" ]]; then
        reset_services
        exit 0
    fi

    # Validate environment
    if [[ ! " ${ENVIRONMENTS[@]} " =~ " ${command} " ]]; then
        echo -e "${RED}Error: Invalid environment '$command'${NC}" >&2
        echo "Valid environments: development, staging, production, reset" >&2
        echo "" >&2
        usage
    fi

    # Check for uncommitted changes
    check_uncommitted_changes

    # Checkout environment
    checkout_environment "$command"
}

# Run main function
main "$@"
