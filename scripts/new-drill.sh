#!/usr/bin/env bash
set -euo pipefail

# ─── new-drill.sh ────────────────────────────────────────────────────
# Interactive scaffold for creating new Local Drills.
# No external dependencies — pure bash.
# ─────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX_FILE="$REPO_ROOT/drill-index.yaml"

# ─── Helpers ─────────────────────────────────────────────────────────

prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  echo ""
  echo "$prompt"
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}"
  done
  while true; do
    read -rp "Choice [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      REPLY="${options[$((choice-1))]}"
      return
    fi
    echo "Invalid choice. Try again."
  done
}

prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  if [[ -n "$default" ]]; then
    read -rp "$prompt [$default]: " REPLY
    REPLY="${REPLY:-$default}"
  else
    while true; do
      read -rp "$prompt: " REPLY
      [[ -n "$REPLY" ]] && return
      echo "Value cannot be empty."
    done
  fi
}

# ─── Collect inputs ─────────────────────────────────────────────────

echo "╔══════════════════════════════════════╗"
echo "║       New Drill Scaffold Tool        ║"
echo "╚══════════════════════════════════════╝"

# 1. Section
prompt_choice "Section:" "aws" "kubernetes" "gitlab"
SECTION="$REPLY"

# 2. Service prefix
case "$SECTION" in
  aws)
    prompt_input "Service prefix (e.g., s3, lambda, iam, sqs, vpc, dynamodb, r53, cfn)"
    ;;
  kubernetes)
    prompt_choice "Prefix:" "k8s" "eks"
    ;;
  gitlab)
    REPLY="gitlab"
    echo ""
    echo "Prefix: gitlab (fixed for gitlab section)"
    ;;
esac
PREFIX="$REPLY"

# 3. Number — suggest next available
SECTION_DIR="$REPO_ROOT/$SECTION"
EXISTING=$(ls -d "$SECTION_DIR/$PREFIX"-* 2>/dev/null | sed "s|.*/||" | grep -oP "(?<=^${PREFIX}-)\d+" | sort -n | tail -1)
if [[ -z "$EXISTING" ]]; then
  SUGGESTED="01"
