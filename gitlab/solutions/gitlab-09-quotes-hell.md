# gitlab-09-quotes-hell

## The Issue

The `.gitlab-ci.yml` has multiple quoting and special character problems that cause YAML parsing errors or unexpected runtime behavior. YAML has strict rules about special characters, and GitLab CI adds another layer of variable expansion on top of YAML parsing. The pipeline fails because:

1. **`CONNECTION_STRING`** contains an unquoted `#` character. In YAML, `#` starts a comment, so everything after `password=s3cr3t` is silently stripped. The variable value becomes `host=db:5432 user=admin password=s3cr3t` instead of `host=db:5432 user=admin password=s3cr3t#2024`.

2. **`FEATURE_FLAGS`** contains `{enable_cache: true, max_retries: 3}`. YAML interprets curly braces as a **flow mapping** (inline dictionary), not a string. The YAML parser attempts to parse this as a mapping and either fails or produces an object instead of a string.

3. **`GREETING`** contains `$USER`. In a GitLab CI variable definition, `$USER` is interpreted as a reference to another CI variable. Since no CI variable named `USER` is defined, it resolves to an empty string, producing `Hello , welcome!`.

4. **`DEPLOY_PATH`** contains `$APP_VERSION`. This works as intended in GitLab CI (variables can reference other variables), but it is a common source of confusion. If someone expects the literal string `$APP_VERSION` in the path, it will be unexpectedly expanded.

5. **The inline `#` in build-app script** -- The line `echo "Setting config value: retry_count=3 # max allowed"` has the `#` inside double quotes, which protects it in YAML. This one actually works correctly, but developers often get confused about when `#` is safe.

6. **The JSON payload line in deploy-app** -- `echo "JSON payload: {"app": "$APP_VERSION", "env": "prod"}"` has nested curly braces and nested quotes. The YAML parser sees the outer double quotes and then encounters inner double quotes, causing a parse error. The curly braces add further ambiguity.

7. **Colons in script values** -- The line `echo "Special chars: colons: here and {braces} too"` must be quoted as a full YAML string. Without wrapping the entire value in quotes, the YAML parser would interpret `echo "Special chars` as a mapping key because of the colon after it. The pipeline wraps this in single quotes at the YAML level, which is the correct approach.

## Solution

Here is the corrected `.gitlab-ci.yml` with all quoting issues fixed:

```yaml
image: alpine:latest

variables:
  APP_VERSION: "2.1.0"
  DEPLOY_PATH: "/opt/app/$APP_VERSION/bin"
  CONNECTION_STRING: "host=db:5432 user=admin password=s3cr3t#2024"
  FEATURE_FLAGS: "{enable_cache: true, max_retries: 3}"
  GREETING: 'Hello $USER, welcome!'
  TAG_PATTERN: "release-v*"

stages:
  - validate
  - build
  - deploy

validate-config:
  stage: validate
  script:
    - echo "Validating version $APP_VERSION"
    - echo "Deploy target: $DEPLOY_PATH"
    - echo "Connection: $CONNECTION_STRING"
    - echo "Flags: $FEATURE_FLAGS"

build-app:
  stage: build
  script:
    - echo "Building version $APP_VERSION"
    - export BUILD_TAG="$APP_VERSION-$(date +%Y%m%d)"
    - echo "Build tag is: $BUILD_TAG"
    - echo "Setting config value: retry_count=3 # max allowed"
    - RESULT=$(echo "$APP_VERSION" | cut -d. -f1)
    - echo "Major version: $RESULT"

deploy-app:
  stage: deploy
  script:
    - echo "Deploying to $DEPLOY_PATH"
    - echo 'No variables expanded here: $APP_VERSION stays literal'
    - echo "Config: password=s3cr3t#2024 host=localhost"
    - |
      if [ "$APP_VERSION" != "" ]; then
        echo "Version is set: $APP_VERSION"
      fi
    - 'echo "JSON payload: {\"app\": \"$APP_VERSION\", \"env\": \"prod\"}"'
    - 'echo "Special chars: colons: here and {braces} too"'
```

### Fix-by-fix Breakdown

#### Fix 1: Quote `CONNECTION_STRING` to protect `#`

```yaml
# BROKEN: # starts a YAML comment, value becomes "host=db:5432 user=admin password=s3cr3t"
CONNECTION_STRING: host=db:5432 user=admin password=s3cr3t#2024

# FIXED: Double quotes protect the # character
CONNECTION_STRING: "host=db:5432 user=admin password=s3cr3t#2024"
```

In YAML, `#` preceded by a space starts a comment. Even without a space before it (as in `s3cr3t#2024`), many YAML parsers still interpret `#` as starting a comment when the string is unquoted. Wrapping the value in double quotes makes the entire content a string literal (with respect to YAML special characters).

#### Fix 2: Quote `FEATURE_FLAGS` to prevent flow mapping parsing

