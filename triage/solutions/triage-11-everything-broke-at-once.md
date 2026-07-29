# Triage 11: Everything Broke At Once

## Root Cause

The "cleanup" MR factored three duplicated `before_script` blocks into a single `.setup` template that every job now `extends`. That shared `before_script` runs `./scripts/ci-setup.sh`, which calls `aws --version`. The `node:20-alpine` runner image does not include the AWS CLI, so the setup script exits non-zero, and every job that extends `.setup` fails in `before_script` before its own `script` runs.

Three unrelated jobs failing simultaneously is not a coincidence and not a runner fault. It is the signature of a single shared dependency breaking. The cleanup introduced exactly one new shared thing: `.setup`. That is where to look first.

## Diagnostic Path

### 1. Confirm the failures are identical

```bash
gitlab-ci-local
```

`lint`, `test`, and `build` all fail with the same message:

```
./scripts/ci-setup.sh: line ...: aws: command not found
```

Identical failure text across unrelated jobs is the tell. They are not independently broken; they share a cause.

### 2. Find what they have in common

Read the pipeline and note what changed. Each job gained `extends: .setup`. The jobs' own `script` blocks were untouched. The only shared, new element is the `.setup` template and the `ci-setup.sh` it calls.

```bash
grep -n "extends" .gitlab-ci.yml
```

All three jobs point at `.setup`. That single block is the common factor.

### 3. Isolate the shared block (rule it out or rule it in)

Temporarily bypass the shared setup on one job to prove the jobs themselves are fine:

```bash
# In .gitlab-ci.yml, comment out `extends: .setup` on `lint` only, then:
gitlab-ci-local --job lint
```

`lint` now passes. One change flipped one job from red to green, which confirms the fault lives entirely in the shared `.setup`, not in any individual job. Restore the `extends` line and fix the real cause.

## Solution

The setup script should not require a tool the image does not have. The `aws --version` call was copied in without checking the runner image. Remove the unmet dependency (or install it, or guard it):

Preferred — drop the line that does not belong in shared setup:

```sh
# scripts/ci-setup.sh
#!/bin/sh
set -e
echo "Configuring CI environment..."
echo "CI environment ready."
```

If the AWS CLI is genuinely needed by *some* jobs, scope it to those jobs instead of the shared block, or install it where required:

```yaml
# only the jobs that need it
deploy:
  extends: .setup
  before_script:
    - !reference [.setup, before_script]
    - apk add --no-cache aws-cli
```

Re-run:

```bash
gitlab-ci-local
```

All three jobs reach and complete their own scripts.

## Triage Lessons

- **When many unrelated things fail together, find the one thing they share.** Simultaneous failure across independent jobs almost always points to a common dependency: a shared template, a base image, a global variable, a common config file.
- **Rule out by isolation, not by guessing.** Bypassing the shared block on a single job is a one-line experiment that proves where the fault is. Change one thing, observe, then act on the evidence.
- **"Nobody touched those jobs" can be true and irrelevant.** The jobs did not change; what they *inherit* changed. Shared setup is code, and refactoring it is a change to every job at once.
- **DRY has a blast radius.** Consolidating duplication is good, but a single shared block now fails all consumers together. Shared setup deserves the same scrutiny as shared library code.

## Common Mistakes

1. **Blaming the runners.** The runner works. It faithfully runs a setup script that calls a missing binary.
2. **Debugging lint, test, and build separately.** Three parallel investigations of the same shared cause waste time. Consolidate on the common factor first.
3. **Reverting the whole cleanup MR.** The consolidation is fine; one line inside the shared script is wrong. Fix the line, keep the DRY improvement.
4. **Copying setup back into each job.** This "fixes" it by undoing the refactor and reintroduces the duplication the MR removed. Scope the unmet dependency instead.
