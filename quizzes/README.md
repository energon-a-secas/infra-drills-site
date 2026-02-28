# Knowledge Check Quizzes

Quick-fire knowledge checks that test and refresh DevOps concepts without requiring any infrastructure. Each quiz takes 30 seconds to 2 minutes.

## Usage

```bash
# From the repo root:
make quiz              # 10 random questions from all sections
make quiz-aws          # 10 random AWS questions
make quiz-k8s          # 10 random Kubernetes questions
make quiz-gitlab       # 10 random GitLab CI/CD questions

# Or run the script directly:
./quizzes/quiz.sh --topic aws/s3-basics       # Specific topic pack
./quizzes/quiz.sh --section aws               # Random from one section
./quizzes/quiz.sh --difficulty beginner        # Filter by difficulty
./quizzes/quiz.sh --count 5                   # Limit question count
./quizzes/quiz.sh --topic aws/s3-basics --all # All questions in a pack
./quizzes/quiz.sh --list                      # List available packs
```

## Question Types

### Diagnose
Multiple choice — read a command/error and pick the root cause or fix.

```
[DIAGNOSE] (s3-b-01)

aws s3api put-object --bucket secure-uploads --key file.txt --body ./file.txt
Error: "Access Denied"
The bucket policy requires encryption. What's missing?

  a) --acl public-read
  b) --server-side-encryption AES256
  c) --storage-class GLACIER
  d) --content-type application/octet-stream

Your answer (a/b/c/d): b
Correct!
```

### Complete
Fill in the blank — type the missing command or value.

```
[COMPLETE] (s3-b-02)

Complete the command to list all S3 buckets:
awslocal s3api ___________

Your answer: list-buckets
Correct!
```

### Match
Match items from left column to right column by entering numbers.

```
[MATCH] (s3-b-03)

Match each encryption type to its key management:

  Left:
    1. SSE-S3
    2. SSE-KMS
    3. SSE-C
    4. Client-side

  Right (shuffled):
    1. Customer-provided keys
    2. S3-managed keys
    3. Encrypted before upload
    4. KMS-managed keys

  SSE-S3 -> 2
  SSE-KMS -> 4
  ...
```

## Topic Packs

### AWS (6 packs, ~50 questions)

| Pack | Difficulty | Questions |
|------|-----------|-----------|
| `aws/s3-basics` | beginner | 8 |
| `aws/iam-permissions` | intermediate | 10 |
| `aws/lambda-fundamentals` | beginner | 8 |
| `aws/vpc-networking` | intermediate | 10 |
| `aws/sqs-patterns` | intermediate | 6 |
| `aws/dynamodb-capacity` | advanced | 8 |

### Kubernetes (5 packs, ~40 questions)

| Pack | Difficulty | Questions |
|------|-----------|-----------|
| `kubernetes/pod-troubleshooting` | beginner | 10 |
| `kubernetes/service-networking` | beginner | 8 |
| `kubernetes/rbac-permissions` | intermediate | 6 |
| `kubernetes/storage-concepts` | intermediate | 8 |
| `kubernetes/deployment-strategies` | intermediate | 8 |

### GitLab CI/CD (3 packs, ~20 questions)

| Pack | Difficulty | Questions |
|------|-----------|-----------|
| `gitlab/pipeline-basics` | beginner | 8 |
| `gitlab/cache-and-artifacts` | beginner | 6 |
| `gitlab/yaml-quoting` | intermediate | 6 |

## Adding New Questions

Create a YAML file in the appropriate section directory following this schema:

```yaml
topic: Topic Name
section: aws|kubernetes|gitlab
difficulty: beginner|intermediate|advanced
related_drills: [drill-name-1, drill-name-2]

questions:
  - id: unique-id
    type: diagnose|complete|match
    prompt: |
      Question text here
    # For diagnose:
    options:
      a: "Option A"
      b: "Option B"
      c: "Option C"
      d: "Option D"
    answer: b
    # For complete:
    answer: expected-answer
    accept: [alt-answer-1, alt-answer-2]
    # For match:
    left: ["Item 1", "Item 2"]
    right: ["Match 1", "Match 2"]
    pairs: [[0,0], [1,1]]
    # All types:
    explanation: >
      Why this is the correct answer.
```

## Requirements

- bash 4+ (uses `mapfile`, associative arrays)
- No external dependencies (no `yq`, no `jq`)