```yaml
# BROKEN: YAML interprets {} as a mapping/dictionary
FEATURE_FLAGS: {enable_cache: true, max_retries: 3}

# FIXED: Double quotes make it a plain string
FEATURE_FLAGS: "{enable_cache: true, max_retries: 3}"
```

Without quotes, the YAML parser sees `{key: value, key: value}` and parses it as a YAML flow mapping (an inline dictionary). The result is a YAML object, not a string. GitLab expects variable values to be strings, so this causes a type error or unexpected behavior.

#### Fix 3: Use single quotes for `GREETING` to prevent variable expansion

```yaml
# BROKEN: $USER is expanded by GitLab CI (resolves to empty string)
GREETING: Hello $USER, welcome!

# FIXED: Single quotes prevent GitLab CI variable expansion
GREETING: 'Hello $USER, welcome!'
```

In GitLab CI `variables:` definitions, double quotes and unquoted strings allow `$VARIABLE` expansion. Single quotes prevent it. If you want the literal string `$USER` to appear in the value (to be expanded later at runtime by the shell), use single quotes. If you want GitLab to expand it at pipeline creation time, use double quotes.

#### Fix 4: Quote the `BUILD_TAG` assignment

```yaml
# FRAGILE: Word splitting can occur without quotes
- export BUILD_TAG=$APP_VERSION-$(date +%Y%m%d)

# FIXED: Double quotes prevent word splitting
- export BUILD_TAG="$APP_VERSION-$(date +%Y%m%d)"
```

In shell, unquoted variable expansions are subject to word splitting. If `$APP_VERSION` contained spaces (unlikely here, but a defensive practice), the assignment would break. Always quote variable expansions in shell.

#### Fix 5: Fix the JSON payload line

```yaml
# BROKEN: Nested double quotes and braces cause YAML parse error
- echo "JSON payload: {"app": "$APP_VERSION", "env": "prod"}"

# FIXED: Wrap entire value in single quotes (YAML level), escape inner quotes for shell
- 'echo "JSON payload: {\"app\": \"$APP_VERSION\", \"env\": \"prod\"}"'
```

This line has two problems:
1. The outer double quotes in YAML are terminated prematurely by the inner `"` before `app`
2. The `{` characters could be interpreted as YAML flow mapping syntax

The fix wraps the entire YAML value in single quotes (so YAML treats everything as a literal string), then uses backslash-escaped double quotes inside the `echo` command for the shell to interpret.

#### Fix 6: Quote variable references in shell commands

```yaml
# FRAGILE: Unquoted variable expansion
- RESULT=$(echo $APP_VERSION | cut -d. -f1)

# FIXED: Quoted variable expansion
- RESULT=$(echo "$APP_VERSION" | cut -d. -f1)
```

Always quote `$VARIABLE` references in shell commands to prevent word splitting and globbing. This is a shell best practice, not a YAML issue, but it comes up frequently in CI pipelines.

## Understanding

### The Three Layers of Interpretation

When you write a GitLab CI pipeline, your strings pass through three layers of interpretation:

```
.gitlab-ci.yml content
        |
        v  (1. YAML parser)
Parsed YAML structure
        |
        v  (2. GitLab CI variable expansion)
Expanded strings
        |
        v  (3. Shell interpreter)
Executed commands
```

Each layer has its own rules about special characters:

#### Layer 1: YAML Parsing

YAML special characters that need quoting:

| Character | Meaning in YAML | Example |
|---|---|---|
| `#` | Comment (after whitespace) | `value # this is lost` |
| `:` | Mapping separator | `key: value` |
| `{` `}` | Flow mapping | `{a: 1, b: 2}` |
| `[` `]` | Flow sequence | `[1, 2, 3]` |
| `"` | Double-quoted string | `"string"` |
| `'` | Single-quoted string | `'string'` |
| `&` | Anchor | `&anchor_name` |
| `*` | Alias | `*anchor_name` |
| `!` | Tag | `!ruby/object` |
| `|` | Literal block scalar | (preserves newlines) |
| `>` | Folded block scalar | (folds newlines) |
| `%` | Directive | `%YAML 1.2` |
| `@` `` ` `` | Reserved | May cause errors |

#### Layer 2: GitLab CI Variable Expansion

GitLab CI expands `$VARIABLE` and `${VARIABLE}` references in:
- `variables:` definitions
- `script:` values
- Most other string fields

In `variables:` definitions:
- **Double-quoted or unquoted**: `$VAR` is expanded
- **Single-quoted**: `$VAR` is kept literal

In `script:` values, GitLab passes the string to the shell, which handles variable expansion itself.

#### Layer 3: Shell Interpretation

The shell (usually bash or sh) interprets:
- `$VAR` and `${VAR}` -- variable expansion
- `$(cmd)` -- command substitution
- `"..."` -- double quotes (allows expansion)
- `'...'` -- single quotes (no expansion)
- `\` -- escape character
- `` `cmd` `` -- backtick command substitution (legacy syntax)

### Quoting Rules Summary

| Scenario | Use | Why |
|---|---|---|
| Value contains `#` | Double quotes in YAML | Prevents YAML comment |
| Value contains `{}` or `[]` | Double quotes in YAML | Prevents flow mapping/sequence |
| Value contains `:` followed by space | Double quotes in YAML | Prevents mapping interpretation |
| Want literal `$VAR` in a CI variable | Single quotes in YAML | Prevents GitLab expansion |
| Want `$VAR` expanded in a CI variable | Double quotes or unquoted | Allows GitLab expansion |
| Shell command with variables | Double quotes in shell | Prevents word splitting |
| Want literal `$VAR` in a script | Single quotes in shell | Prevents shell expansion |

