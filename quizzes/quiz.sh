#!/usr/bin/env bash
set -euo pipefail

# quiz.sh — Interactive knowledge-check quiz runner for Local Drills
# Pure bash, no external dependencies (no yq, no jq)

QUIZ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Defaults
TOPIC=""
SECTION=""
DIFFICULTY=""
COUNT=10
ALL=false

usage() {
    echo "Usage: quiz.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --topic TOPIC        Run a specific topic pack (e.g. aws/s3-basics)"
    echo "  --section SECTION    Random questions from one section (aws, kubernetes, gitlab)"
    echo "  --difficulty LEVEL   Filter by difficulty (beginner, intermediate, advanced)"
    echo "  --count N            Number of questions (default: 10)"
    echo "  --all                Run all matching questions in order"
    echo "  --list               List available topic packs"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  quiz.sh                           # 10 random questions from all sections"
    echo "  quiz.sh --section aws             # 10 random AWS questions"
    echo "  quiz.sh --topic aws/s3-basics     # 10 random from S3 Basics pack"
    echo "  quiz.sh --topic aws/s3-basics --all  # All S3 Basics questions"
    echo "  quiz.sh --difficulty beginner --count 5"
}

list_packs() {
    printf "${BOLD}%-30s %-12s %-14s %s${RESET}\n" "TOPIC" "SECTION" "DIFFICULTY" "QUESTIONS"
    printf "%-30s %-12s %-14s %s\n" "-----" "-------" "----------" "---------"
    local files
    files=$(find "$QUIZ_DIR" -path '*/aws/*.yaml' -o -path '*/kubernetes/*.yaml' -o -path '*/gitlab/*.yaml' 2>/dev/null | sort)
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        local rel
        rel=$(echo "$f" | sed "s|$QUIZ_DIR/||; s|\.yaml$||")
        local sec diff qcount
        sec=$(awk '/^section:/{print $2}' "$f")
        diff=$(awk '/^difficulty:/{print $2}' "$f")
        qcount=$(grep -c '^  - id:' "$f" 2>/dev/null || echo 0)
        printf "%-30s %-12s %-14s %s\n" "$rel" "$sec" "$diff" "$qcount"
    done <<< "$files"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --topic) TOPIC="$2"; shift 2 ;;
        --section) SECTION="$2"; shift 2 ;;
        --difficulty) DIFFICULTY="$2"; shift 2 ;;
        --count) COUNT="$2"; shift 2 ;;
        --all) ALL=true; shift ;;
        --list) list_packs; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Collect matching YAML files
