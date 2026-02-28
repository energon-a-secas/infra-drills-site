# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Local Drills is a collection of near-real-world troubleshooting challenges and simulations for AWS, Kubernetes, and GitLab CI/CD. Everything runs locally using LocalStack, Minikube, and gitlab-ci-local — no cloud costs involved. The repo serves as a learning platform, interview prep tool, and knowledge gap identifier.

## Repository Structure

- `aws/` — AWS drills using LocalStack (pattern: `SERVICE-NUMBER-SHORT-TITLE`)
- `kubernetes/` — Kubernetes drills using Minikube (pattern: `k8s-NUMBER-TITLE` or `eks-NUMBER-TITLE`)
- `gitlab/` — GitLab CI/CD drills using gitlab-ci-local (pattern: `gitlab-NUMBER-TITLE`)
- `projects/` — Working project examples (e.g., Serverless Express+DynamoDB API)
- `scripts/` — Tooling (e.g., `new-drill.sh` scaffold script)
- `assets/` — Documentation images
- `quizzes/` — Knowledge-check quizzes (no infrastructure required)
- `drill-index.yaml` — Central catalog of all drills with metadata

Each section has its own `Makefile`, `docker-compose.yml`, `README.md`, and `solutions/` directory.

## Naming and Numbering Conventions

### Drill prefixes
- **AWS**: Service-based prefix (`s3-`, `lambda-`, `iam-`, `sqs-`, `vpc-`, `dynamodb-`, `r53-`, `cfn-`)
- **Kubernetes**:
  - `k8s-`: Generic Kubernetes (works on any cluster — minikube, kind, etc.)
  - `eks-`: AWS EKS-specific (ALB ingress, IRSA, Secrets Manager CSI, etc.)
- **GitLab**: `gitlab-` prefix for all drills

### Numbering
- `00-09`: Tutorials / beginner
- `10-19`: Intermediate
- `20-29`: Advanced

## Common Commands

### Prerequisites Check
```bash
make check-requirements   # Verifies: aws, curl, jq, docker
make install-tools        # Installs via Homebrew
```

### AWS / LocalStack
```bash
export LOCALSTACK_AUTH_TOKEN=<your-token>
cd aws && make run         # Start LocalStack container
cd aws && make run-app     # Start serverless-app container
```
AWS env defaults: `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, `AWS_DEFAULT_REGION=us-east-1`. Use `awslocal` instead of `aws` for LocalStack commands.

### Kubernetes / Minikube
```bash
cd kubernetes && make install   # Install kubectl, kubectx, minikube
cd kubernetes && make start     # Start minikube
```

### GitLab CI Local
```bash
cd gitlab && make start    # Run gitlab-ci-local via docker-compose
```
Individual drill pipelines: run `gitlab-ci-local` from within a drill directory.

### Scaffold Tool
```bash
make new-drill             # Interactive script to create a new drill
```
Creates the drill directory, README, template files, lab-initialization.sh, solution stub, and appends to `drill-index.yaml`.

### Drill Index Queries
```bash
make list-drills           # Table of all drills with section, difficulty, status
make list-incomplete       # Show drills needing work (incomplete or stub)
```

### Knowledge Check Quizzes
```bash
make quiz                  # 10 random questions from all sections
make quiz-aws              # 10 random AWS questions
make quiz-k8s              # 10 random Kubernetes questions
make quiz-gitlab           # 10 random GitLab CI/CD questions
```
Quizzes are YAML-based and require no infrastructure. Run `./quizzes/quiz.sh --help` for all options (topic packs, difficulty filters, question count). Three question types: diagnose (multiple choice), complete (fill-in-the-blank), match (pair items).

## Drill Authoring Format

Every drill README follows this structure:
- **Problem/Request** — description of the issue (with optional Context and Hint)
- **Validation** — command(s) to verify the solution works
- **Solution** — link to `../solutions/SERVICE-NUMBER-TITLE.md`

Solution files follow: The Issue → Solution steps → Understanding (concepts) → Testing → Common Mistakes → Additional Resources.

Every drill directory should contain:
- `README.md` — Problem description
- `lab-initialization.sh` — Script to set up the broken environment
- Template file(s) — `template.yaml` (CloudFormation or K8s manifest) or `.gitlab-ci.yml`
- Corresponding solution in `../solutions/`

## Quiz Authoring Format

Quiz YAML files live in `quizzes/{aws,kubernetes,gitlab}/`. Each file has metadata (`topic`, `section`, `difficulty`, `related_drills`) and a `questions` list. Three question types:
- **diagnose**: Multiple choice with options `a`-`d`, `answer` is one letter
- **complete**: Fill-in-the-blank, `answer` is the primary answer, `accept` is an array of alternatives
- **match**: Left/right columns with `pairs` mapping indices (e.g. `[[0,0], [1,1]]`)

The quiz runner (`quizzes/quiz.sh`) is pure bash with no external dependencies. It parses YAML with line-by-line matching, so formatting must follow the established patterns in existing quiz files.

## Key Technical Details

- AWS drills use `localstack/localstack-pro` image (port 4566) but `ACTIVATE_PRO=0` by default; most drills work with Community tier
- LocalStack Community tier has simplified IAM (all resources can access everything)
- The serverless-app container uses `arm64v8/node` image — relevant for Apple Silicon
- Serverless Framework v4 with `serverless-localstack` plugin for local deployment
- GitLab CI drills use `energonhq/nodejs:9` image with gitlab-ci-local pre-installed
- macOS Docker Desktop may need the docker-compose symlink fix described in ISSUES.md
- K8s NetworkPolicy drills require a CNI that supports network policies (e.g., `minikube start --cni=calico`)