### Block Scalars: The Safe Harbor

When in doubt about quoting, use YAML block scalars:

```yaml
script:
  - |
    echo "This is safe from YAML: {} [] # : & *"
    echo "Shell still expands: $APP_VERSION"
    echo 'Shell does not expand: $APP_VERSION'
```

The `|` (literal block scalar) preserves the content as-is for YAML parsing purposes. The only interpretation that happens is by the shell. This is the safest approach for complex script blocks.

## Testing

```bash
# Run the broken pipeline first to see the errors
cd gitlab/gitlab-09-quotes-hell
gitlab-ci-local

# Common errors you will see:
# - YAML parse error on the FEATURE_FLAGS line or JSON payload line
# - CONNECTION_STRING missing the #2024 suffix
# - GREETING showing "Hello , welcome!" instead of "Hello $USER, welcome!"

# After applying the fixes:
gitlab-ci-local

# Expected output:
# validate-config  completed successfully
#   - Outputs the full CONNECTION_STRING including #2024
#   - Outputs FEATURE_FLAGS as a string, not a parsed object
# build-app        completed successfully
#   - BUILD_TAG includes both version and date
# deploy-app       completed successfully
#   - Shows literal $APP_VERSION in the single-quoted echo
#   - Shows expanded $APP_VERSION in the double-quoted echo
#   - JSON payload renders correctly with braces and quotes
```

To verify specific fixes:

```bash
# Test that CONNECTION_STRING is complete (should include #2024)
gitlab-ci-local --job validate-config 2>&1 | grep "Connection:"

# Test that GREETING has literal $USER (should show "$USER", not empty)
gitlab-ci-local --job validate-config 2>&1 | grep "Hello"

# Test that the JSON payload line parses
gitlab-ci-local --job deploy-app 2>&1 | grep "JSON payload"
```

## Common Mistakes

1. **Forgetting that `#` starts a YAML comment** -- Even mid-value, an unquoted `#` (especially preceded by a space) is interpreted as a comment. Always quote strings containing `#`. This is the most common YAML quoting trap in CI pipelines.
2. **Using curly braces without quotes in variable values** -- YAML interprets `{key: value}` as a mapping. If you need literal curly braces in a string (JSON, template expressions, etc.), wrap the value in quotes.
3. **Confusing YAML quoting with shell quoting** -- Single quotes in YAML (`variables: KEY: 'value'`) prevent GitLab CI variable expansion. Single quotes in a shell script (`echo '$VAR'`) prevent shell expansion. These are two different layers. A common mistake is quoting for one layer but not the other.
4. **Using double quotes in YAML when you want a literal `$`** -- In `variables:` definitions, double-quoted strings still allow GitLab CI to expand `$VAR` references. Use single quotes if you want the literal dollar sign preserved for later shell expansion.
5. **Nested double quotes breaking YAML parsing** -- `echo "hello "world""` breaks because the YAML parser sees the second `"` as closing the string. Use single quotes at the YAML level and double quotes at the shell level: `'echo "hello \"world\""'`.
6. **Forgetting that colons need quoting in certain positions** -- A colon followed by a space (`: `) is a YAML mapping separator. The value `key: value` in a script line like `- echo key: value` will be parsed as a mapping, not a string. Wrap in quotes: `- "echo key: value"` or `- 'echo key: value'`.
7. **Assuming block scalars solve everything** -- While `|` and `>` block scalars avoid most YAML quoting issues, they do not prevent GitLab CI variable expansion in `variables:` definitions. They are most useful in `script:` blocks.
8. **Not testing with `gitlab-ci-local`** -- Many quoting issues only surface at parse time. Running `gitlab-ci-local` locally catches YAML errors before pushing to a remote GitLab instance and waiting for a pipeline.

## Additional Resources

- [GitLab CI/CD Variable Expansion](https://docs.gitlab.com/ee/ci/variables/#cicd-variable-expressions)
- [YAML Specification: Scalar Styles](https://yaml.org/spec/1.2/spec.html#id2760844)
- [YAML Multiline Strings](https://yaml-multiline.info/)
- [GitLab CI/CD `script` keyword](https://docs.gitlab.com/ee/ci/yaml/#script)
- [ShellCheck: Shell Script Linter](https://www.shellcheck.net/) -- Catches unquoted variable expansions in shell scripts
- [gitlab-ci-local](https://github.com/firecow/gitlab-ci-local)