collect_files() {
    local files=()
    if [[ -n "$TOPIC" ]]; then
        local f="$QUIZ_DIR/${TOPIC}.yaml"
        if [[ ! -f "$f" ]]; then
            echo "Error: topic pack '$TOPIC' not found at $f" >&2
            exit 1
        fi
        files+=("$f")
    elif [[ -n "$SECTION" ]]; then
        for f in "$QUIZ_DIR/$SECTION"/*.yaml; do
            [ -f "$f" ] && files+=("$f")
        done
    else
        local all_files
        all_files=$(find "$QUIZ_DIR" -path '*/aws/*.yaml' -o -path '*/kubernetes/*.yaml' -o -path '*/gitlab/*.yaml' 2>/dev/null | sort)
        while IFS= read -r f; do
            [ -f "$f" ] && files+=("$f")
        done <<< "$all_files"
    fi

    # Filter by difficulty if specified
    if [[ -n "$DIFFICULTY" ]]; then
        local filtered=()
        for f in "${files[@]}"; do
            local fdiff
            fdiff=$(awk '/^difficulty:/{print $2}' "$f")
            if [[ "$fdiff" == "$DIFFICULTY" ]]; then
                filtered+=("$f")
            fi
        done
        files=("${filtered[@]}")
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No matching quiz packs found." >&2
        exit 1
    fi
    printf '%s\n' "${files[@]}"
}

# Parse all questions from a YAML file into arrays
# Sets global arrays: Q_IDS, Q_TYPES, Q_PROMPTS, Q_OPTIONS_A..D, Q_ANSWERS, Q_ACCEPTS, Q_EXPLANATIONS
# For match: Q_LEFTS, Q_RIGHTS, Q_PAIRS
parse_yaml() {
    local file="$1"
    local in_question=false
    local in_prompt=false
    local in_explanation=false
    local in_accept=false
    local in_left=false
    local in_right=false
    local in_pairs=false
    local current_id="" current_type="" current_prompt="" current_answer=""
    local current_opt_a="" current_opt_b="" current_opt_c="" current_opt_d=""
    local current_explanation="" current_accept=""
    local current_left="" current_right="" current_pairs=""
    local prompt_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect question start
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]id:[[:space:]]*(.*) ]]; then
            # Save previous question if any
            if [[ -n "$current_id" ]]; then
                Q_IDS+=("$current_id")
                Q_TYPES+=("$current_type")
                Q_PROMPTS+=("$current_prompt")
                Q_OPTIONS_A+=("$current_opt_a")
                Q_OPTIONS_B+=("$current_opt_b")
                Q_OPTIONS_C+=("$current_opt_c")
                Q_OPTIONS_D+=("$current_opt_d")
                Q_ANSWERS+=("$current_answer")
                Q_ACCEPTS+=("$current_accept")
                Q_EXPLANATIONS+=("$current_explanation")
                Q_LEFTS+=("$current_left")
                Q_RIGHTS+=("$current_right")
                Q_PAIRS+=("$current_pairs")
            fi
            current_id="${BASH_REMATCH[1]}"
            current_type="" current_prompt="" current_answer=""
            current_opt_a="" current_opt_b="" current_opt_c="" current_opt_d=""
            current_explanation="" current_accept=""
            current_left="" current_right="" current_pairs=""
            in_question=true in_prompt=false in_explanation=false
            in_accept=false in_left=false in_right=false in_pairs=false
            continue
        fi

        if ! $in_question; then continue; fi

        # Type
        if [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.*) ]]; then
            current_type="${BASH_REMATCH[1]}"
            in_prompt=false; in_explanation=false; in_accept=false
            in_left=false; in_right=false; in_pairs=false
            continue
        fi

        # Prompt (block scalar)
        if [[ "$line" =~ ^[[:space:]]*prompt:[[:space:]]*\|[[:space:]]*$ ]]; then
            in_prompt=true; in_explanation=false; in_accept=false
            in_left=false; in_right=false; in_pairs=false
            prompt_indent=-1
            continue
        fi
        # Prompt (inline with quotes)
        if [[ "$line" =~ ^[[:space:]]*prompt:[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            current_prompt="${BASH_REMATCH[1]}"
            in_prompt=false
            continue
        fi
        # Prompt (inline without quotes but with content)
        if [[ "$line" =~ ^[[:space:]]*prompt:[[:space:]]*[\"\']?([^|>].+) ]] && ! [[ "$line" =~ prompt:[[:space:]]*\| ]] && ! [[ "$line" =~ prompt:[[:space:]]*\> ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%\"}"
            val="${val%\'}"
            val="${val#\"}"
            val="${val#\'}"
            current_prompt="$val"
            in_prompt=false
            continue
        fi

        # Block prompt continuation
        if $in_prompt; then
            # Detect end of block (line with less indent that starts a key)
            if [[ "$line" =~ ^[[:space:]]*[a-z_]+: ]] && ! [[ "$line" =~ ^[[:space:]]{6,} ]]; then
                in_prompt=false
                # Fall through to parse this line as a key
            else
                if [[ $prompt_indent -eq -1 ]]; then
                    # Detect indent of first line
                    local stripped="${line#"${line%%[![:space:]]*}"}"
                    prompt_indent=$(( ${#line} - ${#stripped} ))
                fi
                local content="${line}"
                if [[ ${#content} -ge $prompt_indent ]]; then
                    content="${content:$prompt_indent}"
                fi
                if [[ -n "$current_prompt" ]]; then
                    current_prompt+=$'\n'"$content"
                else
                    current_prompt="$content"
                fi
                continue
            fi
        fi

        # Options
        if [[ "$line" =~ ^[[:space:]]*a:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
            current_opt_a="$val"
            in_explanation=false; in_accept=false
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*b:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
            current_opt_b="$val"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*c:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
            current_opt_c="$val"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*d:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
            current_opt_d="$val"
            continue
        fi

        # Answer (single value)
        if [[ "$line" =~ ^[[:space:]]*answer:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
            current_answer="$val"
            in_explanation=false; in_accept=false
            continue
        fi

        # Accept (inline array)
        if [[ "$line" =~ ^[[:space:]]*accept:[[:space:]]*\[(.*)\] ]]; then
            current_accept="${BASH_REMATCH[1]}"
            # Clean up quotes and spaces
            current_accept=$(echo "$current_accept" | sed 's/"//g; s/'"'"'//g; s/^[[:space:]]*//; s/[[:space:]]*$//')
            in_accept=false
            continue
        fi

        # Left (inline array for match)
        if [[ "$line" =~ ^[[:space:]]*left:[[:space:]]*\[(.*)\] ]]; then
            current_left="${BASH_REMATCH[1]}"
            current_left=$(echo "$current_left" | sed 's/"//g; s/'"'"'//g')
            continue
        fi

        # Right (inline array for match)
        if [[ "$line" =~ ^[[:space:]]*right:[[:space:]]*\[(.*)\] ]]; then
            current_right="${BASH_REMATCH[1]}"
            current_right=$(echo "$current_right" | sed 's/"//g; s/'"'"'//g')
            continue
        fi

        # Pairs (inline array of arrays)
        if [[ "$line" =~ ^[[:space:]]*pairs:[[:space:]]*\[(.*)\] ]]; then
            current_pairs="${BASH_REMATCH[1]}"
            continue
        fi

        # Explanation (folded scalar >)
        if [[ "$line" =~ ^[[:space:]]*explanation:[[:space:]]*\>[[:space:]]*$ ]]; then
            in_explanation=true; in_prompt=false; in_accept=false
            continue
        fi
        # Explanation (inline)
        if [[ "$line" =~ ^[[:space:]]*explanation:[[:space:]]*(.*) ]] && ! [[ "$line" =~ explanation:[[:space:]]*\> ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
            current_explanation="$val"
            in_explanation=false
            continue
        fi

        # Explanation continuation
        if $in_explanation; then
            if [[ "$line" =~ ^[[:space:]]*[a-z_]+: ]] && ! [[ "$line" =~ ^[[:space:]]{6,} ]]; then
                in_explanation=false
            else
                local trimmed="${line#"${line%%[![:space:]]*}"}"
                if [[ -n "$current_explanation" ]]; then
                    current_explanation+=" $trimmed"
                else
                    current_explanation="$trimmed"
                fi
                continue
            fi
        fi

    done < "$file"

    # Save last question
    if [[ -n "$current_id" ]]; then
        Q_IDS+=("$current_id")
        Q_TYPES+=("$current_type")
        Q_PROMPTS+=("$current_prompt")
        Q_OPTIONS_A+=("$current_opt_a")
        Q_OPTIONS_B+=("$current_opt_b")
        Q_OPTIONS_C+=("$current_opt_c")
        Q_OPTIONS_D+=("$current_opt_d")
        Q_ANSWERS+=("$current_answer")
        Q_ACCEPTS+=("$current_accept")
        Q_EXPLANATIONS+=("$current_explanation")
        Q_LEFTS+=("$current_left")
        Q_RIGHTS+=("$current_right")
        Q_PAIRS+=("$current_pairs")
    fi
}

# Shuffle an array of indices
shuffle_indices() {
    local count=$1
    local indices=()
    for ((i=0; i<count; i++)); do
        indices+=("$i")
    done
    # Fisher-Yates shuffle
    for ((i=count-1; i>0; i--)); do
        local j=$((RANDOM % (i + 1)))
        local tmp="${indices[$i]}"
        indices[$i]="${indices[$j]}"
        indices[$j]="$tmp"
    done
    printf '%s\n' "${indices[@]}"
}

# Run a diagnose question
run_diagnose() {
    local idx=$1
    echo -e "${CYAN}${BOLD}[DIAGNOSE]${RESET} ${DIM}(${Q_IDS[$idx]})${RESET}"
    echo ""
    echo -e "${Q_PROMPTS[$idx]}"
    echo ""
    echo -e "  ${BOLD}a)${RESET} ${Q_OPTIONS_A[$idx]}"
    echo -e "  ${BOLD}b)${RESET} ${Q_OPTIONS_B[$idx]}"
    echo -e "  ${BOLD}c)${RESET} ${Q_OPTIONS_C[$idx]}"
    echo -e "  ${BOLD}d)${RESET} ${Q_OPTIONS_D[$idx]}"
    echo ""
    read -rp "Your answer (a/b/c/d): " user_answer
    user_answer=$(echo "$user_answer" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    if [[ "$user_answer" == "${Q_ANSWERS[$idx]}" ]]; then
        echo -e "${GREEN}${BOLD}Correct!${RESET}"
        SCORE=$((SCORE + 1))
    else
        local correct_text=""
        case "${Q_ANSWERS[$idx]}" in
            a) correct_text="${Q_OPTIONS_A[$idx]}" ;;
            b) correct_text="${Q_OPTIONS_B[$idx]}" ;;
            c) correct_text="${Q_OPTIONS_C[$idx]}" ;;
            d) correct_text="${Q_OPTIONS_D[$idx]}" ;;
        esac
        echo -e "${RED}${BOLD}Wrong.${RESET} The answer is: ${BOLD}${Q_ANSWERS[$idx]})${RESET} $correct_text"
    fi
    echo -e "${YELLOW}Explanation:${RESET} ${Q_EXPLANATIONS[$idx]}"
}

