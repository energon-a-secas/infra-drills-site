#!/usr/bin/env bash
set -euo pipefail

# certification-runner.sh - Simple certification test runner with timing
# This is a lightweight implementation while fixing quiz.sh syntax issues

cert_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/certifications"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

usage() {
    echo "Usage: $0 --test CERTIFICATION_ID"
    echo ""
    echo "Run certification-style timed tests"
    echo ""
    echo "Options:"
    echo "  --test ID    Run specific certification test"
    echo "  --list       List available certification tests"
    echo "  -h, --help   Show this help"
    exit 1
}

list_tests() {
    echo "Available certification tests:"
    echo ""

    if [[ ! -d "$cert_dir" ]]; then
        echo "No certification tests found. Create YAML files in: $cert_dir/"
        exit 0
    fi

    for file in "$cert_dir"/*.yaml; do
        if [[ -f "$file" ]]; then
            local id=$(basename "$file" .yaml | sed 's/-/_/g')
            local duration=$(grep -E "^duration:" "$file" | awk '{print $2}')
            local questions=$(grep -c "^- id:" "$file" 2>/dev/null || echo 0)
            local score=$(grep -E "^passing_score:" "$file" | awk '{print $2}')

            echo "  $id - $questions questions, $duration minutes, passing: $score%"
            grep -E "^description:" "$file" | sed 's/^/    /'
        fi
    done
}

format_time() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d" "$minutes" "$secs"
}

run_certification_test() {
    local test_id="$1"
    local test_file="$cert_dir/${test_id//_/-}.yaml"

    if [[ ! -f "$test_file" ]]; then
        echo "Error: Test file not found: $test_file"
        exit 1
    fi

    # Extract test metadata
    local duration=$(grep -E "^duration:" "$test_file" | awk '{print $2}' || echo "60")
    local passing_score=$(grep -E "^passing_score:" "$test_file" | awk '{print $2}' || echo "70")

    echo -e "${BOLD}Certification Test: ${test_id}${RESET}"
    echo "Duration: ${duration} minutes"
    echo "Passing score: ${passing_score}%"
    echo ""

    # Calculate end time
    local end_time=$((SECONDS + duration * 60))

    # Run simplified quiz (using existing quiz.sh but with timer display)
    # For now, use a placeholder countdown
    local questions_answered=0
    local correct_answers=0

    while [[ $SECONDS -lt $end_time ]]; do
        local remaining=$((end_time - SECONDS))

        clear
        echo -e "${BOLD}Certification Test: ${test_id}${RESET}"
        echo "Time remaining: $(format_time $remaining)"
        echo "Questions answered: $questions_answered"
        echo ""
        echo "[Q] Answer question"
        echo "[S] Show score so far"
        echo "[X] End test early"
        echo ""

        read -t 1 -n 1 -r input || continue

        case "$input" in
            q|Q)
                # In full implementation, this would get next question
                echo -e "\nQuestion $((questions_answered + 1)):"

                # Generate random question for demo
                local questions=$(grep -c "^- id:" "$test_file" 2>/dev/null || echo 10)
                if [[ $((RANDOM % 2)) -eq 0 ]]; then
                    echo "Q: What is the capital of France?"
                    echo "a) London  b) Paris  c) Berlin  d) Madrid"
                    read -p "Answer: " ans
                    if [[ "$ans" == "b" ]]; then
                        correct_answers=$((correct_answers + 1))
                    fi
                else
                    echo "Q: What is 2 + 2?"
                    read -p "Answer: " ans
                    if [[ "$ans" == "4" ]]; then
                        correct_answers=$((correct_answers + 1))
                    fi
                fi

                questions_answered=$((questions_answered + 1))
                sleep 2
                ;;
            s|S)
                if [[ $questions_answered -gt 0 ]]; then
                    local percentage=$((correct_answers * 100 / questions_answered))
                    echo -e "\nScore: $correct_answers/$questions_answered ($percentage%)"
                else
                    echo -e "\nNo questions answered yet"
                fi
                sleep 2
                ;;
            x|X)
                break
                ;;
        esac
    done

    # Test completed (time up or user ended)
    clear
    echo -e "${BOLD}Test Complete!${RESET}"
    echo ""

    if [[ $questions_answered -gt 0 ]]; then
        local percentage=$((correct_answers * 100 / questions_answered))

        echo -e "Final Score: ${BOLD}$correct_answers/$questions_answered ($percentage%)${RESET}"
        echo ""

        if [[ $percentage -ge $passing_score ]]; then
            echo -e "${GREEN}🎉 PASSED!${RESET}"
            echo ""
        else
            echo -e "${RED}❌ FAILED${RESET}"
            echo ""
        fi

        echo "Passing score: $passing_score%"
        echo "Your score: $percentage%"
    else
        echo "No questions were answered."
    fi
}

# Main
if [[ $# -eq 0 ]]; then
    usage
fi

case "${1:-}" in
    --list)
        list_tests
        exit 0
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    --test)
        if [[ -z "${2:-}" ]]; then
            echo "Error: --test requires a certification ID"
            usage
        fi
        run_certification_test "$2"
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        usage
        ;;
esac
