# Certification Tests

Certification-style timed tests for comprehensive skill assessment.

## Format

```yaml
id: aws-certified-solutions-associate-mock
type: certification
duration: 130  # minutes
passing_score: 72  # percent
sections:
  aws: 40%         # 40% of questions from AWS category
  kubernetes: 20%  # 20% from K8s
  gitlab: 10%      # 10% from GitLab
  general: 30%     # 30% mixed general questions
question_count: 65
allow_backtracking: false  # one pass only
```

## Usage

```bash
# Run certification test
./certification-runner.sh --test aws-certified-solutions-associate-mock

# Features:
# - Countdown timer display
# - Progress tracking (question X of Y)
# - Auto-submit when time expires
# - Score report with section breakdown
# - Pass/fail determination
# - Certificate generation (text/PDF)
```

## Creating Certification Tests

Place YAML files in `quizzes/certifications/` directory:

```bash
quizzes/
├── aws/                          # Regular quiz packs
├── kubernetes/
├── gitlab/
└── certifications/              # Certification tests
    ├── aws-solutions-associate.yaml
    ├── aws-sysops-associate.yaml
    └── k8s-cka.yaml
```