# Run a complete question
run_complete() {
    local idx=$1
    echo -e "${BLUE}${BOLD}[COMPLETE]${RESET} ${DIM}(${Q_IDS[$idx]})${RESET}"
    echo ""
    echo -e "${Q_PROMPTS[$idx]}"
    echo ""
    read -rp "Your answer: " user_answer
    user_answer=$(echo "$user_answer" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    local correct=false
    local primary_answer="${Q_ANSWERS[$idx]}"
    local accept_list="${Q_ACCEPTS[$idx]}"

    # Check primary answer
    local check_primary
    check_primary=$(echo "$primary_answer" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "$user_answer" == "$check_primary" ]]; then
        correct=true
    fi

    # Check accept list
    if ! $correct && [[ -n "$accept_list" ]]; then
        IFS=',' read -ra accepts <<< "$accept_list"
        for acc in "${accepts[@]}"; do
            local check_acc
            check_acc=$(echo "$acc" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [[ "$user_answer" == "$check_acc" ]]; then
                correct=true
                break
            fi
        done
    fi

    if $correct; then
        echo -e "${GREEN}${BOLD}Correct!${RESET}"
        SCORE=$((SCORE + 1))
    else
        echo -e "${RED}${BOLD}Wrong.${RESET} Expected: ${BOLD}${primary_answer}${RESET}"
    fi
    echo -e "${YELLOW}Explanation:${RESET} ${Q_EXPLANATIONS[$idx]}"
}

# Run a match question
run_match() {
    local idx=$1
    echo -e "${CYAN}${BOLD}[MATCH]${RESET} ${DIM}(${Q_IDS[$idx]})${RESET}"
    echo ""
    echo -e "${Q_PROMPTS[$idx]}"
    echo ""

    # Parse left and right items
    IFS=',' read -ra left_items <<< "${Q_LEFTS[$idx]}"
    IFS=',' read -ra right_items <<< "${Q_RIGHTS[$idx]}"

    # Parse pairs: [[0,0],[1,1],[2,2],[3,3]]
    local pairs_str="${Q_PAIRS[$idx]}"

    # Trim items
    local left_clean=() right_clean=()
    for item in "${left_items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        left_clean+=("$item")
    done
    for item in "${right_items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        right_clean+=("$item")
    done

    local num_items=${#left_clean[@]}

    # Create shuffled order for right column
    local shuffled_right=()
    local shuffle_map=()
    mapfile -t shuffle_map < <(shuffle_indices "$num_items")
    for si in "${shuffle_map[@]}"; do
        shuffled_right+=("${right_clean[$si]}")
    done

    # Display
    echo -e "  ${BOLD}Left:${RESET}"
    for ((i=0; i<num_items; i++)); do
        echo -e "    $((i+1)). ${left_clean[$i]}"
    done
    echo ""
    echo -e "  ${BOLD}Right (shuffled):${RESET}"
    for ((i=0; i<num_items; i++)); do
        echo -e "    $((i+1)). ${shuffled_right[$i]}"
    done
    echo ""
    echo "For each left item (1-$num_items), enter the matching right number."

    local user_matches=()
    local all_correct=true
    for ((i=0; i<num_items; i++)); do
        read -rp "  ${left_clean[$i]} -> " match_num
        match_num=$(echo "$match_num" | tr -d '[:space:]')
        user_matches+=("$match_num")
    done

    # Build correct mapping: for each left index, find the correct right index in the original,
    # then find where that right item ended up in the shuffled order
    # Parse pairs
    local correct_right_for_left=()
    # Extract pairs like [0,0] [1,1] etc
    local pairs_clean
    pairs_clean=$(echo "$pairs_str" | tr -d '[:space:][]')
    IFS=',' read -ra pair_vals <<< "$pairs_clean"
    # pair_vals is now: 0 0 1 1 2 2 3 3 (alternating left, right)
    for ((i=0; i<${#pair_vals[@]}; i+=2)); do
        local li=${pair_vals[$i]}
        local ri=${pair_vals[$((i+1))]}
        correct_right_for_left[$li]=$ri
    done

    # Check each match
    for ((i=0; i<num_items; i++)); do
        local expected_original_right=${correct_right_for_left[$i]}
        # Find where expected_original_right ended up in shuffled order
        local expected_shuffled_pos=-1
        for ((j=0; j<num_items; j++)); do
            if [[ ${shuffle_map[$j]} -eq $expected_original_right ]]; then
                expected_shuffled_pos=$((j+1))
                break
            fi
        done
        if [[ "${user_matches[$i]}" != "$expected_shuffled_pos" ]]; then
            all_correct=false
        fi
    done

    if $all_correct; then
        echo -e "${GREEN}${BOLD}All correct!${RESET}"
        SCORE=$((SCORE + 1))
    else
        echo -e "${RED}${BOLD}Some matches were wrong.${RESET}"
        echo -e "Correct pairs:"
        for ((i=0; i<num_items; i++)); do
            local ri=${correct_right_for_left[$i]}
            echo -e "  ${left_clean[$i]} -> ${right_clean[$ri]}"
        done
    fi
    echo -e "${YELLOW}Explanation:${RESET} ${Q_EXPLANATIONS[$idx]}"
}

# Main
main() {
    # Global question arrays
    Q_IDS=() Q_TYPES=() Q_PROMPTS=()
    Q_OPTIONS_A=() Q_OPTIONS_B=() Q_OPTIONS_C=() Q_OPTIONS_D=()
    Q_ANSWERS=() Q_ACCEPTS=() Q_EXPLANATIONS=()
    Q_LEFTS=() Q_RIGHTS=() Q_PAIRS=()

    # Collect files
    mapfile -t quiz_files < <(collect_files)

    # Parse all questions from all files
    for f in "${quiz_files[@]}"; do
        parse_yaml "$f"
    done

    local total=${#Q_IDS[@]}
    if [[ $total -eq 0 ]]; then
        echo "No questions found." >&2
        exit 1
    fi

    # Build question order
    local order=()
    if $ALL; then
        for ((i=0; i<total; i++)); do
            order+=("$i")
        done
    else
        mapfile -t order < <(shuffle_indices "$total")
    fi

    # Limit count
    local run_count=$total
    if ! $ALL && [[ $COUNT -lt $total ]]; then
        run_count=$COUNT
    fi

    SCORE=0
    local question_num=0

    echo ""
    echo -e "${BOLD}Local Drills — Knowledge Check${RESET}"
    echo -e "${DIM}$run_count question(s) queued${RESET}"
    echo -e "${DIM}──────────────────────────────${RESET}"

    for ((q=0; q<run_count; q++)); do
        local idx=${order[$q]}
        question_num=$((question_num + 1))
        echo ""
        echo -e "${DIM}── Question $question_num/$run_count ──${RESET}"
        echo ""

        case "${Q_TYPES[$idx]}" in
            diagnose) run_diagnose "$idx" ;;
            complete) run_complete "$idx" ;;
            match)    run_match "$idx" ;;
            *) echo "Unknown question type: ${Q_TYPES[$idx]}"; continue ;;
        esac
    done

    # Score summary
    echo ""
    echo -e "${DIM}══════════════════════════════${RESET}"
    local pct=0
    if [[ $run_count -gt 0 ]]; then
        pct=$(( (SCORE * 100) / run_count ))
    fi

    local color="$RED"
    if [[ $pct -ge 80 ]]; then
        color="$GREEN"
    elif [[ $pct -ge 50 ]]; then
        color="$YELLOW"
    fi

    echo -e "${BOLD}Score: ${color}${SCORE}/${run_count} (${pct}%)${RESET}"

    if [[ $pct -eq 100 ]]; then
        echo -e "${GREEN}Perfect score!${RESET}"
    elif [[ $pct -ge 80 ]]; then
        echo -e "${GREEN}Great job!${RESET}"
    elif [[ $pct -ge 50 ]]; then
        echo -e "${YELLOW}Room for improvement.${RESET}"
    else
        echo -e "${RED}Keep studying — you'll get there.${RESET}"
    fi
    echo ""
}

main
