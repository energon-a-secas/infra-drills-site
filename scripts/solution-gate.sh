#!/usr/bin/env bash
set -euo pipefail

# solution-gate.sh - Manages access to solutions in test mode
# Checks if validation passes before revealing solutions

DRILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

usage() {
    echo "Usage: $0 DRILL_PATH [OPTIONS]"
    echo ""
    echo "Checks if drill validation passes and reveals solution if successful"
    echo ""
    echo "Examples:"
    echo "  $0 aws/s3-01-bucket-does-not-appear    # Check and reveal if validated"
    echo "  $0 --help                              # Show this help"
    echo ""
    echo "Validation checks:"
    echo "  - Runs validation commands from README.md"
    echo "  - Checks if infrastructure is properly fixed"
    echo "  - Reveals solution only on successful validation"
    exit 1
}

# Check if solution should be revealed
check_validation() {
    local drill_path="$1"
    local drill_dir="$DRILLS_DIR/$drill_path"

    echo -e "${BOLD}Checking validation for: $drill_path${RESET}"
    echo ""

    # Check if in test mode
    if [[ ! -f "$drill_dir/README.original.md" ]]; then
        echo -e "${YELLOW}Not in test mode.${RESET}"
        echo "Solutions are already visible."
        return 0
    fi

    # Look for validation section in README
    local validation_section=$(awk '/## Validation/,/^## / {print}' "$drill_dir/README.md" 2>/dev/null || echo "")

    if [[ -z "$validation_section" ]]; then
        echo -e "${YELLOW}Warning:${RESET} No validation section found in README"
        echo -e "${YELLOW}Can't automatically validate. Revealing solution...${RESET}"
        return 0
    fi

    # Extract validation commands
    local validation_commands=$(echo "$validation_section" | grep -E '`([^`]+)`' -o | sed 's/`//g' | head -5)

    if [[ -z "$validation_commands" ]]; then
        echo -e "${YELLOW}Note:${RESET} No validation commands found. Revealing solution..."
        return 0
    fi

    if [[ -z "$validation_commands" ]]; then
        echo -e "${RED}Error:${RESET} No validation commands found"
        return 1
    fi

    echo -e "${YELLOW}Running validation checks...${RESET}"
    echo ""

    local all_passed=true
    local cmd_count=0

    # Run each validation command
    while IFS= read -r cmd; do
        cmd_count=$((cmd_count + 1))

        # Skip comments and empty lines
        if [[ -z "$cmd" || "$cmd" =~ ^# ]]; then
            continue
        fi

        echo -e "  ${DIM}$cmd${RESET}"

        # Execute command in drill directory
        cd "$drill_dir"
        if eval "$cmd" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Passed${RESET}"
        else
            echo -e "  ${RED}✗ Failed${RESET}"
            all_passed=false
        fi
    done <<< "$validation_commands"

    echo ""

    if [[ "$all_passed" == "true" ]]; then
        echo -e "${GREEN}Validation passed!${RESET}"
        return 0
    else
        echo -e "${RED}Validation failed.${RESET}"
        echo ""
        echo "Keep debugging! Review:"
        echo "  - The problem symptoms"
        echo "  - Recent changes or configuration"
        echo "  - Resource status and logs"
        echo ""
        echo -e "${DIM}Hint: Run validation commands manually to see detailed output${RESET}"
        return 1
    fi
}

# Reveal solution
reveal_solution() {
    local drill_path="$1"
    local drill_dir="$DRILLS_DIR/$drill_path"

    echo -e "${BOLD}Revealing solution...${RESET}"
    echo ""

    # Restore original README
    if [[ -f "$drill_dir/README.original.md" ]]; then
        mv "$drill_dir/README.original.md" "$drill_dir/README.md"
        echo -e "${GREEN}✓${RESET} Restored original README"
    fi

    # Restore solution files
    if [[ -d "$drill_dir/.solutions" ]]; then
        # Move solutions back to parent solutions directory
        for solution in "$drill_dir/.solutions"/*.md; do
            if [[ -f "$solution" ]]; then
                mv "$solution" "$DRILLS_DIR/solutions/"
            fi
        done
        rmdir "$drill_dir/.solutions"
        echo -e "${GREEN}✓${RESET} Restored solution files"
    fi

    # Show solution location
    local drill_name=$(basename "$drill_path")
    local solution_file="$DRILLS_DIR/solutions/${drill_name}.md"

    if [[ -f "$solution_file" ]]; then
        echo ""
        echo -e "${GREEN}Solution available at:${RESET}"
        echo "  $solution_file"
        echo ""
        echo -e "${DIM}Review the solution to compare with your approach${RESET}"
    fi
}

# Show solution directly (for admins)
show_solution_now() {
    local drill_path="$1"
    local drill_name=$(basename "$drill_path")
    local solution_file="$DRILLS_DIR/solutions/${drill_name}.md"

    if [[ -f "$solution_file" ]]; then
        echo -e "${GREEN}Solution:${RESET}"
        echo ""
        cat "$solution_file"
    else
        echo -e "${RED}Solution file not found:${RESET} $solution_file"
    fi
}

# Main
case "${1:-}" in
    "--help"|"-h")
        usage
        ;;
    "--show-now")
        if [[ -z "${2:-}" ]]; then
            echo "Error: Drill path required with --show-now"
            exit 1
        fi
        show_solution_now "$2"
        ;;
    "")
        echo "Error: No drill path specified"
        usage
        ;;
    *)
        # Check validation and reveal if passed
        if check_validation "$1"; then
            reveal_solution "$1"
        else
            echo ""
            echo -e "${DIM}Keep working on the fix!${RESET}"
            exit 1
        fi
        ;;
esac
