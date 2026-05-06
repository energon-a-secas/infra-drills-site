#!/usr/bin/env bash
set -euo pipefail

# test-mode-wrapper.sh - Test mode wrapper for infrastructure drills
# Hides solutions and manages access control during test mode

DRILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_STATE_DIR="$HOME/.local-drills"
TEST_STATE_FILE="$TEST_STATE_DIR/drill-test-state.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Create state directory
mkdir -p "$TEST_STATE_DIR"

usage() {
    echo "Usage: $0 [DRILL_PATH] [OPTIONS]"
    echo ""
    echo "Prepares a drill for test mode by hiding solutions"
    echo ""
    echo "Examples:"
    echo "  $0 aws/s3-01-bucket-does-not-appear    # Enter test mode for drill"
    echo "  $0 --list                              # List drills in test mode"
    echo "  $0 --reset                             # Reset all test mode state"
    echo ""
    echo "Environment:"
    echo "  TEST_MODE=1                           # Automatically enter test mode"
    exit 1
}

# Load test state
load_test_state() {
    if [[ -f "$TEST_STATE_FILE" ]]; then
        TEST_STATE=$(cat "$TEST_STATE_FILE" 2>/dev/null || echo "{}")
    else
        TEST_STATE='{}'
    fi
}

# Generate temporary README without solution links
generate_test_readme() {
    local drill_path="$1"
    local drill_dir="$DRILLS_DIR/$drill_path"
    local original_readme="$drill_dir/README.md"
    local test_readme="$drill_dir/README.test.md"

    if [[ ! -f "$original_readme" ]]; then
        echo "Error: No README.md found in $drill_path"
        return 1
    fi

    # Copy original to backup
    cp "$original_readme" "$drill_dir/README.original.md"

    # Create test version without solution link
    sed '/\[Solution\]/d; /## Solution/d; /solution.*\.md/d' "$original_readme" > "$test_readme"

    # Add test mode notice
    cat >> "$test_readme" << EOF

---

> 🧪 TEST MODE ACTIVE
>
> Solutions are hidden. Fix the issue and run validation to unlock.
> Use './scripts/solution-gate.sh $drill_path' to check if solution is available.
EOF

    # Replace original with test version
    mv "$test_readme" "$original_readme"

    echo -e "${YELLOW}Test mode:${RESET} Solutions hidden for $drill_path"
}

# Enter test mode for a drill
enter_test_mode() {
    local drill_path="$1"

    # Check if drill exists
    if [[ ! -d "$DRILLS_DIR/$drill_path" ]]; then
        echo "Error: Drill '$drill_path' not found"
        echo "Check aws/, kubernetes/, or gitlab/ directories"
        exit 1
    fi

    echo -e "${BOLD}Entering test mode for: $drill_path${RESET}"
    echo ""

    # Backup and modify README
    generate_test_readme "$drill_path"

    echo ""
    echo -e "${GREEN}Success!${RESET} Test mode activated."
    echo ""
    echo "Next steps:"
    echo "  1. Read the problem in the README.md"
    echo "  2. Run lab-initialization.sh to set up the environment"
    echo "  3. Debug and fix the issue"
    echo "  4. Run validation commands"
    echo "  5. Use ./scripts/solution-gate.sh to check if you can view the solution"
    echo ""
}

# Main
case "${1:-}" in
    "--list")
        echo "Feature coming soon"
        ;;
    "--reset")
        rm -f "$TEST_STATE_FILE"
        echo -e "${GREEN}Reset:${RESET} Test mode state cleared"
        ;;
    "--help"|"-h")
        usage
        ;;
    "")
        echo "Error: No drill path specified"
        usage
        ;;
    *)
        enter_test_mode "$1"
        ;;
esac