else
  SUGGESTED=$(printf "%02d" $(( 10#$EXISTING + 1 )))
fi

prompt_input "Number (00-09=beginner, 10-19=intermediate, 20-29=advanced)" "$SUGGESTED"
NUMBER="$REPLY"
# Zero-pad to 2 digits
NUMBER=$(printf "%02d" "$((10#$NUMBER))")

# Check for collision
if [[ -d "$SECTION_DIR/$PREFIX-$NUMBER-"* ]]; then
  COLLISION=$(ls -d "$SECTION_DIR/$PREFIX-$NUMBER-"* 2>/dev/null | head -1)
  echo ""
  echo "WARNING: Number collision detected with: $(basename "$COLLISION")"
  read -rp "Continue anyway? [y/N]: " confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted."; exit 1; }
fi

# 4. Title
prompt_input "Title (kebab-case, e.g., bucket-not-found)"
TITLE="$REPLY"
# Sanitize: lowercase, replace spaces with hyphens
TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

DRILL_NAME="$PREFIX-$NUMBER-$TITLE"
DRILL_DIR="$SECTION_DIR/$DRILL_NAME"

if [[ -d "$DRILL_DIR" ]]; then
  echo "ERROR: Directory already exists: $DRILL_DIR"
  exit 1
fi

# 5. Difficulty
prompt_choice "Difficulty:" "beginner" "intermediate" "advanced"
DIFFICULTY="$REPLY"

# 6. Tags
prompt_input "Tags (comma-separated, e.g., s3,encryption,bucket-policy)"
TAGS="$REPLY"
# Format tags as YAML list
TAGS_YAML=$(echo "$TAGS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | awk '{printf ", %s", $0}' | sed 's/^, //')
TAGS_YAML="[$TAGS_YAML]"

# 7. Short description
prompt_input "One-line description of the scenario"
DESCRIPTION="$REPLY"

# ─── Create files ────────────────────────────────────────────────────

echo ""
echo "Creating drill: $DRILL_NAME"
mkdir -p "$DRILL_DIR"

# README.md
cat > "$DRILL_DIR/README.md" << 'READMEEOF'
## Problem

<!-- Describe the issue the user needs to troubleshoot -->

### Context
<!-- Background information to help understand the problem -->

### Hint
<!-- Optional clue to help the user -->

## Validation

Your solution should:
<!-- List the success criteria -->

```bash
# Verification command(s)
```

## [Solution](../solutions/DRILL_NAME.md)
READMEEOF
sed -i '' "s/DRILL_NAME/$DRILL_NAME/g" "$DRILL_DIR/README.md"

# lab-initialization.sh
case "$SECTION" in
  aws)
    cat > "$DRILL_DIR/lab-initialization.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Lab initialization for $DRILL_NAME
# Prerequisites: LocalStack running (make run from aws/)

awslocal cloudformation create-stack \\
    --stack-name $DRILL_NAME \\
    --template-body file://template.yaml
EOF

    # template.yaml (CloudFormation stub)
    cat > "$DRILL_DIR/template.yaml" << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Setup for $DRILL_NAME exercise'

Resources: {}
  # Add your CloudFormation resources here

Outputs: {}
  # Add your stack outputs here
EOF
    ;;

  kubernetes)
    cat > "$DRILL_DIR/lab-initialization.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Lab initialization for $DRILL_NAME
# Prerequisites: minikube running (make start from kubernetes/)

kubectl apply -f template.yaml
EOF

    # template.yaml (Kubernetes manifest stub)
    cat > "$DRILL_DIR/template.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $TITLE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $TITLE
  template:
    metadata:
      labels:
        app: $TITLE
    spec:
      containers:
      - name: $TITLE
        image: nginx:latest
        ports:
        - containerPort: 80
EOF
    ;;

  gitlab)
    cat > "$DRILL_DIR/lab-initialization.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Lab initialization for $DRILL_NAME
# Run: gitlab-ci-local from this directory

echo "Run 'gitlab-ci-local' to execute the pipeline."
EOF

    # .gitlab-ci.yml stub
    cat > "$DRILL_DIR/.gitlab-ci.yml" << EOF
stages:
  - build
  - test

build:
  stage: build
  script:
    - echo "Build step"

test:
  stage: test
  script:
    - echo "Test step"
EOF
    ;;
esac

chmod +x "$DRILL_DIR/lab-initialization.sh"

# Solution file
SOLUTIONS_DIR="$SECTION_DIR/solutions"
mkdir -p "$SOLUTIONS_DIR"
cat > "$SOLUTIONS_DIR/$DRILL_NAME.md" << EOF
# $DRILL_NAME

## The Issue
<!-- Describe what's wrong and why -->

## Solution
<!-- Step-by-step fix -->

## Understanding
<!-- Explain the underlying concepts -->

## Testing
<!-- Commands to verify the fix -->

## Common Mistakes
<!-- List frequent errors -->

## Additional Resources
<!-- Links to relevant docs -->
EOF

# ─── Append to drill-index.yaml ─────────────────────────────────────

cat >> "$INDEX_FILE" << EOF

  - name: $DRILL_NAME
    section: $SECTION
    service: $PREFIX
    difficulty: $DIFFICULTY
    tags: $TAGS_YAML
    status: stub
    prerequisites: []
    description: >
      $DESCRIPTION
EOF

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
echo "Drill created successfully!"
echo ""
echo "Files:"
find "$DRILL_DIR" -type f | sed "s|$REPO_ROOT/||" | sort | sed 's/^/  /'
echo "  $(echo "$SOLUTIONS_DIR/$DRILL_NAME.md" | sed "s|$REPO_ROOT/||")"
echo ""
echo "Next steps:"
echo "  1. Edit $SECTION/$DRILL_NAME/README.md with the problem description"
echo "  2. Edit $SECTION/$DRILL_NAME/template.yaml with the broken resources"
echo "  3. Edit $SECTION/solutions/$DRILL_NAME.md with the solution"
echo "  4. Update status in drill-index.yaml from 'stub' to 'complete'"
